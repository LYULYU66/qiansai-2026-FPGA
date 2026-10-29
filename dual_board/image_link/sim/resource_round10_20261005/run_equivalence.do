onerror {quit -code 1}
if {![file exists work_resource_r10]} {vlib work_resource_r10}
vlog -sv -work work_resource_r10 golden_audio_waveform_analyzer.v golden_video_status_overlay.v golden_audio_visualizer_overlay.v ../../rtl/resource_round10_20261005/audio_waveform_analyzer.v ../../rtl/resource_round10_20261005/video_status_overlay.v ../../rtl/resource_round10_20261005/audio_visualizer_overlay.v tb_resource_equivalence.v tb_visualizer_equivalence.v
vsim -voptargs=+acc -onfinish stop -wlf wave_equivalence.wlf work_resource_r10.tb_wave_resource_equivalence
log /tb_wave_resource_equivalence/new_dut/capture_active
log /tb_wave_resource_equivalence/new_dut/capture_index
log /tb_wave_resource_equivalence/new_wave
log /tb_wave_resource_equivalence/old_wave
run -all
quit -sim
vsim -voptargs=+acc -onfinish stop -wlf status_equivalence.wlf work_resource_r10.tb_status_resource_equivalence
log /tb_status_resource_equivalence/new_dut/width_digits
log /tb_status_resource_equivalence/new_dut/height_digits
log /tb_status_resource_equivalence/new_rgb
log /tb_status_resource_equivalence/old_rgb
run -all
quit -sim
vsim -voptargs=+acc -onfinish stop -wlf visualizer_equivalence.wlf work_resource_r10.tb_visualizer_equivalence
log /tb_visualizer_equivalence/new_dut/wave_smooth_busy
log /tb_visualizer_equivalence/new_dut/wave_scaled_valid
log /tb_visualizer_equivalence/new_dut/wave_lane_valid
log /tb_visualizer_equivalence/new_rgb
log /tb_visualizer_equivalence/old_rgb
run -all
quit -sim
quit -code 0
