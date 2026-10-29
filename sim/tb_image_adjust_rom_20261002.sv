`timescale 1ns/1ps
module tb_image_adjust_rom_20261002;
reg clk=0,rst=1,hs=0,vs=0,de=0;
reg [23:0] rgb=0;
reg [1:0] bri=3,con=0;
wire ah,av,ad,rh,rv,rd;
wire [23:0] actual,reference;
integer b,c,v,n,checks=0,blank_hold_checks=0;
reg [47:0] held_words;
always #5 clk=~clk;
// Capture all exhaustive cases plus the start of randomized traffic without
// dumping the vendor memory internals or a very large 200k-cycle waveform.
initial begin
 $dumpfile("sim/logic_round2_20261002/native_rom_equivalence.vcd");
 $dumpvars(1,tb_image_adjust_rom_20261002);
 $dumpvars(0,dut.brightness_frame,dut.contrast_frame,
  dut.lut_pixels.red_green.I_enable,dut.lut_pixels.red_green.word_a,
  dut.lut_pixels.red_green.word_b,dut.lut_pixels.red_green.lane_a,
  dut.lut_pixels.red_green.lane_b,dut.lut_pixels.blue_only.word_a);
 #60000;$dumpoff;
end
video_image_adjust #(.USE_LUT_ROM(1)) dut(.I_clk(clk),.I_rst(rst),.I_hs(hs),.I_vs(vs),.I_de(de),.I_rgb(rgb),
 .I_brightness_level(bri),.I_contrast_level(con),.O_hs(ah),.O_vs(av),.O_de(ad),.O_rgb(actual));
video_image_adjust_round1_reference old(.I_clk(clk),.I_rst(rst),.I_hs(hs),.I_vs(vs),.I_de(de),.I_rgb(rgb),
 .I_brightness_level(bri),.I_contrast_level(con),.O_hs(rh),.O_vs(rv),.O_de(rd),.O_rgb(reference));
always @(posedge clk)begin
 if(!de || rst)held_words={dut.lut_pixels.red_green.word_a,dut.lut_pixels.red_green.word_b,dut.lut_pixels.blue_only.word_a};
 #1;
 if({ah,av,ad,actual}!=={rh,rv,rd,reference})
  $fatal(1,"FAIL per-clock RGB/timing equality at cycle %0d: %h != %h, reset=%b DE=%b",checks,actual,reference,rst,de);
 if(!de || rst)begin
  if(held_words!=={dut.lut_pixels.red_green.word_a,dut.lut_pixels.red_green.word_b,dut.lut_pixels.blue_only.word_a})
   $fatal(1,"FAIL disabled BRAM changed data");
  blank_hold_checks=blank_hold_checks+1;
 end
 checks=checks+1;
end
task tick;begin @(posedge clk);#2;end endtask
initial begin
 repeat(8)tick;@(negedge clk);rst=0;
 for(b=0;b<4;b=b+1)for(c=0;c<4;c=c+1)begin
  @(negedge clk);de=0;bri=b;con=c;repeat(6)tick;
  @(negedge clk);vs=1;tick;@(negedge clk);vs=0;tick;
  for(v=0;v<256;v=v+1)begin
   @(negedge clk);de=1;hs=v[0];rgb={8'(v),8'(255-v),8'(v^8'h5A)};tick;
  end
 end
 $display("PASS IMAGE_ADJUST_NATIVE 4096 exhaustive mapping cases on all RGB ports; simultaneous dual-port reads; exact one-clock RGB/HS/VS/DE");
 for(n=0;n<200000;n=n+1)begin
  @(negedge clk);rgb=$random;hs=$random;de=($urandom%4)!=0;
  vs=(n%800==0)||(n%1301==0);
  if(n%37==0)begin bri=$random;con=$random;end
  rst=(n%1987==0);
  if(rst)begin #1;if(actual!==0 || ah!==0 || av!==0 || ad!==0)$fatal(1,"FAIL asynchronous reset masking");end
  tick;
 end
 @(negedge clk);rst=0;de=0;vs=0;repeat(20)tick;
 $display("PASS IMAGE_ADJUST_SEQUENCE %0d exact cycles; %0d gated-memory hold checks; random settings/VS+DE overlap/blanking/asynchronous reset/reentry",checks,blank_hold_checks);
 $finish;
end
initial begin #10000000;$fatal(1,"FAIL native image ROM timeout");end
endmodule
