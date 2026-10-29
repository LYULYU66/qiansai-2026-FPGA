param([string]$ModelSimBin='C:/intelFPGA/18.1/modelsim_ase/win32aloem')
$ErrorActionPreference='Stop'
Push-Location (Split-Path -Parent $PSScriptRoot)
try {
 $lib='sim/logic_round3_20261003/work'
 New-Item -ItemType Directory -Force -Path $lib | Out-Null
 & "$ModelSimBin/vlib.exe" $lib | Out-Null
 & "$ModelSimBin/vlog.exe" -sv -work $lib `
  src/user_source/hdl_source/video_status_overlay.v `
  sim/logic_round3_20261003/video_status_overlay_round2_reference.v `
  sim/tb_status_round3_equivalence.sv sim/tb_resolution_status.sv
 if($LASTEXITCODE -ne 0){throw 'Status round3 compile failed'}
 $result=& "$ModelSimBin/vsim.exe" -c -lib $lib tb_status_round3_equivalence `
  -l sim/logic_round3_20261003/equivalence.log -do 'run -all; quit -f' 2>&1
 $result | Select-Object -Last 12
 if($LASTEXITCODE -ne 0 -or ($result -join "`n") -match '\*\* (Error|Fatal)|\bFAIL\b' -or
    ($result -join "`n") -notmatch 'PASS STATUS_ROUND3_EQUIVALENCE'){
  throw 'Status round3 equivalence failed'
 }
 $result=& "$ModelSimBin/vsim.exe" -c -lib $lib tb_resolution_status `
  -l sim/logic_round3_20261003/resolution_status.log -do 'run -all; quit -f' 2>&1
 $result | Select-Object -Last 12
 if($LASTEXITCODE -ne 0 -or ($result -join "`n") -match '\*\* (Error|Fatal)|\bFAIL\b' -or
    ($result -join "`n") -notmatch 'PASS resolution BCD/frame/geometry'){
  throw 'Status resolution test failed'
 }
} finally {Pop-Location}
