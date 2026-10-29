# After running the ModelSim regression, execute this in its GUI.
vsim -view sim/video_fifo_alignment.wlf
add wave /tb_video_fifo_alignment/de
add wave /tb_video_fifo_alignment/read_en
add wave -radix unsigned /tb_video_fifo_alignment/rdusedw
add wave /tb_video_fifo_alignment/empty
add wave /tb_video_fifo_alignment/fifo_valid
add wave -radix hexadecimal /tb_video_fifo_alignment/dout
add wave /tb_video_fifo_alignment/de_r
add wave -radix hexadecimal /tb_video_fifo_alignment/rgb
wave zoom range 1120400ns 1122000ns
