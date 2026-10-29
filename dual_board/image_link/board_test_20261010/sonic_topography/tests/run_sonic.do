onerror {quit -code 1}
if {![file exists work_sonic_topography]} {vlib work_sonic_topography}
vlog -sv -work work_sonic_topography ../rtl/sonic_topography_20261009/video_sonic_topography.v sonic_topography_20261009/tb_sonic_topography.sv
vsim -voptargs=+acc -onfinish stop -wlf sonic_topography_20261009/sonic.wlf work_sonic_topography.tb_sonic_topography
log /tb_sonic_topography/dut/state /tb_sonic_topography/dut/display_bank /tb_sonic_topography/dut/job_index /tb_sonic_topography/dut/height_valid /tb_sonic_topography/dut/volume_frame
run -all
quit -code 0
