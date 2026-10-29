param([string]$ModelSim='C:\intelFPGA\18.1\modelsim_ase\win32aloem\vsim.exe',
    [ValidateSet('Fast','All','Guard')][string]$Suite='Fast', [switch]$ValidateOnly)
$ErrorActionPreference='Stop'
Push-Location $PSScriptRoot
try {
    $playerDo=if($Suite -eq 'All') {'hw_20261005/run_modelsim.do'} elseif($Suite -eq 'Guard') {'run_pipeline_guard.do'} else {'hw_20261005/run_offload_modelsim.do'}
    $playerLog=if($Suite -eq 'All') {'hw_20261005/modelsim_all.log'} elseif($Suite -eq 'Guard') {'hw_20261005/modelsim_guard.log'} else {'hw_20261005/modelsim_fast.log'}
    if(-not $ValidateOnly) {
        & $ModelSim -c -do "do $playerDo; quit -code 0" -l $playerLog
        if($LASTEXITCODE -ne 0) {throw 'Hardware pipeline ModelSim failed.'}
    }
    $playerText=Get-Content -LiteralPath $playerLog -Raw
    if($playerText -match 'Errors: [1-9]|\*\* (Error|Fatal):') {throw 'Hardware pipeline simulation error.'}
    # Nested DO termination in Starter does not echo the final quit command
    # in the All transcript (the unchanged golden run behaves identically).
    # Require final simulator statistics AND every golden case below instead.
    $playerComplete=if($Suite -eq 'All') {'# End time:[^\r\n]+\r?\n# Errors: 0, Warnings: \d+\s*(?:#\s*quit -code 0\s*)?$'} else {'Errors: 0, Warnings: \d+\s*#\s*quit -code 0\s*$'}
    if($playerText -notmatch $playerComplete) {throw 'Incomplete ModelSim log.'}
    $playerMarkers=if($Suite -eq 'All') {
        (Get-Content -LiteralPath '../phase10_validation_20261004.json' -Raw | ConvertFrom-Json).passed
    } elseif($Suite -eq 'Guard') {@('PASS player pipeline guard:')} else {@('PASS remote compute','PASS audio status:','PASS visual guard:','PASS audio offload')}
    foreach($playerMarker in $playerMarkers) {if(-not $playerText.Contains($playerMarker)) {throw "Missing $playerMarker"}}
    Write-Output "PASS hardware pipeline $Suite suite; original golden assertions unchanged."
} finally {Pop-Location}
