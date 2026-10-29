param([string]$ModelSimBin='C:/intelFPGA/18.1/modelsim_ase/win32aloem',
 [string]$PythonExe='C:/Users/28492/.cache/codex-runtimes/codex-primary-runtime/dependencies/python/python.exe')
$ErrorActionPreference='Stop'
Push-Location (Split-Path -Parent $PSScriptRoot)
try {
 & $PythonExe -X utf8 -B sim/check_image_adjust_lut_20261002.py
 if($LASTEXITCODE -ne 0){throw 'Native ROM INIT oracle failed'}
 $lib='sim/logic_round2_20261002/work'
 New-Item -ItemType Directory -Force -Path $lib | Out-Null
 & "$ModelSimBin/vlib.exe" $lib | Out-Null
 $vendor='C:/Anlogic/TD_6.2.1_Engineer_6.2.168.116/sim_release/eg4'
 & "$ModelSimBin/vlog.exe" -sv -work $lib "$vendor/eg_phy_glbl.v" "$vendor/eg_phy_bram32k.v" `
  src/user_source/hdl_source/video_image_adjust.v sim/logic_round2_20261002/video_image_adjust_round1_reference.v sim/tb_image_adjust_rom_20261002.sv
 if($LASTEXITCODE -ne 0){throw 'Native image adjust compile failed'}
 $result=& "$ModelSimBin/vsim.exe" -c -sv_seed 61002 -lib $lib tb_image_adjust_rom_20261002 glbl `
  -l sim/logic_round2_20261002/native_rom.log -wlf sim/logic_round2_20261002/native_rom.wlf `
  -do sim/run_modelsim_vehicle_warning.do 2>&1
 $result | Select-Object -Last 15
 if($LASTEXITCODE -ne 0 -or ($result -join "`n") -match '\*\* (Error|Fatal)|\bFAIL\b' -or ($result -join "`n") -notmatch 'PASS IMAGE_ADJUST_SEQUENCE'){throw 'Native image adjust equivalence failed'}
} finally {Pop-Location}
