$ErrorActionPreference = 'Stop'
Add-Type -AssemblyName System.Drawing

$assetDir = $PSScriptRoot
$sourceFile = 'C:\Users\28492\.codex\generated_images\01a08e5b-de68-78f0-88df-03c3e9673619\exec-baa26642-efd3-4a48-af3e-1a3714f6f43b.png'
$masterFile = Join-Path $assetDir 'instrument_background_master.png'
$pngFile = Join-Path $assetDir 'instrument_background_640x480.png'
$bmpFile = Join-Path $assetDir 'instrument_background_640x480.bmp'
foreach ($assetFile in @($masterFile, $pngFile, $bmpFile)) {
    if (Test-Path -LiteralPath $assetFile) { throw "Refusing to overwrite existing asset: $assetFile" }
}

Copy-Item -LiteralPath $sourceFile -Destination $masterFile
$sourceImage = [System.Drawing.Image]::FromFile($masterFile)
$exportImage = $null
$graphics = $null
$attributes = $null
try {
    if (($sourceImage.Width * 3) -ne ($sourceImage.Height * 4)) {
        throw "Source must be exactly 4:3; got $($sourceImage.Width)x$($sourceImage.Height)"
    }
    $exportImage = New-Object System.Drawing.Bitmap(640, 480, [System.Drawing.Imaging.PixelFormat]::Format24bppRgb)
    $graphics = [System.Drawing.Graphics]::FromImage($exportImage)
    $graphics.CompositingQuality = [System.Drawing.Drawing2D.CompositingQuality]::HighQuality
    $graphics.InterpolationMode = [System.Drawing.Drawing2D.InterpolationMode]::HighQualityBicubic
    $graphics.PixelOffsetMode = [System.Drawing.Drawing2D.PixelOffsetMode]::HighQuality
    $attributes = New-Object System.Drawing.Imaging.ImageAttributes
    $attributes.SetWrapMode([System.Drawing.Drawing2D.WrapMode]::TileFlipXY)
    $rectangle = New-Object System.Drawing.Rectangle(0, 0, 640, 480)
    $graphics.DrawImage($sourceImage, $rectangle, 0, 0, $sourceImage.Width, $sourceImage.Height, [System.Drawing.GraphicsUnit]::Pixel, $attributes)
    $exportImage.Save($pngFile, [System.Drawing.Imaging.ImageFormat]::Png)
    $exportImage.Save($bmpFile, [System.Drawing.Imaging.ImageFormat]::Bmp)
} finally {
    if ($attributes) { $attributes.Dispose() }
    if ($graphics) { $graphics.Dispose() }
    if ($exportImage) { $exportImage.Dispose() }
    $sourceImage.Dispose()
}

$bmpBytes = [System.IO.File]::ReadAllBytes($bmpFile)
$width = [BitConverter]::ToInt32($bmpBytes, 18)
$height = [BitConverter]::ToInt32($bmpBytes, 22)
$bits = [BitConverter]::ToUInt16($bmpBytes, 28)
$compression = [BitConverter]::ToUInt32($bmpBytes, 30)
if ($width -ne 640 -or $height -ne 480 -or $bits -ne 24 -or $compression -ne 0) {
    throw "Unexpected BMP encoding: ${width}x${height}, ${bits}bpp, compression=$compression"
}
[PSCustomObject]@{
    BMP = $bmpFile
    PNG = $pngFile
    Master = $masterFile
    Width = $width
    Height = $height
    BitsPerPixel = $bits
    Compression = $compression
    BMPBytes = $bmpBytes.Length
} | ConvertTo-Json
Get-FileHash -LiteralPath $bmpFile, $pngFile, $masterFile -Algorithm SHA256 | Format-Table -AutoSize
