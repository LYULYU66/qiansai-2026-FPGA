`timescale 1ns/1ps
// Full-song timeline regression for the 20261019 head/lyric sync fix.
// Every event of all six banks fires from the PCM sample counter; the log is
// compared with the generator schedule by check_lyric_sync_20261019.py.
// Idle spans (no sweep in progress) are fast-forwarded; every red sweep is
// stepped sample by sample and must rise monotonically to its column.
module tb_lyric_sync_20261019;
reg clk=0,vclk=0,rst=1,stream=0,match=1,sample_read=0;
reg [2:0] song=0;
always #5 clk=~clk;
always #7 vclk=~vclk;
wire [7:0] line,next_line;
wire [4:0] chars;
wire [9:0] red;
audio_lyric_timeline #(.DUAL_SONG(1)) dut(.I_audio_clk(clk),.I_video_clk(vclk),
 .I_rst(rst),.I_stream_enable(stream),.I_song_matches(match),.I_sample_read(sample_read),.I_song(song),
 .O_line_video(line),.O_next_line_video(next_line),.O_sung_chars_video(chars),.O_red_pixels_video(red));
`include "lyricfix_20261019/event_counts.vh"
integer bank,fired,total,log,expected_events,sweep_checks;
reg [8:0] last_index;
reg [9:0] last_red;
reg [5:0] fire_code;
reg [23:0] fire_sample;
reg [4:0] head0;
initial begin
 log=$fopen("lyricfix_20261019/timeline_events.log","w");
 total=0; sweep_checks=0;
 repeat(5)@(negedge clk);rst=0;
 for(bank=0;bank<6;bank=bank+1)begin
  stream=0;song=bank;repeat(20)@(negedge clk);stream=1;repeat(12)@(negedge clk);
  head0=bank*5+1;
  if(dut.current_line!=={1'b1,head0}||dut.next_line!=={1'b1,head0+5'd1})
   $fatal(1,"song %0d does not start on its head rows: %0d/%0d",bank,dut.current_line,dut.next_line);
  repeat(16)@(negedge vclk);
  if(line!=={3'd6,head0}||next_line!=={3'd6,head0+5'd1})
   $fatal(1,"song %0d head not published to video: %h/%h",bank,line,next_line);
  case(bank) 0:expected_events=EVENTS_0; 1:expected_events=EVENTS_1; 2:expected_events=EVENTS_2;
   3:expected_events=EVENTS_3; 4:expected_events=EVENTS_4; default:expected_events=EVENTS_5; endcase
  fired=0; last_red=0;
  // The sample-0 head boundary may already have fired (no bias on songs 0,2..5).
  if(dut.event_index==1)begin
   $fwrite(log,"%0d %0d %0d %0d %0d\n",bank,0,32,dut.current_line,dut.next_line);
   fired=1; total=total+1;
  end
  while(fired<expected_events)begin
   last_index=dut.event_index;
   // Nothing on screen moves while no sweep is armed: skip ahead safely.
   if(dut.due_valid && !dut.div_busy && dut.rate==0 &&
      dut.event_due_adjusted>{1'b0,dut.sample_count}+25'd8)
     dut.sample_count=dut.event_due_adjusted-8;
   // One sample, then one idle clock: a due event fires inside this window.
   sample_read=1; @(negedge clk); sample_read=0; @(negedge clk);
   if(dut.red_q[29:20]<last_red && dut.event_index==last_index)
     $fatal(1,"red sweep moved backwards song=%0d",bank);
   if(dut.rate!=0 && dut.due_code<=20 && dut.red_q[29:20]>{dut.due_code[4:0],5'd0})
     $fatal(1,"red sweep overshoots its column song=%0d",bank);
   if(dut.rate!=0) sweep_checks=sweep_checks+1;
   last_red=dut.red_q[29:20];
   if(dut.event_index!=last_index)begin
    fire_code=dut.due_code; fire_sample=dut.sample_count;
    if(fire_code<=20 && dut.red_q[29:20]!={fire_code[4:0],5'd0})
     $fatal(1,"column %0d not fully red at its event song=%0d",fire_code,bank);
    $fwrite(log,"%0d %0d %0d %0d %0d\n",bank,dut.sample_count,fire_code,
            fire_code==32?dut.current_line:6'd0,fire_code==32?dut.next_line:6'd0);
    if(fire_code==32 && dut.red_q!=0) $fatal(1,"new row not white");
    last_red=dut.red_q[29:20];
    fired=fired+1; total=total+1;
   end
  end
  repeat(40)@(negedge clk);
  if(dut.due_valid) $fatal(1,"song %0d has events beyond the expected table",bank);
 end
 stream=0;repeat(30)@(negedge clk);
 repeat(16)@(negedge vclk);
 if(line[4:0]!=0||red!=0)$fatal(1,"stop not cleared");
 $fclose(log);
 $display("PASS lyric sync 20261019: %0d events, %0d stepped sweep samples, heads on bank 6",total,sweep_checks);
 $finish;
end
initial begin #2000000000;$fatal(1,"timeline timeout bank=%0d fired=%0d",bank,fired);end
endmodule
