onerror {quit -code 1}
if {![file exists work_player_guard6]} {vlib work_player_guard6}
vlog -sv -work work_player_guard6 ../rtl/hw_round6_20261005/audio_receipt_hw.v hw_round6_20261005/audio_receipt_golden.v tb_audio_receipt_pipeline_equiv.v
vsim -voptargs=+acc -onfinish stop -wlf hw_round6_20261005/audio_receipt_equiv.wlf work_player_guard6.tb_audio_receipt_pipeline_equiv
log -r /tb_audio_receipt_pipeline_equiv/*
run -all
quit -sim
quit -code 0
