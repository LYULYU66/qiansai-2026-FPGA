$ErrorActionPreference = 'Stop'
Add-Type -AssemblyName System.Drawing
$dest = $PSScriptRoot
$src = 'C:\Users\28492\.codex\generated_images\01a08e5b-de68-78f0-88df-03c3e9673619\exec-b65b98df-f105-4a2e-b0b1-44d2e3cbb9bb.png'
if (Test-Path -LiteralPath (Join-Path $dest 'panorama_1280x480.png')) { throw 'Outputs already exist' }
Copy-Item -LiteralPath $src -Destination (Join-Path $dest 'master.png')
$inputImage = [Drawing.Image]::FromFile($src)
$pan = New-Object Drawing.Bitmap(1280,480,[Drawing.Imaging.PixelFormat]::Format24bppRgb)
$g = [Drawing.Graphics]::FromImage($pan)
$g.InterpolationMode = [Drawing.Drawing2D.InterpolationMode]::HighQualityBicubic
$g.PixelOffsetMode = [Drawing.Drawing2D.PixelOffsetMode]::HighQuality
$g.DrawImage($inputImage,0,0,1280,480)
$g.Dispose()
$inputImage.Dispose()
$pan.Save((Join-Path $dest 'panorama_1280x480.png'),[Drawing.Imaging.ImageFormat]::Png)
foreach ($side in @('A_left','B_right')) {
    $start = 0
    if ($side -eq 'B_right') { $start = 640 }
    $rect = New-Object Drawing.Rectangle($start,0,640,480)
    $part = $pan.Clone($rect,[Drawing.Imaging.PixelFormat]::Format24bppRgb)
    $base = Join-Path $dest ('relax_' + $side + '_640x480')
    $part.Save(($base + '.png'),[Drawing.Imaging.ImageFormat]::Png)
    $part.Save(($base + '.bmp'),[Drawing.Imaging.ImageFormat]::Bmp)
    $bytes = [IO.File]::ReadAllBytes($base + '.bmp')
    if ([BitConverter]::ToInt32($bytes,18) -ne 640 -or [BitConverter]::ToInt32($bytes,22) -ne 480 -or [BitConverter]::ToUInt16($bytes,28) -ne 24 -or [BitConverter]::ToInt32($bytes,30) -ne 0) { throw 'Invalid BMP format' }
    for ($y=0; $y -lt 480; $y++) {
        for ($x=0; $x -lt 640; $x++) {
            if ($part.GetPixel($x,$y).ToArgb() -ne $pan.GetPixel($x+$start,$y).ToArgb()) { throw 'Split verification failed' }
        }
    }
    $part.Dispose()
    Write-Output ($side + ': 640x480 24-bit BI_RGB; panorama split pixel-identical; bytes=' + $bytes.Length)
}
$pan.Dispose()
