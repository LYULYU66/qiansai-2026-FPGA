`timescale 1ns/1ps
// A-board picture/sound settings from two keys (20261020).
//   key_select (board KEY2): brightness -> contrast -> volume -> brightness.
//   key_step   (board KEY1): selected parameter +1 level; past the top level
//                            it wraps to the lowest level.
// Power-up state matches the former CTL default 8'h38 (brightness 3,
// contrast 0, volume 8) with brightness selected. Keys are active low.
module local_av_settings #(
    parameter integer CLK_FREQ_HZ = 25_000_000
)(
    input  wire       clk, rst,
    input  wire       key_select, key_step,
    output reg  [1:0] selected,
    output reg  [1:0] brightness_level,
    output reg  [1:0] contrast_level,
    output reg  [3:0] volume_level
);
wire select_press, step_press;
key_press_debounce #(.CLK_FREQ_HZ(CLK_FREQ_HZ)) u_select (
    .clk(clk),.rst(rst),.button_in(key_select),.press_pulse(select_press)
);
key_press_debounce #(.CLK_FREQ_HZ(CLK_FREQ_HZ)) u_step (
    .clk(clk),.rst(rst),.button_in(key_step),.press_pulse(step_press)
);
always @(posedge clk or posedge rst) begin
    if(rst) begin
        selected<=2'd0; brightness_level<=2'd3; contrast_level<=2'd0; volume_level<=4'd8;
    end else begin
        if(select_press) selected<=(selected==2'd2) ? 2'd0 : selected+2'd1;
        if(step_press) case(selected)
            2'd0: brightness_level<=brightness_level+2'd1;           // 0..3
            2'd1: contrast_level<=contrast_level+2'd1;               // 0..3
            default: volume_level<=(volume_level>=4'd8) ? 4'd0 : volume_level+4'd1; // 0..8
        endcase
    end
end
endmodule
