param([string]$ModelSim='C:\intelFPGA\18.1\modelsim_ase\win32aloem\vsim.exe')
$ErrorActionPreference='Stop'
Push-Location $PSScriptRoot
try {
    & $ModelSim -c -do 'do run_modelsim.do; quit -code 0' -l modelsim_hw.log
    if($LASTEXITCODE -ne 0){throw 'Hardware-top ModelSim process failed.'}
    $simLog=Get-Content -LiteralPath 'modelsim_hw.log' -Raw
    if($simLog -notmatch 'PASS fixed UDP hardware tops' -or $simLog -match 'Errors: [1-9]|\*\* (Fatal|Error):'){
        throw 'Hardware-top regression failed or incomplete.'
    }
    Write-Output 'PASS ModelSim fixed UDP full-frame hardware tops.'
} finally {Pop-Location}
