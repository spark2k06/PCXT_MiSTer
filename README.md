# [IBM PC/XT](https://en.wikipedia.org/wiki/IBM_Personal_Computer_XT) for [MiSTer FPGA](https://mister-devel.github.io/MkDocs_MiSTer/)

PCXT port for MiSTer by [@spark2k06](https://github.com/spark2k06/).

Discussion and evolution of the core in the following misterfpga forum section:

https://misterfpga.org/viewforum.php?f=40

![Splash](splash.jpg)

## Description

The purpose of this core is to implement a PCXT as reliable as possible. For this purpose, the [MCL86 core](https://github.com/MicroCoreLabs/Projects/tree/master/MCL86) from [@MicroCoreLabs](https://github.com/MicroCoreLabs/) and [KFPC-XT](https://github.com/kitune-san/KFPC-XT) from [@kitune-san](https://github.com/kitune-san) are used.

The [Graphics Gremlin project](https://github.com/schlae/graphics-gremlin) from TubeTimeUS ([@schlae](https://github.com/schlae)) has also been integrated in this first stage.

[JTOPL](https://github.com/jotego/jtopl) by Jose Tejada (@jotego) was integrated for AdLib sound.

## Key features

* 8088 CPU with these speed settings: 4.77 MHz, 7.16 MHz, 9.54 MHz cycle accurate, and PC/AT 286 at 3.5MHz equivalent (max. speed)
* Support for IBM PCXT 5160 and clones with an EGA-centered video model
* Main memory 640Kb + 384Kb UMB memory
* IBM EGA video path with CGA-compatible text and graphics behavior implemented inside EGA
* EGA BIOS option ROM support
* EMS memory up to 2Mb
* XTIDE support
* Audio: Adlib, C/MS & speaker
* Joystick support
* Mouse support into COM1 serial port, this works like any Microsoft mouse... you just need a driver to configure it, like CTMOUSE 1.9 (available into hdd folder)
* 2nd SD card support

## Build configuration (config.tcl)

This branch is an EGA clean-core configuration. EGA is the only active video
hardware model; CGA-compatible software behavior is handled by the EGA path
instead of a separate CGA adapter. Standalone CGA, HGC, Tandy video, Tandy
audio, and Tandy keyboard variants are not preserved as active hardware
selection paths in this branch.

* System/ROM set to PCXT
* EGA video always active
* CGA-compatible text/graphics behavior through EGA
* OPL2 enabled for common DOS FM audio
* CMS enabled
* EMS enabled for expanded memory

The clean-core refactor is described in `EGA_CLEAN_CORE_SPEC.md` and
`EGA_CLEAN_CORE_PLAN.md`.

## Resource profile

The old resource table for selectable CGA/HGC/Tandy builds is no longer a
current description of this branch. Regenerate resource numbers from a fresh
Quartus build after the clean-core refactor is closed.

## Quick Start

* Copy the contents of `games/PCXT` to your MiSTer SD Card and uncompress `hd_image.zip`. It contains a FreeDOS image ( http://www.freedos.org/ )
* Select the core from Computers/PCXT.
* Press WinKey + F12 on your keyboard.
  * Model: IBM PCXT.
  * CPU Speed: PC/AT 3.5MHz (Max speed)
  * FDD & HDD -> HDD Image: FreeDOS_HD.img
  * BIOS -> PCXT BIOS: pcxt_micro8088.rom
* Choose Reset & apply settings.

## ROM Instructions

ROMs should be provided initially from the BIOS section of the OSD menu. The core has a single BIOS slot; on subsequent boots it is not necessary to provide them unless you want to use others. Original and copyrighted ROMs can be generated on the fly using the python scripts available in the SW folder of this repository:

* `make_rom_with_ibm5160.py`: A valid ROM is created for the PCXT core (pcxt.rom) based on the original IBM 5160 ROM, requires the XTIDE BIOS at address EC00h to work with HD images.
* `make_rom_with_jukost.py`: A valid ROM is created for the PCXT core (pcxt.rom) based on the original Juko ST ROM, and with the XTIDE BIOS embedded at address F000h.

From the same BIOS section of the OSD it is possible to specify an XTIDE ROM of up to 16Kb to work at address EC00h. It is also provided in this repository.

Other Open Source ROMs are available in the same folder:

* `pcxt_pcxt31.rom`: This ROM already has the XTIDE BIOS embedded at address F000h. ([Source Code](https://github.com/virtualxt/pcxtbios))
* `pcxt_micro8088.rom`: This ROM already has the XTIDE BIOS embedded at address F000h. ([Source Code](https://github.com/skiselev/8088_bios))
* `ide_xtl.rom`: This ROM corresponds to the XTIDE BIOS, it must be maintained for some scripts to work, it can also be upgraded to a newer version. ([Source Code](https://www.xtideuniversalbios.org/))

Note: Not all ROMs work with MDA video: (IBM5160, Yuko ST and pcxt31 works)

## Other BIOSes

* https://github.com/640-KB/GLaBIOS

## Mounting the FDD image

The floppy disk image size must be compatible with the BIOS, for example:

* On IBM 5160 only 360Kb images work well.
* On Micro8088 only 720Kb and 1.44Mb images work properly.
* Other BIOS may not be compatible, such as OpenXT by Ja'akov Miles and Jon Petroski.

It is possible to use images smaller than the size supported by the BIOS, but only pre-formatted images, as it will not be possible to format them from MS-Dos.

## Developers

Any contribution and pull request, please carry it out on the prerelease branch. Periodically they will be reviewed, moved and merged into the main branch, together with the corresponding release.

Thank you!
