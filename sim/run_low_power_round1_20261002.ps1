param([string]$ModelSimBin='C:/intelFPGA/18.1/modelsim_ase/win32aloem')
$ErrorActionPreference='Stop'
Push-Location (Split-Path -Parent $PSScriptRoot)
try {
 $lib='sim/low_power_round1_20261002/work'
 New-Item -ItemType Directory -Force -Path $lib | Out-Null
 & "$ModelSimBin/vlib.exe" $lib | Out-Null
 $hdl='src/user_source/hdl_source'
 $sources="$hdl/video_relax_overlay.v $hdl/video_lyric_overlay.v $hdl/video_clock_digit_rom.v $hdl/video_unified_clock.v $hdl/audio_spectrum_analyzer.v sim/tb_video_lyric_overlay.sv sim/tb_clock_overlay.sv sim/tb_low_power_idle.sv sim/tb_low_power_spectrum.sv"
 & "$ModelSimBin/vlog.exe" -sv -work $lib $sources.Split(' ')
 if($LASTEXITCODE -ne 0){throw 'Low-power compile failed'}
 foreach($test in @('tb_low_power_idle','tb_low_power_spectrum','tb_video_lyric_overlay','tb_clock_overlay')) {
  $params=if($test -in @('tb_video_lyric_overlay','tb_clock_overlay')){'-gLOW_POWER=1'}else{''}
  $result=& "$ModelSimBin/vsim.exe" -c -lib $lib $test $params.Split(' ',[StringSplitOptions]::RemoveEmptyEntries) -l "sim/low_power_round1_20261002/$test.log" -do 'run -all; quit -f' 2>&1
  $result | Select-Object -Last 8
  if($LASTEXITCODE -ne 0 -or ($result -join "`n") -match '\*\* (Error|Fatal)|\bFAIL\b' -or ($result -join "`n") -notmatch '# PASS'){throw "Low power test failed: $test"}
 }
} finally {Pop-Location}
