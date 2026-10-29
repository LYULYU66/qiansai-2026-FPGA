`timescale 1ns/1ps
module tb_dualsong_timeline;
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
integer bank,event_no,count_events,checks=0;
wire [4:0] head0=song*5+1;
reg [23:0] held_count;
reg [29:0] held_progress;
reg [5:0] code;
reg [8:0] saved_index;
reg [5:0] expected_current,expected_next;
task freeze_check;
 begin
  sample_read=0;held_count=dut.sample_count;held_progress=dut.red_q;
  repeat(60)@(negedge clk);
  if(dut.sample_count!=held_count||dut.red_q!=held_progress)$fatal(1,"underflow advances lyrics");
 end
endtask
initial begin
 repeat(5)@(negedge clk);rst=0;
 for(bank=0;bank<6;bank=bank+1)begin
  stream=0;song=bank;repeat(20)@(negedge clk);stream=1;
  case(bank)
   0:count_events=EVENTS_0; 1:count_events=EVENTS_1; 2:count_events=EVENTS_2;
   3:count_events=EVENTS_3; 4:count_events=EVENTS_4; default:count_events=EVENTS_5;
  endcase
  for(event_no=0;event_no<count_events;event_no=event_no+1)begin
   wait(dut.due_valid&&!dut.div_busy);@(negedge clk);
   if(dut.event_index!=event_no)$fatal(1,"event order wrong");
   code=dut.due_code;saved_index=dut.event_index;
   expected_current=dut.boundary_current;expected_next=dut.boundary_next;
   // Fast-forward only the long sample gaps; exercise each event's real
   // load/divider/consumption path, including 100 continuous sweep samples.
   if(dut.event_due>dut.sample_count+100)begin
    dut.sample_count=dut.event_due-100;
    freeze_check;
    sample_read=1;
   end else sample_read=1;
   wait(dut.event_index!=saved_index);@(negedge clk);sample_read=0;
   if(code==32 && (dut.current_line!=expected_current||dut.next_line!=expected_next))$fatal(1,"boundary map wrong");
   if(code<=20 && dut.completed!=code)$fatal(1,"red syllable progress wrong");
   checks=checks+1;
   repeat(12)@(negedge vclk);
   // Lyric rows use the song bank, head rows bank 6.
   if((line[7:5]!=song&&line[7:5]!=6)||(next_line[7:5]!=song&&next_line[7:5]!=6))
     $fatal(1,"visual song bank wrong");
  end
  wait(!dut.due_valid);@(negedge clk);
  case(bank)
   0:dut.sample_count=10043559; 1:dut.sample_count=14122495;
   2:dut.sample_count=12484479; 3:dut.sample_count=12391039;
   4:dut.sample_count=11526409; default:dut.sample_count=13232019;
  endcase
  sample_read=1;
  @(posedge clk); #1 sample_read=0;
  @(negedge clk);
  if(dut.current_line!={1'b1,head0}||dut.next_line!={1'b1,head0+5'd1}||dut.sample_count!=0)$fatal(1,"EOF song-head restart wrong bank=%0d cur=%0d next=%0d count=%0d due=%0d samples=%0d",bank,dut.current_line,dut.next_line,dut.sample_count,dut.due_valid,dut.selected_song_samples);
  repeat(12)@(negedge vclk);
  if(line!={3'd6,head0}||next_line!={3'd6,head0+5'd1})$fatal(1,"EOF mailbox head wrong");
 end
 stream=0;repeat(30)@(negedge clk);
 if(line[4:0]!=0||red!=0)$fatal(1,"stop not cleared");
 $display("PASS dualsong timeline: %0d events, both banks, red sweep, underflow freeze, EOF and switch restart",checks);
 $finish;
end
// Six banks exercise the full event ROM; allow the complete regression to
// finish on the slower Intel ModelSim build used in CI.
initial begin #100000000;$fatal(1,"timeline timeout event=%0d bank=%0d",event_no,bank);end
endmodule
