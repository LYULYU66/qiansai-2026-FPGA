onerror {quit -code 1}
if {![file exists work_player_round4]} {vlib work_player_round4}
vlog -sv -work work_player_round4 ../rtl/hw_round4_20261005/player_domain_reset.v tb_player_domain_resets.v
vsim -onfinish stop -wlf hw_round4_20261005/domain_resets.wlf work_player_round4.tb_player_domain_resets
log -r /*
run -all
quit -sim
vsim -onfinish stop -wlf hw_round4_20261005/audio_metadata.wlf work_player_round4.tb_player_audio_metadata
log -r /*
run -all
quit -sim
vlog -sv -work work_player_round4 ../rtl/hw_20261005/audio_receipt_hw.v ../rtl/hw_round4_20261005/audio_visual_packet_hw.v ../rtl/hw_round4_20261005/remote_audio_compute_hw.v ../../../src/user_source/hdl_source/audio_waveform_analyzer.v ../../../src/user_source/hdl_source/audio_spectrum_analyzer.v ../../../src/user_source/hdl_source/audio_lyric_timeline.v ../../../src/user_source/hdl_source/lyric_song_data.v tb_player_pipeline_guard.v
vsim -onfinish stop -wlf hw_round4_20261005/pipeline_guard.wlf work_player_round4.tb_player_pipeline_guard
log -r /*
run -all
quit -sim
quit -code 0
