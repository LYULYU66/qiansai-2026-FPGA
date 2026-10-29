import_device eagle_s20.db -package EG4S20BG256
read_verilog -file {top.v ../../../rtl/star_sky_20261020/star_motion_engine.v} -top probe_top
optimize_rtl
optimize_gate
create_clock -name udp_clk -period 8 [get_ports {uclk}]
create_clock -name video_clk -period 40 [get_ports {vclk}]
puts "MATCH-HIER [llength [get_regs -hier -nowarn {dst_data*}]]"
puts "MATCH [llength [get_regs -nowarn {dst_data*}]]"
set_max_delay -datapath_only -from [get_clocks {udp_clk}] -to [get_regs -nowarn {dst_data*}] 32
report_timing_exception -file e.txt
exit
