onerror {quit -code 1}
if {![file exists work_player_boundary8]} {vlib work_player_boundary8}
set work4 work_player_boundary8
set hw4 ../rtl/hw_round4_20261005
set source4 ../../../src/user_source/hdl_source
set sd4 $source4/SD
vlog -work $work4 C:/Anlogic/TD_6.2.1_Engineer_6.2.168.116/sim_release/eg4/eg_phy_bram32k.v C:/Anlogic/TD_6.2.1_Engineer_6.2.168.116/sim_release/eg4/eg_phy_glbl.v
vlog -sv -work $work4 $hw4/player_domain_reset.v $hw4/image_media_board_b_hw.v ../rtl/hw_round8_20261005/image_tf_source_hw.v $hw4/audio_visual_packet_hw.v $hw4/remote_audio_compute_hw.v ../rtl/hw_round6_20261005/audio_receipt_hw.v ../rtl/hw_round2_20261005/home_index_stream_hw.v ../rtl/home_assets/home_atlas_rom.v
vlog -sv -work $work4 ../rtl/hw_round5_20261005/image_packet_tx_hw.v ../rtl/image_packet_rx.v ../rtl/image_receipt.v ../rtl/image_pixel_cdc.v ../rtl/audio_packet_tx.v ../rtl/audio_packet_rx.v ../rtl/media_link_session.v ../rtl/media_udp_arbiter.v ../rtl/media_control_packet.v ../rtl/sd_card_bmp_remote.v
vlog -sv -work $work4 $source4/IP/afifo_32_16_256.v $source4/audio_waveform_analyzer.v $source4/audio_spectrum_analyzer.v $source4/audio_lyric_timeline.v $source4/lyric_song_data.v $source4/uart_audio_control.v $source4/uart_baud_tick.v $source4/uart_rx.v $source4/uart_tx.v
vlog -sv -work $work4 $sd4/bmp_read.v $sd4/bmp_bilinear_stream.v $sd4/sd_card_top.v $sd4/sd_card_sec_read_write.v $sd4/sd_card_cmd.v $sd4/spi_master.v $sd4/ax_debounce.v tb_home_stage_retry.v
vsim -voptargs=+acc -onfinish stop -wlf hw_round8_20261005/home_stage_retry.wlf $work4.tb_home_stage_retry $work4.glbl
log /tb_home_stage_retry/dut/bridge_sd_reset
log /tb_home_stage_retry/dut/bridge_udp_reset
log /tb_home_stage_retry/dut/source_count
log /tb_home_stage_retry/dut/pixel_ready
log /tb_home_stage_retry/received
run -all
quit -sim
quit -code 0
