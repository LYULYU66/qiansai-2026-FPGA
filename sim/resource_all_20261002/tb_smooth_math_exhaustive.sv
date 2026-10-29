`timescale 1ns/1ps
module tb_smooth_math_exhaustive;
reg clk=0;always #5 clk=~clk;
integer a,b,checks=0;
reg signed [6:0] old_value,target;
audio_waveform_analyzer wave_new(clk,1'b1,1'b0,1'b0,24'd0,24'd0,,,);
audio_waveform_analyzer_resource2_reference wave_old(clk,1'b1,1'b0,1'b0,24'd0,24'd0,,,);
`define VIS_PORTS .I_clk(clk),.I_rst(1'b1),.I_enable(1'b0),.I_vs(1'b0),.I_de(1'b0), \
 .I_rgb(24'd0),.I_vu_left_level(7'd0),.I_vu_right_level(7'd0), \
 .I_spectrum_levels(112'd0),.I_wave_samples(112'd0),.I_volume_level(4'd0), \
 .I_hazard_front(1'b0),.I_hazard_left(1'b0),.I_hazard_right(1'b0),.O_rgb()
audio_visualizer_overlay vis_new(`VIS_PORTS);
audio_visualizer_overlay_resopt_reference vis_old(`VIS_PORTS);
`undef VIS_PORTS
initial begin
 for(a=-64;a<64;a=a+1) for(b=-64;b<64;b=b+1)begin
  old_value=a;target=b;#1;
  if(wave_new.smooth_offset(old_value,target)!==wave_old.smooth_offset(old_value,target))
   $fatal(1,"waveform narrow arithmetic mismatch %0d %0d",a,b);
  if(vis_new.smooth_display_sample(old_value,target)!==vis_old.smooth_display_sample(old_value,target))
   $fatal(1,"display narrow arithmetic mismatch %0d %0d",a,b);
  checks=checks+2;
 end
 $display("PASS exhaustive signed smooth math: %0d comparisons, all 128x128 endpoint pairs, old/new exact including saturation",checks);
 $finish;
end
endmodule
