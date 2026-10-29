onerror {quit -code 1}
if {![file exists work_image_link]} {vlib work_image_link}
set hdl ../../../src/user_source/hdl_source
vlog -sv -work work_image_link ../rtl/media_control_packet.v ../rtl/audio_visual_packet.v ../rtl/media_udp_arbiter.v $hdl/uart_baud_tick.v $hdl/uart_rx.v $hdl/uart_tx.v $hdl/uart_audio_control.v tb_media_control.v tb_control_guard.v
vlog -sv -work work_image_link ../rtl/image_packet_rx.v ../rtl/image_packet_tx.v ../rtl/image_receipt.v ../rtl/image_sdram_sink.v ../rtl/image_main_ingress.v tb_image_reliable.v tb_resolution_guard.v tb_resolution_display.v
vsim -onfinish stop -wlf media_control.wlf work_image_link.tb_media_control
log /tb_media_control/applied
log /tb_media_control/desired
log /tb_media_control/vs
log /tb_media_control/received_updates
run -all
quit -sim
vsim -onfinish stop -wlf control_guard.wlf work_image_link.tb_control_guard
log -r /*
run -all
quit -sim
vsim -onfinish stop -wlf image_resolution.wlf work_image_link.tb_image_resolution
log /tb_image_resolution/u_full/resolutions
log /tb_image_resolution/u_full/cache_valid
log /tb_image_resolution/u_full/writer_finish
run -all
quit -sim
vsim -onfinish stop -wlf resolution_guard.wlf work_image_link.tb_resolution_guard
log /tb_resolution_guard/resolution
log /tb_resolution_guard/bad
log /tb_resolution_guard/starts
run -all
quit -sim
vsim -onfinish stop -wlf resolution_display.wlf work_image_link.tb_resolution_display
log -r /*
run -all
quit -sim
