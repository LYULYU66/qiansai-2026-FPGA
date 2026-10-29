# Formal A clocks. Hardware PLL/IP frequencies/phases are unchanged.
# This initial physical audit intentionally retains RELATED pixel/serial/UDP
# clocks; do not copy the old pixel-versus-serial exclusive clock group.
create_clock -name clk -period 20.000 -waveform {0.000 10.000} [get_ports {clk}]
create_clock -name phy1_rgmii_rx_clk -period 8.000 -waveform {0.000 4.000} [get_ports {phy1_rgmii_rx_clk}]
derive_clocks
rename_clock -name sd_card_clk -source [get_ports {clk}] -master_clock clk [get_pins {sys_pll_m0/pll_inst.clkc[0]}]
rename_clock -name ext_mem_clk -source [get_ports {clk}] -master_clock clk [get_pins {sys_pll_m0/pll_inst.clkc[1]}]
rename_clock -name ext_mem_clk_sft -source [get_ports {clk}] -master_clock clk [get_pins {sys_pll_m0/pll_inst.clkc[2]}]
rename_clock -name mac_tx_clk -source [get_ports {clk}] -master_clock clk [get_pins {u_net/u_clk_gen/u_pll_0/pll_inst.clkc[0]}]
# 20261021: udp_clk (clkc1) is 62.5 MHz; HDMI I_serial_clk is the separate
# 125 MHz clkc2 (pll_gen_62p5.v). Both stay related to clk.
rename_clock -name udp_clk -source [get_ports {clk}] -master_clock clk [get_pins {u_net/u_clk_gen/u_pll_0/pll_inst.clkc[1]}]
rename_clock -name hdmi_5x_clk -source [get_ports {clk}] -master_clock clk [get_pins {u_net/u_clk_gen/u_pll_0/pll_inst.clkc[2]}]
rename_clock -name video_clk -source [get_ports {clk}] -master_clock clk [get_pins {u_net/u_clk_gen/u_pll_0/pll_inst.clkc[3]}]
rename_clock -name rgmii_tx_shift_clk -source [get_ports {clk}] -master_clock clk [get_pins {u_net/u_clk_gen/u_pll_0/pll_inst.clkc[4]}]
rename_clock -name audio_mclk -source [get_ports {clk}] -master_clock clk [get_pins {u_audio_pll/pll_inst.clkc[2]}]
rename_clock -name rgmii_rx_0 -source [get_ports {phy1_rgmii_rx_clk}] -master_clock phy1_rgmii_rx_clk [get_pins {u_net/u_rx_pll/pll_inst.clkc[0]}]
rename_clock -name rgmii_rx_90 -source [get_ports {phy1_rgmii_rx_clk}] -master_clock phy1_rgmii_rx_clk [get_pins {u_net/u_rx_pll/pll_inst.clkc[1]}]
# PHY RX is independent of this board's oscillator; native RX FIFO owns CDC.
set_clock_groups -asynchronous \
    -group [get_clocks {phy1_rgmii_rx_clk rgmii_rx_0 rgmii_rx_90}] \
    -group [get_clocks {clk sd_card_clk ext_mem_clk ext_mem_clk_sft mac_tx_clk udp_clk hdmi_5x_clk video_clk rgmii_tx_shift_clk audio_mclk}]
# PCM FIFO, synchronized enables/progress and I2S sampling own audio CDC.
set_clock_groups -asynchronous \
    -group [get_clocks {audio_mclk}] \
    -group [get_clocks {clk sd_card_clk ext_mem_clk ext_mem_clk_sft mac_tx_clk udp_clk hdmi_5x_clk video_clk rgmii_tx_shift_clk}]
# IO delay values must come from actual PHY/DDC/board specifications. They are
# NOT guessed or replaced with broad false paths to claim complete closure.
# SDRAM is the EG_PHY_SDRAM_2M_32 primitive, not external top-level SDRAM pins.
# 20261019: the TF/SDRAM PLL (sys_pll_m0) and the Ethernet PLL (u_net) are
# separate PLLs. They exchange data only through audited crossings: the frame
# write/read async FIFOs (Gray pointers), 3-flop request synchronisers with
# 2-flop quasi-static index/length/top-down, the writer ACK synchroniser,
# toggle-qualified write-finish, and reset synchronisers. Do not time them.
set_clock_groups -asynchronous \
    -group [get_clocks {sd_card_clk ext_mem_clk ext_mem_clk_sft}] \
    -group [get_clocks {mac_tx_clk udp_clk hdmi_5x_clk video_clk rgmii_tx_shift_clk}]
# 20261020 star sky: the engine bundle (udp_clk) is sampled by star_bundle_cdc
# in video_clk only after its 3-flop toggle synchroniser sees a flip; the
# bundle is then stable for 4096 udp clocks (62.5 MHz). Bound the data path only.
set_max_delay -datapath_only -from [get_clocks {udp_clk}] -to [get_regs -nowarn {*u_control_snapshot/dst_data[*]}] 32 -nowarn
