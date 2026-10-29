onerror {quit -code 1}
set w work_manual_dual_reader
if {![file exists $w]} {vlib $w}
vlog -sv -work $w ../rtl/manual_dual_20261007/bmp_read.v ../rtl/manual_dual_20261007/sd_card_bmp_remote.v ../rtl/hw_round4_20261005/player_domain_reset.v manual_dual_20261007/tb_dualsong_reader.v
vsim -voptargs=+acc -onfinish stop -wlf manual_dual_20261007/reader_six.wlf $w.tb_manual_dualsong_reader
log -r /*
run -all
quit -sim
vsim -voptargs=+acc -onfinish stop -wlf manual_dual_20261007/reader_four.wlf -gMAX_IMAGES=4 $w.tb_manual_dualsong_reader
log -r /*
run -all
quit -code 0
