# Run from project root: vsim -c -do sim/run_modelsim_video_alignment.do
onerror {quit -f -code 1}
vlib sim/video_alignment_work
vlog -sv -work sim/video_alignment_work sim/tb_video_sof_boundaries.v sim/tb_video_fifo_alignment.v src/user_source/hdl_source/video_rgb_to_axis_640x480.v src/user_source/hdl_source/SD/frame_fifo_read.v src/user_source/hdl_source/SD/video_delay.v src/user_source/hdl_source/IP/afifo_32_16_256.v
vsim -onfinish stop -wlf sim/video_sof_boundaries.wlf -lib sim/video_alignment_work tb_video_sof_boundaries
log -r /*
run -all
quit -sim
vsim -onfinish stop -wlf sim/video_fifo_alignment.wlf -lib sim/video_alignment_work tb_video_fifo_alignment
# Ports/status only, not the FIFO memory array.
log /tb_video_fifo_alignment/de /tb_video_fifo_alignment/read_en /tb_video_fifo_alignment/rdusedw /tb_video_fifo_alignment/dout /tb_video_fifo_alignment/empty /tb_video_fifo_alignment/de_r /tb_video_fifo_alignment/rgb /tb_video_fifo_alignment/fifo_valid
run -all
quit -f
