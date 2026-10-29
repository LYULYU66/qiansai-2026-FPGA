# Formal B clocks: UART 50 MHz, TF 100 MHz, compute 25 MHz, UDP/MAC 125 MHz.
create_clock -name clk_50 -period 20.000 -waveform {0.000 10.000} [get_ports {clk_50}]
create_clock -name phy1_rgmii_rx_clk -period 8.000 -waveform {0.000 4.000} [get_ports {phy1_rgmii_rx_clk}]
derive_clocks
rename_clock -name sd_clk -source [get_ports {clk_50}] -master_clock clk_50 [get_pins {u_sd_clock/pll_inst.clkc[0]}]
rename_clock -name mac_tx_clk -source [get_ports {clk_50}] -master_clock clk_50 [get_pins {u_net/u_clk_gen/u_pll_0/pll_inst.clkc[0]}]
rename_clock -name udp_clk -source [get_ports {clk_50}] -master_clock clk_50 [get_pins {u_net/u_clk_gen/u_pll_0/pll_inst.clkc[1]}]
rename_clock -name compute_clk -source [get_ports {clk_50}] -master_clock clk_50 [get_pins {u_net/u_clk_gen/u_pll_0/pll_inst.clkc[3]}]
rename_clock -name rgmii_tx_shift_clk -source [get_ports {clk_50}] -master_clock clk_50 [get_pins {u_net/u_clk_gen/u_pll_0/pll_inst.clkc[4]}]
rename_clock -name rgmii_rx_0 -source [get_ports {phy1_rgmii_rx_clk}] -master_clock phy1_rgmii_rx_clk [get_pins {u_net/u_rx_pll/pll_inst.clkc[0]}]
rename_clock -name rgmii_rx_90 -source [get_ports {phy1_rgmii_rx_clk}] -master_clock phy1_rgmii_rx_clk [get_pins {u_net/u_rx_pll/pll_inst.clkc[1]}]
set_clock_groups -asynchronous \
    -group [get_clocks {phy1_rgmii_rx_clk rgmii_rx_0 rgmii_rx_90}] \
    -group [get_clocks {clk_50 sd_clk mac_tx_clk udp_clk compute_clk rgmii_tx_shift_clk}]
# TF/UART/compute clocks remain related to clk_50. Any bundled-mailbox or Gray
# crossing needing an exception must be justified at its exact endpoints.
# External PHY and TF SPI IO timing still requires specification-based audit.
