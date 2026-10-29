param([string]$ModelSimBin='C:\intelFPGA\18.1\modelsim_ase\win32aloem')
$ErrorActionPreference='Stop'
$projectRoot=Split-Path -Parent $PSScriptRoot
Push-Location -LiteralPath $projectRoot
try {
    $outDir='sim/lyrics_20261001'
    New-Item -ItemType Directory -Force $outDir | Out-Null
    foreach($name in @('audio_lyric_timeline','video_lyric_overlay')) {
        $lib="$outDir/$name"
        if(-not(Test-Path -LiteralPath "$lib/_info")) {
            & "$ModelSimBin/vlib.exe" $lib
            if($LASTEXITCODE -ne 0) { throw "vlib failed: $name" }
        }
        & "$ModelSimBin/vlog.exe" -sv -work $lib `
            "src/user_source/hdl_source/$name.v" "sim/tb_$name.sv"
        if($LASTEXITCODE -ne 0) { throw "Compile failed: $name" }
        & "$ModelSimBin/vsim.exe" -c -lib $lib "tb_$name" `
            -l "$outDir/$name.log" -wlf "$outDir/$name.wlf" `
            -do sim/run_modelsim_vehicle_warning.do
        if($LASTEXITCODE -ne 0) { throw "Simulation failed: $name" }
        if(-not(Select-String -LiteralPath "$outDir/$name.log" -SimpleMatch '# PASS')) {
            throw "Missing PASS: $name"
        }
    }
    $fontLib="$outDir/packed_font"
    if(-not(Test-Path -LiteralPath "$fontLib/_info")) { & "$ModelSimBin/vlib.exe" $fontLib }
    & "$ModelSimBin/vlog.exe" -sv +define+LYRIC_FAST_SIM -work $fontLib `
        src/user_source/hdl_source/lyric_song_data.v sim/tb_packed_font_equivalence.sv
    if($LASTEXITCODE -ne 0) { throw 'Compile failed: lossless packed font' }
    & "$ModelSimBin/vsim.exe" -c -lib $fontLib tb_packed_font_equivalence `
        -l "$outDir/packed_font.log" -wlf "$outDir/packed_font.wlf" `
        -do sim/run_modelsim_vehicle_warning.do
    if($LASTEXITCODE -ne 0 -or -not(Select-String -LiteralPath "$outDir/packed_font.log" -SimpleMatch '# PASS')) {
        throw 'Lossless packed font equivalence failed'
    }
    $lib="$outDir/actual"
    if(-not(Test-Path -LiteralPath "$lib/_info")) { & "$ModelSimBin/vlib.exe" $lib }
    $files=@('audio_lyric_timeline','video_lyric_overlay','lyric_song_data',
        'audio_visualizer_overlay','osd_alpha_overlay','video_status_overlay',
        'video_home_overlay','video_app_icons_rom','video_album_cover_rom') |
        ForEach-Object { "src/user_source/hdl_source/$_.v" }
    # Identical ROM contents from hex avoid Starter Edition's artificial
    # slowdown on thousands of literal init statements. Native inline init
    # is used by TD; the pixel checker compares both representations.
    & "$ModelSimBin/vlog.exe" -sv +define+LYRIC_FAST_SIM -suppress 2600 -work $lib @files sim/tb_lyric_actual_pixels.sv
    if($LASTEXITCODE -ne 0) { throw 'Compile failed: actual lyrics' }
    & "$ModelSimBin/vsim.exe" -c -lib $lib tb_lyric_actual_pixels `
        -l "$outDir/actual.log" -wlf "$outDir/actual.wlf" `
        -do sim/run_modelsim_vehicle_warning.do
    if($LASTEXITCODE -ne 0 -or -not(Select-String -LiteralPath "$outDir/actual.log" -SimpleMatch '# PASS')) {
        throw 'Actual lyric ROM/pixel checks failed'
    }
    & "$ModelSimBin/vlog.exe" -sv -suppress 2600 -work $lib `
        sim/lyrics_music_card_20261002/baseline/video_home_overlay_before_music.v `
        sim/tb_shared_music_card.sv
    if($LASTEXITCODE -ne 0) { throw 'Compile failed: shared music card' }
    & "$ModelSimBin/vsim.exe" -c -lib $lib tb_shared_music_card `
        -l "$outDir/shared_card.log" -wlf "$outDir/shared_card.wlf" `
        -do sim/run_modelsim_vehicle_warning.do
    if($LASTEXITCODE -ne 0 -or -not(Select-String -LiteralPath "$outDir/shared_card.log" -SimpleMatch '# PASS')) {
        throw 'Shared music card / exact homepage regression failed'
    }
} finally { Pop-Location }
