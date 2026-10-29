$ErrorActionPreference = 'Stop'
Push-Location (Split-Path -Parent $PSScriptRoot)
try {
    $iv = 'C:\iverilog\bin\iverilog.exe'
    $vvp = 'C:\iverilog\bin\vvp.exe'
    $hdl = 'src/user_source/hdl_source'
    & $iv -g2012 -s tb_uart_audio_control -o sim/uart_pixel_diag_test.vvp sim/tb_uart_audio_control.v "$hdl/uart_audio_control.v" "$hdl/uart_baud_tick.v" "$hdl/uart_rx.v" "$hdl/uart_tx.v"
    if ($LASTEXITCODE -ne 0) { throw 'UART compilation failed' }
    & $vvp sim/uart_pixel_diag_test.vvp
    if ($LASTEXITCODE -ne 0) { throw 'UART regression failed' }
    & $iv -g2012 -s tb_video_pixel_diagnostics -o sim/pixel_diag_test.vvp sim/tb_video_pixel_diagnostics.v "$hdl/video_pixel_diagnostics.v" "$hdl/video_image_adjust.v"
    if ($LASTEXITCODE -ne 0) { throw 'Pixel diagnostics compilation failed' }
    & $vvp sim/pixel_diag_test.vvp
    if ($LASTEXITCODE -ne 0) { throw 'Pixel diagnostics regression failed' }
    foreach ($crcBench in @('tb_video_frame_crc_monitor','tb_video_frame_crc_full')) {
        & $iv -g2012 -s $crcBench -o "sim/$crcBench.vvp" sim/tb_video_frame_crc_monitor.v "$hdl/video_pixel_diagnostics.v"
        if ($LASTEXITCODE -ne 0) { throw "CRC compilation failed: $crcBench" }
        & $vvp "sim/$crcBench.vvp"
        if ($LASTEXITCODE -ne 0) { throw "CRC regression failed: $crcBench" }
    }
    & $iv -g2012 -s tb_video_rgb_to_axis_640x480 -o sim/video_rgb_to_axis_test.vvp sim/tb_video_rgb_to_axis_640x480.v "$hdl/video_rgb_to_axis_640x480.v"
    if ($LASTEXITCODE -ne 0) { throw 'AXIS compilation failed' }
    & $vvp sim/video_rgb_to_axis_test.vvp
    if ($LASTEXITCODE -ne 0) { throw 'AXIS baseline regression failed' }
    & $iv -g2012 -s frame_read_write -o sim/frame_diag_compile.vvp "$hdl/SD/frame_read_write.v" "$hdl/SD/frame_fifo_read.v" "$hdl/SD/frame_fifo_write.v" "$hdl/IP/afifo_32_16_256.v" "$hdl/IP/afifo_16_32_256.v"
    if ($LASTEXITCODE -ne 0) { throw 'Frame read/write elaboration failed' }
} finally { Pop-Location }
