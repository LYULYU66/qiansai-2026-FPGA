`timescale 1ns/1ps
module tb_dualsong_ui;
reg clk=0,rst=1,vs=0,de=0,home=1,music=0,song=0;
reg [23:0] rgb=24'h385879;
always #20 clk=~clk;
wire [23:0] cover_rgb,out_rgb;
wire [7:0] line_id=song?8'd55:8'd23;
video_song_cover_overlay u_cover(.I_clk(clk),.I_rst(rst),.I_vs(vs),.I_de(de),.I_home(home),
 .I_music(music),.I_song(song),.I_rgb(rgb),.O_rgb(cover_rgb));
video_lyric_overlay #(.LOW_POWER(1)) lyric(.I_clk(clk),.I_rst(rst),.I_vs(vs),.I_de(de),
 .I_enable(1'b0),.I_card_enable(music),.I_home_enable(home),.I_song(song),.I_rgb(cover_rgb),
 .I_line(line_id),.I_next_line(line_id+8'd1),.I_red_pixels(10'd0),.O_rgb(out_rgb));
reg [23:0] ref_cover[0:1599];
reg [15:0] old_font[0:8191];
reg [7:0] glyph=0;
reg [4:0] frow=0,fcol=0;
wire [1:0] fcov;
lyric_font_packed_rom ftest(clk,glyph,frow,fcol,fcov);
integer x,y,f,g,r,c,address,frame_song,sx,sy,title_ink=0,cover_count=0,font_count=0;
reg inside_cover,inside_title;
reg [23:0] expected;
initial begin
 $readmemh("dualsong_20261005/cover_expected.hex",ref_cover);
 $readmemh("../../../assets/lyrics/font24_bram32_00.hex",old_font,0,2047);
 $readmemh("../../../assets/lyrics/font24_bram32_01.hex",old_font,2048,4095);
 $readmemh("../../../assets/lyrics/font24_bram32_02.hex",old_font,4096,6143);
 $readmemh("../../../assets/lyrics/font24_bram32_03.hex",old_font,6144,8191);
 repeat(8)@(negedge clk);rst=0;repeat(5)@(negedge clk);
 // Verify the original song's entire font through native vendor RAM models.
 for(g=0;g<133;g=g+1)for(r=0;r<22;r=r+1)for(c=0;c<22;c=c+1)begin
  @(negedge clk);glyph=g;frow=r;fcol=c;address=g*484+r*22+c;
  @(posedge clk);#2;
  if(fcov!==((old_font[address/8]>>((address%8)*2))&3))$fatal(1,"old glyph changed %0d/%0d/%0d",g,r,c);
  font_count=font_count+1;
 end
 // Full 640x480 frames verify one-clock lookup alignment and untouched art.
 for(f=0;f<4;f=f+1)begin
  @(negedge clk);home=f<2;music=f>=2;song=f%2;frame_song=f%2;
  vs=1;repeat(4)@(negedge clk);vs=0;repeat(80)@(negedge clk);
  title_ink=0;
  for(y=0;y<480;y=y+1)begin
   for(x=0;x<640;x=x+1)begin
    @(negedge clk);de=1;
    inside_cover=home?(x>=184&&x<224&&y>=336&&y<376):(x>=160&&x<224&&y>=136&&y<200);
    inside_title=home?(x>=240&&x<304&&y>=338&&y<354):(x>=248&&x<376&&y>=144&&y<168);
    rgb=inside_title?24'hffffff:24'h385879;
    @(posedge clk);#2;
    expected=rgb;
    if(inside_cover&&frame_song)begin
     sx=home?x-184:(x-160)*5/8;sy=home?y-336:(y-136)*5/8;
     expected=ref_cover[sy*40+sx];cover_count=cover_count+1;
    end
    if(cover_rgb!==expected)$fatal(1,"cover pixel alignment f=%0d x=%0d y=%0d got=%h expected=%h",f,x,y,cover_rgb,expected);
    if(!inside_title&&out_rgb!==expected)$fatal(1,"UI leaked outside title");
    if(inside_title&&out_rgb!=24'hffffff)title_ink=title_ink+1;
   end
   @(negedge clk);de=0;repeat(3)@(negedge clk);
  end
  if(title_ink<100)$fatal(1,"dynamic title missing on frame %0d",f);
  if(lyric.cache_song!=frame_song)$fatal(1,"title cache did not select song");
  if({lyric.row_cache[32],lyric.row_cache[33],lyric.row_cache[34],lyric.row_cache[35]}!==
     (frame_song?32'h0cb18fb2:32'h20212223))$fatal(1,"wrong title characters");
 end
 $display("PASS dualsong UI: 4 full frames, %0d cover pixels, %0d original native-font pixels, both card titles, no RGB/DE delay",cover_count,font_count);
 $finish;
end
initial begin #100000000;$fatal(1,"UI timeout");end
endmodule
