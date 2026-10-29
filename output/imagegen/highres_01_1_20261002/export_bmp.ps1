param(
 [string]$InputPng='C:/Users/28492/.codex/generated_images/01a08e5b-de68-78f0-88df-03c3e9673619/exec-ffc48c2c-c774-47c4-abe3-e89ab54fb820.png',
 [int]$Width=1280,
 [int]$Height=960
)
$ErrorActionPreference='Stop'
Add-Type -AssemblyName System.Drawing
$taskBmpPath=Join-Path $PSScriptRoot "01_1_${Width}x${Height}.bmp"
$taskPngPath=Join-Path $PSScriptRoot '01_1_highres_generated.png'
if((Test-Path -LiteralPath $taskBmpPath) -or (Test-Path -LiteralPath $taskPngPath)) {
 throw 'Destination exists; will not overwrite an existing image.'
}
$taskSource=[System.Drawing.Image]::FromFile($InputPng)
$taskBitmap=$null
$taskGraphics=$null
try {
 $taskBitmap=[System.Drawing.Bitmap]::new($Width,$Height,[System.Drawing.Imaging.PixelFormat]::Format24bppRgb)
 $taskGraphics=[System.Drawing.Graphics]::FromImage($taskBitmap)
 $taskGraphics.CompositingMode=[System.Drawing.Drawing2D.CompositingMode]::SourceCopy
 $taskGraphics.CompositingQuality=[System.Drawing.Drawing2D.CompositingQuality]::HighQuality
 $taskGraphics.InterpolationMode=[System.Drawing.Drawing2D.InterpolationMode]::HighQualityBicubic
 $taskGraphics.SmoothingMode=[System.Drawing.Drawing2D.SmoothingMode]::HighQuality
 $taskGraphics.PixelOffsetMode=[System.Drawing.Drawing2D.PixelOffsetMode]::HighQuality
 $taskRect=[System.Drawing.Rectangle]::new(0,0,$Width,$Height)
 $taskGraphics.DrawImage($taskSource,$taskRect,0,0,$taskSource.Width,$taskSource.Height,[System.Drawing.GraphicsUnit]::Pixel)
 $taskBitmap.Save($taskBmpPath,[System.Drawing.Imaging.ImageFormat]::Bmp)
 Copy-Item -LiteralPath $InputPng -Destination $taskPngPath
} finally {
 if($taskGraphics) {$taskGraphics.Dispose()}
 if($taskBitmap) {$taskBitmap.Dispose()}
 $taskSource.Dispose()
}
$taskBytes=[IO.File]::ReadAllBytes($taskBmpPath)
$taskInfo=[ordered]@{
 path=$taskBmpPath
 magic=[Text.Encoding]::ASCII.GetString($taskBytes,0,2)
 file_bytes=$taskBytes.Length
 declared_bytes=[BitConverter]::ToUInt32($taskBytes,2)
 pixel_offset=[BitConverter]::ToUInt32($taskBytes,10)
 dib_bytes=[BitConverter]::ToUInt32($taskBytes,14)
 width=[BitConverter]::ToInt32($taskBytes,18)
 height=[BitConverter]::ToInt32($taskBytes,22)
 planes=[BitConverter]::ToUInt16($taskBytes,26)
 bit_depth=[BitConverter]::ToUInt16($taskBytes,28)
 compression=[BitConverter]::ToUInt32($taskBytes,30)
 sha256=(Get-FileHash -LiteralPath $taskBmpPath -Algorithm SHA256).Hash
}
if($taskInfo.magic -ne 'BM' -or $taskInfo.width -ne $Width -or $taskInfo.height -ne $Height -or
 $taskInfo.bit_depth -ne 24 -or $taskInfo.compression -ne 0 -or $taskInfo.planes -ne 1 -or
 $taskInfo.pixel_offset -ne 54 -or $taskInfo.file_bytes -ne $taskInfo.declared_bytes -or
 $taskInfo.file_bytes -ne (54+((3*$Width+3)-band(-bnot 3))*$Height)) {
 throw 'Exported BMP failed FPGA format checks.'
}
$taskInfo | ConvertTo-Json -Compress
