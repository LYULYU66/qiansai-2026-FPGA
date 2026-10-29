onerror {quit -f -code 1}
set lib sim/alignment_20260926/source_work
file mkdir sim/alignment_20260926
if {![file exists $lib]} {vlib $lib}
transcript file sim/alignment_20260926/source_sof_modelsim.log
vlog -sv -work $lib sim/tb_video_source_sof.v src/user_source/hdl_source/video_source_test.v
vsim -onfinish stop -wlf sim/alignment_20260926/source_sof.wlf -lib $lib tb_video_source_sof
foreach s {user valid last data x y frames} {log /tb_video_source_sof/$s}
run -all
if {[examine -radix unsigned /tb_video_source_sof/frames] != 2} {quit -f -code 1}
quit -f -code 0
