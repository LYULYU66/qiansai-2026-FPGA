onerror {quit -code 1}
if {![file exists work_player_round2]} {vlib work_player_round2}
vlog -sv -work work_player_round2 ../rtl/media_link_session.v ../rtl/media_udp_arbiter.v ../rtl/image_packet_rx.v ../rtl/image_sdram_sink.v ../rtl/audio_packet_rx.v tb_link_session.v tb_media_generation.v
vlog -work work_player_round2 ../rtl/media_audio_enable_cdc.v ../../../src/user_source/hdl_source/hdmi_audio_pcm_i2s_64fs.v tb_audio_session_reset.v
vsim -voptargs=+acc -onfinish stop -wlf hw_round2_20261005/link_session.wlf work_player_round2.tb_link_session
log -r /*
run -all
quit -sim
vsim -voptargs=+acc -onfinish stop -wlf hw_round2_20261005/media_generation.wlf work_player_round2.tb_media_generation
log -r /*
run -all
quit -sim
vsim -voptargs=+acc -onfinish stop -wlf hw_round2_20261005/cache_recovery.wlf work_player_round2.tb_cache_recovery
log -r /*
run -all
quit -sim
vsim -voptargs=+acc -onfinish stop -wlf hw_round2_20261005/audio_session_reset.wlf work_player_round2.tb_audio_session_reset
log -r /*
run -all
quit -sim
