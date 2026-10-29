param([switch]$IntegrationOnly,
 [string]$ModelSimBin='C:/intelFPGA/18.1/modelsim_ase/win32aloem',
 [string]$PythonExe='C:/Users/28492/.cache/codex-runtimes/codex-primary-runtime/dependencies/python/python.exe')
$ErrorActionPreference='Stop'
$projectRoot=Split-Path -Parent $PSScriptRoot
Push-Location -LiteralPath $projectRoot
try {
 if(-not $IntegrationOnly) {
  & "$PSScriptRoot/run_resource_all_20261002.ps1" -ModelSimBin $ModelSimBin -PythonExe $PythonExe
  & "$PSScriptRoot/run_bmp_resize_20261002.ps1" -ModelSimBin $ModelSimBin
  & "$PSScriptRoot/run_bmp_resize_20261002.ps1" -Native -ModelSimBin $ModelSimBin
  & "$PSScriptRoot/run_bmp_resize_20261002.ps1" -HighResolution -ModelSimBin $ModelSimBin
  & "$PSScriptRoot/run_bmp_resize_20261002.ps1" -Full -Native -ModelSimBin $ModelSimBin
 }
 function Invoke-DownscaleBench([string]$Name,[string]$Top,[string]$Files,[string]$Defines='') {
  $lib="sim/bmp_resize_20261002/$Name"
  New-Item -ItemType Directory -Force -Path $lib | Out-Null
  if(-not(Test-Path -LiteralPath "$lib/_info")) { & "$ModelSimBin/vlib.exe" $lib | Out-Null }
  $commands="onerror {quit -code 1 -f}; vlog -sv $Defines -work {$lib} $Files; vsim -c -lib {$lib} $Top; run -all; quit -f"
  $output=& "$ModelSimBin/vsim.exe" -c -l "$lib.log" -do $commands 2>&1
  $exitCode=$LASTEXITCODE
  $output | Select-Object -Last 8
  if($exitCode -ne 0 -or ($output -join "`n") -match '\*\* (Error|Fatal):|\bFAIL\b' -or
     ($output -join "`n") -notmatch '# PASS') { throw "Failed: $Top" }
 }
 $sd='src/user_source/hdl_source/SD'
 Invoke-DownscaleBench reader tb_bmp_resize_reader "$sd/bmp_bilinear_stream.v $sd/bmp_read.v sim/tb_bmp_resize_reader.sv" '+define+BILINEAR_FAST_SIM'
 Invoke-DownscaleBench cache_pcm tb_resize_cache_pcm "$sd/bmp_bilinear_stream.v $sd/bmp_read.v $sd/sd_card_bmp.v sim/tb_resize_cache_pcm.sv" '+define+BILINEAR_FAST_SIM'
 Invoke-DownscaleBench orientation tb_resize_write_orientation "$sd/frame_fifo_write.v sim/tb_resize_write_orientation.sv"
 Invoke-DownscaleBench status tb_resolution_status 'src/user_source/hdl_source/video_status_overlay.v sim/tb_resolution_status.sv'
 Invoke-DownscaleBench bmp_lut_stress tb_bmp_lutopt_stress "$sd/bmp_read.v sim/lut_opt_20261002/baseline/bmp_read.v sim/lut_opt_20261002/tb_bmp_lutopt_stress.sv"
 & $PythonExe -X utf8 -B "$PSScriptRoot/check_resource_all_logs_20261002.py"
 if($LASTEXITCODE -ne 0) { throw 'Existing 42-bench log gate failed' }
 Write-Output 'PASS downscale integration / metadata / row orientation / PCM / legacy equivalence'
} finally { Pop-Location }
