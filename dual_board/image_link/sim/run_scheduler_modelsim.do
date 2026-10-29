onerror {quit -code 1}
if {![file exists work_image_link]} {vlib work_image_link}
vlog -sv -work work_image_link ../rtl/media_udp_arbiter.v tb_media_scheduler.v
vsim -voptargs=+acc -onfinish stop -wlf flat_scheduler_b.wlf work_image_link.tb_media_scheduler
log -r /*
run -all
quit -sim
vsim -voptargs=+acc -onfinish stop -wlf flat_scheduler_a.wlf work_image_link.tb_media_scheduler_a
log -r /*
run -all
quit -sim
