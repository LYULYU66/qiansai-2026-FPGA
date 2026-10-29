`timescale 1ns/1ps
module tb_star_motion;
reg clk=0,rst=1;always #4 clk=~clk;
wire [15:0] phase,fast_phase;
dual_star_motion_clock #(.TICK_CYCLES(3)) dut(clk,rst,phase);
dual_star_motion_clock #(.TICK_CYCLES(1)) fast(clk,rst,fast_phase);
integer ref_phase=0,ref_fast=0,ref_div=0,ticks=0,wraps=0,cycle;
initial begin
 repeat(8)@(negedge clk);rst=0;
 for(cycle=0;cycle<3*16384*2+7;cycle=cycle+1)begin
  ref_fast=(ref_fast+1)%16384;
  if(ref_div==2)begin
   ref_div=0;ticks=ticks+1;ref_phase=ref_phase+1;
   if(ref_phase==16384)begin ref_phase=0;wraps=wraps+1;end
  end else ref_div=ref_div+1;
  @(posedge clk);#1;
  if(phase!==ref_phase[15:0]||fast_phase!==ref_fast[15:0])
   $fatal(1,"timestamp mismatch cycle=%0d got=%0d/%0d expected=%0d/%0d",cycle,phase,fast_phase,ref_phase,ref_fast);
  if(phase>=16384||fast_phase>=16384)$fatal(1,"phase range overflow");
  @(negedge clk);
 end
 if(wraps!=2)$fatal(1,"timestamp wrap coverage missing");
 rst=1;@(posedge clk);#1;if(phase!=0||fast_phase!=0)$fatal(1,"base reset failed");
 $display("PASS star motion: %0d exact 128Hz timestamp ticks, two 16384-tick seamless periods, TICK_CYCLES=1/3, reset",ticks);
 $finish;
end
initial begin #1500000;$fatal(1,"timestamp timeout");end
endmodule
