transcript on
if {[file exists transition_work]} {
    vdel -lib transition_work -all
}
vlib transition_work
vmap work transition_work
vlog ../src/user_source/hdl_source/video_transition_effects.v tb_video_transition_effects.v
vsim -c tb_video_transition_effects
run -all
quit -f
