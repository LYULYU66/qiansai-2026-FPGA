`timescale 1ns/1ps
// Cycle-equivalent application interface against frozen original RTL, not a
// relaxed packet-only comparison. Independent CRC checks and asynchronous
// resets exercise both sides of the new BRAM/held-pixel boundary.
module tb_image_tx_pipeline_equiv;
reg clk=0;always #4 clk=~clk;
wire [5:0] done;
image_tx_pipeline_pair #(.ID(0),.REL(0),.TAG(0),.RES(0),.EXT(0)) p0(clk,done[0]);
image_tx_pipeline_pair #(.ID(1),.REL(1),.TAG(0),.RES(0),.EXT(1)) p1(clk,done[1]);
image_tx_pipeline_pair #(.ID(2),.REL(1),.TAG(1),.RES(0),.EXT(0)) p2(clk,done[2]);
image_tx_pipeline_pair #(.ID(3),.REL(1),.TAG(1),.RES(1),.EXT(1)) p3(clk,done[3]);
image_tx_pipeline_pair #(.ID(4),.REL(1),.TAG(1),.RES(1),.EXT(0)) p4(clk,done[4]);
image_tx_pipeline_pair #(.ID(5),.REL(1),.TAG(0),.RES(1),.EXT(1)) p5(clk,done[5]);
initial begin
 wait(&done);
 $display("PASS image TX pipeline equivalence: 6 parameter sets, exact valid/data/request/ready cycles, independent CRC, lost/wrong ACK retries, header/prefetch/CRC resets and consecutive frames");
 $finish;
end
initial begin #10000000;$fatal(1,"image TX pipeline equivalence timeout");end
endmodule

module image_tx_pipeline_pair #(parameter ID=0,REL=0,TAG=0,RES=0,EXT=0)(input clk,output reg done=0);
localparam FP=4,WORDS=FP*256,FRAMES=3;
localparam HEADER=RES?16:(REL?12:8),CRC_OFFSET=HEADER+(TAG?1024:768);
localparam LAST_PHASE=TAG?3:2;
reg rst=1,udp_ack=0,receipt_valid=0;
reg [31:0] receipt_token=0;
reg [15:0] receipt_sequence=0;
reg [31:0] rng=32'h98764321+ID;
integer source_words=0,completed=0,cycles=0,total_frames=0,total_packets=0;
integer byte_count=0,pending=0,compared=0,retries=0;
reg previous_valid=0,dropped=0,matching=0;
reg [31:0] pending_token=0;
reg [15:0] pending_sequence=0,crc=16'hffff;
reg [7:0] crc_hi=0;
wire source_valid=!rst && !done && source_words<WORDS*FRAMES && rng[2:0]!=0;
wire [31:0] frame_number=source_words/WORDS;
wire [23:0] source_rgb={source_words[7:0]^8'ha5,source_words[15:8]^8'h3c,source_words[7:0]+8'd19};
wire [7:0] source_tag=source_words[7:0]^source_words[15:8]^ID;
wire [31:0] resolution=frame_number[0]?32'h07800438:32'h050003c0;
wire [31:0] frame_token=32'hfffcfffe+frame_number;
wire net_ready=rng[6:4]!=0;
wire source_ready,request,valid,frame_sent;
wire [7:0]data;
wire [15:0]length,packets,sequence_no;
wire [31:0]token;
wire old_source_ready,old_request,old_valid,old_frame_sent;
wire [7:0]old_data;
wire [15:0]old_length,old_packets,old_sequence;
wire [31:0]old_token;
image_packet_tx #(.FRAME_PACKETS(FP),.INTER_PACKET_CYCLES(7),.RELIABLE(REL),
 .RETRY_CYCLES(120),.EXTERNAL_TOKEN(EXT),.UI_TAG(TAG),.RESOLUTION(RES)) dut(
 .clk(clk),.rst(rst),.source_valid(source_valid),.source_ready(source_ready),
 .source_rgb(source_rgb),.source_tag(source_tag),.source_frame_start(source_words%WORDS==0),
 .source_frame_index(frame_number[1:0]),.source_top_down(frame_number[0]),.source_resolution(resolution),
 .udp_ready(net_ready),.udp_ack(udp_ack),.udp_request(request),.udp_valid(valid),.udp_data(data),.udp_length(length),
 .frame_sent(frame_sent),.packets_sent(packets),.receipt_valid(receipt_valid),.receipt_token(receipt_token),
 .receipt_sequence(receipt_sequence),.transfer_token(token),.packet_sequence(sequence_no),.frame_token(frame_token));
image_packet_tx_golden_r5 #(.FRAME_PACKETS(FP),.INTER_PACKET_CYCLES(7),.RELIABLE(REL),
 .RETRY_CYCLES(120),.EXTERNAL_TOKEN(EXT),.UI_TAG(TAG),.RESOLUTION(RES)) golden(
 .clk(clk),.rst(rst),.source_valid(source_valid),.source_ready(old_source_ready),
 .source_rgb(source_rgb),.source_tag(source_tag),.source_frame_start(source_words%WORDS==0),
 .source_frame_index(frame_number[1:0]),.source_top_down(frame_number[0]),.source_resolution(resolution),
 .udp_ready(net_ready),.udp_ack(udp_ack),.udp_request(old_request),.udp_valid(old_valid),.udp_data(old_data),.udp_length(old_length),
 .frame_sent(old_frame_sent),.packets_sent(old_packets),.receipt_valid(receipt_valid),.receipt_token(receipt_token),
 .receipt_sequence(receipt_sequence),.transfer_token(old_token),.packet_sequence(old_sequence),.frame_token(frame_token));
function [15:0] reference_crc;
 input [15:0] initial_crc;input [7:0] value;
 reg [15:0] c;integer bit_no;
 begin
  c=initial_crc;
  for(bit_no=7;bit_no>=0;bit_no=bit_no-1)
   if(c[15]^value[bit_no])c=(c<<1)^16'h1021;else c=c<<1;
  reference_crc=c;
 end
endfunction
always @(posedge clk or posedge rst)begin
 if(rst)begin
  source_words<=0;completed<=0;cycles<=0;udp_ack<=0;receipt_valid<=0;
  previous_valid<=0;byte_count=0;pending<=0;dropped<=0;matching<=0;
  receipt_token<=0;receipt_sequence<=0;pending_token<=0;pending_sequence<=0;
  rng<=32'h98764321+ID;
 end else if(!done)begin
  if({source_ready,request,valid,frame_sent,length,packets,token,sequence_no} !==
     {old_source_ready,old_request,old_valid,old_frame_sent,old_length,old_packets,old_token,old_sequence})
   $fatal(1,"TX cycle/interface mismatch ID=%0d cycle=%0d",ID,cycles);
  compared=compared+1;cycles<=cycles+1;
  rng<={rng[30:0],rng[31]^rng[21]^rng[1]^rng[0]};
  if(source_ready && source_valid)source_words<=source_words+1;
  udp_ack<=request && rng[3:1]!=0;
  receipt_valid<=0;
  previous_valid<=valid;
  if(valid)begin
   if(data!==old_data)$fatal(1,"TX byte mismatch ID=%0d index=%0d phase=%0d got=%h expected=%h",ID,dut.byte_index,dut.byte_phase,data,old_data);
   if(!previous_valid)begin byte_count=0;crc=16'hffff;end
   if(byte_count<length-2)crc=reference_crc(crc,data);
   else if(byte_count==length-2)crc_hi=data;
   else if({crc_hi,data}!==crc)$fatal(1,"TX independent CRC mismatch ID=%0d",ID);
   byte_count=byte_count+1;
  end else if(previous_valid)begin
   if(byte_count!=length)$fatal(1,"TX packet continuity/length mismatch ID=%0d",ID);
   total_packets=total_packets+1;
   if(REL)begin
    pending<=9;pending_token<=token;pending_sequence<=sequence_no;matching<=dropped;
    if(!dropped)retries=retries+1;
    dropped<=1;
   end
  end
  if(pending!=0)begin
   pending<=pending-1;
   if(pending==2)begin
    receipt_valid<=1;receipt_token<=pending_token^(matching?32'd0:32'd1);
    receipt_sequence<=pending_sequence;
   end
  end
  if(frame_sent)begin completed<=completed+1;total_frames=total_frames+1;end
 end
end
task restart_after_abort;
 begin
  #1.3;rst=1;#0.7;rst=0;
  repeat(3)@(negedge clk);
 end
endtask
initial begin
 repeat(8+ID)@(negedge clk);rst=0;
 wait(completed==FRAMES);
 // Reset the source and both transmitters before each distinct abort point.
 restart_after_abort();
 wait(valid && dut.byte_index==HEADER-1);restart_after_abort();
 wait(valid && dut.byte_index==HEADER+LAST_PHASE);restart_after_abort();
 wait(valid && dut.byte_index==CRC_OFFSET);restart_after_abort();
 wait(completed==FRAMES);@(negedge clk);
 if(total_frames!=6 || total_packets<FP*6 || (REL && retries<2) || compared<20000)
  $fatal(1,"TX equivalence coverage incomplete ID=%0d frames=%0d packets=%0d cycles=%0d",ID,total_frames,total_packets,compared);
 $display("TX pipeline case %0d: %0d compared cycles, %0d CRC-verified packets, %0d complete frames",ID,compared,total_packets,total_frames);
 done=1;
end
endmodule
