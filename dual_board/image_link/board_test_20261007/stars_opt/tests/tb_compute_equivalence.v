`timescale 1ns/1ps
module tb_compute_equivalence;
reg clk=0,udp_clk=0,rst=1;
always #20 clk=~clk;always #4 udp_clk=~udp_clk;
reg [31:0] session=1,file_samples=10043560,pcm=0,head=0,feedback_session=1;
reg source_valid=0,feedback_valid=0,enabled=1;
reg [3:0] volume=8;
wire ready_new,ready_old,settled_new,settled_old;
wire [31:0] analysed_new,analysed_old;
wire [263:0] visual_new,visual_old;
remote_audio_compute dut(udp_clk,clk,rst,session,file_samples,source_valid,pcm,ready_new,
 feedback_valid,feedback_session,head,volume,enabled,visual_new,analysed_new,settled_new);
remote_audio_compute_reference ref_dut(udp_clk,clk,rst,session,file_samples,source_valid,pcm,ready_old,
 feedback_valid,feedback_session,head,volume,enabled,visual_old,analysed_old,settled_old);
integer accepted=0,steps=0,checked=0,samples=0,epoch;
reg [31:0] base=0,rng=32'hced731ac;
reg previous_gray_valid=0;
reg [10:0] previous_gray;
function [31:0] sample_word;
 input integer n;reg signed [15:0] l,r;
 begin l=((n*773)%60000)-30000;r=((n*379)%54000)-27000;sample_word={r,l};end
endfunction
always @(posedge udp_clk)begin
 if(rst)accepted=0;
 else if(source_valid&&ready_new)accepted=accepted+1;
 #2;
 if(!rst)begin
  if(ready_new!==ready_old)$fatal(1,"history ready mismatch count=%d/%d",dut.written,dut.analysed);
  if(dut.analysed_local!==ref_dut.analysed_local[10:0])$fatal(1,"consumed CDC modulo mismatch");
  if((dut.written-dut.analysed)>896)$fatal(1,"history reserve violated");
  if(previous_gray_valid && source_valid && ready_new &&
     $countones(previous_gray^dut.written_gray)>1)$fatal(1,"Gray pointer multi-bit transition");
  previous_gray=dut.written_gray;previous_gray_valid=1;
 end else previous_gray_valid=0;
end
always @(posedge clk)begin
 #2;
 if(!rst&&!dut.compute_reset)begin
  checked=checked+1;
  if({analysed_new,settled_new,visual_new}!=={analysed_old,settled_old,visual_old})
   $fatal(1,"full compute equivalence failed progress=%h/%h",analysed_new,analysed_old);
  if(dut.written_local!==ref_dut.written_local[10:0])$fatal(1,"written CDC modulo mismatch");
  if(dut.sample_valid)samples=samples+1;
 end
end
task seed_wrap;
 begin
  dut.written=base;ref_dut.written=base;dut.analysed=base;ref_dut.analysed=base;
  dut.written_gray=(base[10:0]>>1)^base[10:0];dut.analysed_gray=dut.written_gray;
  ref_dut.written_gray=(base>>1)^base;ref_dut.analysed_gray=ref_dut.written_gray;
  dut.written_g0=dut.written_gray;dut.written_g1=dut.written_gray;
  ref_dut.written_g0=ref_dut.written_gray;ref_dut.written_g1=ref_dut.written_gray;
  dut.analysed_g0=dut.analysed_gray;dut.analysed_g1=dut.analysed_gray;
  ref_dut.analysed_g0=ref_dut.analysed_gray;ref_dut.analysed_g1=ref_dut.analysed_gray;
  dut.controls_udp={base,4'd8,1'b1};ref_dut.controls_udp=dut.controls_udp;
  dut.u_controls_cdc.mailbox=dut.controls_udp;ref_dut.u_controls_cdc.mailbox=dut.controls_udp;
  dut.u_controls_cdc.frame_state=dut.controls_udp;ref_dut.u_controls_cdc.frame_state=dut.controls_udp;
 end
endtask
integer wanted;
initial begin
 for(epoch=0;epoch<2;epoch=epoch+1)begin
  rst=1;source_valid=0;feedback_valid=0;repeat(20)@(negedge udp_clk);
  base=epoch==0?0:32'hfffffc00;session=epoch+1;feedback_session=session;head=base;volume=8;enabled=1;
  rst=0;repeat(30)@(negedge clk);
  if(epoch!=0)begin seed_wrap;repeat(40)@(negedge clk);end
  wanted=epoch==0?10000:2200;steps=0;
  while(accepted<wanted)begin
   @(negedge udp_clk);rng={rng[30:0],rng[31]^rng[21]^rng[1]^rng[0]};steps=steps+1;
   source_valid=ready_new && rng[2:0]!=0;pcm=sample_word(accepted);
   feedback_valid=steps%137==0;
   if(feedback_valid)begin
    // Include stale, impossible future and wrong-session reports amid valid latest heads.
    feedback_session=(rng[5:3]==0)?session+1:session;
    head=(rng[8:6]==0)?base+accepted+1:((rng[8:6]==1)?base:base+accepted);
    volume=rng[12:9]%9;enabled=steps%997!=0;
   end
  end
  @(negedge udp_clk);source_valid=0;head=base+accepted;feedback_session=session;feedback_valid=1;
  @(negedge udp_clk);feedback_valid=0;
  wait(analysed_new==base+wanted);wait(settled_new);repeat(25)@(negedge clk);
 end
 if(samples<12200||checked<100000)$fatal(1,"insufficient equivalence coverage");
 $display("PASS compute equivalence: %0d exact compute clocks, %0d samples, 11-bit CDC/ring and32-bit playback wraps, random stalls/feedback/gain/session, occupancy<=896",checked,samples);
 $finish;
end
initial begin #180000000;$fatal(1,"compute equivalence timeout");end
endmodule
