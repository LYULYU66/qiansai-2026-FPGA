`timescale 1ns/1ps
module tb_low_power_spectrum;
reg clk=0,rst=1,valid=0;
reg [1:0] page=0;
reg signed [15:0] sample=0;
wire vis,relax,enable;
wire [111:0] bands_lp,bands_ref;
wire [6:0] ll,lr,rl,rr;
integer n,t,reads_lp=0,reads_ref=0,checks=0,active_samples=0,hidden_samples=0,nonzero_bands=0;
always #5 clk=~clk;
video_playback_overlay_select policy(.I_valid(1'b1),.I_transition_active(1'b0),.I_pcm_available(1'b1),
 .I_picture_idx(page),.I_regular_rgb(24'd0),.I_relax_rgb(24'd0),.O_visualizer(vis),.O_relax_draw(relax),
 .O_home(),.O_music(),.O_warning_selected(),.O_warning_draw(),.O_relax_selected(),.O_osd(),.O_rgb());
assign enable=vis || relax;
audio_spectrum_analyzer #(.LOW_POWER(1)) lp(.I_clk(clk),.I_rst(rst),.I_enable(enable),.I_audio_valid(valid),
 .I_audio_left({sample,8'd0}),.I_audio_right({sample,8'd0}),.O_vu_left_level(ll),.O_vu_right_level(lr),.O_band_levels(bands_lp));
audio_spectrum_analyzer reference(.I_clk(clk),.I_rst(rst),.I_enable(enable),.I_audio_valid(valid),
 .I_audio_left({sample,8'd0}),.I_audio_right({sample,8'd0}),.O_vu_left_level(rl),.O_vu_right_level(rr),.O_band_levels(bands_ref));
always @(posedge clk)if(!rst)begin
 reads_ref=reads_ref+1;if(lp.history_read_enable)reads_lp=reads_lp+1;
end
always @(negedge clk)if(!rst)begin
 checks=checks+1;
 if({bands_lp,ll,lr}!=={bands_ref,rl,rr})$fatal(1,"RAM CE changed spectrum output");
 if(enable!==(page==1 || page==2))$fatal(1,"wrong production page policy");
end
initial begin
 repeat(4)@(negedge clk);rst=0;
 for(n=0;n<4096;n=n+1)begin
  page=n<512?0:n<1536?1:n<2048?3:n<3072?2:0;
  sample=(n%64<32)?16'sd11000:-16'sd9000;
  valid=1;if(enable)active_samples=active_samples+1;else hidden_samples=hidden_samples+1;
  @(negedge clk);valid=0;repeat(519)@(negedge clk);
  if(enable && bands_lp!=0)nonzero_bands=nonzero_bands+1;
 end
 if(nonzero_bands<500)$fatal(1,"filter state not exercised: %0d nonzero samples",nonzero_bands);
 if(reads_lp*100>=reads_ref*30)$fatal(1,"RAM read enables not sufficiently reduced");
 $display("PASS LOW_POWER_SPECTRUM %d exact cycles; %d active / %d hidden samples; RAM reads %d -> %d; page1/4 disabled, page2/3 active",checks,active_samples,hidden_samples,reads_ref,reads_lp);$finish;
end
endmodule
