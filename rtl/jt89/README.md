# JT89 FPGA Clone of sn76489an hardware by Jose Tejada (@topapate)

You can show your appreciation through:

* [Patreon](https://patreon.com/jotego), by supporting releases
* [Paypal](https://paypal.me/topapate), with a donation


sn76489an compatible Verilog core, with emphasis on FPGA implementation and Megadrive/Master System compatibility.

This project aims to make a Verilog core that will:

* Produce signed output waveforms, with no dc offset
* Produce accurate volume
  * Have volume limiting like reportedly Master System had
  * Different volume settings for noise channel as reported
  * Test if Megadrive 2 version had different volume and apply it
* Reported variations on noise signal length
* Use one single clock for all registers, making it easy to synthesize and constraint on FPGAs
* It will fit well with [JT12](https://github.com/jotego/jt12) in order to produce the Megadrive sound system
* Have separate output channels, so they can be mixed using the interpolator before the sigma-delta DAC

If you use JTFRAME, this project will integrate naturally with it. If not, you can use the .qip file for Quartus in the syn/quartus folder.

## Use Cases

This project has been used in:

* [Genesis MiSTerFPGA core](https://github.com/MiSTer-devel/Genesis_MiSTer)
* [Kicker arcade core](https://github.com/jotego/jtkicker)
* [Yie Ar Kungfu arcade core](https://github.com/jotego/jtkicker)
* [Konami's Ping Pong arcade core](https://github.com/jotego/jtkicker)
* [Mikie arcade core](https://github.com/jotego/jtkicker)
* [Track'n Field arcade core](https://github.com/jotego/jtkicker)
* [Road Fighter arcade core](https://github.com/jotego/jtkicker)
* [Super Basketball arcade core](https://github.com/jotego/jtkicker)
* [Exed Exes arcade core](https://github.com/jotego/jtgng)

## Related Projects

Other sound chips from the same author

Chip                   | Repository
-----------------------|------------
YM2203, YM2612, YM2610 | [JT12](https://github.com/jotego/jt12)
YM2151                 | [JT51](https://github.com/jotego/jt51)
YM3526,OPLL,OPL2       | [JTOPL](https://github.com/jotego/jtopl)
YM2149                 | [JT49](https://github.com/jotego/jt49)
OKI 6295               | [JT6295](https://github.com/jotego/jt6295)
OKI MSM5205            | [JT5205](https://github.com/jotego/jt5205)
sn76489an              | [JT89](https://github.com/jotego/jt89)