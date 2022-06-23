//======================================================================
//
// Project:     XTIDE Universal BIOS, Serial Port Server
//
// File:        Win32.cpp - Microsoft Windows 32-bit application
//
// This file contains the entry point for the Win32 version of the server.
// It also handles log reporting, timers, and command line parameter parsing.
//

//
// XTIDE Universal BIOS and Associated Tools
// Copyright (C) 2009-2010 by Tomi Tilli, 2011-2013 by XTIDE Universal BIOS Team.
//
// This program is free software; you can redistribute it and/or modify
// it under the terms of the GNU General Public License as published by
// the Free Software Foundation; either version 2 of the License, or
// (at your option) any later version.
//
// This program is distributed in the hope that it will be useful,
// but WITHOUT ANY WARRANTY; without even the implied warranty of
// MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
// GNU General Public License for more details.
// Visit http://www.gnu.org/licenses/old-licenses/gpl-2.0.html
//

#include <stdio.h>
#include <stdlib.h>
#include <fcntl.h>
#include <stdarg.h>

#include "../library/library.h"
#include "../library/flatimage.h"

#include "../../XTIDE_Universal_BIOS/inc/version.inc"

char *bannerStrings[] = {
	"SerDrive - XTIDE Universal BIOS Serial Drive Server",
	"Copyright (C) 2012-2013 by XTIDE Universal BIOS Team",
	"Released under GNU GPL v2, with ABSOLUTELY NO WARRANTY",
	ROM_VERSION_STRING,
	"",
	NULL };

char *usageStrings[] = {
	"This is free software, and you are welcome to redistribute it under certain",
	"conditions.  For more license details, see the LICENSE.TXT file included with",
	"this distribution, visit the XTIDE Universal BIOS wiki (address below), or",
 	"http://www.gnu.org/licenses/gpl-2.0.html",
	"",
	"Visit the wiki on http://code.google.com/p/xtideuniversalbios for detailed",
	"serial drive usage directions.",
	"",
	"Usage: SerDrive [options] imagefile [[slave-options] slave-imagefile]",
	"",
	"  -g [cyl:head:sect]  Geometry in cylinders, sectors per cylinder, and heads",
	"                      -g also implies CHS addressing mode (default is LBA28)",
	"",
	"  -n [megabytes]      Create new disk with given size or use -g geometry",
	"                      Maximum size is " USAGE_MAXSECTORS,
	"                      Floppy images can also be created, such as \"360K\"",
	"                      (default is a 32 MB disk, with CHS geometry 65:16:63)",
	"",
	"  -p [pipename]       Named Pipe mode for emulators",
	"                      (must begin with \"\\\\\", default is \"" PIPENAME "\")",
	"",
	"  -c COMPortNumber    COM Port to use (default is first found)",
	"                      Available COM ports on this system are:",
 "COM                          ",
	"",
	"  -b BaudRate         Baud rate to use on the COM port, with client machine",
	"                      rate multiplier in effect:",
	"                          None:  2400,  4800,   9600,  28.8K,  57.6K, 115.2K",
	"                          2x:    4800,  9600,  19200,  57.6K, 115.2K, 230.4K",
	"                          4x:    9600, 19200,  38400, 115.2K, 230.4K, 460.8K",
	"                          8x:   19200, 38400, 115.2K, 230.4K, 460.8K, 921.6K",
	"                          and for completeness:                76.8K, 153.6K",
	"                      (default is 9600, 115.2K when in named pipe mode)",
	"",
	"  -t                  Disable timeout, useful for long delays when debugging",
	"",
	"  -r                  Read Only disk, do not allow writes",
	"",
	"  -v [level]          Reporting level 1-6, with increasing information",
	"",
	"On the client computer, a serial port can be configured for use as a hard disk",
	"with xtidecfg.com.  Or one can hold down the ALT key at the end of the normal",
	"IDE hard disk scan and the XTIDE Universal BIOS will scan COM1-7, at each of",
	"the six speeds given above for BaudRate.  Note that hardware rate multipliers",
	"must be taken into account on the server end, but are invisible on the client.",
	"",
	"Floppy images may also be used.  Image size must be exactly the same size",
	"as a 2.88MB, 1.44MB, 1.2MB, 720KB, 360KB, 320KB, 180KB, or 160KB disk.",
	"Floppy images must be the last disks discovered by the BIOS, and only",
	"two floppy drives are supported by the BIOS at a time.",
	NULL };

void usagePrint( char *strings[] )
{
	for( int t = 0; strings[t]; t++ )
	{
		if( !strncmp( strings[t], "COM", 3 ) )
		{
			char logbuff[ 1024 ];

			SerialAccess::EnumerateCOMPorts( logbuff, 1024 );
			fprintf( stderr, "%s%s\n", strings[t]+3, logbuff );
		}
		else
			fprintf( stderr, "%s\n", strings[t] );
	}
}

