`timescale 1ns/1ps
module tb_dualsong_control;
reg clk=0,rst=1,button=1,event_valid=0,desired=0;
always #4 clk=~clk;
wire press;
key_press_debounce #(.CLK_FREQ_HZ(10000),.DEBOUNCE_MS(1)) key(clk,rst,button,press);
integer presses=0,accepted=0,n,i,mode,before_count;
always @(posedge clk)if(press)presses=presses+1;
wire req,valid;
wire [7:0] data;
wire [15:0] length;
reg ack=0,ready=1,rx_valid=0;
reg [7:0] rx_data=0,packet[0:31];
reg [15:0] rx_length=18;
wire received,song,en;
wire [31:0] session,played;
wire [15:0] seq;
wire [3:0] volume;
audio_receipt_tx #(.EXTENDED(1),.SONG_CONTROL(1),.PERIODIC_CYCLES(100)) tx(
 .clk(clk),.rst(rst),.event_valid(event_valid),.event_session(32'd123),
 .played_words(32'd456),.event_sequence(16'd7),.volume_level(4'd8),
 .analysis_enable(1'b1),.desired_song(desired),.udp_ready(ready),.udp_ack(ack),
 .udp_request(req),.udp_valid(valid),.udp_data(data),.udp_length(length));
song_receipt_rx_b #(.EXTENDED(1),.SONG_CONTROL(1)) rx(
 .clk(clk),.rst(rst),.rx_valid(rx_valid),.rx_data(rx_data),.rx_length(rx_length),
 .receipt_valid(received),.receipt_session(session),.played_words(played),
 .receipt_sequence(seq),.volume_level(volume),.analysis_enable(en),.requested_song(song));
always @(posedge clk)begin #1;if(received)accepted=accepted+1;end
function [15:0] crc_step;
 input [15:0] prior;input [7:0] b;integer k;reg [15:0] c;
 begin c=prior^{b,8'd0};for(k=0;k<8;k=k+1)c=c[15]?(c<<1)^16'h1021:c<<1;crc_step=c;end
endfunction
reg [15:0] crc;
reg requested=0,idle=0;
reg [1:0] found=2'b01;
wire selected,run_song;
song_stream_control switcher(.clk(clk),.rst(rst),.requested_song(requested),
 .reader_idle(idle),.songs_found(found),.selected_song(selected),.run_enable(run_song));
task send_packet;
 input integer size;integer j;
 begin
  for(j=0;j<size;j=j+1)begin @(negedge clk);rx_valid=1;rx_data=packet[j];end
  @(negedge clk);rx_valid=0;repeat(5)@(negedge clk);
 end
endtask
initial begin
 repeat(4)@(negedge clk);rst=0;
 // Debounce and one event per long hold. No KEY2/KEY4 circuitry is touched.
 for(i=0;i<6;i=i+1)begin button=~button;repeat(2)@(negedge clk);end
 button=0;repeat(40)@(negedge clk);
 if(presses!=1)$fatal(1,"KEY3 bounce/hold failure %0d",presses);
 button=1;repeat(20)@(negedge clk);button=0;repeat(30)@(negedge clk);
 if(presses!=2)$fatal(1,"KEY3 second press missing");
 requested=1;repeat(30)@(negedge clk);
 if(selected||!run_song)$fatal(1,"missing MUSIC2 hangs current playback");
 found=3;repeat(20)@(negedge clk);
 if(selected||run_song)$fatal(1,"switch before old sector drains");
 requested=0;idle=1;repeat(25)@(negedge clk);
 if(selected||!run_song)$fatal(1,"latest request revert not respected");
 requested=1;wait(selected);@(negedge clk);
 if(run_song)$fatal(1,"metadata quiet/reset window missing");
 repeat(15)@(negedge clk);
 if(run_song)$fatal(1,"metadata quiet window shortened");
 repeat(3)@(negedge clk);
 if(!run_song)$fatal(1,"new song never resumes");
 // Capture requested song once, not a tearing bit halfway through an AAK3.
 desired=1;event_valid=1;@(negedge clk);event_valid=0;
 wait(req);@(negedge clk);ack=1;@(negedge clk);ack=0;
 i=0;
 while(valid)begin packet[i]=data;if(i==5)desired=0;i=i+1;@(negedge clk);end
 if(i!=18||packet[15]!=1)$fatal(1,"AAK3 song snapshot/length wrong");
 send_packet(18);
 if(accepted!=1||song!=1||session!=123||played!=456||volume!=8||!en)$fatal(1,"AAK3 decode failure");
 // Corruption, reserved bits, truncation, wrong lengths and extra bytes.
 for(n=0;n<120;n=n+1)begin
  mode=n%6;packet[15]=(n&1);rx_length=18;
  if(mode==2)packet[15]=8'h80;
  crc=16'hffff;for(i=0;i<16;i=i+1)crc=crc_step(crc,packet[i]);
  packet[16]=crc[15:8];packet[17]=crc[7:0];packet[18]=0;
  if(mode==1)packet[17]=packet[17]^1;
  if(mode==3)rx_length=17;
  before_count=accepted;
  send_packet(mode==4?17:mode==5?19:18);
  if(accepted!=before_count+(mode==0))$fatal(1,"AAK validation mode=%0d",mode);
 end
 $display("PASS dualsong control: KEY3 debounce, missing-file fallback, drained-sector/quiet-window switching, snapshot, CRC, reserved bits, malformed packets (120 cases)");
 $finish;
end
initial begin #1000000;$fatal(1,"control timeout");end
endmodule
