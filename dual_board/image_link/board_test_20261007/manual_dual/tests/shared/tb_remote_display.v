`timescale 1ns/1ps
module tb_remote_display;
reg clk=0; always #4 clk=~clk;
reg rst=1, key_next=1, key_auto=1, hazard=0;
reg [3:0] cache=0;
wire valid, warning_ready;
wire [1:0] index;
image_remote_display_control #(.CLK_FREQ(1000)) dut (
    .clk(clk),.rst(rst),.key_next(key_next),.key_auto(key_auto),
    .warning_hold(hazard),.cache_valid_async(cache),.display_valid(valid),
    .warning_ready(warning_ready),.requested_index(index)
);
initial begin
    repeat(5) @(negedge clk); rst=0;
    repeat(5) @(negedge clk);
    if(valid) $fatal(1,"display enabled before cache commit");
    cache=1; repeat(5) @(negedge clk);
    if(!valid || index!=0) $fatal(1,"first image unavailable");
    key_next=0; repeat(30) @(negedge clk);
    key_next=1; repeat(30) @(negedge clk);
    if(index!=0) $fatal(1,"selected uncached image");
    cache=3; repeat(5) @(negedge clk);
    key_next=0; repeat(30) @(negedge clk);
    key_next=1; repeat(30) @(negedge clk);
    if(index!=1) $fatal(1,"manual next failed");
    key_auto=0; repeat(30) @(negedge clk);
    key_auto=1; repeat(30) @(negedge clk);
    hazard=1; repeat(1300) @(negedge clk);
    if(index!=1) $fatal(1,"auto advanced during hazard");
    hazard=0; cache=15; repeat(1010) @(negedge clk);
    if(index!=2 || !warning_ready) $fatal(1,"automatic next/cache sync failed");
    $display("PASS remote display: committed cache only, manual/auto switch, hazard pause");
    $finish;
end
endmodule
