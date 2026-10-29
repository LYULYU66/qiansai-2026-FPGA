param([string]$ModelSim = 'C:\intelFPGA\18.1\modelsim_ase\win32aloem', [string[]]$Only = @(),
      [string]$OutputRoot = 'sim/resource_global_20260927')
$ErrorActionPreference = 'Stop'
$projectRoot = Split-Path $PSScriptRoot -Parent
Set-Location $projectRoot
$hdl = 'src/user_source/hdl_source'
$outputRoot = $OutputRoot
$referenceRoot = 'sim/resource_global_20260927'
$cases = @()
foreach ($name in @('alarm_switch_control','audio_alarm_mixer','audio_visualizer_overlay',
    'video_image_adjust','video_status_overlay','video_home_overlay','osd_alpha_overlay',
    'vehicle_hazard_overlay','video_transition_effects','video_frame_valid_gate',
    'video_rgb_to_axis_640x480')) {
    $cases += @{Top="tb_$name"; Files=@("$hdl/$name.v", "sim/tb_$name.v")}
}
$homeCase = $cases | Where-Object { $_.Top -eq 'tb_video_home_overlay' }
$homeCase.Files = @("$hdl/video_album_cover_rom.v", "$hdl/video_app_icons_rom.v", "$hdl/video_home_overlay.v", 'sim/tb_video_home_overlay.v')
$cases += @{Top='tb_home_navigation_card'; Flags='-sv'; Files=@("$hdl/video_album_cover_rom.v", "$hdl/video_app_icons_rom.v", "$hdl/video_home_overlay.v", 'sim/resource_opt_20260928/baseline/video_home_overlay.v', 'sim/tb_home_navigation_card.sv')}
$cases += @{Top='tb_home_dashboard_combined'; Flags='-sv'; Files=@("$hdl/video_status_overlay.v", "$hdl/video_album_cover_rom.v", "$hdl/video_app_icons_rom.v", "$hdl/video_home_overlay.v", 'sim/tb_home_dashboard_combined.sv')}
$cases += @{Top='tb_video_pixel_diagnostics'; Files=@("$hdl/video_pixel_diagnostics.v","$hdl/video_image_adjust.v",'sim/tb_video_pixel_diagnostics.v')}
$cases += @{Top='tb_video_frame_crc_monitor'; Files=@("$hdl/video_pixel_diagnostics.v",'sim/tb_video_frame_crc_monitor.v')}
$cases += @{Top='tb_audio_spectrum_analyzer'; Files=@("$hdl/audio_spectrum_analyzer.v",'sim/tb_audio_spectrum_analyzer.sv')}
$cases += @{Top='tb_audio_waveform_analyzer'; Files=@("$hdl/audio_waveform_analyzer.v",'sim/tb_audio_waveform_analyzer.sv')}
$cases += @{Top='tb_audio_visual_volume_mapping'; Files=@("$hdl/audio_visualizer_overlay.v",'sim/tb_audio_visual_volume_mapping.v')}
$cases += @{Top='tb_uart_audio_control'; Files=@("$hdl/uart_audio_control.v","$hdl/uart_baud_tick.v","$hdl/uart_rx.v","$hdl/uart_tx.v",'sim/tb_uart_audio_control.v')}
$cases += @{Top='tb_hdmi_audio_pcm_i2s'; Flags='-sv'; Files=@("$hdl/hdmi_audio_pcm_i2s_64fs.v","$hdl/I2S_receiver.v",'sim/tb_hdmi_audio_pcm_i2s.v')}
$cases += @{Top='tb_hdmi_audio_chain'; Files=@("$hdl/hdmi_audio_tone_i2s_64fs.v","$hdl/I2S_receiver.v","$hdl/audio_arc_calculate.v",'sim/tb_hdmi_audio_chain.v')}
$cases += @{Top='tb_bmp_pcm_stream'; Files=@("$hdl/SD/bmp_read.v",'sim/tb_bmp_pcm_stream.v')}
$cases += @{Top='tb_sd_card_bmp_playback'; Files=@("$hdl/SD/sd_card_bmp.v",'sim/tb_sd_card_bmp_playback.v')}
$cases += @{Top='tb_audio_spectrum_resource_equivalence'; Files=@("$hdl/audio_spectrum_analyzer.v","$referenceRoot/baseline/audio_spectrum_analyzer.v",'sim/tb_audio_spectrum_resource_equivalence.sv')}
$cases += @{Top='tb_bmp_resource_equivalence'; Files=@("$hdl/SD/bmp_read.v","$referenceRoot/baseline/bmp_read.v",'sim/tb_bmp_resource_equivalence.sv')}
$cases += @{Top='tb_visualizer_resource_equivalence'; Files=@("$hdl/audio_visualizer_overlay.v","$referenceRoot/baseline/audio_visualizer_overlay.v",'sim/tb_visualizer_resource_equivalence.sv')}
$cases += @{Top='tb_waveform_resource_equivalence'; Files=@("$hdl/audio_waveform_analyzer.v",'sim/resource_followup_20260927/baseline/audio_waveform_analyzer.v','sim/tb_waveform_resource_equivalence.sv')}
$cases += @{Top='tb_transition_resource_equivalence'; Files=@("$hdl/video_transition_effects.v",'sim/resource_followup_20260927/baseline/video_transition_effects.v','sim/tb_transition_resource_equivalence.sv')}
$cases += @{Top='tb_visualizer_sequencer_equivalence'; Files=@("$hdl/audio_visualizer_overlay.v",'sim/resource_followup_20260927/baseline/audio_visualizer_overlay.v','sim/tb_visualizer_sequencer_equivalence.sv')}
$failures = @()
if ($Only.Count) { $cases = @($cases | Where-Object { $_.Top -in $Only }) }
if (!$cases.Count) { throw 'No matching regression cases; check -Only test names.' }
foreach ($test in $cases) {
    $name=$test.Top
    $library="$outputRoot/$name"
    if (!(Test-Path $library)) {
        & "$ModelSim/vlib.exe" $library | Out-Null
        if ($LASTEXITCODE -ne 0) { throw "vlib failed: $name" }
    }
    $files=($test.Files | ForEach-Object { '{'+$_+'}' }) -join ' '
    $flags=$test.Flags
    $commands="if {[catch {vlog $flags -work {$library} $files}]} {quit -code 1 -f}; if {[catch {vsim -c -lib {$library} $name}]} {quit -code 1 -f}; run -all; quit -f"
    $log="$outputRoot/$name.log"
    $lines = & "$ModelSim/vsim.exe" -c -l $log -do $commands 2>&1
    $exitCode=$LASTEXITCODE
    $text=$lines -join "`n"
    if ($exitCode -ne 0 -or $text -match '(\*\* (Error|Fatal):|\bFAIL\b)' -or $text -notmatch '\bPASS\b') {
        $failures += $name
        Write-Output "FAILED $name : $log"
        $lines | Select-Object -Last 12 | Write-Output
    } else {
        Write-Output "PASSED $name"
    }
}
Write-Output ("RESULT {0}/{1} passed" -f ($cases.Count-$failures.Count),$cases.Count)
if ($failures.Count) { throw ('Regression failed: '+($failures -join ', ')) }
