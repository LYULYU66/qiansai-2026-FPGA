onerror {quit -code 1}
if {![file exists work_yilu_boundary]} {vlib work_yilu_boundary}
set work4 work_yilu_boundary
set hw4 ../rtl/hw_round4_20261005
set source4 ../../../src/user_source/hdl_source
set sd4 $source4/SD
vlog -work $work4 C:/Anlogic/TD_6.2.1_Engineer_6.2.168.116/sim_release/eg4/eg_phy_bram32k.v C:/Anlogic/TD_6.2.1_Engineer_6.2.168.116/sim_release/eg4/eg_phy_glbl.v
vlog -sv -work $work4 $hw4/player_domain_reset.v ../rtl/dual_stars_20261006/image_media_board_b_hw.v ../rtl/dual_stars_20261006/image_tf_source_hw.v $hw4/audio_visual_packet_hw.v ../rtl/yilu_replace_20261006/remote_audio_compute_hw.v ../rtl/dualsong_20261005/audio_receipt_b.v ../rtl/hw_round2_20261005/home_index_stream_hw.v ../rtl/home_assets/home_atlas_rom.v
vlog -sv -work $work4 ../rtl/hw_round5_20261005/image_packet_tx_hw.v ../rtl/image_packet_rx.v ../rtl/image_receipt.v ../rtl/image_pixel_cdc.v ../rtl/audio_packet_tx.v ../rtl/audio_packet_rx.v ../rtl/media_link_session.v ../rtl/media_udp_arbiter.v ../rtl/dual_stars_20261006/media_control_packet.v ../rtl/dualsong_20261005/sd_card_bmp_remote.v
vlog -sv -work $work4 $source4/IP/afifo_32_16_256.v ../rtl/resource_round10_20261005/audio_waveform_analyzer.v $source4/audio_spectrum_analyzer.v ../rtl/yilu_replace_20261006/audio_lyric_timeline.v ../rtl/yilu_replace_20261006/dual_lyric_song_data.v $source4/uart_audio_control.v $source4/uart_baud_tick.v $source4/uart_rx.v $source4/uart_tx.v
vlog -sv -work $work4 ../rtl/dualsong_20261005/bmp_read.v $sd4/bmp_bilinear_stream.v $sd4/sd_card_top.v $sd4/sd_card_sec_read_write.v $sd4/sd_card_cmd.v $sd4/spi_master.v $sd4/ax_debounce.v dualsong_20261005/audio_receipt_a_test.v yilu_replace_20261006/tb_b_hdmi_boundary.v dual_stars_20261006/tb_b_preview_source.v
vlog -sv -work $work4 +incdir+$sd4 ../rtl/dual_stars_20261006/b_hdmi_preview.v ../rtl/dual_stars_20261006/b_image_capture.v ../rtl/hw_round7_20261005/frame_read_write_hw.v $sd4/frame_fifo_write.v $sd4/frame_fifo_read.v $source4/IP/afifo_16_32_256.v $sd4/color_bar.v $sd4/video_timing_data.v $sd4/video_delay.v $source4/video_rgb_to_axis_640x480.v $source4/startup_pulse.v dual_stars_20261006/b_hdmi_models.v
vlog -sv -work $work4 ../rtl/dual_stars_20261006/video_dual_star_overlay.v
vsim -voptargs=+acc -onfinish stop -wlf yilu_replace_20261006/b_boundary.wlf $work4.tb_dualsong_b_boundary $work4.glbl
log /tb_dualsong_b_boundary/dut/media_reset
log /tb_dualsong_b_boundary/dut/media_sd_reset
log /tb_dualsong_b_boundary/dut/stream_enable
log /tb_dualsong_b_boundary/dut/stream_active
log /tb_dualsong_b_boundary/dut/file_bytes
log /tb_dualsong_b_boundary/dut/file_samples_udp
log /tb_dualsong_b_boundary/dut/audio_session
log /tb_dualsong_b_boundary/dut/pcm_read
log /tb_dualsong_b_boundary/dut/analysed_words
log /tb_dualsong_b_boundary/received
log /tb_dualsong_b_boundary/dut/u_packet_scheduler/remaining
log /tb_dualsong_b_boundary/dut/u_media/epoch_counter
run -all
quit -sim
vsim -voptargs=+acc -onfinish stop -wlf yilu_replace_20261006/source.wlf $work4.tb_b_preview_source $work4.glbl
log /tb_b_preview_source/dut/bridge_sd_reset
log /tb_b_preview_source/dut/bridge_udp_reset
log /tb_b_preview_source/dut/source_count
log /tb_b_preview_source/dut/pixel_ready
log /tb_b_preview_source/received
run -all
quit -sim

quit -code 0
