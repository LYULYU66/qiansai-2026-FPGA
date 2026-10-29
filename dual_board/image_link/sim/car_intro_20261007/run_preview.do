onerror {quit -code 1}
set w work_car_intro_preview
if {![file exists $w]} {vlib $w}
set src ../../../src/user_source/hdl_source
set branch ../rtl/manual_dual_20261007
vlog -work $w C:/Anlogic/TD_6.2.1_Engineer_6.2.168.116/sim_release/eg4/eg_phy_bram32k.v C:/Anlogic/TD_6.2.1_Engineer_6.2.168.116/sim_release/eg4/eg_phy_glbl.v
vlog -sv -work $w +incdir+stars_opt_20261007 +incdir+car_intro_20261007 +incdir+$src/SD ../rtl/hw_round4_20261005/player_domain_reset.v $branch/b_image_capture.v ../rtl/car_intro_20261007/b_hdmi_preview.v $branch/sd_card_bmp_remote.v ../rtl/hw_round7_20261005/frame_read_write_hw.v $src/SD/frame_fifo_write.v $src/SD/frame_fifo_read.v $src/IP/afifo_16_32_256.v $src/IP/afifo_32_16_256.v $src/SD/color_bar.v $src/SD/video_timing_data.v $src/SD/video_delay.v $src/video_rgb_to_axis_640x480.v $src/startup_pulse.v manual_dual_20261007/b_hdmi_models.v car_intro_20261007/tb_b_hdmi_preview.v
vlog -sv -work $w ../rtl/stars_opt_20261007/video_dual_star_overlay.v ../rtl/stars_opt_20261007/audio_visual_packet_hw.v
vlog -sv -work $w ../rtl/car_intro_20261007/video_car_intro.v ../rtl/car_intro_20261007/car_intro_rom.v
vsim -voptargs=+acc -onfinish stop -wlf car_intro_20261007/preview.wlf $w.tb_b_hdmi_preview $w.glbl
log /tb_b_hdmi_preview/dut/u_capture/state
log /tb_b_hdmi_preview/dut/u_capture/accepted
log /tb_b_hdmi_preview/dut/pixel_ready
log /tb_b_hdmi_preview/dut/write_req
log /tb_b_hdmi_preview/dut/write_ack
log /tb_b_hdmi_preview/dut/write_finish
log /tb_b_hdmi_preview/dut/done_toggle
log /tb_b_hdmi_preview/dut/committed_mask
log /tb_b_hdmi_preview/dut/committed_slot0
log /tb_b_hdmi_preview/dut/committed_slot1
log /tb_b_hdmi_preview/dut/requested_page
log /tb_b_hdmi_preview/dut/frame_index
log /tb_b_hdmi_preview/dut/frame_page
log /tb_b_hdmi_preview/dut/frame_valid
log /tb_b_hdmi_preview/dut/page_token
log /tb_b_hdmi_preview/dut/read_en
log /tb_b_hdmi_preview/dut/u_frames/read_empty_a
log /tb_b_hdmi_preview/dut/axis_user
log /tb_b_hdmi_preview/dut/axis_valid
log /tb_b_hdmi_preview/dut/axis_last
log /tb_b_hdmi_preview/dut/star_phase_video
log /tb_b_hdmi_preview/dut/u_stars/frame_phase
run -all
quit -code 0

