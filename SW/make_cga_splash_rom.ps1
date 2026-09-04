# Convert the graphical splash into the packed 320x200x4 CGA ROM.
#
# The source is deliberately kept as a normal PNG so it can be replaced by a
# future artwork revision.  The generated preview shows the exact four RGB
# colours used by the CGA RGBI decoder, while the ROM stores four 2-bit pixels
# per byte, from the leftmost pixel in bits 7:6 to the rightmost in bits 1:0.

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

Add-Type -AssemblyName System.Drawing

$WIDTH = 320
$HEIGHT = 200
$ROOT = Split-Path -Parent (Split-Path -Parent $MyInvocation.MyCommand.Path)
$SOURCE = Join-Path $ROOT 'SW\splash_cga_320x200_source.png'
$PREVIEW = Join-Path $ROOT 'SW\splash_cga_320x200.png'
$ROM = Join-Path $ROOT 'rtl\video\splash_cga_320x200.hex'

# These are the 8-bit equivalents of cga_vgaport's 6-bit RGBI values:
# 0 = black, C = bright red, A = bright green, E = yellow.
$PALETTE = @(
    [System.Drawing.Color]::FromArgb(0, 0, 0),
    [System.Drawing.Color]::FromArgb(255, 0, 0),
    [System.Drawing.Color]::FromArgb(85, 255, 85),
    [System.Drawing.Color]::FromArgb(255, 255, 85)
)

$sourceImage = [System.Drawing.Bitmap]::new($SOURCE)
$scaledImage = [System.Drawing.Bitmap]::new(
    $WIDTH,
    $HEIGHT,
    [System.Drawing.Imaging.PixelFormat]::Format24bppRgb
)
$graphics = $null

try {
    $graphics = [System.Drawing.Graphics]::FromImage($scaledImage)
    $graphics.InterpolationMode = [System.Drawing.Drawing2D.InterpolationMode]::NearestNeighbor
    $graphics.PixelOffsetMode = [System.Drawing.Drawing2D.PixelOffsetMode]::Half
    $graphics.CompositingMode = [System.Drawing.Drawing2D.CompositingMode]::SourceCopy
    $destination = [System.Drawing.Rectangle]::new(0, 0, $WIDTH, $HEIGHT)
    $graphics.DrawImage(
        $sourceImage,
        $destination,
        0,
        0,
        $sourceImage.Width,
        $sourceImage.Height,
        [System.Drawing.GraphicsUnit]::Pixel
    )

    $pixels = New-Object int[] ($WIDTH * $HEIGHT)
    $pixelNumber = 0
    for ($y = 0; $y -lt $HEIGHT; $y++) {
        for ($x = 0; $x -lt $WIDTH; $x++) {
            $sourceColor = $scaledImage.GetPixel($x, $y)
            $bestIndex = 0
            $bestDistance = [double]::PositiveInfinity
            for ($paletteIndex = 0; $paletteIndex -lt $PALETTE.Count; $paletteIndex++) {
                $paletteColor = $PALETTE[$paletteIndex]
                $dr = $sourceColor.R - $paletteColor.R
                $dg = $sourceColor.G - $paletteColor.G
                $db = $sourceColor.B - $paletteColor.B
                $distance = ($dr * $dr) + ($dg * $dg) + ($db * $db)
                if ($distance -lt $bestDistance) {
                    $bestDistance = $distance
                    $bestIndex = $paletteIndex
                }
            }

            $pixels[$pixelNumber++] = $bestIndex
            $scaledImage.SetPixel($x, $y, $PALETTE[$bestIndex])
        }
    }

    $scaledImage.Save($PREVIEW, [System.Drawing.Imaging.ImageFormat]::Png)

    $romText = [System.Text.StringBuilder]::new()
    for ($offset = 0; $offset -lt $pixels.Length; $offset += 4) {
        $packed = ($pixels[$offset] -shl 6) -bor
                  ($pixels[$offset + 1] -shl 4) -bor
                  ($pixels[$offset + 2] -shl 2) -bor
                  $pixels[$offset + 3]
        [void]$romText.AppendFormat('{0:X2}', $packed)
        [void]$romText.Append("`r`n")
    }
    [System.IO.File]::WriteAllText($ROM, $romText.ToString(), [System.Text.Encoding]::ASCII)
}
finally {
    if ($null -ne $graphics) { $graphics.Dispose() }
    $scaledImage.Dispose()
    $sourceImage.Dispose()
}

Write-Host ("Generated {0} and {1}" -f $PREVIEW, $ROM)
