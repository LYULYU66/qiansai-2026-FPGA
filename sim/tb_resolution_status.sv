`timescale 1ns/1ps
module tb_resolution_status;
reg clk=0,rst=1,vs=0,de=0;
reg [15:0] w=800,h=600;
wire [23:0] rgb;
always #5 clk=~clk;
video_status_overlay #(.ENABLE_RESOLUTION(1)) dut(
 .I_clk(clk),.I_rst(rst),.I_enable(1'b1),.I_vs(vs),.I_de(de),.I_rgb(24'h507080),
 .I_brightness_level(2'd3),.I_contrast_level(2'd2),.I_volume_level(4'd8),
 .I_source_width(w),.I_source_height(h),.O_rgb(rgb));
task convert(input integer wi,hi,input [19:0] wb,hb);
 integer x,y,ink;
 begin
  @(negedge clk); de=0; w=wi; h=hi; vs=1;
  repeat(40) @(negedge clk); vs=0;
  if(dut.width_bcd!==wb || dut.height_bcd!==hb) $fatal(1,"BCD %d x %d %h x %h",wi,hi,dut.width_bcd,dut.height_bcd);
  ink=0;
  for(y=0;y<32;y=y+1) begin
   for(x=0;x<640;x=x+1) begin
    @(negedge clk); de=1; @(posedge clk); #1;
    if(x>=282 && x<462 && dut.text_hit) ink=ink+1;
    if(x>=462 && rgb!==24'h507080) $fatal(1,"resolution spills");
   end
   @(negedge clk); de=0; repeat(8) @(negedge clk);
  end
  if(ink<120 || dut.width_frame_bcd!==wb || dut.height_frame_bcd!==hb) $fatal(1,"no resolution text/coherence");
  $display("PASS frameless RES:%0dx%0d ink=%d",wi,hi,ink);
 end
endtask
initial begin
 repeat(5) @(negedge clk); rst=0;
 convert(800,600,20'h00800,20'h00600);
 convert(1920,1080,20'h01920,20'h01080);
 convert(65535,1,20'h65535,20'h00001);
 convert(640,480,20'h00640,20'h00480);
 $display("PASS resolution BCD/frame/geometry"); $finish;
end
initial begin #2000000; $fatal(1,"status timeout"); end
endmodule
