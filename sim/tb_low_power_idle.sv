`timescale 1ns/1ps
module tb_low_power_idle;
reg clk=0,rst=1,en=0,vs=0;
reg [7:0] line=1,nextline=2;
reg [9:0] red=0;
wire [23:0] stars,lyrics;
integer i,j,point_writes=0,row_writes=0,char_writes=0,old_points,old_rows,old_chars;
reg [50:0] snapshot[0:7];
always #5 clk=~clk;
initial begin
 $dumpfile("sim/low_power_round1_20261002/idle_suspend_reentry.vcd");
 $dumpvars(0,tb_low_power_idle);
end
video_relax_overlay #(.LOW_POWER(1)) star(.I_clk(clk),.I_rst(rst),.I_enable(en),.I_vs(vs),.I_de(1'b0),
 .I_rgb(24'h123456),.I_audio_active(1'b1),.I_vu_left(7'd70),.I_vu_right(7'd30),.I_spectrum_levels({16{7'd90}}),.O_rgb(stars));
video_lyric_overlay #(.LOW_POWER(1)) lyric(.I_clk(clk),.I_rst(rst),.I_enable(en),.I_card_enable(en),
 .I_vs(vs),.I_de(1'b0),.I_rgb(24'h654321),.I_line(line),.I_next_line(nextline),.I_red_pixels(red),.O_rgb(lyrics));
always @(posedge clk)if(!rst)begin
 if(star.point_store)point_writes=point_writes+1;
 if(star.work_enable && !star.init_busy && !star.update_busy && star.row_busy && !star.frame_start)row_writes=row_writes+1;
 if(lyric.cache_write)char_writes=char_writes+1;
end
task frame;
 begin @(negedge clk);vs=1;@(negedge clk);vs=0;repeat(80)@(negedge clk);end
endtask
initial begin
 repeat(4)@(negedge clk);rst=0;
 for(j=0;j<5;j=j+1)frame;
 if(point_writes || row_writes || char_writes)$fatal(1,"hidden boot performed work");
 en=1;frame;
 if(!star.initialized || !lyric.cache_loaded || char_writes!=36)$fatal(1,"initial enable/load");
 old_chars=char_writes;
 for(j=0;j<6;j=j+1)begin red=red+10;frame;end
 if(char_writes!=old_chars || lyric.red_frame!=red)$fatal(1,"red sweep caused redundant cache writes");
 for(i=0;i<8;i=i+1)snapshot[i]=star.points[i];
 old_points=point_writes;old_rows=row_writes;old_chars=char_writes;
 en=0;line=2;nextline=1;
 for(j=0;j<9;j=j+1)frame;
 if(point_writes!=old_points || row_writes!=old_rows || char_writes!=old_chars)$fatal(1,"hidden work did not stop");
 for(i=0;i<8;i=i+1)if(snapshot[i]!==star.points[i])$fatal(1,"hidden point moved");
 if(stars!==24'h123456 || lyrics!==24'h654321)$fatal(1,"hidden layer not transparent");
 en=1;frame;
 if(char_writes!=old_chars+36 || lyric.cache_line!=2 || !star.row_ready)$fatal(1,"reentry stale state");
 old_chars=char_writes;frame;if(char_writes!=old_chars)$fatal(1,"unchanged reentry reload");
 line=23;nextline=24;frame;
 if(char_writes!=old_chars+36 || lyric.cache_line!=23)$fatal(1,"intro loop reload");
 $display("PASS LOW_POWER_IDLE hidden boot/suspend/reentry; stars frozen; no hidden writes; unchanged lyric pair zero reload; red sweep retained; credits loop refresh");$finish;
end
endmodule
