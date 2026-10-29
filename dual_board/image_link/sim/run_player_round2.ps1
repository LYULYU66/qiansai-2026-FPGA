param([string]$ModelSim='C:\intelFPGA\18.1\modelsim_ase\win32aloem\vsim.exe', [switch]$ValidateOnly)
$ErrorActionPreference='Stop'
Push-Location $PSScriptRoot
try {
    if(-not $ValidateOnly) {
        & $ModelSim -c -do 'do run_player_round2.do; quit -code 0' -l hw_round2_20261005/modelsim_round2.log
        if($LASTEXITCODE -ne 0) {throw 'Round-2 ModelSim failed.'}
    }
    $round2Text=Get-Content -LiteralPath hw_round2_20261005/modelsim_round2.log -Raw
    if($round2Text -match 'Errors: [1-9]|\*\* (Error|Fatal):') {throw 'Round-2 simulation error.'}
    if($round2Text -notmatch '# End time:[^\r\n]+\r?\n# Errors: 0, Warnings: \d+\s*(?:#\s*quit -code 0\s*)?$') {throw 'Incomplete round-2 log.'}
    foreach($round2Marker in @('PASS player frame reset:','PASS home atlas:','PASS home pixels:','PASS home pipeline:','PASS home source:','PASS tagged image:')) {
        if(-not $round2Text.Contains($round2Marker)) {throw "Missing $round2Marker"}
    }
    Write-Output 'PASS round-2 memory reset and home pixels/source regression.'
} finally {Pop-Location}
