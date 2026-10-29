onerror {quit -code 1}
if {![file exists work_player_hw]} {vlib work_player_hw}
set source_path ../../../src/user_source/hdl_source
vlog -sv -work work_player_hw ../rtl/hw_20261005/audio_receipt_hw.v ../rtl/hw_20261005/remote_audio_compute_hw.v ../rtl/audio_visual_packet.v $source_path/audio_waveform_analyzer.v $source_path/audio_spectrum_analyzer.v $source_path/audio_lyric_timeline.v $source_path/lyric_song_data.v tb_player_pipeline_guard.v
vsim -voptargs=+acc -onfinish stop -wlf hw_20261005/pipeline_guard.wlf work_player_hw.tb_player_pipeline_guard
log /tb_player_pipeline_guard/sent
log /tb_player_pipeline_guard/checked
log /tb_player_pipeline_guard/source_ready
log /tb_player_pipeline_guard/dut/backlog_q
log /tb_player_pipeline_guard/played
run -all
quit -sim
