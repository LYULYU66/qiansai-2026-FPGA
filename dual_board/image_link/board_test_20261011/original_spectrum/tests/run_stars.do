onerror {quit -code 1}
set w work_stars_opt_pixels
if {![file exists $w]} {vlib $w}
vlog -sv -work $w +incdir+stars_opt_20261007 ../rtl/stars_opt_20261007/video_dual_star_overlay.v ../rtl/manual_dual_20261007/media_control_packet.v ../rtl/stars_opt_20261007/audio_visual_packet_hw.v stars_opt_20261007/tb_star_motion.v stars_opt_20261007/tb_star_control.v stars_opt_20261007/tb_dual_stars.v
vsim -onfinish stop $w.tb_star_motion
run -all
quit -sim
vsim -onfinish stop $w.tb_star_control
run -all
quit -sim
vsim -onfinish stop -wlf stars_opt_20261007/stars.wlf $w.tb_dual_stars
log /tb_dual_stars/phase
log /tb_dual_stars/dut_a/row_ready
log /tb_dual_stars/dut_b/row_ready
run -all
quit -code 0
