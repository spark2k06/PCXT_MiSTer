#include <iostream>
#include <iomanip>
#include <fstream>
#include <string>
#include <ctype.h>

using namespace std;

void parse_line( int *buf, ifstream& fin );

int main( int argc, char *argv[] ) {
    if( argc != 2 ) {
        cout << "ERROR: expecting .msg filename\n";
        return 1;
    }
    string fname( argv[1] );
    ifstream fin( fname );
    if( !fin.good() ) {
        cout << "ERROR: cannot open file " << fname << '\n';
        return 2;
    }
    // Parse file
    int *buf = new int[16*1024]; // Max 16 kB
    for(int k=0; k<16*1024; k++ ) buf[k]=0;
    int *pline = buf;
    int line=0;

    try {
        while( !fin.eof() ) {
            parse_line( pline, fin );
            pline += 0x40;
            if( pline-buf >= 16*1024 ) {
                throw "ERROR: file is too long for 16kB ";
            }
            line++;
        }
        // Dump the contents
        ofstream fout( "msg.hex" );
        for( int k=0; k<16*1024; k++ ) {
            fout << hex << buf[k] << '\n';
        }
        fout.close();
        fout.open( "msg.bin" );
        for( int k=0; k<16*1024; k++ ) {
            int v = buf[k];
            for( int bit=0; bit<9; bit++ ) {
                if( v&0x100 ) fout << '1'; else fout << '0';
                v<<=1;
            }
            fout << '\n';
        }
    } catch( const char* error ) {
        cout << "ERROR: " << error << "at line " << dec << (line+1) << '\n';
        delete []buf;
        return 3;
    }

    delete []buf;
    return 0;
}

void parse_line( int *buf, ifstream& fin ) {    
    string line;
    getline( fin, line );
    int pal=3;
    bool brk=false;
    int cnt=0;
    for( int i : line ) {
        if( brk ) {
            if( i=='\\' ) {
                brk = false;
            }
            else {
                switch( toupper(i) ) {
                    case 'R': pal=0; break;
                    case 'G': pal=1; break;
                    case 'B': pal=2; break;
                    case 'W': pal=3; break;
                    default: {
                        throw "ERROR: invalid palette code ";
                    }
                }
                brk = false;
                // cout << pal << '\n';
                continue;
            }
        }
        else if( i=='\\' ) {
            // cout << "BRK";
            brk=true;
            continue;
        }
        // actual chars
        if( cnt++ == 64 ) {
            throw "line is longer than 64 characters, ";
        }
        if( i<0x20 || i>0x7f ) {
            throw "character code out of range ";
        }
        int v = i-0x20;
        v&=0x7f;
        v |= pal<<7;
        *buf++ = v;
    }
}
