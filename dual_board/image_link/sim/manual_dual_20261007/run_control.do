onerror {quit -code 1}
set w work_manual_dual_page_sync
if {![file exists $w]} {vlib $w}
set hdl ../../../src/user_source/hdl_source
vlog -sv -work $w ../rtl/manual_dual_20261007/media_control_packet.v ../rtl/manual_dual_20261007/image_remote_display_control.v ../rtl/audio_visual_packet.v $hdl/SD/sd_card_bmp.v manual_dual_20261007/tb_page_sync.v tb_control_guard.v dual_stars_20261006/tb_star_guard.v tb_remote_display.v
vsim -voptargs=+acc -onfinish stop -wlf manual_dual_20261007/page_sync.wlf $w.tb_page_sync
log /tb_page_sync/received_page
log /tb_page_sync/received_phase
log /tb_page_sync/video_snapshot
log /tb_page_sync/video_capture
log /tb_page_sync/image_index
log /tb_page_sync/display/remote_pending
log /tb_page_sync/display/auto_play
log /tb_page_sync/hazard
log /tb_page_sync/cache
run -all
quit -sim
vsim -onfinish stop $w.tb_control_guard
run -all
quit -sim
vsim -onfinish stop $w.tb_star_guard
run -all
quit -sim
vsim -onfinish stop $w.tb_remote_display
run -all
quit -code 0
