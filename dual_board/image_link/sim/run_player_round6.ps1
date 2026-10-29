param([string]$ModelSim='C:\intelFPGA\18.1\modelsim_ase\win32aloem\vsim.exe',
 [ValidateSet('Guard','Boundary','Audio')][string]$Suite='Guard',[switch]$ValidateOnly)
$ErrorActionPreference='Stop'
Push-Location $PSScriptRoot
try {
 $round6Do=switch($Suite){'Guard' {'run_player_round6_guard.do'} 'Boundary' {'hw_round6_20261005/run_boundary.do'} 'Audio' {'run_player_round6_audio.do'}}
 $round6Log="hw_round6_20261005/modelsim_$($Suite.ToLower()).log"
 if(-not $ValidateOnly){
  & $ModelSim -c -do "do $round6Do; quit -code 0" -l $round6Log
  if($LASTEXITCODE -ne 0){throw 'Round-6 ModelSim failed.'}
 }
 $round6Text=Get-Content -LiteralPath $round6Log -Raw
 if($round6Text -match 'Errors: [1-9]|\*\* (Error|Fatal):'){throw 'Round-6 simulation error.'}
 if($round6Text -notmatch '# End time:[^\r\n]+\r?\n# Errors: 0, Warnings: \d+\s*(?:#\s*quit -code 0\s*)?$'){throw 'Incomplete round-6 log.'}
 $round6Markers=switch($Suite){
  'Guard' {@('PASS receipt pipeline equivalence ext=0','PASS receipt pipeline equivalence ext=1','PASS AAK2/AAK3 pipeline:')}
  'Boundary' {@('PASS player B boundary:','PASS home source:')}
  'Audio' {@('PASS audio status','PASS visual guard','PASS remote compute','PASS audio offload','PASS audio guard','PASS media abort','PASS audio media')}
 }
 foreach($round6Marker in $round6Markers){if(-not $round6Text.Contains($round6Marker)){throw "Missing $round6Marker"}}
 Write-Output "PASS round-6 $Suite suite."
}finally{Pop-Location}
