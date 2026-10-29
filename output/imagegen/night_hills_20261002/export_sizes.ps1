param([string]$InputPng='C:/Users/28492/.codex/generated_images/01a08e5b-de68-78f0-88df-03c3e9673619/exec-680eddfa-3dde-48c0-b249-e8b908c295ef.png')
$ErrorActionPreference='Stop'
Add-Type -AssemblyName System.Drawing
$taskSource=[System.Drawing.Image]::FromFile($InputPng)
$taskResults=@()
try {
 if($taskSource.Width*3 -ne $taskSource.Height*4) {throw 'Generated source is not 4:3; cannot export without distortion.'}
 foreach($taskWidth in @(640,1280)) {
  $taskHeight=[int]($taskWidth*3/4)
  $taskPrefix="night_hills_${taskWidth}x${taskHeight}"
  foreach($taskExt in @('bmp','png')) {
   if(Test-Path -LiteralPath (Join-Path $PSScriptRoot "$taskPrefix.$taskExt")) {throw 'Destination exists; will not overwrite.'}
  }
 }
 if(Test-Path -LiteralPath (Join-Path $PSScriptRoot 'night_hills_generated.png')) {throw 'Native output already exists.'}
 foreach($taskWidth in @(640,1280)) {
  $taskHeight=[int]($taskWidth*3/4)
  $taskPrefix="night_hills_${taskWidth}x${taskHeight}"
  $taskBmpPath=Join-Path $PSScriptRoot "$taskPrefix.bmp"
  $taskPngPath=Join-Path $PSScriptRoot "$taskPrefix.png"
  $taskBitmap=[System.Drawing.Bitmap]::new($taskWidth,$taskHeight,[System.Drawing.Imaging.PixelFormat]::Format24bppRgb)
  $taskGraphics=[System.Drawing.Graphics]::FromImage($taskBitmap)
  try {
   $taskGraphics.CompositingMode=[System.Drawing.Drawing2D.CompositingMode]::SourceCopy
   $taskGraphics.CompositingQuality=[System.Drawing.Drawing2D.CompositingQuality]::HighQuality
   $taskGraphics.InterpolationMode=[System.Drawing.Drawing2D.InterpolationMode]::HighQualityBicubic
   $taskGraphics.SmoothingMode=[System.Drawing.Drawing2D.SmoothingMode]::HighQuality
   $taskGraphics.PixelOffsetMode=[System.Drawing.Drawing2D.PixelOffsetMode]::HighQuality
   $taskRect=[System.Drawing.Rectangle]::new(0,0,$taskWidth,$taskHeight)
   $taskGraphics.DrawImage($taskSource,$taskRect,0,0,$taskSource.Width,$taskSource.Height,[System.Drawing.GraphicsUnit]::Pixel)
   $taskBitmap.Save($taskBmpPath,[System.Drawing.Imaging.ImageFormat]::Bmp)
   $taskBitmap.Save($taskPngPath,[System.Drawing.Imaging.ImageFormat]::Png)
  } finally {$taskGraphics.Dispose(); $taskBitmap.Dispose()}
  $taskBytes=[IO.File]::ReadAllBytes($taskBmpPath)
  $taskInfo=[ordered]@{
   bmp=$taskBmpPath; png=$taskPngPath
   magic=[Text.Encoding]::ASCII.GetString($taskBytes,0,2)
   width=[BitConverter]::ToInt32($taskBytes,18); height=[BitConverter]::ToInt32($taskBytes,22)
   pixel_offset=[BitConverter]::ToUInt32($taskBytes,10); dib_bytes=[BitConverter]::ToUInt32($taskBytes,14)
   planes=[BitConverter]::ToUInt16($taskBytes,26); bit_depth=[BitConverter]::ToUInt16($taskBytes,28)
   compression=[BitConverter]::ToUInt32($taskBytes,30); file_bytes=$taskBytes.Length
   sha256=(Get-FileHash -LiteralPath $taskBmpPath -Algorithm SHA256).Hash
  }
  if($taskInfo.magic -ne 'BM' -or $taskInfo.width -ne $taskWidth -or $taskInfo.height -ne $taskHeight -or
     $taskInfo.pixel_offset -ne 54 -or $taskInfo.dib_bytes -ne 40 -or $taskInfo.planes -ne 1 -or
     $taskInfo.bit_depth -ne 24 -or $taskInfo.compression -ne 0 -or
     $taskInfo.file_bytes -ne [BitConverter]::ToUInt32($taskBytes,2) -or
     $taskInfo.file_bytes -ne (54+3*$taskWidth*$taskHeight)) {throw 'BMP failed FPGA format checks.'}
  $taskResults+=$taskInfo
 }
 Copy-Item -LiteralPath $InputPng -Destination (Join-Path $PSScriptRoot 'night_hills_generated.png')
} finally {$taskSource.Dispose()}
$taskResults | ConvertTo-Json -Depth 3 -Compress
