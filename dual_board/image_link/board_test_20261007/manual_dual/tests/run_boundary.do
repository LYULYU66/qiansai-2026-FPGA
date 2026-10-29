onerror {quit -code 1}
set w work_manual_dual_boundary
if {![file exists $w]} {vlib $w}
set branch ../rtl/manual_dual_20261007
set hw4 ../rtl/hw_round4_20261005
set src ../../../src/user_source/hdl_source
set sd $src/SD
vlog -work $w C:/Anlogic/TD_6.2.1_Engineer_6.2.168.116/sim_release/eg4/eg_phy_bram32k.v C:/Anlogic/TD_6.2.1_Engineer_6.2.168.116/sim_release/eg4/eg_phy_glbl.v
vlog -sv -work $w $hw4/player_domain_reset.v $branch/image_media_board_b_hw.v $branch/image_tf_source_hw.v $hw4/audio_visual_packet_hw.v ../rtl/yilu_replace_20261006/remote_audio_compute_hw.v ../rtl/dualsong_20261005/audio_receipt_b.v ../rtl/hw_round2_20261005/home_index_stream_hw.v ../rtl/home_assets/home_atlas_rom.v
vlog -sv -work $w ../rtl/hw_round5_20261005/image_packet_tx_hw.v ../rtl/image_packet_rx.v ../rtl/image_receipt.v ../rtl/image_pixel_cdc.v ../rtl/audio_packet_tx.v ../rtl/audio_packet_rx.v ../rtl/media_link_session.v ../rtl/media_udp_arbiter.v $branch/media_control_packet.v $branch/sd_card_bmp_remote.v
vlog -sv -work $w $src/IP/afifo_32_16_256.v ../rtl/resource_round10_20261005/audio_waveform_analyzer.v $src/audio_spectrum_analyzer.v ../rtl/yilu_replace_20261006/audio_lyric_timeline.v ../rtl/yilu_replace_20261006/dual_lyric_song_data.v $src/uart_audio_control.v $src/uart_baud_tick.v $src/uart_rx.v $src/uart_tx.v
vlog -sv -work $w $branch/bmp_read.v $sd/bmp_bilinear_stream.v $sd/sd_card_top.v $sd/sd_card_sec_read_write.v $sd/sd_card_cmd.v $sd/spi_master.v $sd/ax_debounce.v dualsong_20261005/audio_receipt_a_test.v manual_dual_20261007/tb_b_boundary.v
vlog -sv -work $w +incdir+$sd $branch/b_hdmi_preview.v $branch/b_image_capture.v ../rtl/hw_round7_20261005/frame_read_write_hw.v $sd/frame_fifo_write.v $sd/frame_fifo_read.v $src/IP/afifo_16_32_256.v $sd/color_bar.v $sd/video_timing_data.v $sd/video_delay.v $src/video_rgb_to_axis_640x480.v $src/startup_pulse.v manual_dual_20261007/b_hdmi_models.v
vlog -sv -work $w ../rtl/firefly_video_20261006/video_dual_star_overlay.v
vsim -voptargs=+acc -onfinish stop -wlf manual_dual_20261007/b_boundary.wlf $w.tb_b_boundary $w.glbl
log /tb_b_boundary/dut/media_reset
log /tb_b_boundary/dut/media_sd_reset
log /tb_b_boundary/dut/stream_enable
log /tb_b_boundary/dut/stream_active
log /tb_b_boundary/dut/file_bytes
log /tb_b_boundary/dut/file_samples_udp
log /tb_b_boundary/dut/audio_session
log /tb_b_boundary/dut/pcm_read
log /tb_b_boundary/dut/analysed_words
log /tb_b_boundary/received
log /tb_b_boundary/dut/u_packet_scheduler/remaining
log /tb_b_boundary/dut/u_media/epoch_counter
log /tb_b_boundary/dut/u_media/udp_index
log /tb_b_boundary/dut/u_local_hdmi/page_token
run -all
quit -code 0
