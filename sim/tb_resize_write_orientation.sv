`timescale 1ns/1ps
module tb_resize_write_orientation;
reg clk=0,rst=1,req=0,topdown=0;
wire ack,finished,we;
wire [20:0] addr;
integer count=0,expected,runid,i;
reg checking=0;
always #5 clk=~clk;
frame_fifo_write #(.DYNAMIC_V_FLIP(1),.FRAME_WIDTH(8),.FRAME_HEIGHT(5),.BURST_SIZE(4)) dut(
 .rst(rst),.mem_clk(clk),.Sdr_init_done(1'b1),.Sdr_init_ref_vld(1'b0),
 .Sdr_busy(1'b0),.App_rd_busy(1'b0),.O_wr_busy(),.App_wr_en(we),.App_wr_addr(addr),
 .write_req(req),.write_req_ack(ack),.write_finish(finished),
 .write_addr_0(21'd100),.write_addr_1(21'd100),.write_addr_2(21'd100),.write_addr_3(21'd100),
 .write_addr_index(2'd0),.write_len(21'd40),.fifo_aclr(),.rdusedw(10'd512),.write_top_down(topdown));
always @(posedge clk) if(checking && we) begin
 expected=100+(runid ? count : ((4-count/8)*8+count%8));
 if(addr!==expected) $fatal(1,"orientation run=%d pixel=%d got=%d want=%d",runid,count,addr,expected);
 count=count+1;
end
initial begin
 for(runid=0;runid<2;runid=runid+1) begin
  @(negedge clk); checking=0; rst=1; topdown=runid; req=0;
  repeat(5) @(negedge clk); rst=0;
  repeat(6) @(negedge clk); count=0; checking=1; req=1;
  wait(ack); @(negedge clk); req=0;
  // An asynchronously changing header must not alter an active frame.
  repeat(8) @(negedge clk); topdown=!runid;
  wait(finished); @(negedge clk);
  if(count!=40) $fatal(1,"wrong write count %d",count);
  $display("PASS dynamic BMP orientation topdown=%d pixels=%d",runid,count);
 end
 $finish;
end
initial begin #100000; $fatal(1,"write watchdog"); end
endmodule
