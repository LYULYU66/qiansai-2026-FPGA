onerror {quit -code 1}
if {![file exists work_player_round5]} {vlib work_player_round5}
vlog -sv -work work_player_round5 ../rtl/hw_round4_20261005/player_domain_reset.v
onerror {quit -code 1}
if {![file exists work_player_round5]} {vlib work_player_round5}
vlog -sv -work work_player_round5 ../rtl/hw_20261005/audio_receipt_hw.v ../rtl/hw_round4_20261005/audio_visual_packet_hw.v tb_audio_status_guard.v tb_audio_visual_guard.v
vsim -voptargs=+acc -onfinish stop -wlf hw_round5_20261005/audio_status_guard.wlf work_player_round5.tb_audio_status_guard
log -r /*
run -all
quit -sim
vsim -voptargs=+acc -onfinish stop -wlf hw_round5_20261005/audio_visual_guard.wlf work_player_round5.tb_audio_visual_guard
log -r /*
run -all
quit -sim
quit -code 0
