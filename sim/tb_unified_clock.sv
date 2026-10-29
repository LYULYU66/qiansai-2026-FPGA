`timescale 1ns/1ps
module tb_unified_clock;
reg clk=0,rst=1,vs=0;
wire [23:0] t;
wire [15:0] frame;
integer cycles=0,seconds=9*3600,frac=0,snap=16'h0900,n,h,m,s;
always #5 clk=~clk;
video_unified_clock #(.CLK_FREQ_HZ(17)) dut(.I_clk(clk),.I_rst(rst),.I_vs(vs),.O_time_bcd(t),.O_frame_hhmm(frame));
function [23:0] bcd(input integer value);
 integer hh,mm,ss;
 begin hh=value/3600;mm=(value/60)%60;ss=value%60;
  bcd={4'(hh/10),4'(hh%10),4'(mm/10),4'(mm%10),4'(ss/10),4'(ss%10)};
 end
endfunction
initial begin
 repeat(3)@(negedge clk);rst=0;
 for(n=0;n<17*86402;n=n+1)begin
  vs=(n%13)==0;
  if(vs)snap=bcd(seconds)>>8;
  frac=frac+1;
  if(frac==17)begin frac=0;seconds=(seconds+1)%86400;end
  @(posedge clk);#1;
  if(t!==bcd(seconds))$fatal(1,"FAIL second/hour rollover n=%d time=%h expect=%h",n,t,bcd(seconds));
  if(frame!==snap)$fatal(1,"FAIL non-atomic shared frame snapshot");
  @(negedge clk);
 end
 rst=1;@(posedge clk);#1;
 if(t!==24'h090000 || frame!==16'h0900)$fatal(1,"FAIL default restart");
 $display("PASS UNIFIED_CLOCK 86402 seconds: all second/minute/hour carries, midnight wrap, frame-atomic HHMM, default09:00 reset");$finish;
end
initial begin #30000000;$fatal(1,"FAIL clock watchdog");end
endmodule
