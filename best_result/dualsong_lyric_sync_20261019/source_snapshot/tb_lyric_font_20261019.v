`timescale 1ns/1ps
// A-side lyric display regression for the 20261019 fix:
//  * all 515 glyphs read back pixel-exact through the vendor EMB32 models
//    and the inferred 9K tail;
//  * every lyric row of every song and every bank-6 head row loads the
//    expected physical glyph ids (including the remapped song) into the
//    overlay cache, with the right row length.
module tb_lyric_font_20261019;
`include "lyricfix_20261019/row_counts.vh"
reg clk=0,rst=1,vs=0,de=0;
always #5 clk=~clk;
reg [9:0] glyph=0;
reg [4:0] frow=0,fcol=0;
wire [1:0] fcov;
lyric_font_packed_rom font(.I_clk(clk),.I_glyph(glyph),.I_row(frow),.I_col(fcol),
 .I_icon(1'b0),.I_icon_pixel(12'd0),.O_cov(fcov),.O_icon_index());
reg [2:0] song=0;
reg [7:0] line_id=0;
wire [23:0] out_rgb;
video_lyric_overlay #(.LOW_POWER(1)) lyric(.I_clk(clk),.I_rst(rst),.I_vs(vs),.I_de(de),
 .I_enable(1'b1),.I_card_enable(1'b0),.I_intro_enable(1'b0),.I_home_enable(1'b0),.I_song(song),
 .I_rgb(24'h0),.I_line(line_id),.I_next_line(line_id),.I_red_pixels(10'd0),.O_rgb(out_rgb));
reg [15:0] words[0:32767];
reg [9:0] rows[0:ROWS*20-1];
integer g,r,c,address,n,k,len,pixels=0,cells=0;
reg [1:0] expected;
initial begin
 $readmemh("lyricfix_20261019/font_words.hex",words);
 $readmemh("lyricfix_20261019/expected_rows.hex",rows);
 repeat(4)@(negedge clk);rst=0;repeat(4)@(negedge clk);
 for(g=0;g<GLYPHS;g=g+1)for(r=0;r<22;r=r+1)for(c=0;c<22;c=c+1)begin
  @(negedge clk);glyph=g;frow=r;fcol=c;address=g*484+r*22+c;
  @(posedge clk);#2;
  expected=(words[address/8]>>((address%8)*2))&3;
  if(fcov!==expected)$fatal(1,"glyph %0d pixel %0d/%0d: got %0d expected %0d",g,r,c,fcov,expected);
  pixels=pixels+1;
 end
 for(n=0;n<ROWS;n=n+1)begin
  @(negedge clk);song=rows[n*20];line_id={rows[n*20+1][2:0],rows[n*20+2][4:0]};len=rows[n*20+3];
  vs=1;@(negedge clk);vs=0;repeat(48)@(negedge clk);
  if(!lyric.cache_loaded||lyric.load_busy)$fatal(1,"row %0d not loaded",n);
  if(lyric.length_frame!=len||lyric.next_length_frame!=len)
   $fatal(1,"row bank %0d id %0d length %0d expected %0d",line_id[7:5],line_id[4:0],lyric.length_frame,len);
  for(k=0;k<len;k=k+1)begin
   if(lyric.row_cache[k]!==rows[n*20+4+k]||lyric.row_cache[16+k]!==rows[n*20+4+k])
    $fatal(1,"song %0d bank %0d id %0d col %0d: glyph %0d expected %0d",song,line_id[7:5],
           line_id[4:0],k,lyric.row_cache[k],rows[n*20+4+k]);
   cells=cells+1;
  end
 end
 $display("PASS lyric font 20261019: %0d glyphs / %0d pixels, %0d rows / %0d cached glyph cells",
          GLYPHS,pixels,ROWS,cells);
 $finish;
end
initial begin #200000000;$fatal(1,"font regression timeout");end
endmodule
