`timescale 1ns/1ps
// Exercise the real A sink, native 512-word FIFO and frame write controller.
// The SDRAM controller is represented only by its application availability;
// every accepted write/address/data is checked, not a physical SDRAM model.
module writer_window_case #(parameter GOLDEN=0,PHASE=0)(output reg done=0);
reg udp_clk=0,mem_clk=0,video_clk=0;
always #4 udp_clk=~udp_clk;
initial begin #(PHASE);forever #5 mem_clk=~mem_clk;end
always #20 video_clk=~video_clk;
reg rst=1,start=0,complete=0,packet_done=0,pixel_valid=0;
reg [23:0] rgb=0;reg [7:0] tag=0;reg [1:0] frame_index=0;
reg [15:0] packet_sequence=0;
wire mem_reset,ready,ack,finish,req,abort,we,pixel_ready,commit,fault;
wire [31:0] write_data,app_data;wire [20:0] app_address;
wire [1:0] write_index;wire top_down,app_we;
wire [3:0] cache;
reg finish_toggle=0;
integer frame=0,sent=0,written=0,lost=0,mismatch=0,accepted=0;
reg [31:0] expected_word;reg [23:0] expected_rgb;
wire fifo_reset_live, fifo_write_reset;
player_frame_reset resetter(.clk(mem_clk),.request(rst),.rst(mem_reset));
image_sdram_sink #(.FRAME_PACKETS(4),.TIMEOUT_CYCLES(30000),.UI_TAG(1)) sink(
 .clk(udp_clk),.rst(rst),.restart_transfer(1'b0),.frame_start(start),
 .frame_complete(complete),.frame_abort(1'b0),.frame_index(frame_index),
 .frame_top_down(1'b1),.frame_resolution(32'h00400010),
 .pixel_valid(pixel_valid),.pixel_rgb(rgb),.pixel_tag(tag),.pixel_ready(pixel_ready),
 .packet_done(packet_done),.packet_token(32'h12340001),.packet_sequence(packet_sequence),
 .writer_ready(ready),.writer_ack(ack),.writer_finish_toggle(finish_toggle),.protected_buffers(4'd0),
 .write_req(req),.write_abort(abort),.write_en(we),.write_data(write_data),
 .write_index(write_index),.write_top_down(top_down),.receipt_event(),.receipt_token(),.receipt_sequence(),
 .cache_valid(cache),.source_resolutions(),.commit_toggle(commit),.receive_reset(),.fault(fault));
generate if(GOLDEN)begin:g
 frame_read_write_golden_r7 #(.BURST_SIZE(256),.WRITE_V_FLIP(0),.DYNAMIC_V_FLIP(1),.FRAME_WIDTH(64),.FRAME_HEIGHT(16)) fw(
  .rst(rst),.mem_reset(mem_reset),.mem_clk(mem_clk),.Sdr_init_done(1'b1),
  .Sdr_init_ref_vld(1'b0),.Sdr_busy(1'b0),.App_rd_en(),.App_rd_addr(),.Sdr_rd_en(1'b0),.Sdr_rd_dout(32'd0),
  .read_clk(video_clk),.read_req(1'b0),.read_req_ack(),.read_finish(),.read_b_enable(1'b0),
  .read_addr_0(21'd0),.read_addr_1(21'd8192),.read_addr_2(21'd16384),.read_addr_3(21'd24576),
  .read_addr_index(2'd0),.read_addr_index_b(2'd0),.read_len(21'd1024),.read_en(1'b0),.read_data(),.read_data_b(),
  .App_wr_en(app_we),.App_wr_addr(app_address),.App_wr_din(app_data),.App_wr_dm(),
  .write_clk(udp_clk),.write_abort(abort),.write_req(req),.write_req_ack(ack),.write_finish(finish),
  .write_addr_0(21'd0),.write_addr_1(21'd8192),.write_addr_2(21'd16384),.write_addr_3(21'd24576),
  .write_addr_index(write_index),.write_len(21'd1024),.write_top_down(top_down),
  .write_en(we),.write_data(write_data),.read_empty_a(),.read_empty_b(),.read_valid_a(),.write_pixel_ready(ready));
 assign fifo_reset_live=g.fw.write_buf.rst;
 assign fifo_write_reset=g.fw.write_buf.wr_rst;
end else begin:f
 frame_read_write #(.BURST_SIZE(256),.WRITE_V_FLIP(0),.DYNAMIC_V_FLIP(1),.FRAME_WIDTH(64),.FRAME_HEIGHT(16)) fw(
  .rst(rst),.mem_reset(mem_reset),.mem_clk(mem_clk),.Sdr_init_done(1'b1),
  .Sdr_init_ref_vld(1'b0),.Sdr_busy(1'b0),.App_rd_en(),.App_rd_addr(),.Sdr_rd_en(1'b0),.Sdr_rd_dout(32'd0),
  .read_clk(video_clk),.read_req(1'b0),.read_req_ack(),.read_finish(),.read_b_enable(1'b0),
  .read_addr_0(21'd0),.read_addr_1(21'd8192),.read_addr_2(21'd16384),.read_addr_3(21'd24576),
  .read_addr_index(2'd0),.read_addr_index_b(2'd0),.read_len(21'd1024),.read_en(1'b0),.read_data(),.read_data_b(),
  .App_wr_en(app_we),.App_wr_addr(app_address),.App_wr_din(app_data),.App_wr_dm(),
  .write_clk(udp_clk),.write_abort(abort),.write_req(req),.write_req_ack(ack),.write_finish(finish),
  .write_addr_0(21'd0),.write_addr_1(21'd8192),.write_addr_2(21'd16384),.write_addr_3(21'd24576),
  .write_addr_index(write_index),.write_len(21'd1024),.write_top_down(top_down),
  .write_en(we),.write_data(write_data),.read_empty_a(),.read_empty_b(),.read_valid_a(),.write_pixel_ready(ready));
 assign fifo_reset_live=f.fw.write_buf.rst;
 assign fifo_write_reset=f.fw.write_buf.wr_rst;
end endgenerate
generate if(GOLDEN)begin
 // ModelSim leaves the legacy missing tenth input bit floating (Z).
 // Tie only this unconnected padding bit, as synthesis zero-extends it.
 initial force g.fw.frame_fifo_write_m0.rdusedw[9]=1'b0;
 initial force g.fw.frame_fifo_read_a.wrusedw[9]=1'b0;
 initial force g.fw.frame_fifo_read_b.wrusedw[9]=1'b0;
 initial begin #10000;$display("EARLY old p%0d state%h rd%h q%h data_ready%b busy%b%b ptr%h/%h",PHASE,g.fw.frame_fifo_write_m0.state,g.fw.rdusedw,g.fw.frame_fifo_write_m0.rdusedw_q,g.fw.frame_fifo_write_m0.write_data_ready,g.fw.App_rd_busy,g.fw.App_wr_busy,g.fw.write_buf.wr_addr,g.fw.write_buf.rd_addr);end
end else begin
 initial begin #10000;$display("EARLY new p%0d state%h rd%h q%h data_ready%b busy%b%b ptr%h/%h",PHASE,f.fw.frame_fifo_write_m0.state,f.fw.rdusedw,f.fw.frame_fifo_write_m0.rdusedw_q,f.fw.frame_fifo_write_m0.write_data_ready,f.fw.App_rd_busy,f.fw.App_wr_busy,f.fw.write_buf.wr_addr,f.fw.write_buf.rd_addr);end
end endgenerate
always @(posedge udp_clk)if(!rst && we)begin
 accepted=accepted+1;
 if(fifo_reset_live || fifo_write_reset)begin
  lost=lost+1;
  if(!GOLDEN)$fatal(1,"Fixed case accepted pixel during FIFO reset, phase %0d",PHASE);
 end
end
always @(posedge mem_clk or posedge mem_reset)begin
 if(mem_reset)finish_toggle<=0;
 else if(finish)finish_toggle<=~finish_toggle;
end
always @(posedge mem_clk)if(!mem_reset && app_we)begin
 expected_rgb=24'h830000+written;
 expected_word={expected_rgb,written[7:0]^8'h5a};
 if(app_data!==expected_word || app_address!==frame*8192+written)begin
  mismatch=mismatch+1;
  if(!GOLDEN)$fatal(1,"Fixed data/address mismatch phase%0d frame%0d word%0d got %h @%0d expected %h",PHASE,frame,written,app_data,app_address,expected_word);
 end
 written=written+1;
end
task send_frame;
 integer i;
 begin
  @(negedge udp_clk);start=1;frame_index=frame;
  @(negedge udp_clk);start=0;
  for(i=0;i<1024;i=i+1)begin
   pixel_valid=1;rgb=24'h830000+i;tag=i^8'h5a;
   do begin @(posedge udp_clk);end while(!pixel_ready);
   sent=sent+1;
   @(negedge udp_clk);pixel_valid=0;
   if(i%256==255)begin packet_done=1;packet_sequence=i/256;end
   if(i==1023)complete=1;
   @(negedge udp_clk);packet_done=0;complete=0;
  end
 end
endtask
initial begin
 repeat(12)@(negedge udp_clk);rst=0;wait(!mem_reset);
 for(frame=0;frame<(GOLDEN ? 1 : 3);frame=frame+1)begin
  sent=0;written=0;accepted=0;
  send_frame();repeat(3000)@(negedge udp_clk);
  if(GOLDEN)begin
   if(lost==0 || cache!=0 || written>=1024)$fatal(1,"Old FIFO reset-window failure did not reproduce");
   $display("PASS old writer failure reproduced phase=%0d offered=%0d accepted=%0d reset_lost=%0d SDRAM_writes=%0d cache=%h",PHASE,sent,accepted,lost,written,cache);
  end else begin
   if(cache[frame]!==1 || written!=1024 || accepted!=1024 || fault || mismatch || lost)
    $fatal(1,"Fixed frame did not commit phase=%0d frame=%0d cache=%h writes=%0d accepted=%0d",PHASE,frame,cache,written,accepted);
  end
 end
 if(!GOLDEN)$display("PASS fixed writer reset window phase=%0d: 3 committed frames, 3072 exact words, no reset-window pixel accepted",PHASE);
 done=1;
end
initial begin #900000;
 $display("WINDOW STATUS phase=%0d golden=%0d sent=%0d written=%0d lost=%0d sink=%0d req=%b ack=%b abort=%b ready=%b fifo_reset=%b local_reset=%b mem_reset=%b",PHASE,GOLDEN,sent,written,lost,sink.state,req,ack,abort,ready,fifo_reset_live,fifo_write_reset,mem_reset);
 #100000;$fatal(1,"Writer window timeout phase=%0d golden=%0d",PHASE,GOLDEN);end
endmodule
module tb_image_writer_reset_window;
wire [7:0] done;
writer_window_case #(.GOLDEN(1),.PHASE(0)) old0(done[0]);
writer_window_case #(.GOLDEN(1),.PHASE(3)) old3(done[1]);
writer_window_case #(.GOLDEN(1),.PHASE(7)) old7(done[2]);
writer_window_case #(.PHASE(0)) new0(done[3]);
writer_window_case #(.PHASE(1)) new1(done[4]);
writer_window_case #(.PHASE(3)) new3(done[5]);
writer_window_case #(.PHASE(5)) new5(done[6]);
writer_window_case #(.PHASE(7)) new7(done[7]);
initial begin wait(&done);$display("PASS image writer reset-window regression: old failure reproduced; fixed 100/125 MHz native FIFO path verified");$finish;end
endmodule
