`timescale 1ns/1ps
// Copy of the Ethernet PLL (ethernet_smoke/prj/board_a/al_ip/pll_gen) used by
// both boards since 20261021 (was B-only pll_gen_b.v),
// 20261021: clkc1 (udp_clk, the application side of the MAC client FIFOs)
// runs at 62.5 MHz instead of 125 MHz. The 125 MHz HDMI 5x clock used to be
// this same output; it now comes from the new clkc2 (125 MHz, same phase
// as before). clkc2 was the unused 12.5 MHz output. clkc0 (MAC TX), clkc3
// (25 MHz HDMI pixel/compute) and clkc4 (RGMII TX shift) are unchanged.
// The client FIFOs are independent-clock designs; B's traffic needs well
// under 10 MB/s.
module pll_gen (
  refclk,
  reset,
  extlock,
  clk0_out,
  clk1_out,
  clk2_out,
  clk3_out,
  clk4_out 
);

  input refclk;
  input reset;
  output extlock;
  output clk0_out;
  output clk1_out;
  output clk2_out;
  output clk3_out;
  output clk4_out;

  wire clk0_buf;

  EG_LOGIC_BUFG bufg_feedback (
    .i(clk0_buf),
    .o(clk0_out) 
  );

  EG_PHY_PLL #(
    .DPHASE_SOURCE("DISABLE"),
    .DYNCFG("DISABLE"),
    .FIN("50.000000"),
    .FEEDBK_MODE("NORMAL"),
    .FEEDBK_PATH("CLKC0_EXT"),
    .STDBY_ENABLE("DISABLE"),
    .PLLRST_ENA("ENABLE"),
    .SYNC_ENABLE("DISABLE"),
    .GMC_GAIN(2),
    .ICP_CURRENT(9),
    .KVCO(2),
    .LPF_CAPACITOR(1),
    .LPF_RESISTOR(8),
    .REFCLK_DIV(2),
    .FBCLK_DIV(5),
    .CLKC0_ENABLE("ENABLE"),
    .CLKC0_DIV(8),
    .CLKC0_CPHASE(7),
    .CLKC0_FPHASE(0),
    .CLKC1_ENABLE("ENABLE"),
    .CLKC1_DIV(16),
    .CLKC1_CPHASE(15),
    .CLKC1_FPHASE(0),
    .CLKC2_ENABLE("ENABLE"),
    .CLKC2_DIV(8),
    .CLKC2_CPHASE(7),
    .CLKC2_FPHASE(0),
    .CLKC3_ENABLE("ENABLE"),
    .CLKC3_DIV(40),
    .CLKC3_CPHASE(39),
    .CLKC3_FPHASE(0),
    .CLKC4_ENABLE("ENABLE"),
    .CLKC4_DIV(8),
    .CLKC4_CPHASE(1),
    .CLKC4_FPHASE(0) 
  ) pll_inst (
    .refclk(refclk),
    .reset(reset),
    .stdby(1'b0),
    .extlock(extlock),
    .load_reg(1'b0),
    .psclk(1'b0),
    .psdown(1'b0),
    .psstep(1'b0),
    .psclksel(3'b000),
    .psdone(pll_gen_open0),
    .dclk(1'b0),
    .dcs(1'b0),
    .dwe(1'b0),
    .di(8'b00000000),
    .daddr(6'b000000),
    .do({pll_gen_open8, pll_gen_open7, pll_gen_open6, pll_gen_open5, pll_gen_open4, pll_gen_open3, pll_gen_open2, pll_gen_open1}),
    .fbclk(clk0_out),
    .clkc({clk4_out, clk3_out, clk2_out, clk1_out, clk0_buf}) 
  );

endmodule

