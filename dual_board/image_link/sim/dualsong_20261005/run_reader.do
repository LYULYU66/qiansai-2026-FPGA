onerror {quit -code 1}
if {![file exists work_dualsong_reader]} {vlib work_dualsong_reader}
vlog -sv -work work_dualsong_reader ../rtl/dualsong_20261005/bmp_read.v ../rtl/dualsong_20261005/sd_card_bmp_remote.v ../rtl/hw_round4_20261005/player_domain_reset.v dualsong_20261005/tb_dualsong_reader.v
vsim -voptargs=+acc -onfinish stop -wlf dualsong_20261005/reader.wlf work_dualsong_reader.tb_dualsong_reader
log -r /*
run -all
quit -code 0
