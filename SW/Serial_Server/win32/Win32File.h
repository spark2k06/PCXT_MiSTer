//======================================================================
//
// Project:     XTIDE Universal BIOS, Serial Port Server
//
// File:        Win32File.h - Microsoft Windows file system access.
//
// Routines for accessing the file system under Win32.  It's important
// to use these direct Win32 calls for large files, since FILE * routines,
// in particular ftell() and fseek(), are limited to signed 32-bits (2 GB).
// These are also likely faster since they are more direct.
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

#include <windows.h>
#include <stdio.h>
#include "../library/library.h"

class FileAccess
{
public:
	int Create( char *p_name )
	{
		fp = CreateFileA( p_name, GENERIC_WRITE, 0, 0, CREATE_NEW, FILE_ATTRIBUTE_NORMAL, 0 );

		if( fp == INVALID_HANDLE_VALUE )
		{
			if( GetLastError() == ERROR_FILE_EXISTS )
			{
				log( 0, "'%s', file already exists", p_name );
				return( 0 );
			}
			else
				log( -1, "'%s', could not create file", p_name );
		}

		name = p_name;

		return( 1 );
	}

	void Open( char *p_name )
	{
		fp = CreateFileA( p_name, GENERIC_READ|GENERIC_WRITE, 0, 0, OPEN_EXISTING, FILE_ATTRIBUTE_NORMAL, 0 );

		if( fp == INVALID_HANDLE_VALUE )
			log( -1, "'%s', could not open file", p_name );

		name = p_name;
	}

	void Close()
	{
		if( fp )
		{
			if( !CloseHandle( fp ) )
				log( 0, "'%s', could not close file handle", name ? name : "unknown" );
		}
	}

	unsigned long SizeSectors(void)
	{
		LARGE_INTEGER li;
		unsigned long i;

		if( !GetFileSizeEx( fp, &li ) )
			log( -1, "'%s', could not retrieve file size (error %ul)", name, GetLastError() );

		if( li.LowPart & 0x1ff )
			log( -1, "'%s', file size is not a multiple of 512 byte sectors", name );

		if( li.HighPart > 0x1f )
			log( -1, "'%s', file size greater than LBA28 limit of 137,438,952,960 bytes", name );

		i = ((li.HighPart << 23 ) & 0xff800000) | ((li.LowPart >> 9) & 0x7fffff);

		return( (unsigned long) i );
	}

	void SeekSectors( unsigned long lba )
	{
		LARGE_INTEGER dist;

		dist.HighPart = lba >> 23;
		dist.LowPart = lba << 9;

		if( !SetFilePointerEx( fp, dist, NULL, FILE_BEGIN ) )
			log( -1, "'%s', Failed to seek to lba=%lu", name, lba );
	}

	void Read( void *buff, unsigned long len )
	{
		unsigned long out_len;

		if( !ReadFile( fp, buff, len, &out_len, NULL ) || len != out_len )
			log( -1, "'%s', ReadFile failed", name );
	}

	void Write( void *buff, unsigned long len )
	{
		unsigned long out_len;

		if( !WriteFile( fp, buff, len, &out_len, NULL ) || len != out_len )
			log( -1, "'%s', WriteFile failed", name );
	}

	FileAccess()
	{
		fp = NULL;
		name = NULL;
	}

    // LBA 28 limit - 28-bits (could be 1 more, but not worth pushing it)
	const static unsigned long MaxSectors = 0xfffffff;
#define USAGE_MAXSECTORS "137438 MB (LBA28 limit)"

private:
	HANDLE fp;
	char *name;
};

