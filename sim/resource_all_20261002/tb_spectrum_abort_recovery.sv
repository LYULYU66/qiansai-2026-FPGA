`timescale 1ns/1ps
module tb_spectrum_abort_recovery;
reg clk=0,rst=1,enable=0,valid=0;
reg [23:0] left=0,right=0;
wire [6:0] vl[0:1],vr[0:1];wire [111:0] bands[0:1];
integer target,mode,n,elapsed,epochs=0,samples=0;
reg [31:0] noise=32'h55181239;
reg [12:0] covered=0;
always #5 clk=~clk;
audio_spectrum_analyzer dut(clk,rst,enable,valid,left,right,vl[0],vr[0],bands[0]);
audio_spectrum_analyzer_resopt_reference old(clk,rst,enable,valid,left,right,vl[1],vr[1],bands[1]);
task launch_sample;
begin
 @(negedge clk);
 noise={noise[30:0],noise[31]^noise[21]^noise[1]^noise[0]};
 left=noise[23:0];right={noise[15:0],noise[31:24]};valid=1;
 @(negedge clk);valid=0;samples=samples+1;
end endtask
task settle_sample;
begin
 repeat(518) @(negedge clk);
 #1;
 if(dut.state!==0 || old.state!==0) $fatal(1,"missed real 520-cycle sample deadline");
 if({vl[0],vr[0],bands[0]}!=={vl[1],vr[1],bands[1]})
  $fatal(1,"abort recovery mismatch target=%0d mode=%0d sample=%0d",target,mode,n);
end endtask
initial begin
 repeat(4) @(negedge clk);rst=0;
 for(mode=0;mode<2;mode=mode+1)begin
  for(target=1;target<=12;target=target+1)begin
   enable=1;
   // Reach evaluation states by REAL sample inputs, never hierarchical force.
   if(target==2 || target==3 || target==4 || target==5 || target==11 || target==12)
    for(n=0;n<255;n=n+1)begin launch_sample;settle_sample;end
   launch_sample;elapsed=0;
   while(dut.state!=target && elapsed<200)begin
    @(negedge clk);elapsed=elapsed+1;
   end
   if(dut.state!=target) $fatal(1,"cannot reach abort state %0d",target);
   covered[target]=1;
   if(mode==0)enable=0;else rst=1;
   repeat(2) @(negedge clk);#1;
   if(dut.state!==0 || dut.history_valid!==0 ||
      {vl[0],vr[0],bands[0]}!==126'd0 || {vl[1],vr[1],bands[1]}!==126'd0)
    $fatal(1,"abort did not clear valid flags/output state=%0d mode=%0d",target,mode);
   enable=0;rst=0;
   repeat(3) @(negedge clk);enable=1;
   for(n=0;n<257;n=n+1)begin launch_sample;settle_sample;end
   enable=0;repeat(3) @(negedge clk);epochs=epochs+1;
  end
 end
 if(covered!==13'h1ffe) $fatal(1,"missing abort state coverage %h",covered);
 $display("PASS packed spectrum abort/recovery: %0d epochs, %0d stereo samples, disable+reset at every 12 processing states, partial writes ignored, exact outputs and 520-cycle deadlines",epochs,samples);
 $finish;
end
initial begin #60000000;$fatal(1,"spectrum recovery timeout");end
endmodule
