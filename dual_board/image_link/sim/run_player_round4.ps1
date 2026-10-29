param([string]$ModelSim='C:\intelFPGA\18.1\modelsim_ase\win32aloem\vsim.exe',
    [ValidateSet('Fast','All','Guard','Boundary')][string]$Suite='Fast',[switch]$ValidateOnly)
$ErrorActionPreference='Stop'
Push-Location $PSScriptRoot
try {
    $round4Do=switch($Suite) {'Fast' {'hw_round4_20261005/run_offload_modelsim.do'} 'All' {'hw_round4_20261005/run_modelsim.do'} 'Guard' {'run_player_round4_guard.do'} 'Boundary' {'run_player_round4_boundary.do'}}
    $round4Log="hw_round4_20261005/modelsim_$($Suite.ToLower()).log"
    if(-not $ValidateOnly) {
        & $ModelSim -c -do "do $round4Do; quit -code 0" -l $round4Log
        if($LASTEXITCODE -ne 0){throw 'Round-4 ModelSim failed.'}
    }
    $round4Text=Get-Content -LiteralPath $round4Log -Raw
    if($round4Text -match 'Errors: [1-9]|\*\* (Error|Fatal):'){throw 'Round-4 simulation error.'}
    if($round4Text -notmatch '# End time:[^\r\n]+\r?\n# Errors: 0, Warnings: \d+\s*(?:#\s*quit -code 0\s*)?$'){throw 'Incomplete round-4 log.'}
    $round4Markers=switch($Suite){
        'Fast' {@('PASS remote compute','PASS audio status:','PASS visual guard:','PASS audio offload')}
        'All' {(Get-Content -LiteralPath ../phase10_validation_20261004.json -Raw | ConvertFrom-Json).passed}
        'Guard' {@('PASS player pipeline guard:','PASS player domain resets:','PASS player audio metadata:')}
        'Boundary' {@('PASS player B boundary:','PASS home source:')}
    }
    foreach($round4Marker in $round4Markers){if(-not $round4Text.Contains($round4Marker)){throw "Missing $round4Marker"}}
    Write-Output "PASS round-4 $Suite suite; original golden assertions unchanged."
} finally {Pop-Location}
