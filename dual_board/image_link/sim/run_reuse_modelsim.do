onerror {quit -code 1}
if {![file exists work_image_link]} {vlib work_image_link}
vlog -sv -work work_image_link ../rtl/image_packet_rx.v ../rtl/image_packet_tx.v ../rtl/image_receipt.v ../rtl/image_sdram_sink.v ../rtl/image_main_ingress.v tb_cache_reuse.v
vlog -sv -work work_image_link ../rtl/media_link_session.v ../rtl/media_udp_arbiter.v ../rtl/audio_packet_tx.v ../rtl/audio_packet_rx.v ../rtl/audio_receipt.v ../rtl/media_audio_enable_cdc.v ../../../src/user_source/hdl_source/IP/afifo_32_16_256.v ../../../src/user_source/hdl_source/hdmi_audio_pcm_i2s_64fs.v tb_media_restart.v
vsim -voptargs=+acc -onfinish stop -wlf cache_reuse_guard.wlf work_image_link.tb_cache_reuse
log /tb_cache_reuse/main/u_sink/state
log /tb_cache_reuse/main/u_sink/frame_crc
log /tb_cache_reuse/main/u_sink/cached_crc
log /tb_cache_reuse/main/u_sink/crc_pending
log /tb_cache_reuse/main/u_sink/final_ack_valid
log /tb_cache_reuse/main/u_sink/cache_valid
log /tb_cache_reuse/write_en
log /tb_cache_reuse/frame_sent
log /tb_cache_reuse/phase
run -all
quit -sim
vsim -voptargs=+acc -onfinish stop -wlf cache_reuse_full.wlf work_image_link.tb_cache_reuse_full
log /tb_cache_reuse_full/full_frame/main/u_sink/state
log /tb_cache_reuse_full/full_frame/main/u_sink/frame_crc
log /tb_cache_reuse_full/full_frame/main/u_sink/final_ack_valid
log /tb_cache_reuse_full/full_frame/main/u_sink/cache_valid
log /tb_cache_reuse_full/full_frame/total_writes
log /tb_cache_reuse_full/full_frame/frame_sent
run -all
quit -sim
vsim -voptargs=+acc -onfinish stop -wlf media_restart.wlf work_image_link.tb_media_restart
log /tb_media_restart/ag
log /tb_media_restart/bg
log /tb_media_restart/a_ready
log /tb_media_restart/b_ready
log /tb_media_restart/br
log /tb_media_restart/page
log /tb_media_restart/protect_mask
log /tb_media_restart/cache
log /tb_media_restart/ingress/u_sink/state
log /tb_media_restart/ingress/u_sink/final_ack_valid
log /tb_media_restart/write_en
log /tb_media_restart/playing_session
log /tb_media_restart/played_words
log /tb_media_restart/fifo_reset
run -all
quit -sim
