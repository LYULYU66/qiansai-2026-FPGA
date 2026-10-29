onerror {quit -code 1}
if {![file exists work_player_round3]} {vlib work_player_round3}
vlog -sv -work work_player_round3 ../rtl/hw_round3_20261005/top_dual_image_hw.v ../../../src/user_source/hdl_source/SD/frame_fifo_read.v tb_player_frame_reset.v
vsim -onfinish stop -wlf hw_round3_20261005/frame_reset.wlf work_player_round3.tb_player_frame_reset
log -r /*
run -all
quit -sim
vlog -sv -work work_player_round3 ../rtl/hw_round3_20261005/frame_read_write_hw.v ../../../src/user_source/hdl_source/SD/frame_fifo_write.v ../../../src/user_source/hdl_source/IP/afifo_32_16_256.v ../../../src/user_source/hdl_source/IP/afifo_16_32_256.v tb_player_frame_credit.v
vsim -onfinish stop -wlf hw_round3_20261005/frame_credit.wlf work_player_round3.tb_player_frame_credit
log -r /*
run -all
quit -sim
do hw_round2_20261005/run_home_modelsim.do
quit -code 0
