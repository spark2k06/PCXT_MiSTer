#include <stdio.h>
#include <conio.h>
#include <string.h>

#define COMP      0x01
#define BORDER    0x02
#define ADLIBOFF  0x10
//#define MDA       0x20 (Reserved)
#define A000HOFF  0x40
#define AT4MHZ    0x80

static int _argc;
static char **_argv;

int chk_arg_opt(char * option)
{
    int index;
    for(index = 1; index < _argc; index++)
	if(strcmpi(_argv[index], option) == 0)
	    return index;
    return 0;
}

int main(int argc, char **argv)
{
    unsigned char arg = 0;
    char * argv0;
    char * bs;

    if(argc < 2)
    {
	printf("XTCTL 1.3\n");
	printf("USAGE:\n");
	bs = strrchr(argv[0], '\\');
	if(bs == NULL)
	    argv0 = argv[0];
	else
	    argv0 = ++bs;
	printf("%s [menu] [composite border adliboff a000hoff 5Mhz/8Mhz/10Mhz/AT4MHz]\n", argv0);
	return -1;
    }

    _argc = argc;
    _argv = argv;

    if (chk_arg_opt("menu"))
        arg = 0;
    else 
    {
        if (chk_arg_opt("composite"))
	    arg |= COMP;

	if (chk_arg_opt("border"))
	    arg |= BORDER;

	if (chk_arg_opt("adliboff"))
	    arg |= ADLIBOFF;

//	if (chk_arg_opt("mda")) (Reserved)
//	    arg |= MDA;
    
	if (chk_arg_opt("a000hoff"))
	    arg |= A000HOFF;

	if (chk_arg_opt("5Mhz") || chk_arg_opt("5"))
	{
	    arg |= 1 << 2;
	    arg &= ~(1 << 3);
	}
	else if (chk_arg_opt("8Mhz") || chk_arg_opt("8"))
	{
	    arg &= ~(1 << 2);
	    arg |= 1 << 3;
	}
	else if (chk_arg_opt("10Mhz") || chk_arg_opt("10"))
	{
	    arg |= 1 << 2;
	    arg |= 1 << 3;
	}
	else if (chk_arg_opt("AT4Mhz") || chk_arg_opt("AT4"))
	{
	    arg &= ~(1 << 2);
	    arg &= ~(1 << 3);        
        arg |= AT4MHZ;
	}
    }

    outp(0x8888, arg);

    return 0;
}
