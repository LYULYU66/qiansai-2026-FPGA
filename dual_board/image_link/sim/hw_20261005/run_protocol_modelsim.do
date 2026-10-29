onerror {quit -code 1}
if {![file exists work_player_hw]} {vlib work_player_hw}
vlog -sv -work work_player_hw ../rtl/audio_packet_rx.v ../rtl/media_udp_arbiter.v tb_audio_guard.v
vsim -voptargs=+acc -onfinish stop -wlf hw_20261005/audio_guard.wlf work_player_hw.tb_audio_guard
log -r /*
run -all
quit -sim
vsim -voptargs=+acc -onfinish stop -wlf hw_20261005/media_abort.wlf work_player_hw.tb_media_abort
log -r /*
run -all
quit -sim
quit -code 0
