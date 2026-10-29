param([string]$ModelSimBin='C:/intelFPGA/18.1/modelsim_ase/win32aloem')
$ErrorActionPreference='Stop'
$lib='sim/unified_clock_20261002/work'
New-Item -ItemType Directory -Force -Path $lib | Out-Null
& "$ModelSimBin/vlib.exe" $lib | Out-Null
foreach($test in @('tb_unified_clock','tb_clock_overlay','tb_home_clock_replacement')) {
 $cmd="vlog -sv -work {$lib} src/user_source/hdl_source/video_unified_clock.v src/user_source/hdl_source/video_clock_digit_rom.v src/user_source/hdl_source/video_home_overlay.v src/user_source/hdl_source/video_album_cover_rom.v src/user_source/hdl_source/video_app_icons_rom.v sim/$test.sv; vsim -c -lib {$lib} $test; run -all; quit -f"
 $output=& "$ModelSimBin/vsim.exe" -c -l "sim/unified_clock_20261002/$test.log" -do $cmd 2>&1
 $output | Select-Object -Last 12
 if($LASTEXITCODE -ne 0 -or ($output -join "`n") -match '\*\* (Error|Fatal)|\bFAIL\b' -or ($output -join "`n") -notmatch '# PASS') {throw "Clock test failed: $test"}
}
