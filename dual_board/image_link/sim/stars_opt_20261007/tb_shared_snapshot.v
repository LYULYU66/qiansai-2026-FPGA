`timescale 1ns/1ps
module shared_snapshot_case #(parameter PERIOD=3)(output reg done=0);
reg src_clk=0,clk=0,rst=1;
always #20 src_clk=~src_clk;always #4 clk=~clk;
reg [31:0] generation=0;
reg [295:0] state_src=0;
wire [295:0] snapshot;
wire capture,hold;
reg have=0,ready=0,ack=0;
wire req,valid;wire [7:0] data;wire [15:0] length;
audio_visual_cdc #(.WIDTH(296),.FRAME_BOUNDARY(0),.DESTINATION_HOLD(1)) cdc(
 .udp_clk(src_clk),.video_clk(clk),.rst(rst),.frame_vs(1'b0),.update_valid(1'b0),
 .publish_enable(1'b1),.hold_capture(hold),.visual_state(state_src),.frame_state(snapshot),.capture_valid(capture));
audio_visual_tx #(.UPDATE_CYCLES(PERIOD),.SHARED_SNAPSHOT(1)) tx(
 .clk(clk),.rst(rst),.source_settled(have),.session_id(32'd1),.analysed_words(snapshot[295:264]),
 .visual_state(snapshot[263:0]),.udp_ready(ready),.udp_ack(ack),.snapshot_hold(hold),
 .udp_request(req),.udp_valid(valid),.udp_data(data),.udp_length(length));
integer i,cycles=0,packets=0,index=0;
reg [295:0] frozen;
reg [15:0] crc;
reg [7:0] expected;
reg [31:0] last_tag=0;
function [15:0] ref_crc;
 input [15:0] old;input [7:0] value;integer b;reg [15:0] c;
 begin c=old;for(b=7;b>=0;b=b-1)begin
  if(c[15]^value[b])c=(c<<1)^16'h1021;else c=c<<1;
 end ref_crc=c;end
endfunction
always @(negedge src_clk)if(!rst)begin
 generation=generation+1;state_src[295:264]=generation;
 for(i=0;i<33;i=i+1)state_src[i*8+:8]=(generation*17+i*23)&255;
end
always @(posedge clk)begin
 if(rst)begin have<=0;ack<=0;cycles=0;index=0;end
 else begin
  cycles=cycles+1;ready<=cycles%91<70;
  ack<=req && ready && cycles%7==0;
  if(capture)have<=1;
  if(tx.state==4)frozen=snapshot;
  if(valid)begin
   if(length!=47||!hold||snapshot!==frozen)$fatal(1,"shared snapshot not frozen");
   case(index)
    0:begin expected="V";crc=16'hffff;end
    1:expected="I";2:expected="Z";3:expected="2";
    4:expected=1;5,6,7:expected=0;
    8:expected=frozen[271:264];9:expected=frozen[279:272];
    10:expected=frozen[287:280];11:expected=frozen[295:288];
    45:expected=crc[15:8];46:expected=crc[7:0];
    default:expected=frozen[(index-12)*8+:8];
   endcase
   if(data!==expected)$fatal(1,"shared byte/CRC mismatch index=%0d got=%h expected=%h",index,data,expected);
   if(index<45)crc=ref_crc(crc,data);
   if(index==46)begin
    if(frozen[295:264]<last_tag)$fatal(1,"stale tag");last_tag=frozen[295:264];packets=packets+1;index=0;
   end else index=index+1;
  end
 end
end
initial begin
 repeat(10)@(negedge clk);rst=0;
 wait(packets>=80);@(negedge clk);rst=1;have=0;generation=0;state_src=0;last_tag=0;
 repeat(10)@(negedge clk);rst=0;
 wait(packets>=160);
 if(last_tag<100)$fatal(1,"latest snapshot stalled");
 $display("PASS shared snapshot PERIOD=%0d:160 exact VIZ2 packets, header/payload/CRC atomic during source updates, busy holds, short-period release and reset",PERIOD);
 done=1;
end
initial begin #3000000;$fatal(1,"shared snapshot timeout");end
endmodule
module tb_shared_snapshot;
wire a,b,c;
shared_snapshot_case #(.PERIOD(1)) one(a);
shared_snapshot_case #(.PERIOD(3)) three(b);
shared_snapshot_case #(.PERIOD(97)) normal(c);
initial begin wait(a&&b&&c);$finish;end
endmodule
