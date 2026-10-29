# Run from project root in ModelSim after successful simulation.
vsim -view sim/alignment_20260926/phase3_lat8.wlf
view wave
add wave -divider {FIFO read-side alignment}
foreach signal {video_clk de actual_re rdusedw empty dout fifo_valid dd raw_rgb} {
    add wave -radix hexadecimal /tb_video_read_axis_stress/$signal
}
add wave -divider {AXIS frame/line alignment}
foreach signal {ad adjusted_rgb valid user last axis_rgb axis_index} {
    add wave -radix hexadecimal /tb_video_read_axis_stress/$signal
}
configure wave -timelineunits ns
wave zoom range 18215000ns 18217500ns
