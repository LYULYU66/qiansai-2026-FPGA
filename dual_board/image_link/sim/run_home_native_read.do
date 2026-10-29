onerror {quit -code 1}
if {![file exists work_home_native7]} {vlib work_home_native7}
set hdl ../../../src/user_source/hdl_source
vlog -work work_home_native7 C:/Anlogic/TD_6.2.1_Engineer_6.2.168.116/sim_release/eg4/eg_phy_bram32k.v C:/Anlogic/TD_6.2.1_Engineer_6.2.168.116/sim_release/eg4/eg_phy_glbl.v
vlog -sv -work work_home_native7 ../rtl/hw_round3_20261005/top_dual_image_hw.v ../rtl/hw_round7_20261005/frame_read_write_hw.v $hdl/SD/frame_fifo_write.v $hdl/SD/frame_fifo_read.v $hdl/IP/afifo_16_32_256.v $hdl/IP/afifo_32_16_256.v $hdl/SD/video_delay.v $hdl/video_transition_effects.v $hdl/video_image_adjust.v ../rtl/video_remote_home_overlay.v ../rtl/home_assets/home_palette_rom.v tb_home_native_read.v
vsim -voptargs=+acc -onfinish stop -wlf hw_round7_20261005/home_native_read.wlf work_home_native7.tb_home_native_read work_home_native7.glbl
log /tb_home_native_read/de /tb_home_native_read/read_en /tb_home_native_read/read_word /tb_home_native_read/raw_word /tb_home_native_read/fw/read_buf_a/rdusedw /tb_home_native_read/read_empty /tb_home_native_read/transition_index /tb_home_native_read/home_rgb
run -all
quit -sim
quit -code 0
