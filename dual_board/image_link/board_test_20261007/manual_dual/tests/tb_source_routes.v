`timescale 1ns/1ps
// ROUTING UNIT TEST ONLY. image_tf_source is production RTL. All surrounding
// components below are explicit interface models, not real SD/FAT/FIFO/UDP IP.
// Real six-file parsing/scaling/PCM are tested by tb_six_scan/tb_six_preload.
module tb_source_routes;
localparam integer N=32;
reg sd_clk=0,udp_clk=0,rst=1;
always #5 sd_clk=~sd_clk;
always #4 udp_clk=~udp_clk;
reg net_credit=1,local_credit=0;
reg udp_ack=0,rx_valid=0,preview_finish=0;
reg [7:0] rx_data=0;
reg [15:0] rx_length=0;
reg [31:0] rx_token=0;
integer cycles=0,expected_source=0,local_pos=0,local_total=0;
integer network_frames=0,preview_starts=0,finish_expected=0;
wire udp_ready=net_credit && cycles%9!=0 && cycles%9!=1;
wire preview_ready=local_credit && cycles%7!=0 && cycles%7!=1;
wire udp_request,udp_valid,preview_valid,preview_start,preview_abort,preview_top;
wire [7:0] udp_data;
wire [15:0] udp_length;
wire [2:0] preview_index;
wire [23:0] preview_rgb;
wire [3:0] state_code,image_number;
image_tf_source #(.SESSION_GUARD(1),.DUAL_SONG(1),.LOCAL_PREVIEW(1),
 .LOCAL_PAIR(1),.FRAME_PIXELS(N)) dut (
 .sd_clk(sd_clk),.udp_clk(udp_clk),.rst(rst),.generation(16'h5a39),
 .generation_exhausted(),.key_next(1'b1),.key_auto(1'b1),
 .SD_nCS(),.SD_DCLK(),.SD_MOSI(),.SD_MISO(1'b1),
 .udp_ready(udp_ready),.udp_ack(udp_ack),.udp_request(udp_request),
 .udp_valid(udp_valid),.udp_data(udp_data),.udp_length(udp_length),
 .rx_valid(rx_valid),.rx_data(rx_data),.rx_length(rx_length),
 .state_code(state_code),.image_number(image_number),.source_resolutions(),.overflow(),
 .audio_fifo_ready(1'b1),.audio_song_request(1'b0),.audio_pcm_wr_en(),
 .audio_stream_enable(),.audio_pcm_data(),.audio_file_bytes(),
 .preview_ready(preview_ready),.preview_finish(preview_finish),
 .preview_start(preview_start),.preview_top_down(preview_top),.preview_abort(preview_abort),
 .preview_valid(preview_valid),.preview_index(preview_index),.preview_rgb(preview_rgb)
);
function [23:0] rgb;
 input integer id,pos;
 begin rgb=24'h400000+(id<<16)+(pos*257);end
endfunction
function [31:0] resolution;
 input integer id;
 begin resolution=((640+id*16)<<16)|(480+id*8);end
endfunction
function [7:0] tag;
 input integer id,pos;
 begin tag=8'h80+id*16+(pos%16);end
endfunction
task wait_inactive;
 begin
  wait(!dut.udp_active && !dut.source_active);
  repeat(5)@(negedge udp_clk);
 end
endtask
task pulse_local_finish;
 begin
  @(negedge udp_clk);preview_finish=1;
  @(negedge udp_clk);preview_finish=0;
 end
endtask
task receipt;
 input [31:0] token;
 begin
  @(negedge udp_clk);rx_token=token;rx_length=8;rx_valid=1;rx_data=8'ha5;
  @(negedge udp_clk);rx_valid=0;
  repeat(4)@(negedge udp_clk);
 end
endtask
task abort_source;
 begin
  @(negedge sd_clk);dut.u_tf.load_abort=1;
  repeat(8)@(negedge sd_clk);
  if(dut.udp_active || dut.staged_valid || preview_valid || udp_request || udp_valid)
   $fatal(1,"abort left active source/packet/preview state");
  @(negedge sd_clk);dut.u_tf.load_abort=0;
  repeat(8)@(negedge udp_clk);
 end
endtask
reg held=0;
reg [23:0] held_rgb;
reg [7:0] held_tag;
reg held_first;
always @(posedge udp_clk)begin
 cycles=cycles+1;
 if(rst || preview_abort)held=0;
 else begin
  if(held && (!dut.staged_valid || dut.staged_rgb!==held_rgb ||
              dut.staged_tag!==held_tag || dut.staged_first!==held_first))
   $fatal(1,"staged network pixel changed while downstream stalled");
  held=dut.staged_valid && !dut.tx_source_ready;
  held_rgb=dut.staged_rgb;held_tag=dut.staged_tag;held_first=dut.staged_first;
  if(preview_start)begin
   if(preview_index!==expected_source || preview_top!==expected_source[0])
    $fatal(1,"bundled source index/orientation %d expected=%d",preview_index,expected_source);
   preview_starts=preview_starts+1;local_pos=0;
  end
  if(preview_valid)begin
   if(expected_source<4 || expected_source>5 || !preview_ready ||
      preview_index!==expected_source || preview_rgb!==rgb(expected_source,local_pos))
    $fatal(1,"local pixel routing/order mismatch id=%d pos=%d",expected_source,local_pos);
   local_pos=local_pos+1;local_total=local_total+1;
  end
  if(expected_source>=4 && (udp_request || udp_valid || dut.u_packets.source_valid || dut.staged_valid))
   $fatal(1,"B-only/unsupported source leaked into IMG4 transmitter");
 end
end
integer id;
reg before_finish;
initial begin
 repeat(8)@(negedge sd_clk);rst=0;
 wait(!dut.source_sd_reset && !dut.bridge_udp_reset);
 // Network frames must ignore local display credit and finish pulses.
 for(id=0;id<4;id=id+1)begin
  expected_source=id;local_credit=0;
  dut.u_tf.open_frame(id);
  dut.u_tf.emit_pixels(id,N);
  wait(dut.u_packets.waiting);
  before_finish=dut.finish_toggle;
  pulse_local_finish();repeat(3)@(negedge udp_clk);
  if(!dut.udp_active || dut.finish_toggle!==before_finish)
   $fatal(1,"local completion prematurely committed network frame");
  wait(udp_request && udp_ready);
  @(negedge udp_clk);udp_ack=1;@(negedge udp_clk);udp_ack=0;
  receipt(dut.u_packets.token_latched^32'h80000000);
  if(!dut.udp_active)$fatal(1,"wrong-token receipt completed image");
  receipt(dut.u_packets.token_latched);
  wait_inactive();finish_expected=finish_expected+1;
  if(dut.u_tf.finish_events!=finish_expected)$fatal(1,"network finish toggle missing");
  network_frames=network_frames+1;
 end
 if(dut.u_packets.total_pixels!=128 || dut.u_home_indices.starts!=4 ||
    dut.u_home_indices.total_consumed!=128 || local_total!=0)
  $fatal(1,"first four frame/tag totals");
 // Local pair must ignore packet ACK/receipts, retain 3-bit source identity,
 // and only complete once local write completion follows the whole frame.
 for(id=4;id<6;id=id+1)begin
  expected_source=id;local_credit=1;
  dut.u_tf.open_frame(id);
  dut.u_tf.emit_pixels(id,7);
  wait(local_pos==7);before_finish=dut.finish_toggle;
  pulse_local_finish();repeat(3)@(negedge udp_clk);
  if(!dut.udp_active || dut.finish_toggle!==before_finish)
   $fatal(1,"early local write completion accepted");
  dut.u_tf.emit_pixels_from(id,7,N-7);
  wait(local_pos==N);
  @(negedge udp_clk);udp_ack=1;@(negedge udp_clk);udp_ack=0;
  receipt(dut.u_packets.token_latched);
  if(!dut.udp_active || dut.finish_toggle!==before_finish)
   $fatal(1,"network ACK/receipt completed local-only frame");
  pulse_local_finish();wait_inactive();finish_expected=finish_expected+1;
  if(dut.u_tf.finish_events!=finish_expected)$fatal(1,"local finish toggle missing");
 end
 if(dut.u_packets.total_pixels!=128 || dut.u_home_indices.starts!=4 || local_total!=64)
  $fatal(1,"local pair alias/UI activity");
 // Aborted partial local frame is discarded; no stale pixel/tag survives.
 expected_source=4;dut.u_tf.open_frame(4);dut.u_tf.emit_pixels(4,10);wait(local_pos==10);
 abort_source();pulse_local_finish();repeat(6)@(negedge udp_clk);
 if(dut.udp_active)$fatal(1,"stale local completion resurrected aborted frame");
 expected_source=5;dut.u_tf.open_frame(5);dut.u_tf.emit_pixels(5,N);wait(local_pos==N);
 pulse_local_finish();wait_inactive();finish_expected=finish_expected+1;
 if(dut.u_tf.finish_events!=finish_expected)$fatal(1,"retry local finish missing");
 // Fault-injected index7 must not alias to A index3 or to a local valid page.
 expected_source=7;dut.u_tf.open_frame(7);dut.u_tf.emit_pixels(7,8);
 repeat(30)@(negedge udp_clk);
 if(dut.udp_index!==3'd7 || dut.source_count!=0 || local_pos!=0 ||
    dut.u_packets.total_pixels!=128 || dut.u_home_indices.starts!=4)
  $fatal(1,"unsupported index7 alias/consumption");
 abort_source();
 $display("PASS SOURCE_ROUTES: A1..4 only IMG4/tagged network (128 exact pixels), B5/6 local only; 3-bit metadata, credit stalls, full-frame completion, wrong-channel/token rejection, abort/retry, index7 blocked. Interface stubs, not SD/IP validation.");
 $finish;
end
initial begin #1000000;$fatal(1,"routing watchdog");end
endmodule

module player_domain_reset(input wire clk,request,output wire rst);
reg [2:0] pipe;
always @(posedge clk or posedge request)begin
 if(request)pipe<=3'b111;else pipe<={pipe[1:0],1'b0};
end
assign rst=pipe[2];
endmodule

// Stub file producer. The bench explicitly chooses source index and bytes.
module sd_card_bmp_remote #(
 parameter CLK_FREQ_HZ=0,ENABLE_RESAMPLE=0,PIPELINED_CLUSTER_ADDR=0,
 parameter FAST_AUDIO_START=0,DUAL_SONG=0,TOTAL_IMAGES=4,
 parameter [2:0] SCAN_TARGET_COUNT=4
)(
 input wire clk,rst,key_next,key_auto,I_warning_hold,
 input wire [15:0] bmp_width,bmp_height,
 output wire display_valid,warning_image_ready,
 output wire [3:0] state_code,image_number,
 input wire write_finish_toggle,
 output reg [2:0] write_buf_idx,
 output wire [2:0] disp_buf_idx,
 output reg load_abort,write_req,write_en,
 input wire write_req_ack,
 output reg [31:0] write_data,
 output reg write_top_down,
 output wire [127:0] source_resolutions,
 output reg [31:0] live_source_resolution,
 input wire write_pixel_ready,audio_fifo_ready,audio_song_request,
 output wire audio_selected_song,audio_pcm_wr_en,audio_stream_enable,
 output wire [31:0] audio_pcm_data,audio_file_bytes,
 output wire SD_nCS,SD_DCLK,SD_MOSI,input wire SD_MISO
);
assign display_valid=0;assign warning_image_ready=0;assign state_code=0;
assign image_number=0;assign disp_buf_idx=0;assign source_resolutions=0;
assign audio_selected_song=0;assign audio_pcm_wr_en=0;assign audio_stream_enable=0;
assign audio_pcm_data=0;assign audio_file_bytes=0;
assign SD_nCS=1;assign SD_DCLK=0;assign SD_MOSI=1;
reg previous_finish=0;
integer finish_events=0;
always @(posedge clk)begin
 if(rst)begin
  load_abort<=0;write_req<=0;write_en<=0;write_buf_idx<=0;
  write_data<=0;write_top_down<=0;live_source_resolution<=0;
  previous_finish<=0;finish_events<=0;
 end else if(load_abort) previous_finish<=write_finish_toggle;
 else begin
  if(previous_finish!=write_finish_toggle)finish_events<=finish_events+1;
  previous_finish<=write_finish_toggle;
 end
end
initial begin
 if(TOTAL_IMAGES!=6 || SCAN_TARGET_COUNT!=6 || !ENABLE_RESAMPLE || !PIPELINED_CLUSTER_ADDR || !DUAL_SONG)
  $fatal(1,"source failed to configure six-file producer");
end
task open_frame;
 input integer id;
 begin
  @(negedge clk);write_buf_idx=id;write_top_down=id[0];
  live_source_resolution=tb_source_routes.resolution(id);write_req=1;
  wait(write_req_ack);@(negedge clk);write_req=0;
 end
endtask
task emit_pixels_from;
 input integer id,first,n;
 integer i;
 begin
  for(i=first;i<first+n;i=i+1)begin
   @(negedge clk);write_en=0;while(!write_pixel_ready)@(negedge clk);
   write_en=1;write_data={tb_source_routes.rgb(id,i),8'd0};
  end
  @(negedge clk);write_en=0;
 end
endtask
task emit_pixels;
 input integer id,n;
 begin emit_pixels_from(id,0,n);end
endtask
endmodule

// Interface-only two-clock queue. It checks credits/order but is not an
// asynchronous FIFO metastability model or an implementation of the real IP.
module image_pixel_cdc(
 input wire rst,wr_clk,wr_valid,input wire [23:0] wr_rgb,
 output wire wr_ready,overflow,input wire rd_clk,rd_ready,
 output wire rd_valid,output wire [23:0] rd_rgb
);
reg [23:0] q[0:63];
integer w=0,r=0;
assign wr_ready=w-r<64;assign rd_valid=w!=r;assign rd_rgb=q[r%64];
assign overflow=wr_valid && !wr_ready;
always @(posedge wr_clk or posedge rst)begin
 if(rst)w<=0;
 else if(wr_valid)begin
  if(!wr_ready)$fatal(1,"producer overflowed routing queue");
  q[w%64]<=wr_rgb;w<=w+1;
 end
end
always @(posedge rd_clk or posedge rst)begin
 if(rst)r<=0;else if(rd_valid && rd_ready)r<=r+1;
end
endmodule

module home_index_stream(
 input wire clk,rst,start,consume,input wire [1:0] frame_index,
 input wire top_down,output wire ready,output wire [7:0] index
);
reg [1:0] id=0;
integer position=0,starts=0,total_consumed=0;
assign ready=1;assign index=tb_source_routes.tag(id,position);
always @(posedge clk)begin
 if(rst)begin id<=0;position<=0;end
 else begin
  if(start)begin
   if(tb_source_routes.expected_source>=4)$fatal(1,"local frame started home tags");
   id<=frame_index;position<=0;starts=starts+1;
  end
  if(consume)begin position<=position+1;total_consumed=total_consumed+1;end
 end
end
endmodule

module image_receipt_rx(
 input wire clk,rst,rx_valid,input wire [7:0] rx_data,input wire [15:0] rx_length,
 output reg receipt_valid,output reg [31:0] receipt_token,
 output wire [15:0] receipt_sequence
);
assign receipt_sequence=0;
always @(posedge clk)begin
 if(rst)begin receipt_valid<=0;receipt_token<=0;end
 else begin
  receipt_valid<=rx_valid && rx_length==8 && rx_data==8'ha5;
  if(rx_valid)receipt_token<=tb_source_routes.rx_token;
 end
end
endmodule

// Deliberately small packet model: collects32 source pixels, ACKs its request,
// then requires a matching transfer-token receipt before asserting frame_sent.
module image_packet_tx #(
 parameter RELIABLE=0,EXTERNAL_TOKEN=0,UI_TAG=0,RESOLUTION=0
)(
 input wire clk,rst,source_valid,output wire source_ready,
 input wire [23:0] source_rgb,input wire [7:0] source_tag,
 input wire source_frame_start,input wire [1:0] source_frame_index,
 input wire source_top_down,udp_ready,udp_ack,
 input wire [31:0] source_resolution,
 output wire udp_request,output reg udp_valid,
 output wire [7:0] udp_data,output wire [15:0] udp_length,
 output reg frame_sent,output wire [31:0] packets_sent,
 input wire receipt_valid,input wire [31:0] receipt_token,
 input wire [15:0] receipt_sequence,
 output wire [31:0] transfer_token,output wire [15:0] packet_sequence,
 input wire [31:0] frame_token
);
integer count=0,total_pixels=0,frames=0;
reg waiting=0,launched=0;
reg [31:0] token_latched=0;
assign source_ready=!waiting && udp_ready;
assign udp_request=waiting && !launched;
assign udp_data=8'h49;assign udp_length=8;assign packets_sent=frames;
assign transfer_token=token_latched;assign packet_sequence=0;
initial if(!RELIABLE || !EXTERNAL_TOKEN || !UI_TAG || !RESOLUTION)
 $fatal(1,"network transmitter feature configuration changed");
always @(posedge clk)begin
 if(rst)begin count<=0;waiting<=0;launched<=0;udp_valid<=0;frame_sent<=0;end
 else begin
  udp_valid<=0;frame_sent<=0;
  if(source_valid && source_ready)begin
   if(tb_source_routes.expected_source>=4 ||
      source_frame_index!==tb_source_routes.expected_source ||
      source_top_down!==tb_source_routes.expected_source[0] ||
      source_rgb!==tb_source_routes.rgb(tb_source_routes.expected_source,count) ||
      source_tag!==tb_source_routes.tag(tb_source_routes.expected_source,count) ||
      source_resolution!==tb_source_routes.resolution(tb_source_routes.expected_source) ||
      source_frame_start!==(count==0))
    $fatal(1,"network pixel/tag/metadata mismatch frame=%d pixel=%d",tb_source_routes.expected_source,count);
   total_pixels=total_pixels+1;
   if(count==31)begin waiting<=1;token_latched<=frame_token;end
   else count<=count+1;
  end
  if(udp_request && udp_ack)begin launched<=1;udp_valid<=1;end
  if(waiting && launched && receipt_valid && receipt_token==token_latched)begin
   waiting<=0;launched<=0;count<=0;frame_sent<=1;frames=frames+1;
  end
 end
end
endmodule
