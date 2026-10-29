onerror {quit -code 1}
if {![file exists work_player_round2]} {vlib work_player_round2}
vlog -sv -work work_player_round2 ../rtl/image_packet_rx.v ../rtl/image_packet_tx.v ../rtl/image_receipt.v ../rtl/audio_packet_tx.v ../rtl/audio_packet_rx.v ../rtl/hw_20261005/audio_receipt_hw.v ../rtl/media_udp_arbiter.v ../rtl/audio_visual_packet.v ../rtl/hw_20261005/remote_audio_compute_hw.v ../rtl/media_control_packet.v
set source_path ../../../src/user_source/hdl_source
vlog -sv -work work_player_round2 $source_path/IP/afifo_32_16_256.v $source_path/hdmi_audio_pcm_i2s_64fs.v $source_path/audio_waveform_analyzer.v $source_path/audio_spectrum_analyzer.v $source_path/audio_lyric_timeline.v $source_path/lyric_song_data.v tb_audio_offload.v tb_remote_compute.v tb_audio_visual_guard.v tb_audio_status_guard.v
vsim -voptargs=+acc -onfinish stop -wlf hw_round2_20261005/audio_status_guard.wlf work_player_round2.tb_audio_status_guard
log -r /*
run -all
quit -sim
vsim -voptargs=+acc -onfinish stop -wlf hw_round2_20261005/audio_visual_guard.wlf work_player_round2.tb_audio_visual_guard
log -r /*
run -all
quit -sim
vsim -voptargs=+acc -onfinish stop -wlf hw_round2_20261005/remote_compute.wlf work_player_round2.tb_remote_compute
log /tb_remote_compute/analysed
log /tb_remote_compute/source_ready
log /tb_remote_compute/dut/target
log /tb_remote_compute/dut/volume
log /tb_remote_compute/dut/sample_valid
log /tb_remote_compute/dut/u_lyrics/sample_count
run -all
quit -sim
vsim -voptargs=+acc -onfinish stop -wlf hw_round2_20261005/audio_offload.wlf work_player_round2.tb_audio_offload
log /tb_audio_offload/played_words
log /tb_audio_offload/analysed_words
log /tb_audio_offload/reported_progress
log /tb_audio_offload/settled
log /tb_audio_offload/blackout
log /tb_audio_offload/playing
log /tb_audio_offload/compute/target
log /tb_audio_offload/compute/u_lyrics/sample_count
log /tb_audio_offload/vis_rx/progress
run -all
quit -sim
# Return to the full regression driver; it now also runs home-offload tests.
