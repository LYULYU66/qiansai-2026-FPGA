# Run from project root. Uses production RTL; no hardware changes.
onerror {quit -f -code 1}
file mkdir sim/alignment_20260926
if {![info exists lib]} {set lib sim/alignment_20260926/work}
if {![file exists $lib]} {vlib $lib}
set hdl src/user_source/hdl_source
if {![info exists skip_compile]} {
    vlog -sv -work $lib +incdir+$hdl/SD sim/tb_video_read_axis_stress.v $hdl/SD/video_timing_data.v $hdl/SD/color_bar.v $hdl/SD/frame_fifo_read.v $hdl/SD/video_delay.v $hdl/IP/afifo_32_16_256.v $hdl/video_frame_valid_gate.v $hdl/video_transition_effects.v $hdl/video_image_adjust.v $hdl/video_rgb_to_axis_640x480.v $hdl/video_pixel_diagnostics.v
}
if {[info exists compile_only]} {quit -f -code 0}
set cases {
    {phase0_lat1 +PHASE=0 +LATENCY=1}
    {phase1_lat8 +PHASE=1 +LATENCY=8}
    {phase3_lat8 +PHASE=3 +LATENCY=8}
    {phase5_lat10 +PHASE=5 +LATENCY=10}
    {phase9_lat10 +PHASE=9 +LATENCY=10}
    {static_6frames +PHASE=3 +LATENCY=8 +FRAMES=6 +PAUSE=650}
    {early_read +SHIFT=-1 +FRAMES=1}
    {late_read +SHIFT=1 +FRAMES=1}
    {late_dout +DATA_DELAY=1 +FRAMES=1}
    {starvation +STARVE +FRAMES=1}
}
if {[info exists group]} {
    if {$group == 0} {set cases [lrange $cases 0 4]}
    if {$group == 1} {set cases [lrange $cases 5 5]}
    if {$group == 2} {set cases [lrange $cases 6 9]}
}
foreach spec $cases {
    set name [lindex $spec 0]
    transcript file sim/alignment_20260926/${name}_modelsim.log
    echo "MODELSIM CASE $name"
    vsim -onfinish stop -voptargs=+acc -wlf sim/alignment_20260926/$name.wlf -lib $lib tb_video_read_axis_stress +OUT=sim/alignment_20260926/$name {*}[lrange $spec 1 end]
    foreach signal {video_clk rst de vs read_req ack aclr actual_re read_en rdusedw empty dout fifo_valid dd raw_rgb ad adjusted_rgb valid user last axis_rgb frame_valid frames read_index raw_index axis_index raw_errors axis_errors underflows sof_errors alignment_flags alignment_ready test_passed} {
        log sim:/tb_video_read_axis_stress/$signal
    }
    run -all
    if {[examine -radix unsigned sim:/tb_video_read_axis_stress/test_passed] != 1} {
        echo "FAILED: $name (see waveform and transcript)"
        quit -f -code 1
    }
    quit -sim
}
echo "PASS MODELSIM READ_AXIS SELECTED CASES: [llength $cases]"
quit -f -code 0
