onerror {quit -code 1}
if {![file exists work_player_round4]} {vlib work_player_round4}
vlog -sv -work work_player_round4 ../rtl/hw_round4_20261005/player_domain_reset.v
onerror {quit -code 1}
if {![file exists work_player_round4]} {vlib work_player_round4}
vlog -sv -work work_player_round4 ../rtl/media_udp_arbiter.v tb_media_scheduler.v
vsim -voptargs=+acc -onfinish stop -wlf hw_round4_20261005/flat_scheduler_b.wlf work_player_round4.tb_media_scheduler
log -r /*
run -all
quit -sim
vsim -voptargs=+acc -onfinish stop -wlf hw_round4_20261005/flat_scheduler_a.wlf work_player_round4.tb_media_scheduler_a
log -r /*
run -all
quit -sim
