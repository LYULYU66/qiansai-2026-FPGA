param([switch]$FullRegression,[string]$ModelSimBin='C:/intelFPGA/18.1/modelsim_ase/win32aloem')
$ErrorActionPreference='Stop'
Push-Location (Split-Path -Parent $PSScriptRoot)
try {
 if($FullRegression) { & sim/run_resource_all_20261002.ps1 -ModelSimBin $ModelSimBin }
 & sim/run_unified_clock_20261002.ps1 -ModelSimBin $ModelSimBin
 & sim/run_fast_audio_20261002.ps1 -ModelSimBin $ModelSimBin
 $lib='sim/fast_audio_20261002/work'
 $commands=@(
  @{Log='sim/fast_audio_20261002/slow_pipeline.log';Do="vsim -c -lib $lib tb_fast_audio_cache -gBYTE_PERIOD=40 -gCOMMAND_DELAY=1024; run -all; quit -f";Pass='PASS FAST_AUDIO'},
  @{Log='sim/fast_audio_20261002/cluster_pipeline.log';Do="vlog -sv -work $lib src/user_source/hdl_source/SD/bmp_read.v sim/tb_cluster_address_pipeline.sv; vsim -c -lib $lib tb_cluster_address_pipeline; vcd file sim/fast_audio_20261002/cluster_pipeline.vcd; vcd add /tb_cluster_address_pipeline/dut/state /tb_cluster_address_pipeline/dut/cluster_index /tb_cluster_address_pipeline/dut/cluster_offset_q /tb_cluster_address_pipeline/dut/sd_sec_read_addr /tb_cluster_address_pipeline/dut/sd_sec_read /tb_cluster_address_pipeline/dut/bmp_len_cnt /tb_cluster_address_pipeline/dut/bmp_byte_idx; run -all; quit -f";Pass='PASS CLUSTER PIPELINE'}
 )
 foreach($test in $commands) {
  $result=& "$ModelSimBin/vsim.exe" -c -l $test.Log -do $test.Do 2>&1
  $result | Select-Object -Last 8
  if($LASTEXITCODE -ne 0 -or ($result -join "`n") -match '\*\* (Error|Fatal)|\bFAIL\b' -or ($result -join "`n") -notmatch $test.Pass) {throw "Test failed: $($test.Log)"}
 }
 & sim/run_bmp_resize_20261002.ps1 -ModelSimBin $ModelSimBin
 & sim/run_bmp_resize_20261002.ps1 -ModelSimBin $ModelSimBin -Native
 & sim/run_bmp_resize_20261002.ps1 -ModelSimBin $ModelSimBin -Full
 & sim/run_bmp_resize_20261002.ps1 -ModelSimBin $ModelSimBin -HighResolution
 $lib='sim/bmp_resize_20261002/high_resolution'
 $result=& "$ModelSimBin/vsim.exe" -c -l sim/bmp_resize_20261002/clockfix_1280x960.log -do "vsim -c -lib $lib tb_bmp_bilinear_stream -gW=640 -gH=480 -gFULL=3; run -all; quit -f" 2>&1
 $result | Select-Object -Last 8
 if($LASTEXITCODE -ne 0 -or ($result -join "`n") -match '\*\* (Error|Fatal)|\bFAIL\b' -or ($result -join "`n") -notmatch 'PASS scaler regression') {throw '1280x960 test failed'}
} finally {Pop-Location}
