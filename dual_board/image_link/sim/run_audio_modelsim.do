onerror {quit -code 1}
if {![file exists work_image_link]} {vlib work_image_link}
vlog -sv -work work_image_link ../rtl/image_packet_rx.v ../rtl/image_packet_tx.v ../rtl/image_receipt.v ../rtl/audio_packet_tx.v ../rtl/audio_packet_rx.v ../rtl/audio_receipt.v ../rtl/media_udp_arbiter.v ../../../src/user_source/hdl_source/IP/afifo_32_16_256.v ../../../src/user_source/hdl_source/hdmi_audio_pcm_i2s_64fs.v tb_audio_media.v tb_audio_guard.v
vsim -voptargs=+acc -onfinish stop -wlf audio_guard.wlf work_image_link.tb_audio_guard
log -r /*
run -all
quit -sim
vsim -voptargs=+acc -onfinish stop -wlf media_abort.wlf work_image_link.tb_media_abort
log -r /*
run -all
quit -sim
vsim -voptargs=+acc -onfinish stop -wlf audio_media.wlf work_image_link.tb_audio_media
log /tb_audio_media/played_words
log /tb_audio_media/fifo_used
log /tb_audio_media/fifo_rdused
log /tb_audio_media/pcm_read
log /tb_audio_media/playing
log /tb_audio_media/underflow
log /tb_audio_media/blackout
log /tb_audio_media/rx/state
log /tb_audio_media/a_sequence
log /tb_audio_media/reported_progress
run -all
quit -code 0
