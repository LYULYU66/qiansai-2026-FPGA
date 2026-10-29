param([string]$ModelSimBin='C:\intelFPGA\18.1\modelsim_ase\win32aloem')
$ErrorActionPreference='Stop'
$projectRoot=Split-Path -Parent $PSScriptRoot
Push-Location -LiteralPath $projectRoot
try {
    $outDir='sim/resource_all_20261002'
    $lib="$outDir/latest_equivalence"
    New-Item -ItemType Directory -Force $outDir | Out-Null
    if(-not(Test-Path -LiteralPath "$lib/_info")) { & "$ModelSimBin/vlib.exe" $lib }
    $hdl='src/user_source/hdl_source'
    & "$ModelSimBin/vlog.exe" -sv -suppress 2600 -work $lib `
        "$hdl/audio_visualizer_overlay.v" "$hdl/audio_spectrum_analyzer.v" `
        "$hdl/audio_waveform_analyzer.v" `
        "$outDir/baseline/audio_visualizer_overlay.v" `
        "$outDir/baseline/audio_spectrum_analyzer.v" `
        sim/resource_followup_20260927/baseline/audio_waveform_analyzer.v `
        "$outDir/tb_visualizer_latest_equivalence.sv" `
        "$outDir/tb_visualizer_latest_sequence.sv" `
        "$outDir/tb_spectrum_abort_recovery.sv" `
        "$outDir/tb_smooth_math_exhaustive.sv"
    if($LASTEXITCODE -ne 0) { throw 'Latest equivalence compilation failed' }
    foreach($test in @('tb_visualizer_latest_equivalence','tb_visualizer_latest_sequence',
        'tb_spectrum_abort_recovery','tb_smooth_math_exhaustive')) {
        & "$ModelSimBin/vsim.exe" -c -lib $lib $test `
            -l "$outDir/$test.log" -wlf "$outDir/$test.wlf" `
            -do sim/run_modelsim_vehicle_warning.do
        if($LASTEXITCODE -ne 0 -or -not(Select-String -LiteralPath "$outDir/$test.log" -SimpleMatch '# PASS')) {
            throw "Latest equivalence failed: $test"
        }
    }
    Write-Output 'PASS four additional exact-equivalence and interrupted-state regressions'
} finally { Pop-Location }
