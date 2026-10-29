onerror {quit -code 1}
set w work_startup_fix_restart
if {![file exists $w]} {vlib $w}
set source_path ../../../src/user_source/hdl_source
vlog -sv -work $w ../rtl/fixed_peer_udp.v fixed_udp_test_link.v ../rtl/startup_fix_20261008/media_udp_arbiter.v startup_fix_20261008/media_udp_scheduler_legacy.v ../rtl/image_packet_rx.v ../rtl/hw_round5_20261005/image_packet_tx_hw.v ../rtl/image_receipt.v ../rtl/image_sdram_sink.v ../rtl/image_main_ingress.v ../rtl/media_link_session.v ../rtl/media_audio_enable_cdc.v ../rtl/audio_packet_tx.v ../rtl/audio_packet_rx.v ../rtl/audio_receipt.v
vlog -sv -work $w $source_path/IP/afifo_32_16_256.v $source_path/hdmi_audio_pcm_i2s_64fs.v startup_fix_20261008/tb_media_restart.v
vsim -voptargs=+acc -onfinish stop -wlf startup_fix_20261008/restart.wlf $w.tb_media_restart_fixed
log /tb_media_restart_fixed/test/ag
log /tb_media_restart_fixed/test/bg
log /tb_media_restart_fixed/test/page
log /tb_media_restart_fixed/test/cache
log /tb_media_restart_fixed/test/a_ready
log /tb_media_restart_fixed/test/b_ready
log /tb_media_restart_fixed/test/played_words
log /tb_media_restart_fixed/test/flat_b/scheduler/remaining
run -all
quit -code 0

