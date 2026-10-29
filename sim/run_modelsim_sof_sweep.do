onerror {quit -f -code 1}
file mkdir sim/alignment_20260926
set lib sim/alignment_20260926/sof_work
if {![file exists $lib]} {vlib $lib}
transcript file sim/alignment_20260926/sof_sweep_modelsim.log
vlog -sv -work $lib sim/tb_sof_phase_sweep.v src/user_source/hdl_source/video_rgb_to_axis_640x480.v
vsim -onfinish stop -voptargs=+acc -wlf sim/alignment_20260926/sof_sweep.wlf -lib $lib tb_sof_phase_sweep
log -r /*
run -all
if {[examine -radix unsigned sim:/tb_sof_phase_sweep/test_passed] != 1} {quit -f -code 1}
quit -f -code 0
