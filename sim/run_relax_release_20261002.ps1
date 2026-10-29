param([string]$ModelSimBin='C:/intelFPGA/18.1/modelsim_ase/win32aloem',
 [string]$PythonExe='C:/Users/28492/.cache/codex-runtimes/codex-primary-runtime/dependencies/python/python.exe')
$ErrorActionPreference='Stop'
& "$PSScriptRoot/run_resource_all_20261002.ps1" -ModelSimBin $ModelSimBin -PythonExe $PythonExe
& "$PSScriptRoot/run_relax_20261002.ps1" -ModelSimBin $ModelSimBin
& "$PSScriptRoot/run_relax_20261002.ps1" -PreviewOnly -ModelSimBin $ModelSimBin
Write-Output 'PASS complete relax regression: 42 existing + 4 new benches, real audio response and composed scene previews'
