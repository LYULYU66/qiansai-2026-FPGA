onerror {quit -code 1}
if {![file exists work_image_link]} {vlib work_image_link}
vlog -sv -work work_image_link ../rtl/audio_receipt.v ../rtl/audio_visual_packet.v tb_audio_status_guard.v tb_audio_visual_guard.v
vsim -voptargs=+acc -onfinish stop -wlf audio_status_guard.wlf work_image_link.tb_audio_status_guard
log -r /*
run -all
quit -sim
vsim -voptargs=+acc -onfinish stop -wlf audio_visual_guard.wlf work_image_link.tb_audio_visual_guard
log -r /*
run -all
quit -sim
quit -code 0
