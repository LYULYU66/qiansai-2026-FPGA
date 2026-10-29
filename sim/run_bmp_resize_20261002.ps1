param([switch]$Full,[switch]$Native,[switch]$HighResolution,
 [string]$ModelSimBin='C:\intelFPGA\18.1\modelsim_ase\win32aloem')
$ErrorActionPreference='Stop'
$root=Split-Path -Parent $PSScriptRoot
Push-Location -LiteralPath $root
try {
 $suffix=if($HighResolution){'high_resolution'}elseif($Full){'full'}else{'small'}
 if($Native) {$suffix='native_'+$suffix}
 $lib="sim/bmp_resize_20261002/$suffix"
 New-Item -ItemType Directory -Force -Path $lib | Out-Null
 & "$ModelSimBin/vlib.exe" $lib | Out-Null
 $flags=if($Native){''}else{'+define+BILINEAR_FAST_SIM'}
 $vendor=if($Native){'{C:/Anlogic/TD_6.2.1_Engineer_6.2.168.116/sim_release/eg4/eg_phy_bram32k.v} {C:/Anlogic/TD_6.2.1_Engineer_6.2.168.116/sim_release/eg4/eg_phy_glbl.v}'}else{''}
 $tops=if($Native){'tb_bmp_bilinear_stream glbl'}else{'tb_bmp_bilinear_stream'}
 $params=if($HighResolution){'-gW=640 -gH=480 -gFULL=2'}elseif($Full){'-gW=640 -gH=480 -gFULL=1'}else{''}
 $cmd="onerror {quit -code 1 -f}; vlog -sv $flags -work {$lib} $vendor {src/user_source/hdl_source/SD/bmp_bilinear_stream.v} {sim/tb_bmp_bilinear_stream.sv}; vsim -c -lib {$lib} $params $tops; run -all; quit -f"
 $result=& "$ModelSimBin/vsim.exe" -c -l "$lib.log" -do $cmd 2>&1
 $code=$LASTEXITCODE; $result | Select-Object -Last 14
 if($code -ne 0 -or ($result -join "`n") -match '\*\* (Error|Fatal)|\bFAIL\b' -or ($result -join "`n") -notmatch 'PASS scaler regression') {throw "Scaler regression failed: $suffix"}
} finally {Pop-Location}
