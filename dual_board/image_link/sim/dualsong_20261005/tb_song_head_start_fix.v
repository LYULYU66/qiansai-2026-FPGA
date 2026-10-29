`timescale 1ns/1ps
// Regression for the startup/track-change title window.  The metadata match
// flag is intentionally delayed to model SD/UDP settling after a stream is
// enabled.  The title/credits must already be published in that interval as
// the same two normal lyric rows used during playback.
module tb_song_head_start_fix;
reg clk=0,vclk=0,rst=1,stream=0,match=0,sample_read=0;
reg [2:0] song=2;
wire [7:0] line,next_line;
wire [4:0] chars;
wire [9:0] red;
always #5 clk=~clk;
always #7 vclk=~vclk;

audio_lyric_timeline #(.DUAL_SONG(1)) dut(
 .I_audio_clk(clk),.I_video_clk(vclk),.I_rst(rst),
 .I_stream_enable(stream),.I_song_matches(match),.I_sample_read(sample_read),
 .I_song(song),.O_line_video(line),.O_next_line_video(next_line),
 .O_sung_chars_video(chars),.O_red_pixels_video(red));

// Head rows are bank-6 rows song*5+1.. (20261019 sync fix).
wire [4:0] head0=song*5+1;
task wait_video_head;
 integer n;
 begin
  for(n=0;n<30;n=n+1) begin
   @(negedge vclk);
   if(line==={3'd6,head0} && next_line==={3'd6,head0+5'd1}) disable wait_video_head;
  end
  $fatal(1,"title did not reach video mailbox line=%0d next=%0d",line,next_line);
 end
endtask

initial begin
 #30 rst=0;
 // Stream starts before the song matcher has accepted its metadata.
 #20 stream=1;
 repeat(5) @(negedge clk);
 if(dut.current_line!=={1'b1,head0} || dut.next_line!=={1'b1,head0+5'd1})
   $fatal(1,"startup head missing while match is pending: cur=%0d next=%0d",
          dut.current_line,dut.next_line);
 wait_video_head;
 // Once matched, the title remains until the first timed lyric event.
 match=1;
 repeat(8) @(negedge clk);
 if(dut.current_line!=={1'b1,head0} || dut.next_line!=={1'b1,head0+5'd1})
   $fatal(1,"head changed before first lyric event");
 // A track switch with the matcher delayed must re-arm the title immediately.
 song=3; match=0;
 repeat(5) @(negedge clk);
 if(dut.current_line!=={1'b1,head0} || dut.next_line!=={1'b1,head0+5'd1})
   $fatal(1,"track-change head missing while match is pending");
 $display("PASS song-head startup/track-change guard");
 $finish;
end
initial begin
 #100000; $fatal(1,"head-start regression timeout");
end
endmodule
