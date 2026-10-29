onerror {quit -code 1}
set w work_dual_stars_uart
if {![file exists $w]} {vlib $w}
set hdl ../../../src/user_source/hdl_source
vlog -sv -work $w ../rtl/dual_stars_20261006/media_control_packet.v ../rtl/hw_round4_20261005/audio_visual_packet_hw.v ../rtl/media_udp_arbiter.v $hdl/uart_baud_tick.v $hdl/uart_rx.v $hdl/uart_tx.v $hdl/uart_audio_control.v dual_stars_20261006/tb_media_control_stars.v
vsim -onfinish stop -wlf dual_stars_20261006/uart.wlf $w.tb_media_control_stars
log /tb_media_control_stars/applied
log /tb_media_control_stars/star_phase
log /tb_media_control_stars/blackout
log /tb_media_control_stars/vs
run -all
quit -code 0
