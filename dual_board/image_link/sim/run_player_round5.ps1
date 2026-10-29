param([string]$ModelSim='C:\intelFPGA\18.1\modelsim_ase\win32aloem\vsim.exe',
 [ValidateSet('Guard','All','Boundary')][string]$Suite='Guard',[switch]$ValidateOnly)
$ErrorActionPreference='Stop'
Push-Location $PSScriptRoot
try {
 $round5Do=switch($Suite){'Guard' {'run_player_round5_guard.do'} 'All' {'hw_round5_20261005/run_modelsim.do'} 'Boundary' {'hw_round5_20261005/run_boundary.do'}}
 $round5Log="hw_round5_20261005/modelsim_$($Suite.ToLower()).log"
 if(-not $ValidateOnly){
  & $ModelSim -c -do "do $round5Do; quit -code 0" -l $round5Log
  if($LASTEXITCODE -ne 0){throw 'Round-5 ModelSim failed.'}
 }
 $round5Text=Get-Content -LiteralPath $round5Log -Raw
 if($round5Text -match 'Errors: [1-9]|\*\* (Error|Fatal):'){throw 'Round-5 simulation error.'}
 if($round5Text -notmatch '# End time:[^\r\n]+\r?\n# Errors: 0, Warnings: \d+\s*(?:#\s*quit -code 0\s*)?$'){throw 'Incomplete round-5 log.'}
 $round5Markers=switch($Suite){
  'Guard' {@('PASS image TX pipeline equivalence:')}
  'All' {(Get-Content -LiteralPath ../phase10_validation_20261004.json -Raw|ConvertFrom-Json).passed}
  'Boundary' {@('PASS player B boundary:','PASS home source:')}
 }
 foreach($round5Marker in $round5Markers){if(-not $round5Text.Contains($round5Marker)){throw "Missing $round5Marker"}}
 Write-Output "PASS round-5 $Suite suite; original golden assertions unchanged."
}finally{Pop-Location}
