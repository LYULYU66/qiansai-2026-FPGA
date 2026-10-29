`timescale 1ns/1ps
// Actual R4 B top, FIFO, packet scheduler, receipt receiver and compute path.
// Only PLL/network pin transport and decoded SD outputs are substituted.
// This is not a PHY/MAC, real TF/FAT or HDMI hardware test.
module tb_dualsong_b_boundary;
reg clk50=0; always #10 clk50=~clk50;
reg sys_rst_n=0,uart_rx=1;
reg link_up=0,restart=0,sd_stream=0,sd_write=0;
reg [15:0] link_gen=16'h2222;
reg [31:0] sd_bytes=0,sd_pcm=0;
reg image_req=0,image_valid=0,image_abort=0;
reg [1:0] image_index=0;
reg [31:0] image_word=0,image_resolution=32'h050003c0;
image_media_board_b dut(.clk_50(clk50),.sys_rst_n(sys_rst_n),
 .uart_rx(uart_rx),.uart_tx(),.phy1_rgmii_rx_clk(1'b0),
 .phy1_rgmii_rx_ctl(1'b0),.phy1_rgmii_rx_data(4'd0),
 .phy1_rgmii_tx_clk(),.phy1_rgmii_tx_ctl(),.phy1_rgmii_tx_data(),
 .SD_nCS(),.SD_DCLK(),.SD_MOSI(),.SD_MISO(1'b1),.led());
wire receiver_reset=dut.media_reset || !dut.stream_active;
wire pcm_valid,receipt_event,ack_request,ack_valid;
wire [31:0] pcm_data,received_samples,received_session,receipt_session;
wire [15:0] receipt_sequence,ack_length;
wire [7:0] ack_data;
reg ack_ack=0,desired_song=0;
integer received=0,total_received=0,accepted_packets=0,image_epochs=0;
reg [15:0] expected_seed=0;
reg [31:0] expected_session=0,expected_samples=0;
wire [31:0] played_count=received;
audio_packet_rx #(.SESSION_GUARD(1)) receiver(.clk(dut.udp_clk),.rst(receiver_reset),
 .generation(link_gen),.rx_valid(dut.tx_valid && dut.tx_length==530),
 .rx_data(dut.tx_data),.rx_length(dut.tx_length),.pcm_ready(1'b1),
 .pcm_valid(pcm_valid),.pcm_data(pcm_data),.stream_enable(),
 .file_samples(received_samples),.stream_session(received_session),.fifo_reset(),
 .receipt_event(receipt_event),.receipt_session(receipt_session),.receipt_sequence(receipt_sequence));
song_control_tx_a #(.EXTENDED(1),.SONG_CONTROL(1),.PERIODIC_CYCLES(200)) receipt(.clk(dut.udp_clk),.rst(receiver_reset),
 .event_valid(receipt_event),.event_session(receipt_session),.event_sequence(receipt_sequence),
 .desired_song(desired_song),.played_words(played_count),.volume_level(4'd4),.analysis_enable(1'b1),
 .udp_ready(1'b1),.udp_ack(ack_ack),.udp_request(ack_request),
 .udp_valid(ack_valid),.udp_data(ack_data),.udp_length(ack_length));
function [31:0] sample_word;
 input integer index; input [15:0] seed;
 reg [15:0] left,right;
 begin left=seed+index*3;right=~left;sample_word={right,left};end
endfunction
always @(posedge dut.udp_clk) begin
 if(receiver_reset) begin received=0;ack_ack<=0;end
 else begin
  ack_ack<=ack_request;
  if(pcm_valid) begin
   if(pcm_data!==sample_word(received,expected_seed))
    $fatal(1,"B top lost/reordered PCM word %0d got %h",received,pcm_data);
   if(received_session!==expected_session || received_samples!==expected_samples)
    $fatal(1,"B top incoherent session/length %h / %0d",received_session,received_samples);
   received=received+1;total_received=total_received+1;
  end
  if(receipt_event)accepted_packets=accepted_packets+1;
 end
 if(!dut.compute_reset && dut.analysed_words>played_count)
  $fatal(1,"B top analysed future/unplayed audio");
end
task start_audio;
 input [31:0] bytes; input [15:0] seed; input [15:0] session_low;
 begin
  @(negedge dut.sd_clk);sd_bytes=bytes;expected_seed=seed;
  expected_session={link_gen,session_low};expected_samples=bytes>>2;
  repeat(4)@(negedge dut.sd_clk);sd_stream=1;
  wait(dut.stream_active);#1;
  if(dut.audio_session!==expected_session || dut.file_samples_udp!==expected_samples)
   $fatal(1,"B top metadata not committed with stream start");
  wait(!dut.compute_reset);repeat(8)@(negedge dut.compute_clk);
  if(dut.u_remote_compute.song_match_sync[1] !== (expected_samples==10043560 || expected_samples==14122496))
   $fatal(1,"B top song-match CDC mismatch");
  if(dut.u_remote_compute.song_type_sync[1] !== (expected_samples==14122496))$fatal(1,"new song bank selection wrong");
 end
endtask
task push_audio;
 input integer words;input [15:0] seed;
 integer i;
 begin
  i=0;@(negedge dut.sd_clk);
  while(i<words)begin
   sd_write=!dut.pcm_full && !dut.media_sd_reset;
   sd_pcm=sample_word(i,seed);
   if(sd_write)i=i+1;
   @(negedge dut.sd_clk);
  end
  sd_write=0;
 end
endtask
task stop_audio;
 begin
  @(negedge dut.sd_clk);sd_write=0;sd_stream=0;
  wait(!dut.stream_active);repeat(8)@(negedge dut.compute_clk);
  if(!dut.compute_reset || !dut.pcm_empty || dut.analysed_words!=0)
   $fatal(1,"B top audio stop did not clear local state");
 end
endtask
task uart_byte;
 input [7:0] value;integer b;
 begin
  @(negedge clk50);uart_rx=0;#8680;
  for(b=0;b<8;b=b+1)begin uart_rx=value[b];#8680;end
  uart_rx=1;#8680;
 end
endtask
integer j,k,old_bad;
initial begin
 force dut.link_ready=link_up;force dut.link_generation=link_gen;force dut.link_restart=restart;
 force dut.stream_enable=sd_stream;force dut.file_bytes=sd_bytes;
 force dut.pcm_write=sd_write;force dut.pcm_write_data=sd_pcm;
 force dut.u_media.write_req=image_req;force dut.u_media.write_en=image_valid;
 force dut.u_media.write_data=image_word;force dut.u_media.write_index=image_index;
 force dut.u_media.top_down=1'b1;force dut.u_media.load_abort=image_abort;
 force dut.u_media.live_source_resolution=image_resolution;
 force dut.rx_valid=ack_valid;force dut.rx_data=ack_data;
 force dut.rx_length=ack_length;force dut.rx_port=16'h5002;
 #137;sys_rst_n=1;#203;link_up=1;
 wait(!dut.media_reset && !dut.media_sd_reset);
 start_audio(32'd40174240,16'h1234,16'd1);
 push_audio(384,16'h1234);
 // A changing SD-domain file bus must not change the ongoing song's metadata.
 @(negedge dut.sd_clk);sd_bytes=8000;
 wait(received==384);repeat(30)@(negedge dut.udp_clk);
 if(dut.file_samples_udp!=10043560 || dut.u_remote_compute.song_match_sync[1]!=1)
  $fatal(1,"B top used live file-size bus mid-song");
 desired_song=1;
 wait(dut.requested_song_udp && dut.song_request_sd[1]);
 stop_audio();
 start_audio(32'd56489984,16'h2345,16'd2);
 push_audio(384,16'h2345);wait(received==384);
 // CRC-qualified but old-session controls must not undo the new song.
 force dut.receipt_valid=1;force dut.receipt_session=32'h22220001;force dut.remote_song_request=0;
 repeat(3)@(negedge dut.udp_clk);
 if(dut.requested_song_udp!=1)$fatal(1,"old-session song request accepted");
 release dut.receipt_valid;release dut.receipt_session;release dut.remote_song_request;
 desired_song=0;wait(!dut.requested_song_udp&&!dut.song_request_sd[1]);
 stop_audio();
 // Real 115200 UART -> 50/125 MHz control mailbox, preserved across link restart.
 uart_byte("V");uart_byte("O");uart_byte("L");uart_byte(" ");uart_byte("4");uart_byte(13);
 #20000;
 if(dut.control_volume!=4 || dut.control_settings[3:0]!=4)
  $fatal(1,"B top PC UART/control CDC did not deliver volume");
 start_audio(32'd8000,16'h3456,16'd3);
 old_bad=dut.u_net.bad_packets;
 push_audio(256,16'h3456);
 wait(dut.tx_valid && dut.tx_length==530);
 repeat(30)@(negedge dut.udp_clk);
 // Abort an accepted packet: base-owned scheduler must drain/poison its tail.
 #1.3;link_up=0;sd_stream=0;
 wait(dut.u_net.bad_packets>old_bad);
 if(received!=0)$fatal(1,"B top accepted an aborted PCM packet");
 repeat(12)@(negedge dut.sd_clk);link_gen=16'h3333;link_up=1;
 wait(!dut.media_reset && !dut.media_sd_reset);
 if(dut.control_volume!=4 || dut.control_settings[3:0]!=4)
  $fatal(1,"B top link restart erased PC settings");
 start_audio(32'd16384,16'h5678,16'd1);
 push_audio(256,16'h5678);wait(received==256);stop_audio();
 // Actual image-source wrapper: short abort does not reuse the failed token.
 for(j=0;j<3;j=j+1)begin
  @(negedge dut.sd_clk);image_index=j;image_resolution=32'h050003c0+j;image_req=1;
  wait(dut.u_media.write_ack);@(negedge dut.sd_clk);image_req=0;
  wait(dut.u_media.udp_active);#1;
  image_epochs=image_epochs+1;
  if(dut.u_media.epoch_counter!=image_epochs || dut.u_media.udp_index!=j ||
     dut.u_media.udp_resolution!=image_resolution)
   $fatal(1,"B top image bundled metadata/epoch mismatch");
  for(k=0;k<16;k=k+1)begin
   @(negedge dut.sd_clk);image_valid=dut.u_media.fifo_ready;image_word={24'h123456,8'd0};
  end
  @(negedge dut.sd_clk);image_valid=0;#2.1;image_abort=1;#0.6;image_abort=0;
  repeat(12)@(negedge dut.sd_clk);
  if(dut.u_media.epoch_counter!=image_epochs || dut.u_media.udp_active ||
     dut.u_media.pixel_valid || dut.u_media.write_ack)
   $fatal(1,"B top image abort retained stale pixels or reset epoch");
 end
 if(total_received!=1024 || accepted_packets!=8 || dut.u_net.bad_packets!=old_bad+1)
  $fatal(1,"B top boundary coverage incomplete words=%0d packets=%0d bad=%0d",total_received,accepted_packets,dut.u_net.bad_packets);
 $display("PASS player B boundary: actual top/FIFO/scheduler/compute, 1024 PCM words, both tracks and stale-song guard, metadata freeze, UART, poisoned packet/relink and 3 image aborts");
 $finish;
end
initial begin #10000000;$fatal(1,"player B boundary timeout");end
endmodule

// Clock/PLL abstraction only. No FPGA primitive or clock setting is modified.
module sys_pll(input refclk,reset,output extlock,output reg clk0_out=0,
 output clk1_out,clk2_out);
always #5 clk0_out=~clk0_out;
assign extlock=!reset;assign clk1_out=clk0_out;assign clk2_out=~clk0_out;
endmodule
module dual_board_eth_transport #(parameter ROLE=0,UDP_PORT=16'h5002,FIXED_PEER=0)(
 input clk_50,sys_rst_n,phy1_rgmii_rx_clk,phy1_rgmii_rx_ctl,
 input [3:0]phy1_rgmii_rx_data,
 output phy1_rgmii_tx_clk,phy1_rgmii_tx_ctl,output [3:0]phy1_rgmii_tx_data,
 output reg udp_clk=0,output reset,tx_ready_app,output reg tx_ack_app=0,
 input tx_request_app,tx_valid_app,input [7:0]tx_data_app,input [15:0]tx_length_app,
 output rx_valid_app,output [7:0]rx_data_app,output [15:0]rx_length_app,rx_port_app,
 output reg media_video_clk=0,output media_5x_clk,media_clock_ready);
always #4 udp_clk=~udp_clk;always #20 media_video_clk=~media_video_clk;
assign reset=!sys_rst_n;assign media_clock_ready=sys_rst_n;
assign phy1_rgmii_tx_clk=udp_clk;assign phy1_rgmii_tx_ctl=0;assign phy1_rgmii_tx_data=0;
assign media_5x_clk=udp_clk;assign rx_valid_app=0;assign rx_data_app=0;
assign rx_length_app=0;assign rx_port_app=UDP_PORT;
integer count=0,length=0,cycles=0,bad_packets=0,packets=0;
reg busy=0,started=0;reg [15:0]crc=16'hffff;
reg [7:0]crc_hi=0;
assign tx_ready_app=!busy && cycles%17>=3;
function [15:0] crc_byte;
 input [15:0] old;input [7:0]value;reg [15:0]c;integer i;
 begin c=old^{value,8'd0};for(i=0;i<8;i=i+1)c=c[15]?(c<<1)^16'h1021:c<<1;crc_byte=c;end
endfunction
always @(posedge udp_clk)begin
 tx_ack_app<=0;
 if(!sys_rst_n)begin busy=0;started=0;count=0;cycles=0;bad_packets=0;packets=0;end
 else begin
  cycles=cycles+1;
  if(!busy && tx_ready_app && tx_request_app)begin
   busy=1;started=0;length=tx_length_app;count=0;crc=16'hffff;tx_ack_app<=1;
  end
  if(tx_valid_app)begin
   if(!busy || length!=tx_length_app)$fatal(1,"transport request/length ownership lost");
   started=1;
   if(count<length-2)crc=crc_byte(crc,tx_data_app);
   else if(count==length-2)crc_hi=tx_data_app;
   else if({crc_hi,tx_data_app}!==crc)bad_packets=bad_packets+1;
   count=count+1;
   if(count==length)begin busy=0;started=0;packets=packets+1;end
  end else if(started)$fatal(1,"transport truncated an accepted packet");
 end
end
endmodule
