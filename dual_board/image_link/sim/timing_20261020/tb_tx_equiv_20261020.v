`timescale 1ns/1ps
// Byte-exact equivalence of a pipelined packet TX against its previous RTL.
// Both instances see identical inputs; the transmitted byte streams (the
// bytes presented while udp_valid is high) must match one for one.
module tb_audio_tx_equiv;
reg clk=0,rst=1; always #4 clk=~clk;
reg [31:0] session=32'h12340001, samples=32'd10043560, pcm=0;
reg src_valid=0, ready=0, ack=0, rv=0;
reg [31:0] rsess=0; reg [15:0] rseq=0;
wire sr_n,sr_o,req_n,req_o,val_n,val_o; wire [7:0] d_n,d_o; wire [15:0] l_n,l_o,seq_n,seq_o;
audio_packet_tx #(.RETRY_CYCLES(900)) dut(.clk(clk),.rst(rst),.session_id(session),.file_samples(samples),
 .source_valid(src_valid),.source_pcm(pcm),.source_ready(sr_n),.udp_ready(ready),.udp_ack(ack),
 .udp_request(req_n),.udp_valid(val_n),.udp_data(d_n),.udp_length(l_n),.receipt_valid(rv),
 .receipt_session(rsess),.receipt_sequence(rseq),.sequence_no(seq_n));
audio_packet_tx_ref #(.RETRY_CYCLES(900)) golden(.clk(clk),.rst(rst),.session_id(session),.file_samples(samples),
 .source_valid(src_valid),.source_pcm(pcm),.source_ready(sr_o),.udp_ready(ready),.udp_ack(ack),
 .udp_request(req_o),.udp_valid(val_o),.udp_data(d_o),.udp_length(l_o),.receipt_valid(rv),
 .receipt_session(rsess),.receipt_sequence(rseq),.sequence_no(seq_o));
integer bytes=0, packets=0, n, k;
always @(posedge clk) if(!rst) begin
  if({sr_n,req_n,val_n,l_n,seq_n}!=={sr_o,req_o,val_o,l_o,seq_o}) $fatal(1,"control mismatch t=%0t",$time);
  if(val_n && d_n!==d_o) $fatal(1,"byte %0d mismatch %h/%h",bytes,d_n,d_o);
  if(val_n) bytes=bytes+1;
end
initial begin
  repeat(5)@(negedge clk); rst=0;
  for(n=0;n<6;n=n+1) begin
    for(k=0;k<128;k=k+1) begin
      wait(sr_n); @(negedge clk); pcm=$random; src_valid=1; @(negedge clk); src_valid=0;
    end
    @(negedge clk); ready=1; wait(req_n); @(negedge clk); ack=1; @(negedge clk); ack=0; ready=0;
    wait(!val_n && dut.state==5); repeat(3)@(negedge clk);
    if(n==2) begin repeat(1000)@(negedge clk); ready=1; wait(req_n); @(negedge clk); ack=1; @(negedge clk); ack=0; ready=0; wait(dut.state==5); end
    wait(dut.state==5); @(negedge clk);
    rsess=session; rseq=seq_n; rv=1; wait(dut.state!=5); @(negedge clk); rv=0; packets=packets+1;
    if(n==3) session=session+1;
  end
  $display("PASS audio TX equivalence: %0d packets incl. retransmit, %0d bytes identical",packets,bytes);
  $finish;
end
initial begin #3000000; $fatal(1,"equiv timeout n=%0d state=%0d/%0d bytes=%0d",n,dut.state,golden.state,bytes); end
endmodule
