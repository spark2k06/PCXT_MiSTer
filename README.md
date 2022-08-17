# PCXT_MiSTer
PCXT port for MiSTer by spark2k06.

The purpose of this core is to implement a PCXT as reliable as possible. For this purpose, the MCL86 core from @MicroCoreLabs and KTPC-XT from @kitune-san are used.

The Graphics Gremlin project from TubeTimeUS (@schlae) has also been integrated in this first stage.

JTOPL by Jose Tejada (@topapate)

SN76489AN Compatible Implementation in VHDL Copyright (c) 2005, 2006, Arnim Laeuger (arnim.laeuger@gmx.net)

Place pcxt.rom and tandy.rom (in SW folder) inside games/PCXT folder at root of SD card. Original and copyrighted ROMs can be generated on the fly using the python scripts available in the SW folder of this repository. OpenSource ROMs are available in the same folder.

https://github.com/virtualxt/pcxtbios

https://github.com/skiselev/8088_bios

https://www.xtideuniversalbios.org/

Discussion and evolution of the core in the following misterfpga forum thread:

https://misterfpga.org/viewtopic.php?t=4680&start=1020

# Mounting the disk image

Initially, and until an 8-bit IDE module compatible with XTIDE is available, floppy and hdd mounting will be done through the serial port available in the core. The available transfer speeds are as follows:

* 115200 Kbps
* 230400 Kbps
* 460800 Kbps
* 921600 Kbps

By default it is set to 115200, but this speed does not work, as XTIDE does not identify it... The most suitable speed is 460800, although 921600 is possible to use only with the CPU speed at 14.318MHz.

# To-do list and challenges

* Refactor Graphics Gremlin module, the new KFPC-XT system will make this refactor possible.
* 8-bit IDE module implementation
* Floppy implementation
* Addition of other modules