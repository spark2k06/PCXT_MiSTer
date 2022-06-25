//======================================================================
//
// Project:     XTIDE Universal BIOS, Serial Port Server
//
// File:        Win32Serial.h - Microsoft Windows serial code
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
#include "windows.h"
#include "../library/library.h"

#define PIPENAME "\\\\.\\pipe\\xtide"

class SerialAccess
{
public:
	void Connect( char *name, struct baudRate *p_baudRate )
	{
		char buff1[20], buff2[1024];

		baudRate = p_baudRate;

		pipe = NULL;

		if( !name )
		{
			for( int t = 1; t <= 30 && !name; t++ )
			{
				sprintf( buff1, "COM%d", t );
				if( QueryDosDeviceA( buff1, buff2, sizeof(buff2) ) )
					name = buff1;
			}
			if( !name )
				log( -1, "No physical COM ports found" );
		}

		if( name[0] == '\\' && name[1] == '\\' )
		{
			log( 0, "Opening named pipe %s (simulating %s baud)", name, baudRate->display );

			pipe = CreateNamedPipeA( name, PIPE_ACCESS_DUPLEX, PIPE_TYPE_BYTE, 2, 1024, 1024, 0, NULL );
			if( pipe == INVALID_HANDLE_VALUE )
				log( -1, "Could not CreateNamedPipe " PIPENAME );

			if( !ConnectNamedPipe( pipe, NULL ) )
				log( -1, "Could not ConnectNamedPipe" );

			if( baudRate->divisor > 0x80 )
				log( -1, "Cannot simulate baud rates with hardware multipliers" );

			speedEmulation = 1;
			resetConnection = 1;
		}
		else
		{
			if( QueryDosDeviceA( name, buff2, sizeof(buff2) ) )
			{
				COMMTIMEOUTS timeouts;
				DCB dcb;

				log( 0, "Opening %s (%s baud)", name, baudRate->display );

				pipe = CreateFileA( name, GENERIC_READ|GENERIC_WRITE, 0, 0, OPEN_EXISTING, FILE_ATTRIBUTE_NORMAL, 0 );
				if( pipe == INVALID_HANDLE_VALUE )
					log( -1, "Could not Open \"%s\"", name );

				FillMemory(&dcb, sizeof(dcb), 0);
				FillMemory(&timeouts, sizeof(timeouts), 0);

				dcb.DCBlength = sizeof(dcb);
				dcb.BaudRate = baudRate->rate;
				dcb.ByteSize = 8;
				dcb.StopBits = ONESTOPBIT;
				dcb.Parity = NOPARITY;
				if( !SetCommState( pipe, &dcb ) )
				{
					char *msg = "";
					COMMPROP comProp;

					if( GetCommProperties( pipe, &comProp ) )
					{
						if( comProp.dwMaxBaud != BAUD_USER )
							msg = "\n    On this COM port, baud rate is limited to 115.2K";
					}
					log( -1, "Could not SetCommState: baud rate selected may not be available%s", msg );
				}

				if( !SetCommTimeouts( pipe, &timeouts ) )
					log( -1, "Could not SetCommTimeouts" );
			}
			else
			{
				char logbuff[ 1024 ];

				EnumerateCOMPorts( logbuff, 1024 );

				log( -1, "Serial port '%s' not found, detected COM ports: %s", name, logbuff );
			}
		}
	}

	static void EnumerateCOMPorts( char *logbuff, int logbuffLen )
	{
		int found = 0;
		char buff1[20], buff2[1024];

		logbuff[0] = 0;

		for( int t = 1; t <= 40 && strlen(logbuff) < (logbuffLen - 40); t++ )
		{
			sprintf( buff1, "COM%d", t );
			if( QueryDosDeviceA( buff1, buff2, sizeof(buff2) ) )
			{
				if( found )
					strcat( logbuff, ", " );
				strcat( logbuff, buff1 );
				found = 1;
			}
		}

		if( !found )
			strcat( logbuff, "(none)" );
	}

	void Disconnect()
	{
		if( pipe )
		{
			CloseHandle( pipe );
			pipe = NULL;
		}
	}

	unsigned long readCharacters( void *buff, unsigned long len )
	{
		unsigned long readLen;
		int ret;

		ret = ReadFile( pipe, buff, len, &readLen, NULL );

		if( !ret || readLen == 0 )
		{
			if( GetLastError() == ERROR_BROKEN_PIPE )
				return( 0 );
		    else
				log( -1, "read serial failed (error code %d)", GetLastError() );
		}

		return( readLen );
	}

	int writeCharacters( void *buff, unsigned long len )
	{
		unsigned long writeLen;
		int ret;

		ret = WriteFile( pipe, buff, len, &writeLen, NULL );

		if( !ret || len != writeLen )
		{
			if( GetLastError() == ERROR_BROKEN_PIPE )
				return( 0 );
			else
				log( -1, "write serial failed (error code %d)", GetLastError() );
		}

		return( 1 );
	}

	SerialAccess()
	{
		pipe = NULL;
		speedEmulation = 0;
		resetConnection = 0;
		baudRate = NULL;
	}

	~SerialAccess()
	{
		Disconnect();
	}

	int speedEmulation;
	int resetConnection;

	struct baudRate *baudRate;

private:
	HANDLE pipe;
};

