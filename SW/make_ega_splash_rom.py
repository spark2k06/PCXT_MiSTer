"""Pack the quantized EGA splash into a 320x200x16 ROM.

The output stores the left pixel in bits 7:4 and the right pixel in bits 3:0.
Each palette entry is the conventional EGA DAC color index.
"""

from pathlib import Path

from PIL import Image


WIDTH = 320
HEIGHT = 200
EGA_PALETTE = [
    (0x00, 0x00, 0x00),  # 0 black
    (0x00, 0x00, 0xAA),  # 1 blue
    (0x00, 0xAA, 0x00),  # 2 green
    (0x00, 0xAA, 0xAA),  # 3 cyan
    (0xAA, 0x00, 0x00),  # 4 red
    (0xAA, 0x00, 0xAA),  # 5 magenta
    (0xAA, 0x55, 0x00),  # 6 brown
    (0xAA, 0xAA, 0xAA),  # 7 light gray
    (0x55, 0x55, 0x55),  # 8 dark gray
    (0x55, 0x55, 0xFF),  # 9 light blue
    (0x55, 0xFF, 0x55),  # A light green
    (0x55, 0xFF, 0xFF),  # B light cyan
    (0xFF, 0x55, 0x55),  # C light red
    (0xFF, 0x55, 0xFF),  # D light magenta
    (0xFF, 0xFF, 0x55),  # E yellow
    (0xFF, 0xFF, 0xFF),  # F white
]

ROOT = Path(__file__).resolve().parents[1]
PREVIEW = ROOT / "SW" / "splash_ega_320x200.png"
ROM = ROOT / "rtl" / "video" / "splash_ega_320x200.hex"


def main() -> None:
    image = Image.open(PREVIEW).convert("RGB")
    if image.size != (WIDTH, HEIGHT):
        raise ValueError(f"Expected {WIDTH}x{HEIGHT}, got {image.size}")

    color_index = {color: index for index, color in enumerate(EGA_PALETTE)}
    pixels = []
    for color in image.getdata():
        try:
            pixels.append(color_index[color])
        except KeyError as error:
            raise ValueError(f"Image contains non-EGA color {color}") from error
    packed = bytes(
        (pixels[offset] << 4) | pixels[offset + 1]
        for offset in range(0, WIDTH * HEIGHT, 2)
    )
    assert len(packed) == WIDTH * HEIGHT // 2
    ROM.write_text("\n".join(f"{value:02X}" for value in packed) + "\n", encoding="ascii")


if __name__ == "__main__":
    main()
