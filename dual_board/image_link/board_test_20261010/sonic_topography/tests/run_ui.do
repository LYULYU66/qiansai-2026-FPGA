onerror {quit -code 1}
set w work_sonic_ui
if {![file exists $w]} {vlib $w}
set src ../../../src/user_source/hdl_source
vlog -sv -work $w ../rtl/sonic_topography_20261009/audio_visualizer_overlay.v ../rtl/sonic_topography_20261009/video_sonic_topography.v ../rtl/video_remote_home_overlay.v ../rtl/home_assets/home_palette_rom.v $src/video_image_adjust.v $src/video_rgb_to_axis_640x480.v sonic_topography_20261009/tb_sonic_chain.sv sonic_topography_20261009/tb_sonic_vu.sv ../../../sim/tb_audio_visualizer_overlay.v resource_round10_20261005/golden_audio_visualizer_overlay.v resource_round10_20261005/tb_visualizer_equivalence.v
foreach test {tb_sonic_chain tb_sonic_vu tb_audio_visualizer_overlay tb_visualizer_equivalence} {
 vsim -voptargs=+acc -onfinish stop -wlf sonic_topography_20261009/${test}.wlf $w.$test
 run -all
 quit -sim
}
quit -code 0
