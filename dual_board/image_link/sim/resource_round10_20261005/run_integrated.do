onerror {quit -code 1}
if {![file exists work_resource10_audio]} {vlib work_resource10_audio}
vlog -work work_resource10_audio C:/Anlogic/TD_6.2.1_Engineer_6.2.168.116/sim_release/eg4/eg_phy_bram32k.v C:/Anlogic/TD_6.2.1_Engineer_6.2.168.116/sim_release/eg4/eg_phy_glbl.v
do resource_round10_20261005/run_audio_offload.do
do resource_round10_20261005/run_audio_media.do
quit -sim
do resource_round10_20261005/run_native_home.do
do resource_round10_20261005/run_writer_full.do
do resource_round10_20261005/run_boundary.do
do resource_round10_20261005/run_retry.do
quit -code 0
