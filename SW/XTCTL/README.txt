XTCTL is a small legacy runtime-control utility for the PCXT core. The current
OSD is the preferred interface; this program writes the compatibility control
port at 8888h and is useful for old DOS launchers.

USAGE:

xtctl.exe [menu] [composite border adliboff a000hoff 5Mhz/8Mhz/10Mhz/AT4MHz]

The utility can override simulated composite video and the visible border:

    xtctl composite border
    
AdLib hidden and the legacy AT 4 MHz selection would be:

    xtctl adliboff AT4

This would restore normal operation:

    sysctl menu
    
It is not cumulative. Each execution first clears the previous overrides; any
option that is not selected follows the current OSD configuration. The speed
names are historical XTCTL names and do not replace the current OSD labels of
4.77 MHz, 7.16 MHz, 9.54 MHz and Max.

A warm restart (CTRL+ALT+SUPR) does not restore the initial state, but a cold restart does (restart from the menu).
