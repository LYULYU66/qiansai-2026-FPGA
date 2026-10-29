`timescale 1ns/1ps
module tb_packed_font_equivalence;
reg clk=0;always #20 clk=~clk;
reg [15:0] address=0; reg [7:0] gid=0;reg [4:0] row=0,col=0;
wire [1:0] packed_cov,native_cov;
integer i,n,checks=0;reg [31:0] noise=32'h22314173;
lyric_font_rom original(clk,address,native_cov);
lyric_font_packed_rom compressed(clk,gid,row,col,packed_cov);
initial begin
 for(i=0;i<128744;i=i+1)begin
  @(negedge clk);
  noise={noise[30:0],noise[31]^noise[21]^noise[1]^noise[0]};
  n=(i<64372)?i:noise%64372;
  address=n;gid=n/484;row=(n%484)/22;col=n%22;
  @(posedge clk);#1;
  if(packed_cov!==native_cov || ^packed_cov===1'bx)
   $fatal(1,"packed font differs at gid=%0d row=%0d col=%0d got=%0d expected=%0d",gid,row,col,packed_cov,native_cov);
  checks=checks+1;
 end
 $display("PASS packed font: %0d synchronous pixel checks, all 133 glyphs, 64372 sequential + random addresses, one-clock latency, exact 2-bit antialias coverage",checks);
 $finish;
end
endmodule
