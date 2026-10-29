onerror {quit -code 1}
set w work_manual_dual_scan
if {![file exists $w]} {vlib $w}
set src ../../../src/user_source/hdl_source
vlog -sv -work $w ../rtl/manual_dual_20261007/bmp_read.v manual_dual_20261007/tb_six_scan.v
vsim -onfinish stop $w.tb_six_scan
run -all
quit -sim
vsim -onfinish stop -gMAX_IMAGES=4 $w.tb_six_scan
run -all
quit -sim
vsim -onfinish stop -gPICTURE_COUNT=5 $w.tb_six_scan
run -all
quit -sim
vsim -onfinish stop -gMUSIC_COUNT=0 $w.tb_six_scan
run -all
quit -sim
set w work_manual_dual_preload
if {![file exists $w]} {vlib $w}
vlog -sv -work $w +define+BILINEAR_FAST_SIM ../rtl/manual_dual_20261007/bmp_read.v ../rtl/manual_dual_20261007/sd_card_bmp_remote.v $src/SD/bmp_bilinear_stream.v manual_dual_20261007/tb_six_preload.sv
vsim -onfinish stop $w.tb_six_preload
run -all
quit -sim
vsim -onfinish stop -gTOTAL_IMAGES=4 $w.tb_six_preload
run -all
quit -code 0
