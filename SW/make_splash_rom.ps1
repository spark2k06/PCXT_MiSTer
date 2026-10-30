# Convert the boot splash into the packed 320x200, 16-colour ROM.
#
# Same conversion as make_splash_rom.py, for Windows without Python or Pillow.
# Every pixel of SW\splash_320x200_source.png is mapped to the nearest of the
# 16 CGA/EGA RGBI colours; the ROM stores two 4-bit RGBI indexes per byte, the
# left pixel in bits 7:4, 160 bytes per line.  The preview shows the result at
# 4:3, as a monitor shows a 320x200 picture.

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

Add-Type -AssemblyName System.Drawing

$WIDTH = 320
$HEIGHT = 200
$ROOT = Split-Path -Parent (Split-Path -Parent $MyInvocation.MyCommand.Path)
$SOURCE = Join-Path $ROOT 'SW\splash_320x200_source.png'
$PREVIEW = Join-Path $ROOT 'SW\splash_320x200_preview.png'
$ROM = Join-Path $ROOT 'rtl\video\splash_320x200.hex'

# 8-bit equivalents of the RGBI colours, in RGBI index order.
$PALETTE = @(
    @(0x00, 0x00, 0x00), @(0x00, 0x00, 0xAA), @(0x00, 0xAA, 0x00), @(0x00, 0xAA, 0xAA),
    @(0xAA, 0x00, 0x00), @(0xAA, 0x00, 0xAA), @(0xAA, 0x55, 0x00), @(0xAA, 0xAA, 0xAA),
    @(0x55, 0x55, 0x55), @(0x55, 0x55, 0xFF), @(0x55, 0xFF, 0x55), @(0x55, 0xFF, 0xFF),
    @(0xFF, 0x55, 0x55), @(0xFF, 0x55, 0xFF), @(0xFF, 0xFF, 0x55), @(0xFF, 0xFF, 0xFF)
)

$sourceImage = [System.Drawing.Bitmap]::new($SOURCE)
if ($sourceImage.Width -ne $WIDTH -or $sourceImage.Height -ne $HEIGHT) {
    throw "The source must be ${WIDTH}x${HEIGHT}, not $($sourceImage.Width)x$($sourceImage.Height)"
}
$previewImage = [System.Drawing.Bitmap]::new($WIDTH * 4, [int]($HEIGHT * 24 / 5))

try {
    $indices = New-Object int[] ($WIDTH * $HEIGHT)
    for ($y = 0; $y -lt $HEIGHT; $y++) {
        for ($x = 0; $x -lt $WIDTH; $x++) {
            $c = $sourceImage.GetPixel($x, $y)
            $best = 0
            $bestDistance = [double]::PositiveInfinity
            for ($i = 0; $i -lt 16; $i++) {
                $dr = $c.R - $PALETTE[$i][0]
                $dg = $c.G - $PALETTE[$i][1]
                $db = $c.B - $PALETTE[$i][2]
                $distance = $dr * $dr + $dg * $dg + $db * $db
                if ($distance -lt $bestDistance) {
                    $best = $i
                    $bestDistance = $distance
                }
            }
            $indices[$y * $WIDTH + $x] = $best
        }
    }

    # 4:3 preview: each source pixel is 4 wide and 4.8 tall
    for ($py = 0; $py -lt $previewImage.Height; $py++) {
        $sy = [int][math]::Floor(($py + 0.5) * 5 / 24)
        for ($px = 0; $px -lt $previewImage.Width; $px++) {
            $p = $PALETTE[$indices[$sy * $WIDTH + [int][math]::Floor($px / 4)]]
            $previewImage.SetPixel($px, $py, [System.Drawing.Color]::FromArgb($p[0], $p[1], $p[2]))
        }
    }
    $previewImage.Save($PREVIEW, [System.Drawing.Imaging.ImageFormat]::Png)

    $lines = New-Object string[] ($WIDTH * $HEIGHT / 2)
    for ($i = 0; $i -lt $lines.Count; $i++) {
        $lines[$i] = '{0:X2}' -f (($indices[2 * $i] -shl 4) -bor $indices[2 * $i + 1])
    }
    [System.IO.File]::WriteAllText($ROM, ($lines -join "`r`n") + "`r`n", [System.Text.Encoding]::ASCII)
}
finally {
    $previewImage.Dispose()
    $sourceImage.Dispose()
}
