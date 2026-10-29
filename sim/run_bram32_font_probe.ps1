param([string]$ModelSimBin='C:/intelFPGA/18.1/modelsim_ase/win32aloem')
$ErrorActionPreference='Stop'
$projectRoot=Split-Path -Parent $PSScriptRoot
Push-Location -LiteralPath $projectRoot
try {
 $out='sim/resource_all_20261002/bram32_native'
 if(-not(Test-Path -LiteralPath "$out/_info")) { & "$ModelSimBin/vlib.exe" $out }
 $vendor='C:/Anlogic/TD_6.2.1_Engineer_6.2.168.116/sim_release/eg4'
 # Compile production with NO fast-sim macro: real vendor INIT and ROM port.
 & "$ModelSimBin/vlog.exe" -sv -work $out `
  "$vendor/eg_phy_glbl.v" "$vendor/eg_phy_bram32k.v" `
  src/user_source/hdl_source/lyric_song_data.v `
  sim/resource_all_20261002/tb_bram32_font.sv
 if($LASTEXITCODE -ne 0) { throw 'Native BRAM32K font compile failed' }
 & "$ModelSimBin/vsim.exe" -c -lib $out tb_bram32_font glbl `
  -l sim/resource_all_20261002/bram32_font.log -wlf sim/resource_all_20261002/bram32_font.wlf `
  -do sim/run_modelsim_vehicle_warning.do
 if($LASTEXITCODE -ne 0 -or -not(Select-String -LiteralPath sim/resource_all_20261002/bram32_font.log -SimpleMatch '# PASS')) { throw 'Native BRAM32K font test failed' }
} finally { Pop-Location }
