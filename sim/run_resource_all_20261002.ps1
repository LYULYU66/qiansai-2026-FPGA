param(
    [string]$ModelSimBin='C:\intelFPGA\18.1\modelsim_ase\win32aloem',
    [string]$PythonExe='C:\Users\28492\.cache\codex-runtimes\codex-primary-runtime\dependencies\python\python.exe'
)
$ErrorActionPreference='Stop'
$projectRoot=Split-Path -Parent $PSScriptRoot
Push-Location -LiteralPath $projectRoot
try {
    $core=@('tb_alarm_switch_control','tb_audio_alarm_mixer','tb_audio_visualizer_overlay',
        'tb_video_image_adjust','tb_video_status_overlay','tb_osd_alpha_overlay',
        'tb_video_frame_valid_gate','tb_video_rgb_to_axis_640x480',
        'tb_video_pixel_diagnostics','tb_video_frame_crc_monitor',
        'tb_audio_spectrum_analyzer','tb_audio_waveform_analyzer','tb_audio_visual_volume_mapping',
        'tb_uart_audio_control','tb_hdmi_audio_pcm_i2s','tb_hdmi_audio_chain',
        'tb_bmp_pcm_stream','tb_sd_card_bmp_playback','tb_audio_spectrum_resource_equivalence',
        'tb_bmp_resource_equivalence','tb_waveform_resource_equivalence')
    & "$PSScriptRoot/run_resource_regression.ps1" -ModelSim $ModelSimBin -Only $core -OutputRoot sim/resource_all_20261002
    & "$PSScriptRoot/run_modelsim_warning_4dir.ps1" -ModelSimBin $ModelSimBin -PythonExe $PythonExe
    & "$PSScriptRoot/run_modelsim_home_light.ps1" -ModelSimBin $ModelSimBin -PythonExe $PythonExe
    & "$PSScriptRoot/run_modelsim_lyrics.ps1" -ModelSimBin $ModelSimBin
    & "$PSScriptRoot/run_bram32_font_probe.ps1" -ModelSimBin $ModelSimBin
    & $PythonExe "$PSScriptRoot/check_lyric_smooth_pixels.py"
    if($LASTEXITCODE -ne 0) { throw 'Independent lyric/font/init pixel check failed' }
    & "$PSScriptRoot/run_resource_all_extra_20261002.ps1" -ModelSimBin $ModelSimBin
    & $PythonExe "$PSScriptRoot/check_resource_all_logs_20261002.py"
    if($LASTEXITCODE -ne 0) { throw '42-bench release log gate failed' }
    Write-Output 'PASS complete resource regression: 42 distinct ModelSim benches, 4 independent asset/pixel checks; no removed features'
} finally { Pop-Location }
