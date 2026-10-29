onerror {quit -code 1}
if {![file exists work_startup_fix_scheduler]} {vlib work_startup_fix_scheduler}
vlog -sv -work work_startup_fix_scheduler ../rtl/startup_fix_20261008/media_udp_arbiter.v startup_fix_20261008/tb_media_scheduler.v
vsim -voptargs=+acc -onfinish stop -wlf startup_fix_20261008/flat_scheduler_b.wlf work_startup_fix_scheduler.tb_media_scheduler
log -r /*
run -all
quit -sim
vsim -voptargs=+acc -onfinish stop -wlf startup_fix_20261008/flat_scheduler_a.wlf work_startup_fix_scheduler.tb_media_scheduler_a
log -r /*
run -all
quit -sim

quit -code 0

