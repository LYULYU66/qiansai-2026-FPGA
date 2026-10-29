param(
    [string]$ModelSimBin='C:/intelFPGA/18.1/modelsim_ase/win32aloem',
    [string]$PythonExe='C:/Users/28492/.cache/codex-runtimes/codex-primary-runtime/dependencies/python/python.exe'
)
# LUT optimisation release regression (2026-10-02).
# 1. Archive every gated log so that each one must be regenerated.
# 2. Run the complete 42-bench resource regression and its log gate.
# 3. Run the randomised bmp_read stress equivalence against the
#    pre-optimisation copy (aborts, SD re-init, rescans, loads, PCM).
$ErrorActionPreference='Stop'
$projectRoot=Split-Path -Parent $PSScriptRoot
Push-Location -LiteralPath $projectRoot
try {
    $archive="sim/lut_opt_20261002/pre_run_logs/$(Get-Date -Format yyyyMMdd_HHmmss)"
    New-Item -ItemType Directory -Force $archive | Out-Null
    $gated=@(& $PythonExe -c @'
import sys
sys.path.insert(0,'sim')
from check_resource_all_logs_20261002 import GROUPS
for folder,names in GROUPS.items():
    for name in names:
        print(folder+'/'+(name if folder.endswith('lyrics_20261001') else 'tb_'+name)+'.log')
print('sim/resource_all_20261002/bram32_font.log')
'@)
    if($LASTEXITCODE -ne 0 -or $gated.Count -ne 42) { throw 'Could not list the 42 gated logs' }
    foreach($log in $gated) {
        if(Test-Path -LiteralPath $log) {
            $target=Join-Path $archive ($log -replace '[/\\]','__')
            Move-Item -LiteralPath $log -Destination $target
        }
    }
    & "$PSScriptRoot/run_resource_all_20261002.ps1" -ModelSimBin $ModelSimBin -PythonExe $PythonExe
    foreach($log in $gated) {
        if(-not(Test-Path -LiteralPath $log)) { throw "Gated log was not regenerated: $log" }
    }

    $outDir='sim/lut_opt_20261002'
    $lib="$outDir/w_bmp"
    if(-not(Test-Path -LiteralPath "$lib/_info")) { & "$ModelSimBin/vlib.exe" $lib }
    & "$ModelSimBin/vlog.exe" -sv -work $lib src/user_source/hdl_source/SD/bmp_read.v `
        "$outDir/baseline/bmp_read.v" "$outDir/tb_bmp_lutopt_stress.sv"
    if($LASTEXITCODE -ne 0) { throw 'Compile failed: bmp_read stress equivalence' }
    $stressLog="$outDir/bmp_lutopt_stress.log"
    if(Test-Path -LiteralPath $stressLog) { Remove-Item -LiteralPath $stressLog }
    & "$ModelSimBin/vsim.exe" -c -lib $lib tb_bmp_lutopt_stress -l $stressLog -do 'run -all; quit -f'
    $text=Get-Content -LiteralPath $stressLog -Raw
    if($LASTEXITCODE -ne 0 -or $text -match '\*\* (Error|Fatal):' -or
       $text -notmatch 'PASS BMP_LUTOPT_STRESS 2000000 cycles') {
        throw 'bmp_read LUT-optimisation stress equivalence failed'
    }
    Write-Output 'PASS LUT optimisation regression: 42 regenerated ModelSim benches, 4 asset/pixel checks, bmp_read randomised stress equivalence'
} finally { Pop-Location }
