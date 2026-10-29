`timescale 1ns/1ps
// Music card render for all six songs: QQ logo replaces the cover, the old
// service logo is removed and the full title is centred. Dumps y128..211.
module tb_music_card_20261019;
reg clk=0,rst=1,vs=0,de=0;
always #5 clk=~clk;
reg [2:0] song=0;
reg [23:0] bg[0:307199];
reg [23:0] rgb=0;
wire [23:0] out_rgb;
video_lyric_overlay #(.LOW_POWER(1)) lyric(.I_clk(clk),.I_rst(rst),.I_vs(vs),.I_de(de),
 .I_enable(1'b1),.I_card_enable(1'b1),.I_intro_enable(1'b0),.I_home_enable(1'b0),.I_song(song),
 .I_rgb(rgb),.I_line(8'd0),.I_next_line(8'd0),.I_red_pixels(10'd0),.O_rgb(out_rgb));
integer s,f,x,y,fd;
initial begin
 $readmemh("lyricfix_20261019/music_bg.hex",bg);
 fd=$fopen("lyricfix_20261019/music_card.hex","w");
 repeat(4)@(negedge clk);rst=0;
 for(s=0;s<6;s=s+1)begin
  song=s;
  for(f=0;f<2;f=f+1)begin
   @(negedge clk);vs=1;repeat(4)@(negedge clk);vs=0;repeat(80)@(negedge clk);
   for(y=0;y<480;y=y+1)begin
    for(x=0;x<640;x=x+1)begin
     @(negedge clk);de=1;rgb=bg[y*640+x];
     @(posedge clk);#2;
     if(f==1 && y>=128 && y<212) $fwrite(fd,"%06h\n",out_rgb);
    end
    @(negedge clk);de=0;repeat(3)@(negedge clk);
   end
  end
 end
 $fclose(fd);
 $display("PASS music card dump: 6 songs");
 $finish;
end
endmodule
