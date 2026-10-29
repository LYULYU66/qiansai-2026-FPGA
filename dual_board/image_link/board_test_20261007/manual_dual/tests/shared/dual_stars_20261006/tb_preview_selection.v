`timescale 1ns/1ps
// Selection-only regression. The unchanged native FIFO/SDRAM/video pipeline
// already passed full-frame tests in the now hardware-confirmed image #2 build.
module tb_preview_selection;
reg clk=0;always #4 clk=~clk;
reg rst=1,start=0,abort=0,top=1,valid=0,ack=0,credit=0,done=0;
reg viewed_valid=0,viewed_index=0;
reg [1:0] index=0;
wire ready,req,we,slot,write_top,committed_valid,committed_index;
wire [31:0] word;
integer i,accepted=0;
b_image_capture #(.FRAME_PIXELS(16),.PREVIEW_INDEX(2'd2)) dut(
 .clk(clk),.rst(rst),.source_start(start),.source_abort(abort),
 .source_top_down(top),.source_index(index),.pixel_valid(valid),.pixel_rgb(24'h345678),
 .pixel_ready(ready),.writer_ack(ack),.writer_credit(credit),.writer_done_toggle(done),
 .displayed_valid(viewed_valid),.displayed_index(viewed_index),.write_req(req),
 .write_index(slot),.write_top_down(write_top),.write_en(we),.write_data(word),
 .committed_valid(committed_valid),.committed_index(committed_index));
always @(posedge clk)if(we)begin
 accepted=accepted+1;
 if(word!==32'h34567800)$fatal(1,"selected capture altered raw RGB");
end
task trigger;
 input [1:0] n;
 begin @(negedge clk);index=n;start=1;
  @(negedge clk);start=0;end
endtask
task send_complete;
 input orientation;
 begin
  credit=0;top=orientation;trigger(2);wait(req);
  if(write_top!==orientation)$fatal(1,"orientation changed with selection");
  @(negedge clk);ack=1;repeat(4)@(negedge clk);ack=0;
  if(req || ready)$fatal(1,"writer credit not respected");
  credit=1;repeat(3)@(negedge clk);valid=1;
  repeat(16)@(negedge clk);valid=0;
  if(ready)$fatal(1,"accepted beyond frame length");
  done=~done;repeat(6)@(negedge clk);
  if(!committed_valid || committed_index!=slot)$fatal(1,"selected capture not committed");
 end
endtask
initial begin
 repeat(8)@(negedge clk);rst=0;
 for(i=0;i<4;i=i+1)if(i!=2)begin
  trigger(i);repeat(8)@(negedge clk);
  if(req || ready || committed_valid)$fatal(1,"captured non-third picture index %0d",i);
 end
 send_complete(0);viewed_valid=1;viewed_index=committed_index;
 repeat(5)@(negedge clk);
 // Aborting a selected load must leave the already committed picture intact.
 trigger(2);wait(req);@(negedge clk);abort=1;
 repeat(5)@(negedge clk);abort=0;
 if(!committed_valid || committed_index!=0 || req || ready)$fatal(1,"abort changed display");
 send_complete(1);
 if(accepted!=32 || committed_index!=1)$fatal(1,"selection/slot coverage incomplete");
 $display("PASS B third-image selection: indices 0/1/3 ignored, index 2 selected, raw RGB and orientation preserved, credit gating, completed slot swap and abort retention");
 $finish;
end
initial begin #200000;$fatal(1,"selection test timeout");end
endmodule
