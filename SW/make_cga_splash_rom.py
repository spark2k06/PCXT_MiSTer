"""Build the packed 320x200x4 CGA splash ROM.

The PowerShell version next to this file performs the same conversion on
Windows without requiring Python or Pillow.  The source artwork remains a
normal PNG so it can be replaced without changing the renderer.
"""

from pathlib import Path

from PIL import Image


WIDTH = 320
HEIGHT = 200
ROOT = Path(__file__).resolve().parents[1]
SOURCE = ROOT / "SW" / "splash_cga_320x200_source.png"
PREVIEW = ROOT / "SW" / "splash_cga_320x200.png"
ROM = ROOT / "rtl" / "video" / "splash_cga_320x200.hex"

# 8-bit equivalents of cga_vgaport's 6-bit RGBI values for 0/C/A/E.
# The order is the semantic source palette: black, red, green, yellow.
PALETTE = (
    (0, 0, 0),
    (255, 0, 0),
    (85, 255, 85),
    (255, 255, 85),
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
    image = Image.open(SOURCE).convert("RGB").resize((WIDTH, HEIGHT), Image.Resampling.NEAREST)
    quantized = Image.new("RGB", (WIDTH, HEIGHT))
    indices = []

    for offset, pixel in enumerate(image.getdata()):
        index = nearest_colour(pixel)
        indices.append(index)
        quantized.putpixel((offset % WIDTH, offset // WIDTH), PALETTE[index])

    quantized.save(PREVIEW)

    rom_lines = []
    for offset in range(0, len(indices), 4):
        packed = (
            (indices[offset] << 6)
            | (indices[offset + 1] << 4)
            | (indices[offset + 2] << 2)
            | indices[offset + 3]
        )
        rom_lines.append(f"{packed:02X}")
    ROM.write_bytes(("\r\n".join(rom_lines) + "\r\n").encode("ascii"))


if __name__ == "__main__":
    main()
