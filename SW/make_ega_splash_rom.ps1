# Pack the quantized EGA splash into a 320x200x16 ROM.
#
# PowerShell equivalent of make_ega_splash_rom.py, for Windows machines without
# Python/Pillow installed. Both scripts produce a byte-identical ROM.
#
# The output stores the left pixel in bits 7:4 and the right pixel in bits 3:0.
# Each palette entry is the conventional EGA DAC color index.

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

Add-Type -AssemblyName System.Drawing

$WIDTH  = 320
$HEIGHT = 200
$EGA_PALETTE = @(
    0x000000,  # 0 black
    0x0000AA,  # 1 blue
    0x00AA00,  # 2 green
    0x00AAAA,  # 3 cyan
    0xAA0000,  # 4 red
    0xAA00AA,  # 5 magenta
    0xAA5500,  # 6 brown
    0xAAAAAA,  # 7 light gray
    0x555555,  # 8 dark gray
    0x5555FF,  # 9 light blue
    0x55FF55,  # A light green
    0x55FFFF,  # B light cyan
    0xFF5555,  # C light red
    0xFF55FF,  # D light magenta
    0xFFFF55,  # E yellow
    0xFFFFFF   # F white
)

$ROOT    = Split-Path -Parent (Split-Path -Parent $MyInvocation.MyCommand.Path)
$PREVIEW = Join-Path $ROOT 'SW\splash_ega_320x200.png'
$ROM     = Join-Path $ROOT 'rtl\video\splash_ega_320x200.hex'

$colorIndex = @{}
for ($index = 0; $index -lt $EGA_PALETTE.Count; $index++) {
    $colorIndex[$EGA_PALETTE[$index]] = $index
}

$image = New-Object System.Drawing.Bitmap $PREVIEW
try {
    if ($image.Width -ne $WIDTH -or $image.Height -ne $HEIGHT) {
        throw "Expected ${WIDTH}x${HEIGHT}, got $($image.Width)x$($image.Height)"
    }

    # LockBits into 32bppArgb so indexed and truecolour PNGs read the same way,
    # and so we walk the raster once instead of making 64000 GetPixel calls.
    $rect = New-Object System.Drawing.Rectangle 0, 0, $WIDTH, $HEIGHT
    $data = $image.LockBits($rect, [System.Drawing.Imaging.ImageLockMode]::ReadOnly,
                            [System.Drawing.Imaging.PixelFormat]::Format32bppArgb)
    try {
        $raw = New-Object byte[] ($data.Stride * $HEIGHT)
        [System.Runtime.InteropServices.Marshal]::Copy($data.Scan0, $raw, 0, $raw.Length)
        $stride = $data.Stride
    } finally {
        $image.UnlockBits($data)
    }
} finally {
    $image.Dispose()
}

$pixels = New-Object int[] ($WIDTH * $HEIGHT)
$next = 0
for ($y = 0; $y -lt $HEIGHT; $y++) {
    $row = $y * $stride
    for ($x = 0; $x -lt $WIDTH; $x++) {
        $offset = $row + $x * 4   # BGRA in memory
        $color = ([int]$raw[$offset + 2] -shl 16) -bor
                 ([int]$raw[$offset + 1] -shl 8)  -bor
                  [int]$raw[$offset]
        if (-not $colorIndex.ContainsKey($color)) {
            throw ("Image contains non-EGA color #{0:X6} at {1},{2}" -f $color, $x, $y)
        }
        $pixels[$next++] = $colorIndex[$color]
    }
}

$packed = New-Object Text.StringBuilder
for ($offset = 0; $offset -lt $WIDTH * $HEIGHT; $offset += 2) {
    [void]$packed.AppendFormat('{0:X2}', (($pixels[$offset] -shl 4) -bor $pixels[$offset + 1]))
    [void]$packed.Append("`r`n")   # matches Path.write_text() newline translation on Windows
}
[IO.File]::WriteAllText($ROM, $packed.ToString(), (New-Object Text.ASCIIEncoding))
