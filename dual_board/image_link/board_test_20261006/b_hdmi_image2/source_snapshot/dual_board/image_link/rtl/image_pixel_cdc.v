`timescale 1ns/1ps
// Small dual-clock FIFO with Gray pointers and reset-free synchronous RAM
// reads. Deliberately two read clocks per pixel: SD throughput is much lower
// than this rate, and the simpler port infers BRAM on TD.
module image_pixel_cdc #(
    parameter integer ADDR_BITS=10
) (
    input wire rst,
    input wire wr_clk, wr_valid,
    input wire [23:0] wr_rgb,
    output wire wr_ready,
    output reg overflow,
    input wire rd_clk, rd_ready,
    output reg rd_valid,
    output wire [23:0] rd_rgb
);
localparam integer DEPTH=1<<ADDR_BITS;
reg [1:0] wr_reset_pipe, rd_reset_pipe;
wire wr_reset=wr_reset_pipe[1];
wire rd_reset=rd_reset_pipe[1];
always @(posedge wr_clk or posedge rst) begin
    if(rst) wr_reset_pipe<=2'b11;
    else wr_reset_pipe<={wr_reset_pipe[0],1'b0};
end
always @(posedge rd_clk or posedge rst) begin
    if(rst) rd_reset_pipe<=2'b11;
    else rd_reset_pipe<={rd_reset_pipe[0],1'b0};
end
reg [15:0] rg_mem [0:DEPTH-1]; /* fehdl force_ram=1, ram_style="bram" */
reg [7:0] b_mem [0:DEPTH-1]; /* fehdl force_ram=1, ram_style="bram" */
reg [ADDR_BITS:0] wr_bin, wr_gray, rd_bin, rd_gray;
(* async_reg="true" *) reg [ADDR_BITS:0] rd_sync0, rd_sync1, wr_sync0, wr_sync1;
reg [15:0] rg_out;
reg [7:0] b_out;
function [ADDR_BITS:0] gray_to_bin;
    input [ADDR_BITS:0] value;
    integer i;
    begin gray_to_bin[ADDR_BITS]=value[ADDR_BITS];
        for(i=ADDR_BITS-1;i>=0;i=i-1)
            gray_to_bin[i]=gray_to_bin[i+1]^value[i];
    end
endfunction
wire [ADDR_BITS:0] used_words=wr_bin-gray_to_bin(rd_sync1);
// Reserve 32 words for registered producer outputs after ready goes low.
assign wr_ready=used_words < DEPTH-32 && !wr_reset;
wire fetch=!rd_valid && (rd_gray!=wr_sync1) && !rd_reset;
assign rd_rgb={rg_out,b_out};
always @(posedge wr_clk) if(wr_valid && used_words<DEPTH && !wr_reset) begin
    rg_mem[wr_bin[ADDR_BITS-1:0]]<=wr_rgb[23:8];
    b_mem[wr_bin[ADDR_BITS-1:0]]<=wr_rgb[7:0];
end
always @(posedge rd_clk) if(fetch) begin
    rg_out<=rg_mem[rd_bin[ADDR_BITS-1:0]];
    b_out<=b_mem[rd_bin[ADDR_BITS-1:0]];
end
always @(posedge wr_clk or posedge wr_reset) begin
    if(wr_reset) begin wr_bin<=0; wr_gray<=0; rd_sync0<=0; rd_sync1<=0; overflow<=0; end
    else begin
        rd_sync0<=rd_gray; rd_sync1<=rd_sync0;
        if(wr_valid) begin
            if(used_words>=DEPTH) overflow<=1;
            else begin wr_bin<=wr_bin+1'b1; wr_gray<=((wr_bin+1'b1)>>1)^(wr_bin+1'b1); end
        end
    end
end
always @(posedge rd_clk or posedge rd_reset) begin
    if(rd_reset) begin rd_bin<=0; rd_gray<=0; wr_sync0<=0; wr_sync1<=0; rd_valid<=0; end
    else begin
        wr_sync0<=wr_gray; wr_sync1<=wr_sync0;
        if(fetch) rd_valid<=1;
        if(rd_valid && rd_ready) begin
            rd_valid<=0; rd_bin<=rd_bin+1'b1;
            rd_gray<=((rd_bin+1'b1)>>1)^(rd_bin+1'b1);
        end
    end
end
endmodule
