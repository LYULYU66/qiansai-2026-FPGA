onerror {quit -code 1}
if {![file exists work_fixed_udp]} {vlib work_fixed_udp}
vlog -sv -work work_fixed_udp ../rtl/fixed_peer_udp.v tb_fixed_peer_udp.v
vsim -voptargs=+acc -onfinish stop -wlf fixed_udp_unit.wlf work_fixed_udp.tb_fixed_peer_udp
log -r /tb_fixed_peer_udp/*
run -all
quit -sim
vsim -voptargs=+acc -onfinish stop -wlf fixed_udp_pair.wlf work_fixed_udp.tb_fixed_peer_udp_pair
log -r /tb_fixed_peer_udp_pair/*
run -all
quit -sim
