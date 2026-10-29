param([switch]$SkipPreview)
$ErrorActionPreference='Stop'
$simExe='C:\intelFPGA\18.1\modelsim_ase\win32aloem\vsim.exe'
$simDir=Split-Path $PSScriptRoot -Parent
$tests=@(
    @{Name='preview';Script='b_hdmi_20261006/run_preview.do';Pass=@('PASS B HDMI preview:')},
    @{Name='boundary';Script='b_hdmi_20261006/run_boundary.do';Pass=@('PASS player B boundary:','PASS B preview source:')},
    @{Name='reader';Script='dualsong_20261005/run_reader.do';Pass=@('PASS two-song reader reverse=0','PASS two-song reader reverse=1')},
    @{Name='features';Script='dualsong_20261005/run_features.do';Pass=@('PASS dualsong control:','PASS dualsong timeline:')},
    @{Name='audio';Script='dualsong_20261005/run_audio.do';Pass=@('PASS audio status:','PASS visual guard:','PASS remote compute:','PASS audio offload:')}
)
if($SkipPreview){$tests=@($tests|Where-Object {$_.Name -ne 'preview'})}
Push-Location $simDir
try {
    foreach($case in $tests){
        $logPath=Join-Path $PSScriptRoot ($case.Name+'.log')
        & $simExe -c -do $case.Script -l $logPath | Out-Null
        if($LASTEXITCODE -ne 0){throw ('ModelSim failed: '+$case.Name)}
        $logText=Get-Content -LiteralPath $logPath -Raw
        if($logText -match '\*\* (Fatal|Error)' -or $logText -match 'Errors: [1-9]'){
            throw ('Simulation failure: '+$case.Name)
        }
        foreach($marker in $case.Pass){if(-not $logText.Contains($marker)){throw ('Missing PASS: '+$marker)}}
        Write-Host ('Verified '+$case.Name)
    }
    Write-Host 'PASS B HDMI regression groups'
} finally {Pop-Location}
