module dual_board_smoke_a (
    input  wire       clk_50,
    input  wire       sys_rst_n,
    input  wire       key_send_n,
    input  wire       phy1_rgmii_rx_clk,
    input  wire       phy1_rgmii_rx_ctl,
    input  wire [3:0] phy1_rgmii_rx_data,
    output wire       phy1_rgmii_tx_clk,
    output wire       phy1_rgmii_tx_ctl,
    output wire [3:0] phy1_rgmii_tx_data,
    output wire [3:0] led
);
dual_board_smoke_core #(.ROLE(0)) core (
    .clk_50(clk_50), .sys_rst_n(sys_rst_n),
    .key_send_n(key_send_n),
    .phy1_rgmii_rx_clk(phy1_rgmii_rx_clk),
    .phy1_rgmii_rx_ctl(phy1_rgmii_rx_ctl),
    .phy1_rgmii_rx_data(phy1_rgmii_rx_data),
    .phy1_rgmii_tx_clk(phy1_rgmii_tx_clk),
    .phy1_rgmii_tx_ctl(phy1_rgmii_tx_ctl),
    .phy1_rgmii_tx_data(phy1_rgmii_tx_data),
    .led(led)
);
endmodule
