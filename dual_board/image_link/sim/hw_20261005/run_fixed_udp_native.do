onerror {quit -code 1}
if {![file exists work_player_fixed_udp_native]} {vlib work_player_fixed_udp_native}
vlog -sv -work work_player_fixed_udp_native ../rtl/fixed_peer_udp.v fixed_udp_native_ram_model.v ../../ethernet_smoke/source_code/rtl/tx_client_fifo.v ../../ethernet_smoke/source_code/rtl/rx_client_fifo.v tb_fixed_udp_native_fifo.v
vsim -voptargs=+acc -onfinish stop -wlf hw_20261005/fixed_udp_native_padded.wlf work_player_fixed_udp_native.tb_fixed_udp_native_fifo
log -r /tb_fixed_udp_native_fifo/*
run -all
quit -sim
vsim -voptargs=+acc -onfinish stop -wlf hw_20261005/fixed_udp_native_stripped.wlf work_player_fixed_udp_native.tb_fixed_udp_native_fifo_stripped
log -r /tb_fixed_udp_native_fifo_stripped/test/*
run -all
quit -sim
