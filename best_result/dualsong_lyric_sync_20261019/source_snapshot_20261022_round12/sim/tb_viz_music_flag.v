`timescale 1ns/1ps
// B's VIZ2 transmitter (B build file) -> A's receiver: bit 31 of the tag is
// SW1 and must not disturb the progress ordering/availability checks.
module tb_viz_music_flag;
reg clk=0,rst=1; always #8 clk=~clk;
reg [31:0] words=0; reg music=0; reg [31:0] played=0;
reg [263:0] state=264'h1234;
wire req,valid; wire [7:0] data; wire [15:0] len;
reg ack=0;
audio_visual_tx #(.UPDATE_CYCLES(200)) tx(.clk(clk),.rst(rst),.source_settled(1'b1),
  .session_id(32'h55),.analysed_words({music,words[30:0]}),.visual_state(state),
  .udp_ready(1'b1),.udp_ack(ack),.udp_request(req),.udp_valid(valid),.udp_data(data),.udp_length(len));
always @(posedge clk) ack<=req && !ack;
wire upd,mstate; wire [263:0] vstate;
audio_visual_rx_a rx(.clk(clk),.rst(rst),.rx_valid(valid),.rx_data(data),.rx_length(len),
  .session_id(32'h55),.played_words(played),.update_valid(upd),.visual_state(vstate),.music_state(mstate));
integer accepted=0, errors=0; reg last_m;
always @(posedge clk) if(upd) begin accepted=accepted+1; last_m=mstate;
  if(vstate!==state) begin errors=errors+1; $display("FAIL state"); end end
task expect_accept(input want_m, input [8*30-1:0] what);
  integer a; begin repeat(300) @(posedge clk); a=accepted; repeat(400) @(posedge clk);
    if(accepted==a || last_m!==want_m) begin errors=errors+1; $display("FAIL %0s acc=%0d m=%b",what,accepted-a,last_m); end
    else $display("ok   %0s m=%b",what,last_m); end endtask
task expect_reject(input [8*30-1:0] what);
  integer a; begin repeat(300) @(posedge clk); a=accepted; repeat(400) @(posedge clk);
    if(accepted!=a) begin errors=errors+1; $display("FAIL %0s accepted",what); end
    else $display("ok   %0s rejected",what); end endtask
initial begin
  repeat(4) @(posedge clk); rst=0;
  words=100; played=200; music=1; expect_accept(1,"play flag");
  music=0; expect_accept(0,"pause flag");
  words=300; expect_reject("tag ahead of played");
  played=300; music=1; expect_accept(1,"caught up, play");
  words=32'd9_000_000; played=32'd9_000_100; expect_accept(1,"9M-sample song tag");
  music=0; expect_accept(0,"pause late in song");
  if(errors==0) $display("PASS tb_viz_music_flag"); else $display("FAIL tb_viz_music_flag %0d",errors);
  $finish;
end
endmodule
