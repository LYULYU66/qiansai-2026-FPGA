onerror {quit -code 1}
if {![file exists work_fixed_udp_hw]} {vlib work_fixed_udp_hw}
vlog -sv -work work_fixed_udp_hw ../../image_link/rtl/fixed_peer_udp.v ../../image_link/rtl/image_packet_rx.v ../../image_link/rtl/image_receipt.v ../rtl/fixed_udp_hw_pattern.v ../rtl/fixed_udp_hw_a.v ../rtl/fixed_udp_hw_b.v tb_fixed_udp_hw.v
vsim -voptargs=+acc -onfinish stop -wlf fixed_udp_hw_full.wlf work_fixed_udp_hw.tb_fixed_udp_hw
log /tb_fixed_udp_hw/a/count
log /tb_fixed_udp_hw/a/good
log /tb_fixed_udp_hw/a/error_latched
log /tb_fixed_udp_hw/b/count
log /tb_fixed_udp_hw/b/packets_sent
log /tb_fixed_udp_hw/b/ack_latched
run -all
quit -sim
