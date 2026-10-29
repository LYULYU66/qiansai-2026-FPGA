param([string]$TdExe='C:\Anlogic\TD_6.2.1_Engineer_6.2.168.116\bin\td_commands_prompt.exe',
      [switch]$ReuseSynthesis,
      [string]$PhysicalRun='phy_lyrics_music_card_s3_20261002')
$ErrorActionPreference='Stop'
$projectRoot=Split-Path -Parent $PSScriptRoot
$sourcePaths=@('top_tf_hdmi_audio.v','audio_lyric_timeline.v','video_lyric_overlay.v',
    'lyric_song_data.v','video_home_overlay.v','SD/bmp_read.v','SD/sd_card_bmp.v') |
    ForEach-Object { Join-Path $projectRoot "src/user_source/hdl_source/$_" }
$before=@($sourcePaths | ForEach-Object { (Get-FileHash -LiteralPath $_ -Algorithm SHA256).Hash })
if($ReuseSynthesis) {
    $synMarker=Join-Path $projectRoot 'src/td_project/resopt_Runs/syn_lyrics_music_card_20261002/.opt_gate.end.f'
    if(-not(Test-Path -LiteralPath $synMarker)) { throw 'Synthesis completion marker missing.' }
    $synFinished=(Get-Item -LiteralPath $synMarker).LastWriteTimeUtc
    if(@($sourcePaths | Where-Object { (Get-Item -LiteralPath $_).LastWriteTimeUtc -gt $synFinished }).Count) {
        throw 'Source modified after synthesis; do not reuse the gate DB.'
    }
}
$runs=if($ReuseSynthesis) { @($PhysicalRun) } else {
    @('syn_lyrics_music_card_20261002',$PhysicalRun)
}
foreach($runName in $runs) {
    $runDir=Join-Path $projectRoot "src/td_project/resopt_Runs/$runName"
    $started=[DateTime]::UtcNow
    Push-Location -LiteralPath $runDir
    try {
        & $TdExe lab_ex5_i2s_v1.0.tcl
        if($LASTEXITCODE -ne 0) { throw "TD failed: $runName ($LASTEXITCODE)" }
        $endMarker=if($runName.StartsWith('syn_')) { '.opt_gate.end.f' } else { '.bitgen.end.f' }
        if(-not(Test-Path -LiteralPath $endMarker) -or
            (Get-Item -LiteralPath $endMarker).LastWriteTimeUtc -lt $started) {
            throw "Build did not complete: $runName"
        }
    } finally { Pop-Location }
}
$after=@($sourcePaths | ForEach-Object { (Get-FileHash -LiteralPath $_ -Algorithm SHA256).Hash })
if(($before -join ',') -ne ($after -join ',')) { throw 'Source changed during build; do not use generated bit.' }
Write-Output 'PASS completed shared music card / two-row credits / early verse / outro-info synthesis, routing and bitgen; source unchanged.'
