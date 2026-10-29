onerror {quit -f -code 1}
file mkdir sim/alignment_probe_20260926
set lib sim/alignment_probe_20260926/integration_work
if {![file exists $lib]} {vlib $lib}
set hdl src/user_source/hdl_source
vlog -sv -work $lib +incdir+$hdl/SD sim/tb_video_read_axis_stress.v $hdl/SD/video_timing_data.v $hdl/SD/color_bar.v $hdl/SD/frame_fifo_read.v $hdl/SD/video_delay.v $hdl/IP/afifo_32_16_256.v $hdl/video_frame_valid_gate.v $hdl/video_transition_effects.v $hdl/video_image_adjust.v $hdl/video_rgb_to_axis_640x480.v $hdl/video_pixel_diagnostics.v
foreach spec {{normal +FRAMES=2} {early_read +SHIFT=-1 +FRAMES=1}} {
    set name [lindex $spec 0]
    transcript file sim/alignment_probe_20260926/${name}_modelsim.log
    vsim -onfinish stop -wlf sim/alignment_probe_20260926/$name.wlf -lib $lib tb_video_read_axis_stress +OUT=sim/alignment_probe_20260926/$name {*}[lrange $spec 1 end]
    foreach s {video_clk de vs actual_re rdusedw empty dout fifo_valid dd raw_rgb ad adjusted_rgb valid user last axis_rgb alignment_flags alignment_ready raw_errors axis_errors underflows sof_errors test_passed} {log /tb_video_read_axis_stress/$s}
    run -all
    if {[examine -radix unsigned /tb_video_read_axis_stress/test_passed] != 1} {quit -f -code 1}
    echo "PROBE FLAGS [examine -radix binary /tb_video_read_axis_stress/alignment_flags] READY [examine /tb_video_read_axis_stress/alignment_ready]"
    quit -sim
}
echo "PASS ALIGNMENT PROBE IN REAL READ/AXIS CHAIN"
quit -f -code 0
