`timescale 1ns/1ps
// B's VIZ2 transmitter (B build file) -> A's receiver: tag bit 31 is B SW1
// (music), bit 30 is B SW2 (A photo-only).  Neither may disturb the
// progress ordering/availability checks, and they must not leak into each other.
module tb_viz_photo_flag;
reg clk=0,rst=1; always #8 clk=~clk;
reg [31:0] words=0; reg music=0, photo=0; reg [31:0] played=0;
reg [263:0] state=264'h1234;
wire req,valid; wire [7:0] data; wire [15:0] len;
reg ack=0;
audio_visual_tx #(.UPDATE_CYCLES(200)) tx(.clk(clk),.rst(rst),.source_settled(1'b1),
  .session_id(32'h55),.analysed_words({music,photo,words[29:0]}),.visual_state(state),
  .udp_ready(1'b1),.udp_ack(ack),.udp_request(req),.udp_valid(valid),.udp_data(data),.udp_length(len));
always @(posedge clk) ack<=req && !ack;
wire upd,mstate,pstate; wire [263:0] vstate;
audio_visual_rx_a rx(.clk(clk),.rst(rst),.rx_valid(valid),.rx_data(data),.rx_length(len),
  .session_id(32'h55),.played_words(played),.update_valid(upd),.visual_state(vstate),
  .music_state(mstate),.photo_state(pstate));
integer accepted=0, errors=0; reg last_m, last_p;
always @(posedge clk) if(upd) begin accepted=accepted+1; last_m=mstate; last_p=pstate;
  if(vstate!==state) begin errors=errors+1; $display("FAIL state"); end end
task expect_accept(input want_m, input want_p, input [8*30-1:0] what);
  integer a; begin repeat(300) @(posedge clk); a=accepted; repeat(400) @(posedge clk);
    if(accepted==a || last_m!==want_m || last_p!==want_p) begin errors=errors+1;
      $display("FAIL %0s acc=%0d m=%b p=%b",what,accepted-a,last_m,last_p); end
    else $display("ok   %0s m=%b p=%b",what,last_m,last_p); end endtask
task expect_reject(input [8*30-1:0] what);
  integer a; begin repeat(300) @(posedge clk); a=accepted; repeat(400) @(posedge clk);
    if(accepted!=a) begin errors=errors+1; $display("FAIL %0s accepted",what); end
    else $display("ok   %0s rejected",what); end endtask
initial begin
  repeat(4) @(posedge clk); rst=0;
  words=100; played=200; music=1; photo=0; expect_accept(1,0,"play, normal");
  photo=1; expect_accept(1,1,"play, photo-only");
  music=0; expect_accept(0,1,"pause, photo-only");
  photo=0; expect_accept(0,0,"pause, normal");
  photo=1; words=300; expect_reject("tag ahead of played");
  played=300; music=1; expect_accept(1,1,"caught up, photo");
  words=32'd15_000_000; played=32'd15_000_100; photo=0; expect_accept(1,0,"15M-word song tag");
  photo=1; music=0; expect_accept(0,1,"photo late in song");
  // A smaller tag than the last accepted one is still refused with bit 30 set.
  words=32'd14_000_000; expect_reject("tag going backwards");
  if(errors==0) $display("PASS tb_viz_photo_flag"); else $display("FAIL tb_viz_photo_flag %0d",errors);
  $finish;
end
endmodule
