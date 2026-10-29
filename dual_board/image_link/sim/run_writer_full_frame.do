onerror {quit -code 1}
if {![file exists work_writer_full7]} {vlib work_writer_full7}
set hdl ../../../src/user_source/hdl_source
vlog -work work_writer_full7 C:/Anlogic/TD_6.2.1_Engineer_6.2.168.116/sim_release/eg4/eg_phy_bram32k.v C:/Anlogic/TD_6.2.1_Engineer_6.2.168.116/sim_release/eg4/eg_phy_glbl.v
vlog -sv -work work_writer_full7 ../rtl/hw_round3_20261005/top_dual_image_hw.v ../rtl/hw_round7_20261005/frame_read_write_hw.v hw_round7_20261005/frame_read_write_golden.v ../rtl/image_sdram_sink.v $hdl/SD/frame_fifo_write.v $hdl/SD/frame_fifo_read.v $hdl/IP/afifo_16_32_256.v $hdl/IP/afifo_32_16_256.v tb_image_writer_full_frame.v
vsim -voptargs=+acc -onfinish stop -wlf hw_round7_20261005/writer_reset_window.wlf work_writer_full7.tb_image_writer_full_frame work_writer_full7.glbl
log -r /tb_image_writer_full_frame/*
run -all
quit -sim
quit -code 0
