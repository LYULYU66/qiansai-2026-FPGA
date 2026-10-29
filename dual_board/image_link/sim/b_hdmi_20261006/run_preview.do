onerror {quit -code 1}
set w work_b_preview_20261006
if {![file exists $w]} {vlib $w}
set src ../../../src/user_source/hdl_source
set branch ../rtl/b_hdmi_20261006
vlog -work $w C:/Anlogic/TD_6.2.1_Engineer_6.2.168.116/sim_release/eg4/eg_phy_bram32k.v C:/Anlogic/TD_6.2.1_Engineer_6.2.168.116/sim_release/eg4/eg_phy_glbl.v
vlog -sv -work $w +incdir+$src/SD ../rtl/hw_round4_20261005/player_domain_reset.v $branch/b_image_capture.v $branch/b_hdmi_preview.v ../rtl/hw_round7_20261005/frame_read_write_hw.v $src/SD/frame_fifo_write.v $src/SD/frame_fifo_read.v $src/IP/afifo_16_32_256.v $src/IP/afifo_32_16_256.v $src/SD/color_bar.v $src/SD/video_timing_data.v $src/SD/video_delay.v $src/video_rgb_to_axis_640x480.v $src/startup_pulse.v b_hdmi_20261006/b_hdmi_models.v b_hdmi_20261006/tb_b_hdmi_preview.v
vsim -voptargs=+acc -onfinish stop -wlf b_hdmi_20261006/preview.wlf $w.tb_b_hdmi_preview $w.glbl
log /tb_b_hdmi_preview/dut/u_capture/state
log /tb_b_hdmi_preview/dut/u_capture/accepted
log /tb_b_hdmi_preview/dut/pixel_ready
log /tb_b_hdmi_preview/dut/write_req
log /tb_b_hdmi_preview/dut/write_ack
log /tb_b_hdmi_preview/dut/write_finish
log /tb_b_hdmi_preview/dut/done_toggle
log /tb_b_hdmi_preview/dut/frame_index
log /tb_b_hdmi_preview/dut/frame_valid
log /tb_b_hdmi_preview/dut/read_en
log /tb_b_hdmi_preview/dut/u_frames/read_empty_a
log /tb_b_hdmi_preview/dut/axis_user
log /tb_b_hdmi_preview/dut/axis_valid
log /tb_b_hdmi_preview/dut/axis_last
run -all
quit -code 0
