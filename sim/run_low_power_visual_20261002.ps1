param([switch]$LyricsOnly,[string]$ModelSimBin='C:/intelFPGA/18.1/modelsim_ase/win32aloem')
$ErrorActionPreference='Stop'
Push-Location (Split-Path -Parent $PSScriptRoot)
try {
 $root='sim/low_power_round1_20261002'
 $name=if($LyricsOnly){'actual_lyrics'}else{'visual'}
 $lib="$root/$name/work"
 New-Item -ItemType Directory -Force -Path $lib | Out-Null
 & "$ModelSimBin/vlib.exe" $lib | Out-Null
 $modules=if($LyricsOnly){@('audio_lyric_timeline','video_lyric_overlay','lyric_song_data','audio_visualizer_overlay','osd_alpha_overlay','video_status_overlay','video_home_overlay','video_app_icons_rom','video_album_cover_rom')}else{@('video_relax_overlay','audio_waveform_analyzer','audio_spectrum_analyzer','video_status_overlay','video_unified_clock','video_clock_digit_rom')}
 $tests=if($LyricsOnly){@('tb_lyric_actual_pixels')}else{@('tb_video_relax_overlay','tb_relax_audio_response','tb_relax_clock_preview')}
 $files=@($modules | ForEach-Object {"src/user_source/hdl_source/$_.v"})+@($tests | ForEach-Object {"sim/$_.sv"})
 & "$ModelSimBin/vlog.exe" -sv +define+LYRIC_FAST_SIM -suppress 2600 -work $lib @files
 if($LASTEXITCODE -ne 0){throw "Low power visual compile: $name"}
 foreach($test in $tests) {
  $options=@('-gLOW_POWER=1')
  if($test -in @('tb_lyric_actual_pixels','tb_relax_clock_preview')){$options+="-gOUTPUT_DIR=$root/$name"}
  $result=& "$ModelSimBin/vsim.exe" -c -lib $lib $test @options -l "$root/$test.log" -do 'run -all; quit -f' 2>&1
  $result | Select-Object -Last 12
  if($LASTEXITCODE -ne 0 -or ($result -join "`n") -match '\*\* (Error|Fatal)|\bFAIL\b' -or ($result -join "`n") -notmatch '# PASS'){throw "Low power visual test: $test"}
 }
} finally {Pop-Location}
