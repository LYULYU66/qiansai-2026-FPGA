// A: static home/music UI is already indexed by B, in SDRAM's spare byte.
// I_index precedes adjusted I_rgb/I_de by ONE pixel clock, just like the
// brightness LUT input. The synchronous palette introduces no new RGB delay.
// Do not blend the tag byte: UI is disabled throughout image transitions.
module video_remote_home_overlay(
    input wire I_clk,I_rst,I_enable,I_de,
    input wire [7:0] I_index,
    input wire [23:0] I_rgb,
    output wire [23:0] O_rgb
);
wire [23:0] palette_rgb;
reg opaque;
home_palette_rom palette(.clk(I_clk),.enable(1'b1),.index(I_index),.rgb(palette_rgb));
always @(posedge I_clk or posedge I_rst) begin
    if(I_rst) opaque<=0;
    else opaque<=I_index!=0;
end
assign O_rgb=(I_enable && I_de && opaque) ? palette_rgb : I_rgb;
endmodule
