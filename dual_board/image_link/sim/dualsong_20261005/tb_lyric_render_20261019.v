`timescale 1ns/1ps
// Renders the two lyric rows (y 220..309) of four scenes to hex text for a
// visual check: song-head row with red sweep, a formerly missing lyric row,
// the remapped-glyph head row of song 2 and a formerly blanked lyric row.
module tb_lyric_render_20261019;
reg clk=0,rst=1,vs=0,de=0;
always #5 clk=~clk;
reg [2:0] song=0;
reg [7:0] line_id=0,next_id=0;
reg [9:0] red_px=0;
reg [23:0] rgb=24'h385879;
wire [23:0] out_rgb;
video_lyric_overlay #(.LOW_POWER(1)) lyric(.I_clk(clk),.I_rst(rst),.I_vs(vs),.I_de(de),
 .I_enable(1'b1),.I_card_enable(1'b0),.I_intro_enable(1'b0),.I_home_enable(1'b0),.I_song(song),
 .I_rgb(rgb),.I_line(line_id),.I_next_line(next_id),.I_red_pixels(red_px),.O_rgb(out_rgb));
integer scene,f,x,y,fd;
task frame(input integer dump);
 begin
  @(negedge clk);vs=1;repeat(4)@(negedge clk);vs=0;repeat(80)@(negedge clk);
  for(y=0;y<480;y=y+1)begin
   for(x=0;x<640;x=x+1)begin
    @(negedge clk);de=1;
    @(posedge clk);#2;
    if(dump && y>=220 && y<310) $fwrite(fd,"%06h\n",out_rgb);
   end
   @(negedge clk);de=0;repeat(3)@(negedge clk);
  end
 end
endtask
initial begin
 fd=$fopen("lyricfix_20261019/render.hex","w");
 repeat(4)@(negedge clk);rst=0;
 for(scene=0;scene<4;scene=scene+1)begin
  case(scene)
   0:begin song=5;line_id={3'd6,5'd26};next_id={3'd6,5'd27};red_px=150;end
   1:begin song=3;line_id={3'd3,5'd23};next_id={3'd3,5'd24};red_px=200;end
   2:begin song=2;line_id={3'd6,5'd11};next_id={3'd2,5'd1};red_px=0;end
   default:begin song=5;line_id={3'd5,5'd1};next_id={3'd5,5'd2};red_px=230;end
  endcase
  frame(0); frame(1);
 end
 $fclose(fd);
 $display("PASS render dump: 4 scenes");
 $finish;
end
endmodule
