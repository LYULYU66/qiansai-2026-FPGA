`timescale 1ns/1ps
// Renders the real home/music page backgrounds through the pause-icon and
// status-readout overlays (A pipeline order): paused and playing frames.
module tb_card_status_render;
reg clk=0,rst=1,vs=0,de=0,home=0,music=0,paused=0;
always #5 clk=~clk;
reg [23:0] home_bg[0:307199], music_bg[0:307199];
reg [23:0] rgb=0;
wire [23:0] pause_rgb, out_rgb;
video_pause_icon_overlay pause(.I_clk(clk),.I_rst(rst),.I_vs(vs),.I_de(de),
  .I_home(home),.I_music(music),.I_paused(paused),.I_rgb(rgb),.O_rgb(pause_rgb));
video_status_overlay #(.ENABLE_RESOLUTION(1),.SELECT_HIGHLIGHT(1)) status(.I_clk(clk),.I_rst(rst),
  .I_enable(1'b1),.I_vs(vs),.I_de(de),.I_rgb(pause_rgb),
  .I_brightness_level(2'd3),.I_contrast_level(2'd1),.I_volume_level(4'd8),
  .I_source_width(16'd1920),.I_source_height(16'd1080),.I_selected(2'd0),.O_rgb(out_rgb));
integer f,x,y,fd;
task frame(input page_music, input is_paused, input dump);
  begin
    home=!page_music; music=page_music; paused=is_paused;
    @(negedge clk);vs=1;repeat(4)@(negedge clk);vs=0;repeat(80)@(negedge clk);
    for(y=0;y<480;y=y+1)begin
      for(x=0;x<640;x=x+1)begin
        @(negedge clk);de=1;rgb=page_music?music_bg[y*640+x]:home_bg[y*640+x];
        @(posedge clk);#2;
        if(dump) $fwrite(fd,"%06h\n",out_rgb);
      end
      @(negedge clk);de=0;repeat(3)@(negedge clk);
    end
  end
endtask
initial begin
  $readmemh("../dualsong_20261005/lyricfix_20261019/home_bg.hex",home_bg);
  $readmemh("../dualsong_20261005/lyricfix_20261019/music_bg.hex",music_bg);
  fd=$fopen("render.hex","w");
  repeat(4)@(negedge clk);rst=0;
  // Order in render.hex: home paused, home playing, music paused, music playing.
  frame(0,1,0); frame(0,1,1); frame(0,0,1);
  frame(1,1,0); frame(1,1,1); frame(1,0,1);
  $fclose(fd);
  $display("PASS render dump");
  $finish;
end
endmodule
