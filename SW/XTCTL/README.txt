USAGE:

xtctl.exe [menu] [composite border adliboff 4Mhz/7Mhz/14Mhz]

Composite video simulated and visible bordes would be:

    xtctl composite border
    
Adlib hidden and 14Mhz would be:

    xtctl adliboff 14

This would restore normal operation:

    sysctl menu
    
It is not cumulative, any new execution of the tool resets the status beforehand, all options that are not selected will take into account the menu configuration. 

A warm restart (CTRL+ALT+SUPR) does not restore the initial state, but a cold restart does (restart from the menu).