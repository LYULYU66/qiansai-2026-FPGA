param([switch]$FastOnly)
$ErrorActionPreference = 'Stop'
$simExe = 'C:\intelFPGA\18.1\modelsim_ase\win32aloem\vsim.exe'
$simDir = Split-Path $PSScriptRoot -Parent
$tests = @(
    @{ Name='reader'; Script='run_reader.do'; Pass=@('PASS two-song reader reverse=0','PASS two-song reader reverse=1') },
    @{ Name='features'; Script='run_features.do'; Pass=@('PASS dualsong control:','PASS dualsong timeline:') },
    @{ Name='ui'; Script='run_ui.do'; Pass=@('PASS dualsong UI:') },
    @{ Name='boundary'; Script='run_boundary.do'; Pass=@('PASS player B boundary:','PASS home source:') },
    @{ Name='audio'; Script='run_audio.do'; Pass=@('PASS audio status:','PASS visual guard:','PASS remote compute:','PASS audio offload:') }
)
if ($FastOnly) { $tests = @($tests | Where-Object { $_.Name -in @('reader','features','ui') }) }
Push-Location $simDir
try {
    foreach ($case in $tests) {
        $logPath = Join-Path $PSScriptRoot ($case.Name+'.log')
        & $simExe -c -do ('dualsong_20261005/'+$case.Script) -l $logPath
        if ($LASTEXITCODE -ne 0) { throw ('ModelSim failed: '+$case.Name) }
        $logText = Get-Content -LiteralPath $logPath -Raw
        if ($logText -match '\*\* (Fatal|Error)' -or $logText -match 'Errors: [1-9]') { throw ('Simulation failure: '+$case.Name) }
        foreach ($marker in $case.Pass) {
            if (-not $logText.Contains($marker)) { throw ('Missing PASS marker: '+$marker) }
        }
        Write-Host ('Verified '+$case.Name)
    }
    Write-Host 'PASS all dualsong regression groups'
} finally { Pop-Location }
