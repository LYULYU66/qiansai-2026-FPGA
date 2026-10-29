onerror {quit -code 1}
if {![file exists work_player_round2]} {vlib work_player_round2}
vlog -sv -work work_player_round2 ../rtl/hw_20261005/audio_receipt_hw.v ../rtl/audio_visual_packet.v tb_audio_status_guard.v tb_audio_visual_guard.v
vsim -voptargs=+acc -onfinish stop -wlf hw_round2_20261005/audio_status_guard.wlf work_player_round2.tb_audio_status_guard
log -r /*
run -all
quit -sim
vsim -voptargs=+acc -onfinish stop -wlf hw_round2_20261005/audio_visual_guard.wlf work_player_round2.tb_audio_visual_guard
log -r /*
run -all
quit -sim
quit -code 0
