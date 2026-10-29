onerror {quit -code 1}
set w work_dual_stars_pixels
if {![file exists $w]} {vlib $w}
vlog -sv -work $w +incdir+dual_stars_20261006 ../rtl/dual_stars_20261006/video_dual_star_overlay.v ../rtl/dual_stars_20261006/media_control_packet.v ../rtl/hw_round4_20261005/audio_visual_packet_hw.v dual_stars_20261006/tb_dual_stars.v dual_stars_20261006/tb_star_control.v dual_stars_20261006/tb_star_guard.v tb_control_guard.v
vsim -voptargs=+acc -onfinish stop -wlf dual_stars_20261006/star_control.wlf $w.tb_star_control
log /tb_star_control/master
log /tb_star_control/remote
log /tb_star_control/applied_a
log /tb_star_control/applied_b
log /tb_star_control/drop
log /tb_star_control/corrupt
log /tb_star_control/vs
run -all
quit -sim
vsim -onfinish stop -wlf dual_stars_20261006/star_pixels.wlf $w.tb_dual_stars
log /tb_dual_stars/phase
log /tb_dual_stars/dut_a/frame_phase
log /tb_dual_stars/dut_b/frame_phase
log /tb_dual_stars/vs
run -all
quit -sim
vsim -onfinish stop $w.tb_control_guard
run -all
quit -sim
vsim -onfinish stop $w.tb_star_guard
run -all
quit -code 0
