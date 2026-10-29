$ErrorActionPreference = 'Stop'
$projectRoot = Split-Path -Parent $PSScriptRoot
Push-Location $projectRoot
try {
    $iv = 'C:\iverilog\bin\iverilog.exe'
    $vvp = 'C:\iverilog\bin\vvp.exe'
    $hdl = 'src/user_source/hdl_source'
    & $iv -g2012 -s tb_video_sof_boundaries -o sim/sof_boundaries_test.vvp sim/tb_video_sof_boundaries.v "$hdl/video_rgb_to_axis_640x480.v"
    if ($LASTEXITCODE -ne 0) { throw 'SOF compile failed' }
    & $vvp sim/sof_boundaries_test.vvp
    if ($LASTEXITCODE -ne 0) { throw 'SOF regression failed' }
    & $iv -g2012 -s tb_video_source_sof -o sim/source_sof_test.vvp sim/tb_video_source_sof.v "$hdl/video_source_test.v"
    if ($LASTEXITCODE -ne 0) { throw 'Test source compile failed' }
    & $vvp sim/source_sof_test.vvp
    if ($LASTEXITCODE -ne 0) { throw 'Test source regression failed' }
    & $iv -g2012 -s tb_video_fifo_alignment -o sim/fifo_alignment_test.vvp sim/tb_video_fifo_alignment.v "$hdl/SD/frame_fifo_read.v" "$hdl/SD/video_delay.v" "$hdl/IP/afifo_32_16_256.v"
    if ($LASTEXITCODE -ne 0) { throw 'FIFO compile failed' }
    & $vvp sim/fifo_alignment_test.vvp
    if ($LASTEXITCODE -ne 0) { throw 'FIFO regression failed' }
    & $vvp sim/fifo_alignment_test.vvp +STARVE
    if ($LASTEXITCODE -ne 0) { throw 'Starvation detection failed' }
} finally { Pop-Location }
