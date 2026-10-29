param([switch]$SkipPreview,[string[]]$Only)
$ErrorActionPreference='Stop'
$simExe='C:\intelFPGA\18.1\modelsim_ase\win32aloem\vsim.exe'
$tests=@(
 @{Name='stars';Script='dual_stars_20261006/run_stars.do';Pass=@('PASS star control:','PASS dual stars pixels:','PASS control guard:','PASS CTL3 guard:')},
 @{Name='selection';Script='dual_stars_20261006/run_selection.do';Pass=@('PASS B third-image selection:')},
 @{Name='uart';Script='dual_stars_20261006/run_uart.do';Pass=@('PASS CTL3 UART control:')},
 @{Name='boundary';Script='dual_stars_20261006/run_boundary.do';Pass=@('PASS player B boundary:','PASS B third-image source:')},
 @{Name='preview';Script='dual_stars_20261006/run_preview.do';Pass=@('PASS B third-image star preview:')},
 @{Name='reader';Script='dualsong_20261005/run_reader.do';Pass=@('PASS two-song reader reverse=0','PASS two-song reader reverse=1')},
 @{Name='features';Script='dualsong_20261005/run_features.do';Pass=@('PASS dualsong control:','PASS dualsong timeline:')},
 @{Name='audio';Script='dualsong_20261005/run_audio.do';Pass=@('PASS audio status:','PASS visual guard:','PASS remote compute:','PASS audio offload:')}
)
if($SkipPreview){$tests=@($tests|Where-Object {$_.Name -ne 'preview'})}
if($Only){$tests=@($tests|Where-Object {$_.Name -in $Only})}
Push-Location (Split-Path $PSScriptRoot -Parent)
try{
 foreach($t in $tests){
  $log=Join-Path $PSScriptRoot ($t.Name+'.log')
  & $simExe -c -do $t.Script -l $log | Out-Null
  if($LASTEXITCODE -ne 0){throw ('ModelSim failed: '+$t.Name)}
  $txt=Get-Content -LiteralPath $log -Raw
  if($txt -match '\*\* (Fatal|Error)|Errors: [1-9]'){throw ('Regression failed: '+$t.Name)}
  foreach($p in $t.Pass){if(-not $txt.Contains($p)){throw ('Missing '+$p)}}
  Write-Host ('Verified '+$t.Name)
 }
 Write-Host 'PASS dual-screen star regression groups'
}finally{Pop-Location}
