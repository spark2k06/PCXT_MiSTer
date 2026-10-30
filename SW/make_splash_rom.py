"""Build the packed 320x200, 16-colour boot splash ROM.

The source artwork is SW/splash_320x200_source.png, 320x200 pixels.  Every
pixel is mapped to the nearest of the 16 CGA/EGA RGBI colours and the ROM
stores two 4-bit RGBI indexes per byte, the left pixel in bits 7:4, 160 bytes
per line.  The same ROM feeds the CGA and the EGA renderer (rtl/video/
splash_rom.v).  SW/splash_320x200_preview.png shows the result at 4:3, as a
monitor shows a 320x200 picture.

The PowerShell version next to this file performs the same conversion on
Windows without requiring Python or Pillow.
"""

from pathlib import Path

from PIL import Image


WIDTH = 320
HEIGHT = 200
ROOT = Path(__file__).resolve().parents[1]
SOURCE = ROOT / "SW" / "splash_320x200_source.png"
PREVIEW = ROOT / "SW" / "splash_320x200_preview.png"
ROM = ROOT / "rtl" / "video" / "splash_320x200.hex"

# 8-bit equivalents of the RGBI colours, in RGBI index order.
PALETTE = (
    (0x00, 0x00, 0x00), (0x00, 0x00, 0xAA), (0x00, 0xAA, 0x00), (0x00, 0xAA, 0xAA),
    (0xAA, 0x00, 0x00), (0xAA, 0x00, 0xAA), (0xAA, 0x55, 0x00), (0xAA, 0xAA, 0xAA),
    (0x55, 0x55, 0x55), (0x55, 0x55, 0xFF), (0x55, 0xFF, 0x55), (0x55, 0xFF, 0xFF),
    (0xFF, 0x55, 0x55), (0xFF, 0x55, 0xFF), (0xFF, 0xFF, 0x55), (0xFF, 0xFF, 0xFF),
)


def nearest_colour(pixel):
    return min(
        range(len(PALETTE)),
        key=lambda index: sum(
            (pixel[channel] - PALETTE[index][channel]) ** 2
            for channel in range(3)
        ),
    )


def main():
    image = Image.open(SOURCE).convert("RGB")
    if image.size != (WIDTH, HEIGHT):
        image = image.resize((WIDTH, HEIGHT), Image.Resampling.NEAREST)
    pixels = image.load()
    indices = [nearest_colour(pixels[x, y]) for y in range(HEIGHT) for x in range(WIDTH)]

    quantized = Image.new("RGB", (WIDTH, HEIGHT))
    quantized.putdata([PALETTE[index] for index in indices])
    quantized.resize((WIDTH * 4, HEIGHT * 24 // 5), Image.Resampling.NEAREST).save(PREVIEW)

    rom_lines = [
        f"{(indices[offset] << 4) | indices[offset + 1]:02X}"
        for offset in range(0, len(indices), 2)
    ]
    ROM.write_bytes(("\r\n".join(rom_lines) + "\r\n").encode("ascii"))


if __name__ == "__main__":
    main()
