# PCXT_MiSTer
PCXT port for MiSTer by spark2k06.

The purpose of this core is to implement a PCXT as reliable as possible. For this purpose, the MCL86 core from @MicroCoreLabs and KTPC-XT from @kitune-san are used.

The Graphics Gremlin project from TubeTimeUS (@schlae) has also been integrated in this first stage.

JTOPL by Jose Tejada (@topapate)

SN76489AN Compatible Implementation in VHDL Copyright (c) 2005, 2006, Arnim Laeuger (arnim.laeuger@gmx.net)

Place boot.rom (in SW folder) inside games/PCXT folder at root of SD card.

### Demo

![alt text](/demo/MiSTer_PCXT.gif "MiSTer PCXT")

# TODO

* Refactor Graphics Gremlin module, the new KFPC-XT system will make this refactor possible.
* Use SDRAM as system memory. Currently BRAM is used for everything, providing the system with 256Kb of RAM, 64Kb for the BIOS and 64Kb for VRAM.
* IDE module implementation
* Floppy implementation
* VHD support for easy integration with [XTIDE Universal BIOS](https://www.xtideuniversalbios.org/)
* Addition of other modules:
    * EMS    
    * Others...

* Turbo mode (7.16Mhz)

# ChangeLog

### Beta 0.7

* 4.77Mhz CPU clock with 33% duty cycle, thanks to @MicroCoreLabs
* Peripheral clock now works at half cpu clock, for correct synchronisation with the 8253 timer, thanks to @kitune-san
* Turbo option is disabled for the moment, requires a redesign of the BIU... for the to-do list

### Beta 0.6

* UART module implementation fix, thanks to @kitune-san

### Beta 0.5

* Added UART module from ao486 project (COM1 assigned to USER I/O pins)
* Automatic loading of the BIOS ROM from /games/PCXT directory
* BIOS ROM hot swapping from the OSD menu
* Updated the code to the latest version of the SDRAM module of KFPC-XT, but not yet implemented in the core... needs to be revised and improved, it does not work properly

### Beta 0.4

* Added Adlib FM (JTOPL2)
* Added SN76489AN (PCjr Sound)
* Change to alternative BIOS from PCXT version 0.9.8 developed by Sergey Kiselev, with OPL FM sound card detector

### Beta 0.3

* Change to KFPC-XT. The use of MCL86 and Graphics Gremlin are maintained.
* Use of Sergey Kiselev's (@skiselev) XT 8088 BIOS project.
* Turbo mode enabled, 4.77Mhz or 7.16Mhz selectable from OSD.

### Beta 0.2

* PIC module downgraded to the first versions of the Next186 project, more basic and without ISR
* Possibility to activate and deactivate IRQ0 from the OSD menu, temporary feature.

### Beta 0.1

* Monochrome monitor simulation option (green, amber, B&W)

Unstable version:

* Hardware interrupts are not executed.
* No VHD or SD support.
* BASIC ROM execution set in the BIOS, before the OS load routine.
