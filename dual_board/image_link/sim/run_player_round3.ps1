param([string]$ModelSim='C:\intelFPGA\18.1\modelsim_ase\win32aloem\vsim.exe', [switch]$ValidateOnly)
$ErrorActionPreference='Stop'
Push-Location $PSScriptRoot
try {
    if(-not $ValidateOnly) {
        & $ModelSim -c -do 'do run_player_round3.do; quit -code 0' -l hw_round3_20261005/modelsim_round3.log
        if($LASTEXITCODE -ne 0) {throw 'Round-3 ModelSim failed.'}
    }
    $round3Text=Get-Content -LiteralPath hw_round3_20261005/modelsim_round3.log -Raw
    if($round3Text -match 'Errors: [1-9]|\*\* (Error|Fatal):') {throw 'Round-3 simulation error.'}
    if($round3Text -notmatch '# End time:[^\r\n]+\r?\n# Errors: 0, Warnings: \d+\s*(?:#\s*quit -code 0\s*)?$') {throw 'Incomplete round-3 log.'}
    foreach($round3Marker in @('PASS player frame reset:','PASS player frame credit:','PASS home atlas:','PASS home pixels:','PASS home pipeline:','PASS home source:','PASS tagged image:')) {
        if(-not $round3Text.Contains($round3Marker)) {throw "Missing $round3Marker"}
    }
    Write-Output 'PASS round-3 memory reset/UDP credit and round-2 home pixels/source regression.'
} finally {Pop-Location}
