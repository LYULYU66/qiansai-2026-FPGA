onerror {quit -code 1}
if {![file exists work_image_link]} {vlib work_image_link}
vlog -sv -work work_image_link ../rtl/media_link_session.v ../rtl/media_udp_arbiter.v ../rtl/image_packet_rx.v ../rtl/image_sdram_sink.v ../rtl/audio_packet_rx.v tb_link_session.v tb_media_generation.v
vlog -work work_image_link ../rtl/media_audio_enable_cdc.v ../../../src/user_source/hdl_source/hdmi_audio_pcm_i2s_64fs.v tb_audio_session_reset.v
vsim -voptargs=+acc -onfinish stop -wlf link_session.wlf work_image_link.tb_link_session
log -r /*
run -all
quit -sim
vsim -voptargs=+acc -onfinish stop -wlf media_generation.wlf work_image_link.tb_media_generation
log -r /*
run -all
quit -sim
vsim -voptargs=+acc -onfinish stop -wlf cache_recovery.wlf work_image_link.tb_cache_recovery
log -r /*
run -all
quit -sim
vsim -voptargs=+acc -onfinish stop -wlf audio_session_reset.wlf work_image_link.tb_audio_session_reset
log -r /*
run -all
quit -sim
