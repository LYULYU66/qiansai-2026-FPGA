onerror {quit -code 1}
if {![file exists work_player_guard5]} {vlib work_player_guard5}
vlog -sv -work work_player_guard5 hw_round5_20261005/image_packet_tx_golden.v ../rtl/hw_round5_20261005/image_packet_tx_hw.v tb_image_tx_pipeline_equiv.v
vsim -voptargs=+acc -onfinish stop -wlf hw_round5_20261005/image_tx_pipeline_equiv.wlf work_player_guard5.tb_image_tx_pipeline_equiv
log /tb_image_tx_pipeline_equiv/p3/dut/packet_read_enable
log /tb_image_tx_pipeline_equiv/p3/dut/ram_pixel
log /tb_image_tx_pipeline_equiv/p3/dut/payload_pixel
log /tb_image_tx_pipeline_equiv/p3/dut/byte_phase
log /tb_image_tx_pipeline_equiv/p3/dut/byte_index
log /tb_image_tx_pipeline_equiv/p3/dut/udp_data
log /tb_image_tx_pipeline_equiv/p3/dut/crc_running
log /tb_image_tx_pipeline_equiv/p3/golden/udp_data
log /tb_image_tx_pipeline_equiv/p3/rst
run -all
quit -sim
quit -code 0
