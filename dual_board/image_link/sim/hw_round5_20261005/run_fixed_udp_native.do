onerror {quit -code 1}
if {![file exists work_player_round5]} {vlib work_player_round5}
vlog -sv -work work_player_round5 ../rtl/hw_round4_20261005/player_domain_reset.v
onerror {quit -code 1}
if {![file exists work_player_fixed_round5_native]} {vlib work_player_fixed_round5_native}
vlog -sv -work work_player_fixed_round5_native ../rtl/fixed_peer_udp.v fixed_udp_native_ram_model.v ../../ethernet_smoke/source_code/rtl/tx_client_fifo.v ../../ethernet_smoke/source_code/rtl/rx_client_fifo.v tb_fixed_udp_native_fifo.v
vsim -voptargs=+acc -onfinish stop -wlf hw_round5_20261005/fixed_udp_native_padded.wlf work_player_fixed_round5_native.tb_fixed_udp_native_fifo
log -r /tb_fixed_udp_native_fifo/*
run -all
quit -sim
vsim -voptargs=+acc -onfinish stop -wlf hw_round5_20261005/fixed_udp_native_stripped.wlf work_player_fixed_round5_native.tb_fixed_udp_native_fifo_stripped
log -r /tb_fixed_udp_native_fifo_stripped/test/*
run -all
quit -sim
