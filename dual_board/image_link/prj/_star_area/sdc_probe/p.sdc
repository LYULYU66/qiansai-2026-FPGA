create_clock -name udp_clk -period 8 [get_ports {uclk}]
create_clock -name video_clk -period 40 [get_ports {vclk}]
set_max_delay -datapath_only -from [get_clocks {udp_clk}] -to [get_regs -nowarn {u_control_snapshot/dst_data[*]}] 32
