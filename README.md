# PCXT_MiSTer
PCXT port for MiSTer by spark2k06.

The purpose of this core is to implement a PCXT as reliable as possible. For this purpose, the MCL86 core from @MicroCoreLabs is used.

The Graphics Gremlin project from TubeTimeUS (@schlae) has also been integrated in this first stage.

### Demo

[![Alt text](https://lh3.googleusercontent.com/pw/AM-JKLX6yF_arRb4KKyip_5JoBaw5833WP69UKpYuh60pZ_0_QQQyk3J4-gw6rwvjP3GDFn0e9ILm10DrPzzLP5bomQ-yQxUXIlFATjXykWWHrjSIu12Jz9ZdScxMahPVxaDl3kvg8XEu_Drv8tDIgmgSUEzTQ=w589-h331-no?authuser=0)](https://www.youtube.com/watch?v=bInahbseaaY)

# TODO

* Check the PIC8259 module and check the INTs trigger.
* Loading ROMs from the OSD menu
* IDE module implementation
* VHD support for easy integration with [XTIDE Universal BIOS](https://www.xtideuniversalbios.org/)
* Addition of other modules:
    * EMS
    * Adlib (JTOPL2)
    * Others...

# ChangeLog

### Beta 0.1

* Monochrome monitor simulation option (green, amber, B&W)

Unstable version:

* Hardware interrupts are not executed.
* No VHD or SD support.
* BASIC ROM execution set in the BIOS, before the OS load routine.