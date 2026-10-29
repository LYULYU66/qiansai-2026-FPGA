`timescale 1ns/1ps
module tb_audio_silent_start;
reg mclk=0,vclk=0,rst=1,enable=0,empty=1;
reg [8:0] level=0;
wire read_pcm,bclk,lrck,dout,playing,underflow,valid;
wire [23:0] left,right;
integer quiet_frames=0,music_frames=0;
always #40.69 mclk=~mclk;
always #20 vclk=~vclk;
hdmi_audio_pcm_i2s_64fs dut(.I_mclk(mclk),.I_rst(rst),.I_enable(enable),
 .I_pcm_data({16'hF000,16'h1000}),.I_pcm_empty(empty),.I_pcm_level(level),
 .I_volume_level(4'd8),.O_pcm_read(read_pcm),.O_i2s_BCLK(bclk),
 .O_i2s_LRCK(lrck),.O_i2s_DOUT(dout),.O_playing(playing),.O_underflow(underflow));
I2S_receiver receiver(.I_clk(vclk),.I_rst(rst),.I_i2s_BCLK(bclk),
 .I_i2s_LRCK(lrck),.I_i2s_DOUT(dout),.O_audio_valid(valid),
 .O_audio_left_data(left),.O_audio_right_data(right));
always @(posedge vclk) if(!rst && valid) begin
 if(!playing)begin
  if(left!==0 || right!==0)$fatal(1,"FAIL startup sent audible data");
  quiet_frames=quiet_frames+1;
 end else if(left==24'h100000 && right==24'hF00000)music_frames=music_frames+1;
 else if(left!==0 || right!==0)$fatal(1,"FAIL TF PCM serialization");
end
initial begin
 repeat(8)@(negedge mclk);rst=0;
 wait(quiet_frames>=16);
 @(negedge mclk);enable=1;empty=0;level=127;
 repeat(8192)@(negedge mclk);
 if(playing || read_pcm)$fatal(1,"FAIL insufficient prefill started PCM");
 level=128;
 wait(music_frames>=8);
 if(quiet_frames<32 || underflow)$fatal(1,"FAIL startup/silence/prefill");
 $display("PASS SILENT_START: %d silent stereo frames, no tone, 128-frame guard retained, TF stereo correct",quiet_frames);
 $finish;
end
initial begin #10000000;$fatal(1,"FAIL startup timeout");end
endmodule
