`timescale 1ns/1ps
// Port-only contract test: no references to DUT state or arbitration choices.
module tb_scheduler_lock;
reg clk=0,rst=1,ack=0;
always #4 clk=~clk;
reg [4:0] req=0,v=0;
reg [39:0] data=0;
reg [79:0] lengths=0;
wire [4:0] ready,acks;
wire request,valid;
wire [7:0] out_data;
wire [15:0] out_length;
localparam LO_LEN=1042,HI_LEN=14;
media_udp_scheduler dut(.clk(clk),.rst(rst),.net_ready(1'b1),.net_ack(ack),
 .net_request(request),.net_valid(valid),.net_data(out_data),.net_length(out_length),
 .c_request(req),.c_valid(v),.c_data(data),.c_length(lengths),.c_ready(ready),.c_ack(acks));
reg [7:0] lo_bytes[0:LO_LEN-1],hi_bytes[0:HI_LEN-1];
integer lo_pos=0,hi_pos=0,active=-1,received=0,finished=0,acks_seen=0,i;
reg [15:0] crc;
function [15:0] crc_byte(input [15:0] old_crc,input [7:0] b);
 reg [15:0] c;integer bitno;
 begin c=old_crc;for(bitno=7;bitno>=0;bitno=bitno-1)
 c=(c<<1)^((c[15]^b[bitno])?16'h1021:16'd0);crc_byte=c;end
endfunction
always @(posedge clk)if(!rst)begin
 if(acks!=0)begin
  if(active!=-1)$fatal(1,"ACK while previous packet active");
  if(acks_seen==0 && acks!==5'b00001)$fatal(1,"late priority stole low-channel ACK");
  if(acks_seen==1 && acks!==5'b10000)$fatal(1,"pending high channel lost");
  if(acks_seen>1)$fatal(1,"duplicate/spurious ACK");
  active=acks_seen;acks_seen=acks_seen+1;received=0;
 end
 if(acks[0])begin req[0]<=0;v[0]<=1;lo_pos<=0;data[7:0]<=lo_bytes[0];end
 else if(v[0])begin
  if(lo_pos==LO_LEN-1)v[0]<=0;
  else begin lo_pos<=lo_pos+1;data[7:0]<=lo_bytes[lo_pos+1];end
 end
 if(acks[4])begin req[4]<=0;v[4]<=1;hi_pos<=0;data[39:32]<=hi_bytes[0];end
 else if(v[4])begin
  if(hi_pos==HI_LEN-1)v[4]<=0;
  else begin hi_pos<=hi_pos+1;data[39:32]<=hi_bytes[hi_pos+1];end
 end
 if(valid)begin
  if(active<0)$fatal(1,"byte without accepted packet");
  if(out_length!==(active==0?16'd1042:16'd14))$fatal(1,"declared length changed");
  if(out_data!==(active==0?lo_bytes[received]:hi_bytes[received]))
   $fatal(1,"packet content changed active=%0d byte=%0d",active,received);
  received=received+1;
  if(received==(active==0?LO_LEN:HI_LEN))begin finished=finished+1;active=-1;end
 end
end
initial begin
 crc=16'hffff;
 for(i=0;i<LO_LEN-2;i=i+1)begin lo_bytes[i]=(i*17+3)&255;crc=crc_byte(crc,lo_bytes[i]);end
 lo_bytes[LO_LEN-2]=crc[15:8];lo_bytes[LO_LEN-1]=crc[7:0];
 crc=16'hffff;
 for(i=0;i<HI_LEN-2;i=i+1)begin hi_bytes[i]=(i*23+7)&255;crc=crc_byte(crc,hi_bytes[i]);end
 hi_bytes[HI_LEN-2]=crc[15:8];hi_bytes[HI_LEN-1]=crc[7:0];
 repeat(5)@(negedge clk);rst=0;lengths[15:0]=LO_LEN;req[0]=1;
 wait(request);@(negedge clk);
 // The externally observed request establishes the frozen packet contract.
 if(out_length!=LO_LEN)$fatal(1,"wrong initial request length");
 req[4]=1;lengths[79:64]=HI_LEN;
 for(i=0;i<20;i=i+1)begin
  // Even withdrawing/changing the selected producer's metadata must not
  // replace an already published request. Reassert before ACK to stream it.
  req[0]=i[0];lengths[15:0]=i[0]?16'd0:16'hffff;
  data[39:32]=i*13;
  @(negedge clk);
  if(request!==1'b1 || out_length!==16'd1042 || acks!==0 || valid!==0)
   $fatal(1,"waiting request/length not stable, or premature ACK/data");
 end
 req[0]=1;ack=1;@(negedge clk);ack=0;
 wait(finished==1);wait(request);@(negedge clk);
 if(out_length!=HI_LEN)$fatal(1,"high-priority pending packet not selected next");
 repeat(5)@(negedge clk);
 ack=1;@(negedge clk);ack=0;
 wait(finished==2);repeat(20)@(negedge clk);
 if(request || valid || acks_seen!=2)$fatal(1,"packet tail did not drain");
 $display("PASS scheduler locked request: port-only delayed ACK, late high priority, withdrawn request, changing lengths, exact 1042+14 byte payloads and CRC");
 $finish;
end
initial begin #100000;$fatal(1,"locked-request timeout");end
endmodule
