`timescale 1ns/1ps
// B SW1 turn-on jumps A to page 2 exactly once; keys keep working; a held
// switch (e.g. across song changes) never re-jumps; a warning defers the jump.
module tb_music_page_jump;
reg clk=0,rst=1,key_next=1,key_auto=1,warn=0,music=0;
reg [3:0] cache=4'b1111;
wire valid,wready; wire [1:0] page;
always #5 clk=~clk;
image_remote_display_control #(.CLK_FREQ(1000)) dut(.clk(clk),.rst(rst),.key_next(key_next),
  .key_auto(key_auto),.warning_hold(warn),.music_on(music),.cache_valid_async(cache),
  .display_valid(valid),.warning_ready(wready),.requested_index(page));
integer errors=0;
task check(input [1:0] want, input [8*40-1:0] what);
  begin if(page!==want) begin errors=errors+1; $display("FAIL %0s: page=%0d want %0d",what,page,want); end
        else $display("ok   %0s: page=%0d",what,page); end
endtask
task press; begin key_next=0; repeat(60) @(posedge clk); key_next=1; repeat(60) @(posedge clk); end endtask
initial begin
  repeat(5) @(posedge clk); rst=0; repeat(10) @(posedge clk);
  check(0,"power-up home");
  music=1; repeat(10) @(posedge clk); check(1,"switch on -> music page");
  press; check(2,"KEY3 still changes page");
  press; check(3,"KEY3 again");
  repeat(200) @(posedge clk); check(3,"held switch does not re-jump");
  music=0; repeat(10) @(posedge clk); check(3,"switch off keeps page");
  press; check(0,"KEY3 wraps to home");
  music=1; repeat(10) @(posedge clk); check(1,"second turn-on jumps again");
  music=0; press; press; check(3,"paused, page 4");
  warn=1; music=1; repeat(20) @(posedge clk); check(3,"warning defers jump");
  warn=0; repeat(10) @(posedge clk); check(1,"jump after warning clears");
  music=0; press; check(2,"page 3");
  cache=4'b1101; repeat(5) @(posedge clk); music=1; repeat(20) @(posedge clk); check(2,"page 2 not cached: wait");
  cache=4'b1111; repeat(10) @(posedge clk); check(1,"jump once page 2 cached");
  music=0; repeat(3) @(posedge clk); music=1; repeat(1) @(posedge clk); music=0; repeat(10) @(posedge clk);
  press; check(2,"glitch then off: no late jump");
  if(errors==0) $display("PASS tb_music_page_jump"); else $display("FAIL tb_music_page_jump errors=%0d",errors);
  $finish;
end
endmodule
