`timescale 1ns/1ps
// Real two-clock frame-reader handshake plus the production transition FSM.
// The SDRAM PHY is intentionally outside this functional page-selection test.
module tb_warning_direct_switch;
reg clk=0, mem_clk=0, rst=1, frame_vs=1, req=0;
reg valid=0, danger=0, ready=1, de=0;
reg [1:0] requested=0;
wire [1:0] read_a, read_b, displayed;
wire active, read_b_enable, ack, app_rd, finished;
wire [20:0] addr;
wire [23:0] rgb;
integer frames=0, scenes, i, bursts_checked=0;
reg first_read=1;
reg [1:0] frame_fetch;
always #20 clk=~clk;
always #5 mem_clk=~mem_clk;
video_transition_effects dut(
 .I_clk(clk),.I_rst(rst),.I_frame_vs(frame_vs),.I_frame_read_req(req),
 .I_force_warning(danger),.I_warning_ready(ready),.I_display_valid(valid),
 .I_requested_idx(requested),.I_hs(1'b1),.I_vs(frame_vs),.I_de(de),
 .I_rgb_a(24'h123456),.I_rgb_b(24'hABCDEF),.O_read_idx_a(read_a),
 .O_read_idx_b(read_b),.O_read_b_enable(read_b_enable),.O_display_idx(displayed),
 .O_transition_active(active),.O_transition_kind(),.O_transition_step(),
 .O_hs(),.O_vs(),.O_de(),.O_rgb(rgb));
frame_fifo_read #(.BURST_SIZE(16)) reader(
 .rst(rst),.mem_clk(mem_clk),.Sdr_init_done(!rst),.Sdr_init_ref_vld(1'b0),
 .Sdr_busy(1'b0),.Sdr_rd_en(1'b0),.App_wr_busy(1'b0),.I_rd_grant(1'b1),
 .O_rd_busy(),.O_rd_want(),.App_rd_en(app_rd),.App_rd_addr(addr),
 .read_req(req),.read_req_ack(ack),.read_finish(finished),
 .read_addr_0(21'h00000),.read_addr_1(21'h10000),
 .read_addr_2(21'h20000),.read_addr_3(21'h30000),
 .read_addr_index(read_a),.read_len(21'd64),.fifo_aclr(),.wrusedw(10'd0));
always @(posedge mem_clk) begin
 if(rst || req) first_read=1;
 else if(app_rd && first_read) begin
  if(addr !== {3'b000,frame_fetch,16'd0})
   $fatal(1,"SDRAM frame address mismatch frame=%0d selected=%0d addr=%h",frames,frame_fetch,addr);
  bursts_checked=bursts_checked+1; first_read=0;
 end
end
task tick; begin @(posedge clk); #1; end endtask
task settle; begin repeat(6) tick; end endtask
task start_frame;
begin
 de=0; frame_vs=1; repeat(3) tick;
 req=1; tick; frame_fetch=read_a;
 frame_vs=0; tick; frames=frames+1;
end
endtask
task finish_frame;
begin
 wait(ack); tick; req=0;
 // Wait for the real reader to complete its short frame.
 wait(finished); repeat(4) tick;
end
endtask
task frame; begin start_frame; finish_frame; end endtask
task require_warning;
begin
 if(displayed!==2'd3 || active || read_b_enable || frame_fetch!==2'd3)
  $fatal(1,"warning was not a direct cut: display=%d active=%b B=%b fetch=%d",displayed,active,read_b_enable,frame_fetch);
 de=1; repeat(3) tick;
 if(rgb!==24'h123456) $fatal(1,"warning pixel blended with previous page");
 de=0;
end
endtask
initial begin
 repeat(4) tick; rst=0; valid=1; settle;
 // Cut from every page, including page 4 itself, and restore its request.
 for(scenes=0;scenes<4;scenes=scenes+1) begin
  rst=1; repeat(3) tick; rst=0; requested=scenes; danger=0; ready=1; settle;
  frame;
  danger=1; settle; start_frame; require_warning; finish_frame;
  requested=scenes; repeat(2) begin start_frame; require_warning; finish_frame; end
  danger=0; settle; frame;
  if(displayed!==requested || active || read_b_enable || frame_fetch!==requested)
   $fatal(1,"normal page did not resume directly");
 end
 // Interrupt every effect after it actually started, not just a pending cut.
 for(scenes=0;scenes<4;scenes=scenes+1) begin
  rst=1; repeat(3) tick; rst=0; requested=scenes; danger=0; settle;
  frame; requested=(scenes+1)%4; settle; frame;
  if(!active) $fatal(1,"normal transition did not start");
  danger=1; settle; start_frame; require_warning; finish_frame;
  danger=0; settle; frame;
  if(displayed!==requested || active) $fatal(1,"animation interruption recovery failed");
 end
 // Do not fetch an uninitialized image-4 buffer during startup/preload.
 rst=1; repeat(3) tick; rst=0; requested=0; danger=1; ready=0; settle;
 frame; if(displayed!==0 || frame_fetch!==0) $fatal(1,"unloaded warning page selected");
 ready=1; settle; start_frame; require_warning; finish_frame;
 // A release after the read decision must NOT change the page halfway through
 // the same frame. The next request restores the page.
 start_frame; danger=0; require_warning; finish_frame;
 settle; frame;
 if(displayed!==0 || active) $fatal(1,"late release recovery failed");
 // A danger asserted after a normal read request is deferred, not half-cut.
 start_frame; danger=1; finish_frame;
 if(displayed!==0) $fatal(1,"late assertion changed an already fetched frame");
 settle; start_frame; require_warning; finish_frame;
 $display("PASS direct warning switch: %0d frames, %0d SDRAM base checks, all pages/effects, hold/release, preload and boundary races",frames,bursts_checked);
 $finish;
end
initial begin #2000000; $fatal(1,"direct-switch test timeout"); end
endmodule
