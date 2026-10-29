`timescale 1ns/1ps
module tb_star_motion;
reg clk=0,rst=1;always #4 clk=~clk;
wire [15:0] phase;
dual_star_motion_clock #(.TICK_CYCLES(3)) dut(clk,rst,phase);
integer ref_phase=0,ref_speed=0,ref_frac=0,ref_ramp=0,ref_div=0;
integer dir=1,accel=1,step,total,ticks=0,turns=0,saw_zero=0,saw_peak=0;
integer cycle,leg_origin=0,forward_wraps=0,back_wraps=0;
initial begin
 repeat(8)@(negedge clk);rst=0;
 for(cycle=0;cycle<3*12*128*5;cycle=cycle+1)begin
  // Also test both modulus boundaries at high speed, not just the normal 192px arc.
  if(ticks==2100&&ref_div==0)begin dut.phase_q4=0;ref_phase=0;end
  if(ticks==3650&&ref_div==0)begin dut.phase_q4=20479;ref_phase=20479;end
  if(ref_div==2)begin
   ref_div=0;ticks=ticks+1;total=ref_speed+ref_frac;step=total/16;ref_frac=total%16;
   if(ref_speed==0)saw_zero=saw_zero+1;if(ref_speed==64)saw_peak=saw_peak+1;
   ref_phase=ref_phase+dir*step;
   if(ref_phase>=20480)begin ref_phase=ref_phase-20480;forward_wraps=forward_wraps+1;end
   if(ref_phase<0)begin ref_phase=ref_phase+20480;back_wraps=back_wraps+1;end
   ref_ramp=ref_ramp+1;
   if(ref_ramp==12)begin
    ref_ramp=0;ref_speed=ref_speed+accel;
    if(ref_speed==64)accel=-1;
    if(ref_speed==0)begin
     accel=1;dir=-dir;turns=turns+1;
     if(ticks==1536&&ref_phase!=3072)$fatal(1,"first leg distance/time incorrect");
     if(step>1)$fatal(1,"reverse at nonzero velocity");
    end
   end
  end else ref_div=ref_div+1;
  @(posedge clk);#1;
  if(phase!==ref_phase[15:0]||dut.speed_q4!=ref_speed||dut.fractional_step!=ref_frac||dut.reverse!=(dir<0))
   $fatal(1,"motion reference mismatch tick=%0d got=%0d expected=%0d v=%0d",ticks,phase,ref_phase,dut.speed_q4);
  if(phase>=20480||dut.speed_q4>64)$fatal(1,"range overflow");
  @(negedge clk);
 end
 if(turns!=5||saw_zero==0||saw_peak==0||forward_wraps==0||back_wraps==0)$fatal(1,"motion coverage missing turns=%0d wrap=%0d/%0d",turns,forward_wraps,back_wraps);
 rst=1;@(posedge clk);#1;if(phase!=0||dut.speed_q4!=0)$fatal(1,"base reset failed");
 $display("PASS star motion: %0d exact ticks, five smooth direction reversals, 0..32px/s ramp, fractional integrator, 192px/12s first leg, both modulus boundaries, reset",ticks);
 $finish;
end
initial begin #1000000;$fatal(1,"motion timeout");end
endmodule
