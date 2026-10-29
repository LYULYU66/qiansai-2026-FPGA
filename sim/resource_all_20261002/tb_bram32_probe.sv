`timescale 1ns/1ps
module tb_bram32_probe;
reg clk=0;always #20 clk=~clk;
reg [10:0] address=0;wire [15:0] data;
EG_PHY_BRAM32K #(.MODE("DP16K"),.DATA_WIDTH_A("16"),.DATA_WIDTH_B("16"),
 .REGMODE_A("NOREG"),.REGMODE_B("NOREG"),
 .INIT_00(256'h0000000000000000000000000000000000000000000000001234039200E4))
 ram(.doa(data),.dia(16'd0),.addra(address),.bytea(1'b0),.bytewea(1'b0),
 .csa(1'b1),.wea(1'b0),.clka(clk),.rsta(1'b0),.ocea(1'b1),
 .dob(),.dib(16'd0),.addrb(11'd0),.byteb(1'b0),.byteweb(1'b0),
 .csb(1'b0),.web(1'b0),.clkb(1'b0),.rstb(1'b0),.oceb(1'b0));
integer n;
reg [15:0] expected;
initial begin
 repeat(3)@(negedge clk);
 for(n=0;n<16;n=n+1)begin
  @(negedge clk);address=n;
  @(posedge clk);#1;
  case(n)0:expected=16'h00e4;1:expected=16'h0392;2:expected=16'h1234;default:expected=0;endcase
  if(data!==expected)$fatal(1,"BRAM32K INIT/latency mismatch address=%0d data=%h expected=%h",n,data,expected);
 end
 $display("PASS vendor BRAM32K probe: DP16K/16bit 2048-word model, synchronous one-clock read, native INIT bit order");$finish;
end
endmodule
