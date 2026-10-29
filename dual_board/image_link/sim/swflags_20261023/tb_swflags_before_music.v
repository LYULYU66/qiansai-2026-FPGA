`timescale 1ns/1ps
// 20261023: B SW2 must reach A before SW1 has ever started a song.
// B's TX (B build file) -> A's CRC-only flags receiver and A's visual receiver.
// The visual receiver is held in reset while A has no PCM stream, as on A.
module tb_swflags_before_music;
reg clk=0,rst=1; always #8 clk=~clk;
reg settled=0, music=0, photo=0, pcm_reset=1, corrupt=0;
reg [29:0] words=0; reg [31:0] played=0;
reg [263:0] state=264'h1234;
wire req,valid; wire [7:0] data; wire [15:0] len;
reg ack=0;
audio_visual_tx #(.UPDATE_CYCLES(200)) tx(.clk(clk),.rst(rst),.source_settled(settled),
  .session_id(32'h55),.analysed_words({music,photo,words}),.visual_state(state),
  .udp_ready(1'b1),.udp_ack(ack),.udp_request(req),.udp_valid(valid),.udp_data(data),.udp_length(len));
always @(posedge clk) ack<=req && !ack;
// One bit flipped in a payload byte when corrupt=1.
reg [5:0] byte_no; always @(posedge clk) byte_no<= valid ? byte_no+1'b1 : 0;
wire [7:0] rx_byte=data ^ {7'd0,corrupt && byte_no==20};
wire fvalid,fm,fp;
audio_visual_flags_rx flags(.clk(clk),.rst(rst),.rx_valid(valid),.rx_data(rx_byte),.rx_length(len),
  .flags_valid(fvalid),.music_state(fm),.photo_state(fp));
wire upd; wire [263:0] vstate;
audio_visual_rx_a vis(.clk(clk),.rst(rst || pcm_reset),.rx_valid(valid),.rx_data(rx_byte),.rx_length(len),
  .session_id(32'h55),.played_words(played),.update_valid(upd),.visual_state(vstate),
  .music_state(),.photo_state());
integer f_acc=0, v_acc=0, errors=0;
always @(posedge clk) begin
  if(fvalid) f_acc=f_acc+1;
  if(upd) begin v_acc=v_acc+1; if(vstate!==state) begin errors=errors+1; $display("FAIL visual state"); end end
end
task check(input want_f, input want_m, input want_p, input want_v, input [8*40-1:0] what);
  integer fa, va; begin repeat(300) @(posedge clk); fa=f_acc; va=v_acc; repeat(500) @(posedge clk);
    if((f_acc!=fa)!==want_f || (want_f && (fm!==want_m || fp!==want_p)) || (v_acc!=va)!==want_v) begin
      errors=errors+1; $display("FAIL %0s flags=%0d m=%b p=%b visual=%0d",what,f_acc-fa,fm,fp,v_acc-va); end
    else $display("ok   %0s flags=%0d m=%b p=%b visual=%0d",what,f_acc-fa,fm,fp,v_acc-va); end endtask
initial begin
  repeat(4) @(posedge clk); rst=0;
  // Power-up: no snapshot on B, no PCM stream on A (visual RX in reset).
  check(1,0,0,0,"power-up, SW1=0 SW2=0 (VIZF)");
  photo=1; check(1,0,1,0,"SW2 on before SW1 ever on");
  photo=0; check(1,0,0,0,"SW2 off again");
  photo=1; music=1; check(1,1,1,0,"SW1 on, song not streaming yet");
  // Song streams: A has the session, B's snapshot settles -> VIZ2.
  pcm_reset=0; settled=1; words=100; played=200; check(1,1,1,1,"streaming: VIZ2 visual + flags");
  music=0; photo=0; check(1,0,0,1,"paused, SW2 off (VIZ2)");
  // Song change: B snapshot reset, A stream reset -> back to VIZF only.
  settled=0; pcm_reset=1; photo=1; check(1,0,1,0,"between songs, SW2 on (VIZF)");
  // VIZF must never load A's visual state even when A has a session.
  pcm_reset=0; check(1,0,1,0,"VIZF with A streaming: no visual");
  corrupt=1; photo=0; check(0,0,1,0,"bad CRC: flags held");
  corrupt=0; check(1,0,0,0,"good CRC again");
  if(errors==0) $display("PASS tb_swflags_before_music"); else $display("FAIL tb_swflags_before_music %0d",errors);
  $finish;
end
endmodule
