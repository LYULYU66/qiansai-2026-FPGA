`timescale 1ns/1ps
module tb_relax_page_policy;
reg valid=0,transition=0,pcm=0;
reg [1:0] idx=0;
reg [23:0] regular=24'h123456,relax=24'hAABBCC;
wire home,music,warning_sel,warning_draw,relax_sel,relax_draw,osd,visual;
wire [23:0] rgb;
integer v,t,p,n,c,tests=0;
reg old_home,old_music,old_warning,old_osd;
video_playback_overlay_select dut(.I_valid(valid),.I_transition_active(transition),
 .I_pcm_available(pcm),.I_picture_idx(idx),.I_regular_rgb(regular),.I_relax_rgb(relax),
 .O_home(home),.O_music(music),.O_warning_selected(warning_sel),.O_warning_draw(warning_draw),
 .O_relax_selected(relax_sel),.O_relax_draw(relax_draw),.O_osd(osd),.O_visualizer(visual),.O_rgb(rgb));
initial begin
 for(v=0;v<2;v=v+1)for(t=0;t<2;t=t+1)for(p=0;p<2;p=p+1)for(n=0;n<4;n=n+1)begin
  valid=v;transition=t;pcm=p;idx=n;
  old_home=v && n==0 && !t;old_music=v && n==1 && !t;
  old_warning=v && n==3;old_osd=v && !old_home && !old_warning;
  for(c=0;c<100;c=c+1)begin
   regular=$random;relax=$random;#1;
   if(home!==old_home || music!==old_music || warning_sel!==old_warning ||
      warning_draw!==(old_warning&&!t)) $fatal(1,"FAIL unchanged page rules");
   if(v && n==2)begin
    if(osd || visual || home || music || warning_sel || !relax_sel || rgb!==relax ||
       relax_draw!==!t) $fatal(1,"FAIL page3 playback layer removal");
   end else begin
    if(osd!==old_osd || visual!==(old_osd&&p) || relax_sel || relax_draw || rgb!==regular)
     $fatal(1,"FAIL other page changed");
   end
   tests=tests+1;
  end
 end
 $display("PASS production page policy %0d combinations: only picture3 changed, transitions/PCM/invalid frames exact",tests);
 $finish;
end
endmodule