#define usage() { usagePrint( usageStrings ); exit(1); }

int verbose = 0;

int main(int argc, char* argv[])
{
	DWORD len;

	unsigned long check;
	unsigned char w;

	unsigned short wbuff[256];

	SerialAccess serial;
	Image *img;
	struct baudRate *baudRate = NULL;

	int timeoutEnabled = 1;

	char *ComPort = NULL, ComPortBuff[20];

	_fmode = _O_BINARY;

	unsigned long cyl = 0, sect = 0, head = 0;
	int readOnly = 0, createFile = 0;
	int useCHS = 0;

	int imagecount = 0;
	Image *images[2] = { NULL, NULL };

	usagePrint( bannerStrings );

	for( int t = 1; t < argc; t++ )
	{
		char *next = (t+1 < argc ? argv[t+1] : NULL );

		if( argv[t][0] == '/' || argv[t][0] == '-' )
		{
		    char *c;
			unsigned long a;
			for( c = &argv[t][1]; *c && !isdigit( *c ); c++ )
				;
			a = atol(c);

			switch( argv[t][1] )
			{
			case 'c': case 'C':
				if( !next )
					usage();
				t++;
				a = atol( next );
				if( a < 1 )
					usage();
				sprintf( ComPortBuff, "COM%d", a );
				ComPort = &ComPortBuff[0];
				break;
			case 'v': case 'V':
			    if( next && atol(next) != 0 )
				{
					t++;
					verbose = atol(next);
				}
				else
					verbose = 1;
				break;
			case 'r': case 'R':
				readOnly = 1;
				break;
			case 'p': case 'P':
				if( next && next[0] == '\\' && next[1] == '\\' )
				{
					t++;
					ComPort = next;
				}
				else
					ComPort = PIPENAME;
				if( !baudRate )
					baudRate = baudRateMatchString( "115200" );
				break;
			case 'g': case 'G':
				if( next && atol(next) != 0 )
				{
					t++;
					if( !Image::parseGeometry( next, &cyl, &head, &sect ) )
						usage();
				}
				useCHS = 1;
				break;
			case 'h': case 'H': case '?':
				usage();
				break;
			case 'n': case 'N':
				createFile = 1;
				if( next && atol(next) != 0 )
				{
					double size = atof(next);
					struct floppyInfo *fi;
					char *c;

					t++;

					size *= 2;
					for( c = argv[t]; *c && *c != 'k' && *c != 'K'; c++ ) ;
					if( !(*c) )
						size *= 1000;

					if( (fi = FindFloppyInfoBySize( size )) )
					{
						sect = fi->sectors;
						head = fi->heads;
						cyl = fi->cylinders;
					}
					else
					{
						sect = 63;
						head = 16;
						cyl = size / (16*63);
					}
				}
				break;
			case 't': case 'T':
				timeoutEnabled = 0;
				break;
			case 'b': case 'B':
				if( !next )
					usage();
				t++;
				if( !(baudRate = baudRateMatchString( next )) || !baudRate->rate )
					log( -2, "Unknown Baud Rate \"%s\"", next );
				break;
			default:
				log( -2, "Unknown Option: \"%s\"", argv[t] );
			}
		}
		else if( imagecount < 2 )
		{
			if( createFile && cyl == 0 )
			{
				cyl = 65;
				sect = 63;
				head = 16;
			}
			images[imagecount] = new FlatImage( argv[t], readOnly, imagecount, createFile, cyl, head, sect, useCHS );
			imagecount++;
			createFile = readOnly = cyl = sect = head = useCHS = 0;
		}
		else
			usage();
	}

	if( imagecount == 0 )
		usage();

	if( !baudRate )
		baudRate = baudRateMatchString( "9600" );

	do
	{
		serial.Connect( ComPort, baudRate );

		processRequests( &serial, images[0], images[1], timeoutEnabled, verbose );

		serial.Disconnect();

		if( serial.resetConnection )
			log( 0, "Serial Connection closed, reset..." );
	}
	while( serial.resetConnection );
}

void log( int level, char *message, ... )
{
	va_list args;

	va_start( args, message );

	if( level < 0 )
	{
		fprintf( stderr, "ERROR: " );
		vfprintf( stderr, message, args );
		fprintf( stderr, "\n" );
		if( level < -1 )
		{
			fprintf( stderr, "\n" );
			usage();
		}
		exit( 1 );
	}
	else if( verbose >= level )
	{
		vprintf( message, args );
		printf( "\n" );
	}

	va_end( args );
}

unsigned long GetTime(void)
{
	return( GetTickCount() );
}

unsigned long GetTime_Timeout(void)
{
	return( 1000 );
}
