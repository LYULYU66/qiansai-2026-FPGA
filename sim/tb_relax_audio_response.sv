`timescale 1ns/1ps
// Connect the unchanged production analyzers, not fabricated band levels.
// 937.5Hz stereo PCM at 48kHz/520 pixel clocks drives the matching light lane.
module tb_relax_audio_response;
parameter LOW_POWER=0;
reg clk=0,rst=1,valid=0,vs=0;
reg signed [15:0] sample=0;
wire [6:0] vl,vr;
wire [111:0] bands;
integer n,phase=0,total=0,silent_energy,loud_energy,silent_amp,loud_amp;
always #5 clk=~clk;
audio_waveform_analyzer wave(.I_clk(clk),.I_rst(rst),.I_enable(1'b1),
 .I_audio_valid(valid),.I_audio_left({sample,8'd0}),.I_audio_right({sample,8'd0}),
 .O_vu_left_level(vl),.O_vu_right_level(vr),.O_wave_samples());
audio_spectrum_analyzer #(.LOW_POWER(LOW_POWER)) analyzer(.I_clk(clk),.I_rst(rst),.I_enable(1'b1),
 .I_audio_valid(valid),.I_audio_left({sample,8'd0}),.I_audio_right({sample,8'd0}),
 .O_vu_left_level(),.O_vu_right_level(),.O_band_levels(bands));
video_relax_overlay #(.LOW_POWER(LOW_POWER)) dut(.I_clk(clk),.I_rst(rst),.I_enable(1'b1),.I_vs(vs),.I_de(1'b0),
 .I_rgb(24'd0),.I_audio_active(1'b1),.I_vu_left(vl),.I_vu_right(vr),.I_spectrum_levels(bands),.O_rgb());
task send;
 input integer amplitude;
 begin
  @(negedge clk);sample=$rtoi(amplitude*$sin(6.283185307179586*phase/256.0));
  phase=(phase+5)%256;valid=1;vs=(total%800)==0;
  @(negedge clk);valid=0;vs=0;repeat(519)@(negedge clk);total=total+1;
 end
endtask
task commit;
 begin @(negedge clk);vs=1;@(negedge clk);vs=0;repeat(40)@(negedge clk);end
endtask
initial begin
 repeat(4)@(negedge clk);rst=0;repeat(40)@(negedge clk);
 for(n=0;n<1600;n=n+1)send(0);
 commit;silent_energy=dut.points[2]&2047;silent_amp=(dut.points[2]>>43)&255;
 if(silent_energy!=0 || vl!=0 || vr!=0)$fatal(1,"FAIL silent PCM not silent");
 for(n=0;n<8000;n=n+1)send(12000);
 commit;loud_energy=dut.points[2]&2047;loud_amp=(dut.points[2]>>43)&255;
 if(vl<40 || vr<40 || bands[4*7+:7]<88 || loud_energy<1000 || loud_amp<silent_amp+80)
  $fatal(1,"FAIL actual audio response VU=%0d,%0d band4=%0d energy=%0d amp=%0d->%0d",vl,vr,bands[4*7+:7],loud_energy,silent_amp,loud_amp);
 $display("PASS real 48kHz PCM -> VU/Goertzel -> glow: samples=%0d band4=%0d energy=%0d->%0d amplitude=%0d->%0d",total,bands[4*7+:7],silent_energy,loud_energy,silent_amp,loud_amp);
 $finish;
end
initial begin #200000000;$fatal(1,"FAIL audio response timeout");end
endmodule
