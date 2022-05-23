# PCXT_MiSTer
PCXT port for MiSTer by spark2k06.

The purpose of this core is to implement a PCXT as reliable as possible. For this purpose, the MCL86 core from @MicroCoreLabs and KTPC-XT from @kitune-san are used.

The Graphics Gremlin project from TubeTimeUS (@schlae) has also been integrated in this first stage.

### Demo

![alt text](/demo/MiSTer_PCXT.png "MiSTer PCXT")

# TODO

* Check the Keyboard, at the moment it does not seem to be working.
* Refactor Graphics Gremlin module, the new KFPC-XT system will make this refactor possible.
* Loading ROMs from the OSD menu or fixed from MiSTer config folder (boot0.rom)
* Use SDRAM as system memory. Currently BRAM is used for everything, providing the system with 256Kb of RAM, 64Kb for the BIOS and 32Kb for VRAM.
* IDE module implementation
* VHD support for easy integration with [XTIDE Universal BIOS](https://www.xtideuniversalbios.org/)
* Addition of other modules:
    * EMS
    * Adlib (JTOPL2)
    * Others...

# ChangeLog

### Beta 0.3

* Change to XTPC-XT. The use of MCL86 and Graphics Gremlin are maintained.
* Use of Sergey Kiselev's (@skiselev) XT 8088 project.
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
