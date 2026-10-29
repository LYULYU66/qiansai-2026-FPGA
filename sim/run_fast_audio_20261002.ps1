param([string]$ModelSimBin='C:/intelFPGA/18.1/modelsim_ase/win32aloem')
$ErrorActionPreference='Stop'
$lib='sim/fast_audio_20261002/work'
New-Item -ItemType Directory -Force -Path $lib | Out-Null
& "$ModelSimBin/vlib.exe" $lib | Out-Null
$sources='src/user_source/hdl_source/SD/bmp_bilinear_stream.v src/user_source/hdl_source/SD/bmp_read.v src/user_source/hdl_source/SD/sd_card_bmp.v sim/tb_fast_audio_cache.sv'
$cmd="onerror {quit -code 1 -f}; vlog -sv +define+BILINEAR_FAST_SIM -work {$lib} $sources; vsim -c -lib {$lib} tb_fast_audio_cache; run -all; quit -f"
$result=& "$ModelSimBin/vsim.exe" -c -l sim/fast_audio_20261002/cache.log -do $cmd 2>&1
$result | Select-Object -Last 20
if($LASTEXITCODE -ne 0 -or ($result -join "`n") -match '\*\* (Error|Fatal)|\bFAIL\b' -or ($result -join "`n") -notmatch 'PASS FAST_AUDIO') {throw 'Fast audio cache test failed'}
$cmd="onerror {quit -code 1 -f}; vlog -sv -work {$lib} src/user_source/hdl_source/hdmi_audio_pcm_i2s_64fs.v src/user_source/hdl_source/I2S_receiver.v sim/tb_audio_silent_start.sv; vsim -c -lib {$lib} tb_audio_silent_start; run -all; quit -f"
$result=& "$ModelSimBin/vsim.exe" -c -l sim/fast_audio_20261002/silence.log -do $cmd 2>&1
$result | Select-Object -Last 12
if($LASTEXITCODE -ne 0 -or ($result -join "`n") -match '\*\* (Error|Fatal)|\bFAIL\b' -or ($result -join "`n") -notmatch 'PASS SILENT_START') {throw 'Silent audio startup test failed'}
