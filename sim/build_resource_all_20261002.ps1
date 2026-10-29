param([string]$TdExe='C:\Anlogic\TD_6.2.1_Engineer_6.2.168.116\bin\td_commands_prompt.exe',
      [switch]$ReuseSynthesis,
      [string]$SynthesisRun='syn_resource_bram32_char_20261002',
      [string]$PhysicalRun='phy_resource_bram32_char_s7_20261002')
$ErrorActionPreference='Stop'
$projectRoot=Split-Path -Parent $PSScriptRoot
Push-Location -LiteralPath $projectRoot
try {
    $sourcePaths=@(& rg --files src/user_source src/td_project/al_ip |
        Where-Object { $_ -match '\.(v|sv|vhd|tcl|sdc|adc)$' })
    if(-not $sourcePaths.Count) { throw 'No source files to fingerprint' }
    $before=@($sourcePaths | ForEach-Object { (Get-FileHash -LiteralPath $_ -Algorithm SHA256).Hash })
    if($ReuseSynthesis) {
        $marker="src/td_project/resopt_Runs/$SynthesisRun/.opt_gate.end.f"
        if(-not(Test-Path -LiteralPath $marker)) { throw 'Synthesis incomplete' }
        $finished=(Get-Item -LiteralPath $marker).LastWriteTimeUtc
        if(@($sourcePaths | Where-Object { (Get-Item -LiteralPath $_).LastWriteTimeUtc -gt $finished }).Count) {
            throw 'Source changed after synthesis; cannot reuse gate DB'
        }
    }
    $runs=if($ReuseSynthesis) { @($PhysicalRun) } else { @($SynthesisRun,$PhysicalRun) }
    foreach($name in $runs) {
        $started=[DateTime]::UtcNow
        Push-Location -LiteralPath "src/td_project/resopt_Runs/$name"
        try {
            & $TdExe lab_ex5_i2s_v1.0.tcl
            if($LASTEXITCODE -ne 0) { throw "TD failed: $name" }
            $end=if($name.StartsWith('syn_')) { '.opt_gate.end.f' } else { '.bitgen.end.f' }
            if(-not(Test-Path -LiteralPath $end) -or (Get-Item -LiteralPath $end).LastWriteTimeUtc -lt $started) {
                throw "No new completion marker: $name"
            }
        } finally { Pop-Location }
    }
    $after=@($sourcePaths | ForEach-Object { (Get-FileHash -LiteralPath $_ -Algorithm SHA256).Hash })
    if(($before -join ',') -ne ($after -join ',')) { throw 'Source changed during build; do not publish bit' }
    Write-Output "PASS full resource build / routed bitgen / $($sourcePaths.Count) source and constraint hashes unchanged"
} finally { Pop-Location }
