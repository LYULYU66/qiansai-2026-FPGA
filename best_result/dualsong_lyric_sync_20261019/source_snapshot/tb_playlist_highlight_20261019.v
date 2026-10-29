`timescale 1ns/1ps
// IMAGE3 song-list highlight: frames for songs 0..5 playing, then stopped.
module tb_playlist_highlight_20261019;
reg clk=0,rst=1,vs=0,de=0,playing=0;
always #5 clk=~clk;
reg [2:0] song=0;
reg [23:0] img[0:307199];
reg [23:0] rgb=0;
wire [23:0] out_rgb;
video_playlist_highlight dut(.I_clk(clk),.I_rst(rst),.I_enable(1'b1),.I_vs(vs),.I_de(de),
 .I_playing(playing),.I_song(song),.I_rgb(rgb),.O_rgb(out_rgb));
integer s,x,y,fd,changed;
initial begin
 $readmemh("lyricfix_20261019/image3.hex",img);
 fd=$fopen("lyricfix_20261019/playlist.hex","w");
 repeat(4)@(negedge clk);rst=0;
 for(s=0;s<7;s=s+1)begin
  song=(s<6)?s:0; playing=(s<6);
  @(negedge clk);vs=1;repeat(4)@(negedge clk);vs=0;repeat(20)@(negedge clk);
  changed=0;
  for(y=0;y<480;y=y+1)begin
   for(x=0;x<640;x=x+1)begin
    @(negedge clk);de=1;rgb=img[y*640+x];#1;
    if(out_rgb!==rgb)changed=changed+1;
    $fwrite(fd,"%06h\n",out_rgb);
   end
   @(negedge clk);de=0;repeat(3)@(negedge clk);
  end
  if(s==6 && changed!=0)$fatal(1,"stopped playback must not recolour the list");
  if(s<6 && changed<300)$fatal(1,"song %0d row not highlighted (%0d px)",s,changed);
 end
 $fclose(fd);
 $display("PASS playlist highlight: 6 songs + stopped frame");
 $finish;
end
endmodule
