param([switch]$Starter, [switch]$SE)
$ErrorActionPreference = 'Stop'
Push-Location (Split-Path -Parent $PSScriptRoot)
try {
    # This process only: inherit existing configured licenses, never edit them.
    if (-not $env:LM_LICENSE_FILE) {
        $env:LM_LICENSE_FILE = [Environment]::GetEnvironmentVariable('LM_LICENSE_FILE','User')
    }
    if (-not $env:MGLS_LICENSE_FILE) {
        $env:MGLS_LICENSE_FILE = [Environment]::GetEnvironmentVariable('MGLS_LICENSE_FILE','Machine')
    }
    # Starter is the verified runnable default on this machine. SE requires
    # a working Verilog simulation feature, not only a shell/compiler license.
    if (-not $SE) {
        & 'C:\intelFPGA\18.1\modelsim_ase\win32aloem\vsim.exe' -c -do 'set lib sim/alignment_20260926/starter_work; do sim/run_modelsim_read_axis_stress.do'
    } else {
        & 'C:\modeltech64_2020.4\win64\vsim.exe' -c -do 'do sim/run_modelsim_read_axis_stress.do'
    }
    if ($LASTEXITCODE -ne 0) { throw 'ModelSim read/AXIS regression failed; see transcript/WLF' }
} finally { Pop-Location }
