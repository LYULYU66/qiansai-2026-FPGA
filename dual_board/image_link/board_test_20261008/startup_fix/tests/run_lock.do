onerror {quit -code 1}
set w work_startup_fix_lock
if {![file exists $w]} {vlib $w}
vlog -sv -work $w ../rtl/startup_fix_20261008/media_udp_arbiter.v startup_fix_20261008/tb_scheduler_lock.v
vsim -voptargs=+acc -onfinish stop -wlf startup_fix_20261008/lock.wlf $w.tb_scheduler_lock
log -r /*
run -all
quit -code 0
