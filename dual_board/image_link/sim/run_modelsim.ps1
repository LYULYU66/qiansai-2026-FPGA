param(
    [string]$ModelSim = 'C:\intelFPGA\18.1\modelsim_ase\win32aloem\vsim.exe',
    [ValidateSet('All','Guard','HomeCapture','Home','Control','Link','Reuse','NetOpt','Scheduler','FixedUdp','FixedUdpUnit','FixedUdpMedia','FixedUdpNative')][string]$Suite='All'
)
$ErrorActionPreference = 'Stop'
Push-Location $PSScriptRoot
try {
    $doFile=if($Suite -eq 'Reuse') {'run_reuse_modelsim.do'} elseif($Suite -eq 'Link') {'run_link_modelsim.do'} elseif($Suite -eq 'Control') {'run_control_modelsim.do'} elseif($Suite -eq 'Home') {'run_home_modelsim.do'} elseif($Suite -eq 'HomeCapture') {'run_home_capture.do'} elseif($Suite -eq 'Guard') {'run_metadata_guard.do'} else {'run_modelsim.do'}
    $logFile=if($Suite -eq 'Reuse') {'modelsim_reuse.log'} elseif($Suite -eq 'Link') {'modelsim_link.log'} elseif($Suite -eq 'Control') {'modelsim_control.log'} elseif($Suite -eq 'Home') {'modelsim_home.log'} elseif($Suite -eq 'HomeCapture') {'modelsim_home_capture.log'} elseif($Suite -eq 'Guard') {'modelsim_metadata_guard.log'} else {'modelsim_regression.log'}
    if($Suite -eq 'NetOpt') {$doFile='run_netopt_modelsim.do';$logFile='modelsim_netopt.log'}
    if($Suite -eq 'Scheduler') {$doFile='run_scheduler_modelsim.do';$logFile='modelsim_scheduler.log'}
    if($Suite -eq 'FixedUdpUnit') {$doFile='run_fixed_udp_unit.do';$logFile='modelsim_fixed_udp_unit.log'}
    if($Suite -eq 'FixedUdpMedia') {$doFile='run_fixed_udp_media.do';$logFile='modelsim_fixed_udp_media.log'}
    if($Suite -eq 'FixedUdpNative') {$doFile='run_fixed_udp_native.do';$logFile='modelsim_fixed_udp_native.log'}
    if($Suite -eq 'FixedUdp') {$doFile='run_fixed_udp_modelsim.do';$logFile='modelsim_fixed_udp.log'}
    & $ModelSim -c -do "do $doFile; quit -code 0" -l $logFile
    if ($LASTEXITCODE -ne 0) { throw 'ModelSim failed.' }
    $simLog = Get-Content $logFile -Raw
    if($Suite -in 'All','FixedUdp') {
        foreach($required in 'PASS fixed UDP unit','PASS fixed UDP pair','PASS fixed UDP native FIFO padded','PASS fixed UDP native FIFO stripped','PASS fixed UDP audio offload','PASS fixed UDP media restart') {
            if($simLog -notmatch $required) {throw "Missing $required"}
        }
        if($simLog -match 'Errors: [1-9]|\*\* (Fatal|Error):') {throw 'Fixed UDP endpoint/media regression failed.'}
        if($Suite -eq 'FixedUdp') {Write-Output 'PASS 6 ModelSim fixed UDP endpoint, native FIFO and media integration cases.';return}
    }
    if($Suite -eq 'FixedUdpNative') {
        foreach($required in 'PASS fixed UDP native FIFO padded','PASS fixed UDP native FIFO stripped') {
            if($simLog -notmatch $required) {throw "Missing $required"}
        }
        if($simLog -match 'Errors: [1-9]|\*\* (Fatal|Error):') {throw 'Fixed UDP native FIFO regression failed.'}
        Write-Output 'PASS 2 ModelSim fixed UDP native FIFO integration cases.';return
    }
    if($Suite -eq 'FixedUdpMedia') {
        foreach($required in 'PASS fixed UDP audio offload','PASS fixed UDP media restart') {
            if($simLog -notmatch $required) {throw "Missing $required"}
        }
        if($simLog -match 'Errors: [1-9]|\*\* (Fatal|Error):') {throw 'Fixed UDP media regression failed.'}
        Write-Output 'PASS 2 ModelSim fixed UDP media integration cases.';return
    }
    if($Suite -eq 'FixedUdpUnit') {
        foreach($required in 'PASS fixed UDP unit','PASS fixed UDP pair') {
            if($simLog -notmatch $required) {throw "Missing $required"}
        }
        if($simLog -match 'Errors: [1-9]|\*\* (Fatal|Error):') {throw 'Fixed UDP unit regression failed.'}
        Write-Output 'PASS 2 ModelSim fixed UDP endpoint cases.';return
    }
    if($Suite -eq 'Scheduler') {
        foreach($required in 'PASS flat scheduler A','PASS flat scheduler B') {
            if($simLog -notmatch $required) {throw "Missing $required"}
        }
        if($simLog -match 'Errors: [1-9]|\*\* (Fatal|Error):') {throw 'Flat scheduler unit regression failed.'}
        Write-Output 'PASS 2 ModelSim flat scheduler unit cases.';return
    }
    if($Suite -in 'All','NetOpt') {
        foreach($required in 'PASS flat scheduler A','PASS flat scheduler B','PASS flat audio offload','PASS flat media restart') {
            if($simLog -notmatch $required) {throw "Missing $required"}
        }
        if($simLog -match 'Errors: [1-9]|\*\* (Fatal|Error):') {throw 'Network scheduler optimization regression failed.'}
        if($Suite -eq 'NetOpt') {Write-Output 'PASS 4 ModelSim flat scheduler/media cases.';return}
    }
    if($Suite -in 'All','Reuse') {
        foreach($required in 'PASS cache reuse guard','PASS cache reuse full','PASS media restart') {
            if($simLog -notmatch $required) {throw "Missing $required"}
        }
        if($simLog -match 'Errors: [1-9]|\*\* (Fatal|Error):') {throw 'Cache reuse regression failed.'}
        if($Suite -eq 'Reuse') {Write-Output 'PASS 3 ModelSim cache reuse/restart cases.';return}
    }
    if($Suite -in 'All','Link') {
        foreach($required in 'PASS link session','PASS media generation','PASS cache recovery','PASS audio session reset') {
            if($simLog -notmatch $required) {throw "Missing $required"}
        }
        if($simLog -match 'Errors: [1-9]|\*\* Fatal:') {throw 'Link recovery regression failed.'}
        if($Suite -eq 'Link') {Write-Output 'PASS 4 ModelSim session/recovery cases.';return}
    }
    if($Suite -in 'All','Control') {
        foreach($required in 'PASS media control','PASS control guard','PASS resolution image','PASS resolution guard','PASS resolution display') {
            if($simLog -notmatch $required) {throw "Missing $required"}
        }
        if($simLog -match 'Errors: [1-9]|\*\* Fatal:') {throw 'Control/resolution regression failed.'}
        if($Suite -eq 'Control') {Write-Output 'PASS 5 ModelSim control/resolution cases.';return}
    }
    if($Suite -eq 'HomeCapture') {
        if($simLog -notmatch 'PASS home capture' -or $simLog -match 'Errors: [1-9]|\*\* Fatal:') {throw 'Home capture failed.'}
        Write-Output 'PASS original home/music UI capture.'
        return
    }
    if($Suite -in 'All','Home') {
        foreach($required in 'PASS home atlas','PASS home pixels','PASS tagged image','PASS home pipeline','PASS home source') {
            if($simLog -notmatch $required) {throw "Missing $required"}
        }
        if($simLog -match 'Errors: [1-9]|\*\* Fatal:') {throw 'Home offload regression failed.'}
        if($Suite -eq 'Home') {Write-Output 'PASS 5 ModelSim home-offload cases.';return}
    }
    if (($Suite -eq 'All' -and (
        $simLog -notmatch 'PASS image link TX/RX: 1200 packets, 307200 RGB pixels' -or
        $simLog -notmatch 'PASS image_packet_rx' -or
        $simLog -notmatch 'PASS image pixel CDC' -or
        $simLog -notmatch 'PASS reliable image: 1200 packets' -or
        $simLog -notmatch 'PASS image sink guard' -or
        $simLog -notmatch 'PASS remote display' -or
        $simLog -notmatch 'PASS audio media' -or
        $simLog -notmatch 'PASS audio guard' -or
        $simLog -notmatch 'PASS media abort' -or
        $simLog -notmatch 'PASS visual guard' -or
        $simLog -notmatch 'PASS remote compute' -or
        $simLog -notmatch 'PASS audio offload' -or
        $simLog -notmatch 'PASS audio status')) -or
        $simLog -notmatch 'PASS visual guard' -or $simLog -notmatch 'PASS audio status' -or
        $simLog -match 'Errors: [1-9]' -or $simLog -match '\*\* Fatal:') {
        throw 'Required PASS results were not found; inspect modelsim_regression.log.'
    }
    if($Suite -eq 'All') {Write-Output 'PASS 40 ModelSim image, PCM, audio, home, control, resolution, session, cache reuse, flat scheduler and fixed UDP cases.'}
    else {Write-Output 'PASS ModelSim metadata/status guard cases.'}
} finally {
    Pop-Location
}
