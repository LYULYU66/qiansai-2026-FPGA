`timescale 1ns/1ps
module song_reader_case #(parameter REVERSE=0)(output reg done=0);
reg clk=0,udp_clk=0,rst=1,scan_start=0,request=0,fifo_ready=1;
always #5 clk=~clk;
always #4 udp_clk=~udp_clk;
wire [1:0] found;
wire idle,selected,run_enable,audio_valid,sd_read,scan_done;
wire [7:0] audio_data;
wire [31:0] bytes,sd_addr,session,samples;
wire stream_active;
reg [7:0] sd_data=0;
reg sd_valid=0,sd_end=0,sending=0,end_pending=0,armed=1;
reg [31:0] active_sector=0;
reg [8:0] offset=0;
integer delay=0,cycles=0,images=0,track_bytes=0,transitions=0;
reg previous_run=0;
wire stream=scan_done && found[selected] && run_enable;
song_stream_control control(.clk(clk),.rst(rst),.requested_song(request),
    .reader_idle(idle),.songs_found(found),.selected_song(selected),.run_enable(run_enable));
player_audio_session sessions(.clk(udp_clk),.rst(rst),.stream_async(stream),
    .generation(16'h1234),.file_bytes_async(bytes),.stream_active(stream_active),
    .session_id(session),.file_samples(samples));
bmp_read #(.DUAL_SONG(1),.PIPELINED_CLUSTER_ADDR(1)) dut(
    .clk(clk),.rst(rst),.ready(),.scan_start(scan_start),.scan_target_count(3'd4),
    .scan_done(scan_done),.scan_found_valid(),.scan_found_sector(),.scan_found_cluster(),.scan_found_total(),
    .load_start(1'b0),.load_abort(1'b0),.load_sector(32'd0),.load_cluster(32'd0),
    .audio_enable(stream),.audio_fifo_ready(fifo_ready),.audio_file_found(),
    .audio_song_select(selected),.audio_songs_found(found),.audio_idle(idle),
    .audio_file_bytes(bytes),.audio_data_valid(audio_valid),.audio_data(audio_data),
    .sd_init_done(1'b1),.state_code(),.bmp_width(16'd640),.bmp_height(16'd480),
    .write_req(),.write_req_ack(1'b0),.sd_sec_read(sd_read),.sd_sec_read_addr(sd_addr),
    .sd_sec_read_data(sd_data),.sd_sec_read_data_valid(sd_valid),.sd_sec_read_end(sd_end),
    .bmp_data_wr_en(),.bmp_data(),.source_width(),.source_height(),.source_top_down(),.write_pixel_ready(1'b1));
function [7:0] entry_byte;
 input integer entry;input [4:0] pos;
 reg track;
 begin
  entry_byte=0;track=(entry==5)^REVERSE;
  if(entry<4)case(pos)
   0:entry_byte="P";1:entry_byte="I";2:entry_byte="C";3:entry_byte="1"+entry;
   4,5,6,7:entry_byte=" ";8:entry_byte="B";9:entry_byte="M";10:entry_byte="P";
   11:entry_byte=8'h20;26:entry_byte=3+entry;
  endcase
  else if(entry<6)case(pos)
   0:entry_byte="M";1:entry_byte="U";2:entry_byte="S";3:entry_byte="I";4:entry_byte="C";
   5:entry_byte=track ? "2" : " ";6,7:entry_byte=" ";
   8:entry_byte="P";9:entry_byte="C";10:entry_byte="M";11:entry_byte=8'h20;
   26:entry_byte=track?11:7;29:entry_byte=track?6:4;
  endcase
 end
endfunction
function [7:0] sector_byte;
 input [31:0] sector;input [8:0] at;
 begin
  sector_byte=0;
  case(sector)
   0:case(at)12:sector_byte=2;13,14,16,36:sector_byte=1;44:sector_byte=2;endcase
   1:case(at)
    28:sector_byte=9;36,37,38,39:sector_byte=8'hff;
    44:sector_byte=14;56:sector_byte=16;64,65,66,67:sector_byte=8'hff;
   endcase
   2:sector_byte=entry_byte(at[8:5],at[4:0]);
   7,9,11,14,16:sector_byte=at[7:0]^sector[7:0];
  endcase
 end
endfunction
always @(posedge clk) begin
 sd_valid<=0;sd_end<=0;cycles<=cycles+1;
 if(!sd_read)armed<=1;
 if(end_pending)begin sd_end<=1;end_pending<=0;end
 else if(!sending && sd_read && armed)begin
  sending<=1;armed<=0;active_sector<=sd_addr;offset<=0;delay<=3;
 end else if(sending)begin
  if(delay!=0)delay<=delay-1;
  else begin
   sd_valid<=1;sd_data<=sector_byte(active_sector,offset);delay<=(offset+REVERSE)%3;
   if(offset==511)begin sending<=0;end_pending<=1;end
   else offset<=offset+1'b1;
  end
 end
end
integer expected_sector,position;
always @(posedge clk) begin
 previous_run<=stream;
 if(dut.scan_found_valid)images=images+1;
 if(stream && !previous_run)begin track_bytes=0;transitions=transitions+1;end
 if(audio_valid && stream)begin
  position=track_bytes % (selected?1536:1024);
  if(selected)expected_sector=position<512 ? 11 : position<1024 ? 14 : 16;
  else expected_sector=position<512 ? 7 : 9;
  if(audio_data!==((position & 255)^expected_sector))
   $fatal(1,"track=%0d byte=%0d sector=%0d data=%02x",selected,track_bytes,expected_sector,audio_data);
  track_bytes=track_bytes+1;
 end
 if(stream && bytes!==(selected ? 1536 : 1024))$fatal(1,"Metadata changed inside stream");
end
task change_track;
 input target;
 begin
  @(negedge clk);request=target;
  wait(!run_enable);wait(run_enable);wait(selected==target);
  repeat(12)@(negedge clk);
  wait(track_bytes>=1800);
  if(session[31:16]!=16'h1234 || samples!==(target?384:256))
   $fatal(1,"Session metadata mismatch target=%d samples=%d session=%h",target,samples,session);
 end
endtask
initial begin
 repeat(5)@(negedge clk);rst=0;
 @(negedge clk);scan_start=1;@(negedge clk);scan_start=0;
 wait(scan_done);repeat(3)@(negedge clk);
 if(found!==3 || images!=4)$fatal(1,"Directory scan lost a track/image reverse=%0d",REVERSE);
 wait(track_bytes>=1300);
 change_track(1);
 // Request during a live SD sector with FIFO backpressure; drain must not hang.
 @(negedge clk);fifo_ready=0;request=0;
  wait(!run_enable);wait(run_enable);fifo_ready=1;
  repeat(12)@(negedge clk);
 wait(track_bytes>=1500);
 change_track(1);change_track(0);
 // Bounce the request back before the old sector completes; latest state wins.
 @(negedge clk);request=1;wait(!run_enable);
  @(negedge clk);request=0;wait(run_enable);
  repeat(12)@(negedge clk);
 wait(track_bytes>=1300);
 if(selected!==0 || images!=4 || transitions<5)$fatal(1,"Rapid switch changed image cache");
 $display("PASS two-song reader reverse=%0d cycles=%0d sessions=%0d images=%0d fragmented/FIFO/midsector/rapid/loop",REVERSE,cycles,session[15:0],images);
 done=1;
end
initial begin #3000000;$fatal(1,"Song reader timeout");end
endmodule
module tb_dualsong_reader;
wire a,b;
song_reader_case #(.REVERSE(0)) normal(a);
song_reader_case #(.REVERSE(1)) reversed(b);
initial begin wait(a && b);$finish;end
endmodule
