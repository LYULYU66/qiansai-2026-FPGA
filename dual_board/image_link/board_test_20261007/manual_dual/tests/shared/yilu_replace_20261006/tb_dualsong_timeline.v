`timescale 1ns/1ps
module tb_dualsong_timeline;
reg clk=0,vclk=0,rst=1,stream=0,match=1,sample_read=0,song=0;
always #5 clk=~clk;
always #7 vclk=~vclk;
wire [7:0] line,next_line;
wire [4:0] chars;
wire [9:0] red;
audio_lyric_timeline #(.DUAL_SONG(1)) dut(.I_audio_clk(clk),.I_video_clk(vclk),
 .I_rst(rst),.I_stream_enable(stream),.I_song_matches(match),.I_sample_read(sample_read),.I_song(song),
 .O_line_video(line),.O_next_line_video(next_line),.O_sung_chars_video(chars),.O_red_pixels_video(red));
integer bank,event_no,count_events,checks=0;
reg [23:0] held_count;
reg [29:0] held_progress;
reg [5:0] code;
reg [8:0] saved_index;
reg [4:0] expected_current,expected_next;
reg [17:0] ref_events[0:1023];
integer expected_due;
task freeze_check;
 begin
  sample_read=0;held_count=dut.sample_count;held_progress=dut.red_q;
  repeat(60)@(negedge clk);
  if(dut.sample_count!=held_count||dut.red_q!=held_progress)$fatal(1,"underflow advances lyrics");
 end
endtask
initial begin
 $readmemh("../../../assets/lyrics/yilu_replace_20261006/events_ref.hex",ref_events);
 repeat(5)@(negedge clk);rst=0;
 for(bank=0;bank<2;bank=bank+1)begin
  stream=0;song=bank;repeat(20)@(negedge clk);stream=1;
  expected_due=0;
  count_events=bank?360:373;
  for(event_no=0;event_no<count_events;event_no=event_no+1)begin
   wait(dut.due_valid&&!dut.div_busy);@(negedge clk);
   if(dut.event_index!=event_no)$fatal(1,"event order wrong");
   code=dut.due_code;saved_index=dut.event_index;
   expected_due=expected_due+(ref_events[bank*512+event_no]>>6)*480;
   if(dut.event_due!=expected_due||code!=ref_events[bank*512+event_no][5:0])$fatal(1,"ROM/audio timestamp mismatch");
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
   if(line[5]!=song||next_line[5]!=song)$fatal(1,"visual song bank wrong");
  end
  wait(!dut.due_valid);@(negedge clk);
  dut.sample_count=bank?14122495:10043559;sample_read=1;
  @(negedge clk);sample_read=0;
  if(dut.current_line!=23||dut.next_line!=24||dut.sample_count!=0)$fatal(1,"EOF intro flash/restart wrong");
  repeat(12)@(negedge vclk);
  if(line!=(bank?55:23)||next_line!=(bank?56:24))$fatal(1,"EOF mailbox wrong");
 end
 stream=0;repeat(30)@(negedge clk);
 if(line[4:0]!=0||red!=0)$fatal(1,"stop not cleared");
 $display("PASS dualsong timeline: %0d events, both banks, red sweep, underflow freeze, EOF and switch restart",checks);
 $finish;
end
initial begin #10000000;$fatal(1,"timeline timeout event=%0d bank=%0d",event_no,bank);end
endmodule
