$ErrorActionPreference='Stop'
$exe='C:\intelFPGA\18.1\modelsim_ase\win32aloem\vsim.exe'
$tests=@(
 @{Name='selection';Markers=@('PASS B third-image selection:')},
 @{Name='boundary';Markers=@('PASS player B boundary:','PASS B third-image source:')}
)
Push-Location (Split-Path $PSScriptRoot -Parent)
try{
 foreach($t in $tests){
  $log=Join-Path $PSScriptRoot ($t.Name+'.log')
  & $exe -c -do ('b_hdmi_image3_20261006/run_'+$t.Name+'.do') -l $log | Out-Null
  if($LASTEXITCODE -ne 0){throw ('ModelSim failed: '+$t.Name)}
  $text=Get-Content -LiteralPath $log -Raw
  if($text -match '\*\* (Fatal|Error)|Errors: [1-9]'){throw ('Regression failed: '+$t.Name)}
  foreach($m in $t.Markers){if(-not $text.Contains($m)){throw ('Missing '+$m)}}
  Write-Host ('Verified '+$t.Name)
 }
 Write-Host 'PASS B third-image regression'
}finally{Pop-Location}
