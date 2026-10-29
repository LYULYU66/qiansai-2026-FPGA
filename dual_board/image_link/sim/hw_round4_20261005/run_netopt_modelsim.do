onerror {quit -code 1}
if {![file exists work_player_round4]} {vlib work_player_round4}
vlog -sv -work work_player_round4 ../rtl/hw_round4_20261005/player_domain_reset.v
onerror {quit -code 1}
if {![file exists work_player_round4]} {vlib work_player_round4}
do hw_round4_20261005/run_scheduler_modelsim.do
# Real media producers, receivers, original audio analysers and native FIFO.
vlog -sv -work work_player_round4 ../rtl/image_packet_rx.v ../rtl/image_packet_tx.v ../rtl/image_receipt.v ../rtl/image_sdram_sink.v ../rtl/image_main_ingress.v ../rtl/media_link_session.v ../rtl/media_audio_enable_cdc.v ../rtl/audio_packet_tx.v ../rtl/audio_packet_rx.v ../rtl/hw_20261005/audio_receipt_hw.v ../rtl/hw_round4_20261005/audio_visual_packet_hw.v ../rtl/hw_round4_20261005/remote_audio_compute_hw.v ../rtl/media_control_packet.v
set source_path ../../../src/user_source/hdl_source
vlog -sv -work work_player_round4 $source_path/IP/afifo_32_16_256.v $source_path/hdmi_audio_pcm_i2s_64fs.v $source_path/audio_waveform_analyzer.v $source_path/audio_spectrum_analyzer.v $source_path/audio_lyric_timeline.v $source_path/lyric_song_data.v tb_audio_offload.v tb_media_restart.v
vsim -voptargs=+acc -onfinish stop -wlf hw_round4_20261005/flat_audio_offload.wlf work_player_round4.tb_audio_offload_flat
log /tb_audio_offload_flat/test/played_words
log /tb_audio_offload_flat/test/analysed_words
log /tb_audio_offload_flat/test/blackout
log /tb_audio_offload_flat/test/flat_outgoing/scheduler/owner
log /tb_audio_offload_flat/test/flat_outgoing/scheduler/remaining
run -all
quit -sim
vsim -voptargs=+acc -onfinish stop -wlf hw_round4_20261005/flat_media_restart.wlf work_player_round4.tb_media_restart_flat
log /tb_media_restart_flat/test/ag
log /tb_media_restart_flat/test/bg
log /tb_media_restart_flat/test/played_words
log /tb_media_restart_flat/test/cache
log /tb_media_restart_flat/test/flat_b/scheduler/aborting
run -all
quit -sim
