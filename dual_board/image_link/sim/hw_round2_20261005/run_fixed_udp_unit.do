onerror {quit -code 1}
if {![file exists work_player_fixed_round2]} {vlib work_player_fixed_round2}
vlog -sv -work work_player_fixed_round2 ../rtl/fixed_peer_udp.v tb_fixed_peer_udp.v
vsim -voptargs=+acc -onfinish stop -wlf hw_round2_20261005/fixed_udp_unit.wlf work_player_fixed_round2.tb_fixed_peer_udp
log -r /tb_fixed_peer_udp/*
run -all
quit -sim
vsim -voptargs=+acc -onfinish stop -wlf hw_round2_20261005/fixed_udp_pair.wlf work_player_fixed_round2.tb_fixed_peer_udp_pair
log -r /tb_fixed_peer_udp_pair/*
run -all
quit -sim
