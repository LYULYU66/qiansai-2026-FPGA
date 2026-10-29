param([switch]$PreviewOnly,[switch]$AudioOnly,[string]$ModelSimBin='C:/intelFPGA/18.1/modelsim_ase/win32aloem')
$ErrorActionPreference='Stop'
$projectRoot=Split-Path -Parent $PSScriptRoot
Push-Location -LiteralPath $projectRoot
try {
 $lib='sim/relax_20261002/work'
 New-Item -ItemType Directory -Force -Path $lib | Out-Null
 if(-not(Test-Path -LiteralPath "$lib/_info")) {& "$ModelSimBin/vlib.exe" $lib | Out-Null}
 $tests=if($PreviewOnly){@('tb_relax_scene_preview')}elseif($AudioOnly){@('tb_relax_audio_response')}else{@('tb_relax_page_policy','tb_video_relax_overlay','tb_relax_audio_response')}
 foreach($test in $tests) {
  $source="src/user_source/hdl_source/video_relax_overlay.v src/user_source/hdl_source/video_status_overlay.v src/user_source/hdl_source/audio_waveform_analyzer.v src/user_source/hdl_source/audio_spectrum_analyzer.v sim/$test.sv"
  $cmd="onerror {quit -code 1 -f}; vlog -sv -work {$lib} $source; vsim -c -lib {$lib} $test; run -all; quit -f"
  $output=& "$ModelSimBin/vsim.exe" -c -l "sim/relax_20261002/$test.log" -do $cmd 2>&1
  $code=$LASTEXITCODE;$output | Select-Object -Last 10
  if($code -ne 0 -or ($output -join "`n") -match '\*\* (Error|Fatal):|\bFAIL\b' -or
     ($output -join "`n") -notmatch '# PASS') {throw "Relax test failed: $test"}
 }
} finally {Pop-Location}
