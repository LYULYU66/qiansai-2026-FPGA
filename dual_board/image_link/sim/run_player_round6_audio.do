onerror {quit -code 1}
if {![file exists work_player_round6_audio]} {vlib work_player_round6_audio}
vlog -work work_player_round6_audio C:/Anlogic/TD_6.2.1_Engineer_6.2.168.116/sim_release/eg4/eg_phy_bram32k.v C:/Anlogic/TD_6.2.1_Engineer_6.2.168.116/sim_release/eg4/eg_phy_glbl.v
do hw_round6_20261005/run_offload_modelsim.do
do hw_round6_20261005/run_audio_modelsim.do
quit -code 0
