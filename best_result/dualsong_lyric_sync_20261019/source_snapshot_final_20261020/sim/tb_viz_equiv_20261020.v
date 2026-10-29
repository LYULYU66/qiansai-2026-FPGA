`timescale 1ns/1ps
module tb_viz_tx_equiv;
reg clk=0,rst=1; always #4 clk=~clk;
reg settled=0, ready=0, ack=0; reg [31:0] sess=32'h55660002, words=0; reg [263:0] st=0;
wire rq_n,rq_o,v_n,v_o; wire [7:0] d_n,d_o; wire [15:0] l_n,l_o;
audio_visual_tx #(.UPDATE_CYCLES(60)) dut(.clk(clk),.rst(rst),.source_settled(settled),.session_id(sess),.analysed_words(words),
 .visual_state(st),.udp_ready(ready),.udp_ack(ack),.udp_request(rq_n),.udp_valid(v_n),.udp_data(d_n),.udp_length(l_n));
audio_visual_tx_ref #(.UPDATE_CYCLES(60)) golden(.clk(clk),.rst(rst),.source_settled(settled),.session_id(sess),.analysed_words(words),
 .visual_state(st),.udp_ready(ready),.udp_ack(ack),.udp_request(rq_o),.udp_valid(v_o),.udp_data(d_o),.udp_length(l_o));
integer bytes=0,n;
always @(posedge clk) if(!rst) begin
  if({rq_n,v_n,l_n}!=={rq_o,v_o,l_o}) $fatal(1,"control mismatch");
  if(v_n && d_n!==d_o) $fatal(1,"byte %0d %h/%h",bytes,d_n,d_o);
  if(v_n) bytes=bytes+1;
end
initial begin
  repeat(5)@(negedge clk); rst=0; settled=1;
  for(n=0;n<8;n=n+1) begin
    st={$random,$random,$random,$random,$random,$random,$random,$random,$random}; words=words+97;
    ready=1; wait(rq_n); @(negedge clk); ack=1; @(negedge clk); ack=0; ready=0;
    wait(!v_n && dut.state==0); repeat(2)@(negedge clk);
  end
  $display("PASS visual TX equivalence: 8 packets, %0d bytes identical",bytes); $finish;
end
initial begin #2000000; $fatal(1,"viz equiv timeout"); end
endmodule
