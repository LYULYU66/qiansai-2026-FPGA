`timescale 1ns/1ps
module receipt_equiv_case #(parameter EXTENDED=0)(output reg done=0);
reg clk=0,rst=1,rx_valid=0;
always #4 clk=~clk;
reg [7:0] rx_data=0, packet[0:95];
reg [15:0] rx_length=0;
wire v0,v1,a0,a1;
wire [31:0] s0,s1,p0,p1;
wire [15:0] q0,q1;
wire [3:0] vol0,vol1;
audio_receipt_rx #(.EXTENDED(EXTENDED)) candidate(clk,rst,rx_valid,rx_data,rx_length,v0,s0,p0,q0,vol0,a0);
audio_receipt_rx_golden_r6 #(.EXTENDED(EXTENDED)) golden(clk,rst,rx_valid,rx_data,rx_length,v1,s1,p1,q1,vol1,a1);
integer cycles=0,accepted=0,rejected=0,seed=32'h731654+EXTENDED;
integer n,i,mode,size,total,gap,rnd,before_count;
reg [15:0] crc;
function [15:0] crc_step;
 input [15:0] prior;input [7:0] byte_value;
 reg [15:0] value;integer k;
 begin
  value=prior;
  for(k=7;k>=0;k=k-1) begin
   if(value[15]^byte_value[k]) value={value[14:0],1'b0}^16'h1021;
   else value={value[14:0],1'b0};
  end
  crc_step=value;
 end
endfunction
always @(posedge clk) begin
 #1; cycles=cycles+1;
 if({v0,s0,p0,q0,vol0,a0} !== {v1,s1,p1,q1,vol1,a1}) begin
  $display("FAIL receipt equivalence ext=%0d cycle=%0d packet=%0d mode=%0d count=%0d",EXTENDED,cycles,n,mode,candidate.count);
  $fatal(1,"AAK output or valid-cycle mismatch");
 end
 if(v0)accepted=accepted+1;
end
task pulse_reset;
 begin rst=1;#1;rst=0;end
endtask
initial begin
 total=EXTENDED ? 18 : 16;
 repeat(3)@(negedge clk);rst=0;
 for(n=0;n<1200;n=n+1) begin
  mode=n%20;size=total;rx_length=total;
  for(i=0;i<96;i=i+1)begin rnd=$random(seed);packet[i]=rnd;end
  packet[0]="A";packet[1]="A";packet[2]="K";packet[3]=EXTENDED ? "3" : "2";
  if(EXTENDED)begin packet[14]=(n%9)|((n&1)<<4);packet[15]=0;end
  // Header, controls and CRC failures include all packet boundaries.
  case(mode)
   1:packet[0]="X";
   2:packet[2]="J";
   3:rx_length=total+1;
   6:size=total-1;
   7:size=total+1;
   8:size=65;
   9:if(EXTENDED)packet[14]=8'h88;else packet[1]=0;
   10:if(EXTENDED)packet[14]=9;else packet[3]="3";
   11:if(EXTENDED)packet[15]=1;else size=1;
   12:packet[3]=EXTENDED ? "2" : "3";
   13:begin size=2+n%30;packet[0]=0;end
   18:size=2*total;
  endcase
  crc=16'hffff;
  for(i=0;i<total-2;i=i+1)crc=crc_step(crc,packet[i]);
  packet[total-2]=crc[15:8];packet[total-1]=crc[7:0];
  if(mode==4)packet[total-2]=packet[total-2]^8'h01;
  if(mode==5)packet[total-1]=packet[total-1]^8'h80;
  before_count=accepted;
  for(i=0;i<size;i=i+1)begin
   @(negedge clk);rx_valid=1;rx_data=packet[i];
   // Only the first length sample is meaningful in the original protocol.
   if(mode==19 && i!=0)rx_length=i;
   if(mode==14 && i==total/2)begin
    rx_valid=0;@(negedge clk);rx_valid=1;
   end
   if(mode==15 && i==total/2)begin #1;pulse_reset;end
   if(mode==16 && i==total-1)begin #1;pulse_reset;end
  end
  @(negedge clk);rx_valid=0;
  if(mode==17)begin #1;pulse_reset;end
  gap=1+n%4;repeat(gap)@(negedge clk);
  if(mode==0 || mode==19)begin
   if(accepted!=before_count+1)$fatal(1,"Valid packet not accepted once");
  end else begin
   if(accepted!=before_count)$fatal(1,"Malformed/reset packet was accepted");
   rejected=rejected+1;
  end
 end
 repeat(3)@(negedge clk);
 if(accepted<100 || rejected<1000)$fatal(1,"Insufficient acceptance/rejection coverage");
 $display("PASS receipt pipeline equivalence ext=%0d cycles=%0d accepted=%0d rejected=%0d",EXTENDED,cycles,accepted,rejected);
 done=1;
end
endmodule
module tb_audio_receipt_pipeline_equiv;
wire done0,done1;
receipt_equiv_case #(.EXTENDED(0)) case0(done0);
receipt_equiv_case #(.EXTENDED(1)) case1(done1);
initial begin wait(done0 && done1);$display("PASS AAK2/AAK3 pipeline: exact output cycles, CRC, invalid lengths, controls, gaps and resets");$finish;end
initial begin #2000000;$fatal(1,"Receipt equivalence timeout");end
endmodule
