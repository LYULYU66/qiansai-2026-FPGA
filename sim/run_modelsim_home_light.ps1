param(
    [string]$ModelSimBin='C:\intelFPGA\18.1\modelsim_ase\win32aloem',
    [string]$PythonExe='C:\Users\28492\.cache\codex-runtimes\codex-primary-runtime\dependencies\python\python.exe'
)
$ErrorActionPreference='Stop'
$projectRoot=Split-Path -Parent $PSScriptRoot
Push-Location -LiteralPath $projectRoot
try {
    $outDir='sim/home_nav_app_20260930'
    $workLib="$outDir/intel_work"
    New-Item -ItemType Directory -Force $outDir | Out-Null
    if(-not (Test-Path -LiteralPath "$workLib/_info")) {
        & "$ModelSimBin/vlib.exe" $workLib
        if($LASTEXITCODE -ne 0) { throw 'ModelSim library creation failed' }
    }
    $sourceFiles=@(
        'src/user_source/hdl_source/video_home_overlay.v',
        'src/user_source/hdl_source/video_app_icons_rom.v',
        'src/user_source/hdl_source/video_album_cover_rom.v',
        'src/user_source/hdl_source/video_status_overlay.v',
        'sim/home_nav_app_20260930/baseline/video_home_overlay.v',
        'sim/home_nav_app_20260930/baseline/video_app_icons_rom.v',
        'sim/tb_home_light_apps.sv','sim/tb_video_home_overlay.v',
        'sim/tb_home_navigation_card.sv','sim/tb_home_dashboard_combined.sv',
        'sim/tb_video_status_overlay.v','sim/tb_nav_toolbar_alignment.sv'
    )
    & "$ModelSimBin/vlog.exe" -sv -suppress 2600 -work $workLib @sourceFiles
    if($LASTEXITCODE -ne 0) { throw 'ModelSim compilation failed' }
    foreach($testName in @('tb_home_light_apps','tb_video_home_overlay',
        'tb_home_navigation_card','tb_home_dashboard_combined','tb_video_status_overlay',
        'tb_nav_toolbar_alignment')) {
        & "$ModelSimBin/vsim.exe" -c -lib $workLib $testName `
            -wlf "$outDir/$testName.wlf" -l "$outDir/$testName.log" `
            -do sim/run_modelsim_vehicle_warning.do
        if($LASTEXITCODE -ne 0) { throw "Failed: $testName" }
        if(-not (Select-String -LiteralPath "$outDir/$testName.log" -SimpleMatch '# PASS')) {
            throw "No PASS result: $testName"
        }
    }
    & $PythonExe sim/check_home_light_pixels.py
    if($LASTEXITCODE -ne 0) { throw 'ROM/sprite pixel comparison failed' }
    & $PythonExe sim/check_crisp_ui_assets.py
    if($LASTEXITCODE -ne 0) { throw 'Crisp toolbar/font/QQ pixel comparison failed' }
    Write-Host 'PASS all six home regressions and independent sprite/font/toolbar/QQ checks'
} finally { Pop-Location }
