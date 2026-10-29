onerror {quit -code 1}
if {![file exists work_player_round4]} {vlib work_player_round4}
vlog -sv -work work_player_round4 ../rtl/hw_round4_20261005/player_domain_reset.v
onerror {quit -code 1}
do hw_round4_20261005/run_fixed_udp_unit.do
do hw_round4_20261005/run_fixed_udp_native.do
do hw_round4_20261005/run_fixed_udp_media.do
