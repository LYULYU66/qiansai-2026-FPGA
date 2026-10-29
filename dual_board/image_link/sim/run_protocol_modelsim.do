onerror {quit -code 1}
if {![file exists work_image_link]} {vlib work_image_link}
vlog -sv -work work_image_link ../rtl/audio_packet_rx.v ../rtl/media_udp_arbiter.v tb_audio_guard.v
vsim -voptargs=+acc -onfinish stop -wlf audio_guard.wlf work_image_link.tb_audio_guard
log -r /*
run -all
quit -sim
vsim -voptargs=+acc -onfinish stop -wlf media_abort.wlf work_image_link.tb_media_abort
log -r /*
run -all
quit -sim
quit -code 0
