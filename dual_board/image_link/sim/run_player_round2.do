onerror {quit -code 1}
if {![file exists work_player_round2]} {vlib work_player_round2}
vlog -sv -work work_player_round2 ../rtl/hw_round2_20261005/top_dual_image_hw.v ../../../src/user_source/hdl_source/SD/frame_fifo_read.v tb_player_frame_reset.v
vsim -onfinish stop -wlf hw_round2_20261005/frame_reset.wlf work_player_round2.tb_player_frame_reset
log -r /*
run -all
quit -sim
do hw_round2_20261005/run_home_modelsim.do
quit -code 0
