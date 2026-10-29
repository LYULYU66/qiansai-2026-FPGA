param(
    [string]$ModelSimBin = 'C:\intelFPGA\18.1\modelsim_ase\win32aloem',
    [string]$PythonExe = 'C:\Users\28492\.cache\codex-runtimes\codex-primary-runtime\dependencies\python\python.exe'
)
$ErrorActionPreference = 'Stop'
$projectRoot = Split-Path -Parent $PSScriptRoot
Push-Location -LiteralPath $projectRoot
try {
    $outDir = 'sim/vehicle_warning_4dir_20260930'
    $workLib = "$outDir/intel_work"
    New-Item -ItemType Directory -Force $outDir | Out-Null
    if (-not (Test-Path -LiteralPath "$workLib/_info")) {
        & "$ModelSimBin/vlib.exe" $workLib
        if ($LASTEXITCODE -ne 0) { throw 'ModelSim library creation failed' }
    }
    $sourceFiles = @(
        'src/user_source/hdl_source/video_transition_effects.v',
        'src/user_source/hdl_source/vehicle_hazard_overlay.v',
        'src/user_source/hdl_source/alarm_switch_control.v',
        'src/user_source/hdl_source/audio_alarm_mixer.v',
        'src/user_source/hdl_source/osd_alpha_overlay.v',
        'src/user_source/hdl_source/audio_visualizer_overlay.v',
        'src/user_source/hdl_source/SD/sd_card_bmp.v',
        'src/user_source/hdl_source/SD/frame_fifo_read.v',
        'sim/resource_followup_20260927/baseline/video_transition_effects.v',
        'sim/tb_alarm_switch_control.v',
        'sim/tb_vehicle_hazard_overlay.v',
        'sim/tb_video_transition_effects.v',
        'sim/tb_sd_card_bmp_playback.v',
        'sim/tb_warning_preload.v',
        'sim/tb_warning_direct_switch.v',
        'sim/tb_transition_resource_equivalence.sv',
        'sim/tb_vehicle_warning_page.v',
        'sim/tb_audio_alarm_mixer.v'
    )
    & "$ModelSimBin/vlog.exe" -sv -suppress 2600 -work $workLib @sourceFiles
    if ($LASTEXITCODE -ne 0) { throw 'ModelSim compilation failed' }
    foreach ($testName in @(
        'tb_alarm_switch_control', 'tb_vehicle_hazard_overlay',
        'tb_video_transition_effects', 'tb_sd_card_bmp_playback',
        'tb_warning_preload', 'tb_warning_direct_switch',
        'tb_transition_resource_equivalence', 'tb_vehicle_warning_page',
        'tb_audio_alarm_mixer'
    )) {
        $doFile = if ($testName -eq 'tb_warning_direct_switch') {
            'sim/run_modelsim_warning_direct.do'
        } else { 'sim/run_modelsim_vehicle_warning.do' }
        & "$ModelSimBin/vsim.exe" -c -lib $workLib $testName `
            -wlf "$outDir/$testName.wlf" -l "$outDir/$testName.log" -do $doFile
        if ($LASTEXITCODE -ne 0) { throw "Failed: $testName" }
        if (-not (Select-String -LiteralPath "$outDir/$testName.log" -SimpleMatch '# PASS')) {
            throw "No PASS result: $testName"
        }
    }
    & $PythonExe sim/check_warning_font_32.py
    if ($LASTEXITCODE -ne 0) { throw 'Font/pixel comparison failed' }
    Write-Host 'PASS all nine ModelSim regressions and independent font pixel check'
} finally {
    Pop-Location
}
