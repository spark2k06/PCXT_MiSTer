import os

zeros_length = 57344
rom_filename = "boot0.rom"
bios_filename = "bios.com"

with open(rom_filename, 'wb') as romf:
    romf.write(b'\x00' * zeros_length)

with open(rom_filename, "ab") as romf, open(bios_filename, "rb") as f:
     romf.write(f.read())
    