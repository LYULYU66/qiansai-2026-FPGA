create_clock -name {clk_in} -period 20.000 -waveform {0.000 10.000} [get_ports {clk_50}]
create_clock -name {phy1_rgmii_rx_clk} -period 8.000 -waveform {0.000 4.000} [get_ports {phy1_rgmii_rx_clk}]
derive_clocks
