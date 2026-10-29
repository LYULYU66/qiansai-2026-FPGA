# Formal B clocks: system 50 MHz, TF 50 MHz, compute 25 MHz, MAC 125 MHz,
# UDP application side 62.5 MHz since 20261021 (pll_gen_b.v clkc1).
create_clock -name clk_50 -period 20.000 -waveform {0.000 10.000} [get_ports {clk_50}]
create_clock -name phy1_rgmii_rx_clk -period 8.000 -waveform {0.000 4.000} [get_ports {phy1_rgmii_rx_clk}]
derive_clocks
rename_clock -name sd_clk -source [get_ports {clk_50}] -master_clock clk_50 [get_pins {u_sd_clock/pll_inst.clkc[0]}]
rename_clock -name mem_clk -source [get_ports {clk_50}] -master_clock clk_50 [get_pins {u_sd_clock/pll_inst.clkc[1]}]
rename_clock -name mem_shift_clk -source [get_ports {clk_50}] -master_clock clk_50 [get_pins {u_sd_clock/pll_inst.clkc[2]}]
rename_clock -name mac_tx_clk -source [get_ports {clk_50}] -master_clock clk_50 [get_pins {u_net/u_clk_gen/u_pll_0/pll_inst.clkc[0]}]
rename_clock -name udp_clk -source [get_ports {clk_50}] -master_clock clk_50 [get_pins {u_net/u_clk_gen/u_pll_0/pll_inst.clkc[1]}]
rename_clock -name compute_clk -source [get_ports {clk_50}] -master_clock clk_50 [get_pins {u_net/u_clk_gen/u_pll_0/pll_inst.clkc[3]}]
# 20261021: HDMI 5x serial clock, 125 MHz on clkc2 (udp_clk is 62.5 MHz now).
rename_clock -name hdmi_5x_clk -source [get_ports {clk_50}] -master_clock clk_50 [get_pins {u_net/u_clk_gen/u_pll_0/pll_inst.clkc[2]}]
rename_clock -name rgmii_tx_shift_clk -source [get_ports {clk_50}] -master_clock clk_50 [get_pins {u_net/u_clk_gen/u_pll_0/pll_inst.clkc[4]}]
rename_clock -name rgmii_rx_0 -source [get_ports {phy1_rgmii_rx_clk}] -master_clock phy1_rgmii_rx_clk [get_pins {u_net/u_rx_pll/pll_inst.clkc[0]}]
rename_clock -name rgmii_rx_90 -source [get_ports {phy1_rgmii_rx_clk}] -master_clock phy1_rgmii_rx_clk [get_pins {u_net/u_rx_pll/pll_inst.clkc[1]}]
set_clock_groups -asynchronous \
    -group [get_clocks {phy1_rgmii_rx_clk rgmii_rx_0 rgmii_rx_90}] \
    -group [get_clocks {clk_50 sd_clk mem_clk mem_shift_clk mac_tx_clk udp_clk compute_clk hdmi_5x_clk rgmii_tx_shift_clk}]
# TF/compute clocks remain related to clk_50. Any bundled-mailbox or Gray
# crossing needing an exception must be justified at its exact endpoints.
# External PHY and TF SPI IO timing still requires specification-based audit.
# 20261019: the TF/SDRAM PLL (u_sd_clock) and the Ethernet PLL (u_net) only
# exchange data through audited crossings: PCM/pixel/frame async FIFOs (Gray
# pointers), two-flop synchronisers (song request, link_ready, stream enable),
# toggle-qualified bundled metadata (image index/resolution/top, file bytes)
# and reset synchronisers (asynchronous assert, synchronous release). Their
# relative phase is not a timing requirement, so do not time or hold-fix them.
set_clock_groups -asynchronous \
    -group [get_clocks {sd_clk mem_clk mem_shift_clk}] \
    -group [get_clocks {udp_clk compute_clk hdmi_5x_clk mac_tx_clk rgmii_tx_shift_clk}]
# 20261020 star sky: the CTL4 bundle register (udp_clk) is sampled by
# star_bundle_cdc in compute_clk only after its 3-flop toggle synchroniser
# sees a flip; it is then stable until the next CTL4 packet (250 us).
set_max_delay -datapath_only -from [get_clocks {udp_clk}] -to [get_regs -nowarn {*/u_star_snapshot/dst_data[*]}] 32 -nowarn
