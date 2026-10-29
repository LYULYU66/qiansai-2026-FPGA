onerror {quit -code 1}
if {![file exists work_player_hw]} {vlib work_player_hw}
vlog -sv -work work_player_hw ../rtl/fixed_peer_udp.v fixed_udp_test_link.v ../rtl/media_udp_arbiter.v ../rtl/image_packet_rx.v ../rtl/image_packet_tx.v ../rtl/image_receipt.v ../rtl/image_sdram_sink.v ../rtl/image_main_ingress.v ../rtl/media_link_session.v ../rtl/media_audio_enable_cdc.v ../rtl/audio_packet_tx.v ../rtl/audio_packet_rx.v ../rtl/hw_20261005/audio_receipt_hw.v ../rtl/audio_visual_packet.v ../rtl/hw_20261005/remote_audio_compute_hw.v ../rtl/media_control_packet.v
set source_path ../../../src/user_source/hdl_source
vlog -sv -work work_player_hw $source_path/IP/afifo_32_16_256.v $source_path/hdmi_audio_pcm_i2s_64fs.v $source_path/audio_waveform_analyzer.v $source_path/audio_spectrum_analyzer.v $source_path/audio_lyric_timeline.v $source_path/lyric_song_data.v tb_audio_offload.v tb_media_restart.v
vsim -voptargs=+acc -onfinish stop -wlf hw_20261005/fixed_udp_audio_offload.wlf work_player_hw.tb_audio_offload_fixed
log /tb_audio_offload_fixed/test/played_words
log /tb_audio_offload_fixed/test/analysed_words
log /tb_audio_offload_fixed/test/blackout
log /tb_audio_offload_fixed/test/net_rx_valid
log /tb_audio_offload_fixed/test/net_rx_length
log /tb_audio_offload_fixed/test/fixed_transport/media_link/sender/tx_state
log /tb_audio_offload_fixed/test/fixed_transport/media_link/receiver/rx_state
run -all
quit -sim
vsim -voptargs=+acc -onfinish stop -wlf hw_20261005/fixed_udp_media_restart.wlf work_player_hw.tb_media_restart_fixed
log /tb_media_restart_fixed/test/ag
log /tb_media_restart_fixed/test/bg
log /tb_media_restart_fixed/test/played_words
log /tb_media_restart_fixed/test/cache
log /tb_media_restart_fixed/test/a_rx_valid
log /tb_media_restart_fixed/test/b_rx_valid
log /tb_media_restart_fixed/test/a_rx_length
log /tb_media_restart_fixed/test/b_rx_length
run -all
quit -sim
