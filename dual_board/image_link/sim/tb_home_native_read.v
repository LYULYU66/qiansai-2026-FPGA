`timescale 1ns/1ps
// R7 A native FIFO read + video_delay + transition + adjustment + palette.
// Application-level SDRAM latency/refresh model, not physical SDRAM timing.
module tb_home_native_read;
reg video_clk=0,mem_clk=0,udp_clk=0;
always #20 video_clk=~video_clk;
always #5 mem_clk=~mem_clk;
always #4 udp_clk=~udp_clk;
reg rst=1,vs=0,de=0,read_req=0;
wire mem_reset,read_ack,read_en,app_rd_en,app_wr_en,read_empty,read_valid;
wire [20:0] app_rd_addr,app_wr_addr;
wire [31:0] app_wr_data,read_word,read_word_b,raw_word;
wire raw_hs,raw_vs,raw_de,transition_hs,transition_vs,transition_de;
wire [23:0] transition_rgb,adjusted_rgb,home_rgb;
wire adjusted_hs,adjusted_vs,adjusted_de,write_ack,write_ready,write_finish;
reg [7:0] transition_index=0;
reg [7:0] atlas[0:614399];
reg [9:0] pending_valid=0;
reg [20:0] pending_address[0:9];
reg [31:0] memory_data=0;
reg memory_valid=0;
integer mem_cycle=0,m,underflows=0,reads=0,outputs=0,raw_count=0,writes=0;
integer row=0,col=0,i;
wire refresh=mem_cycle%782<8;
wire busy=refresh || (|pending_valid);
function [31:0] image_word;
 input [20:0] address;
 begin image_word={address[23:0],atlas[address]};end
endfunction
// Correctly extend 21-bit address to 24-bit RGB without undefined high bits.
wire [31:0] incoming_word={3'd0,pending_address[9],atlas[pending_address[9]]};
always @(posedge mem_clk)begin
 if(mem_reset)begin pending_valid<=0;memory_valid<=0;mem_cycle<=0;end
 else begin
  mem_cycle<=mem_cycle+1;
  pending_valid<={pending_valid[8:0],app_rd_en};
  pending_address[0]<=app_rd_addr;
  for(m=1;m<10;m=m+1)pending_address[m]<=pending_address[m-1];
  memory_valid<=pending_valid[9];
  if(pending_valid[9])begin
   if(pending_address[9]>=307200)$fatal(1,"Invalid read address %d",pending_address[9]);
   memory_data<=incoming_word;
  end
  if(app_rd_en)reads=reads+1;
  if(app_wr_en)writes=writes+1;
 end
end
player_frame_reset resetter(.clk(mem_clk),.request(rst),.rst(mem_reset));
reg write_req=0,write_abort=1,write_valid=0;
reg [31:0] write_data=0;
frame_read_write #(.WRITE_V_FLIP(0),.DYNAMIC_V_FLIP(1)) fw(
 .rst(rst),.mem_reset(mem_reset),.mem_clk(mem_clk),.Sdr_init_done(1'b1),
 .Sdr_init_ref_vld(refresh),.Sdr_busy(busy),.App_rd_en(app_rd_en),.App_rd_addr(app_rd_addr),
 .Sdr_rd_en(memory_valid),.Sdr_rd_dout(memory_data),
 .read_clk(video_clk),.read_req(read_req),.read_req_ack(read_ack),.read_finish(),.read_b_enable(1'b0),
 .read_addr_0(21'd0),.read_addr_1(21'd307200),.read_addr_2(21'd614400),.read_addr_3(21'd921600),
 .read_addr_index(2'd0),.read_addr_index_b(2'd0),.read_len(21'd307200),.read_en(read_en),
 .read_data(read_word),.read_data_b(read_word_b),
 .App_wr_en(app_wr_en),.App_wr_addr(app_wr_addr),.App_wr_din(app_wr_data),.App_wr_dm(),
 .write_clk(udp_clk),.write_abort(write_abort),.write_req(write_req),.write_req_ack(write_ack),
 .write_finish(write_finish),.write_addr_0(21'd0),.write_addr_1(21'd307200),
 .write_addr_2(21'd614400),.write_addr_3(21'd921600),.write_addr_index(2'd2),
 .write_len(21'd307200),.write_top_down(1'b1),.write_en(write_valid && write_ready),.write_data(write_data),
 .read_empty_a(read_empty),.read_empty_b(),.read_valid_a(read_valid),.write_pixel_ready(write_ready));
video_delay #(.DATA_WIDTH(32)) delay(.video_clk(video_clk),.rst(rst),.read_en(read_en),
 .read_data(read_word),.hs(1'b0),.vs(vs),.de(de),.hs_r(raw_hs),.vs_r(raw_vs),.de_r(raw_de),.vout_data(raw_word));
video_transition_effects transition(.I_clk(video_clk),.I_rst(rst),.I_frame_vs(vs),
 .I_hs(raw_hs),.I_vs(raw_vs),.I_de(raw_de),.I_rgb_a(raw_word[31:8]),.I_rgb_b(24'd0),
 .I_display_valid(1'b1),.I_requested_idx(2'd0),.I_frame_read_req(read_req),
 .I_force_warning(1'b0),.I_warning_ready(1'b0),.O_read_idx_a(),.O_read_idx_b(),
 .O_read_b_enable(),.O_display_idx(),.O_transition_active(),.O_transition_kind(),.O_transition_step(),
 .O_hs(transition_hs),.O_vs(transition_vs),.O_de(transition_de),.O_rgb(transition_rgb));
always @(posedge video_clk)transition_index<=raw_word[7:0];
video_image_adjust #(.USE_LUT_ROM(1)) adjust(.I_clk(video_clk),.I_rst(rst),
 .I_hs(transition_hs),.I_vs(transition_vs),.I_de(transition_de),.I_rgb(transition_rgb),
 .I_brightness_level(2'd3),.I_contrast_level(2'd0),
 .O_hs(adjusted_hs),.O_vs(adjusted_vs),.O_de(adjusted_de),.O_rgb(adjusted_rgb));
video_remote_home_overlay home(.I_clk(video_clk),.I_rst(rst),.I_enable(1'b1),
 .I_de(adjusted_de),.I_index(transition_index),.I_rgb(adjusted_rgb),.O_rgb(home_rgb));
reg [31:0] expected_raw;
reg [23:0] expected_home;
always @(posedge video_clk)begin
 if(!rst && read_en && read_empty)underflows=underflows+1;
 #2;
 if(!rst && raw_de)begin
  expected_raw={raw_count[23:0],atlas[raw_count]};
  if(raw_word!==expected_raw)$fatal(1,"Native read misalignment pixel=%0d x=%0d y=%0d got=%h expected=%h underflow=%0d",raw_count,raw_count%640,raw_count/640,raw_word,expected_raw,underflows);
  raw_count=raw_count+1;
 end
 if(!rst && adjusted_de)begin
  expected_home=atlas[outputs]!=0 ? home.palette.mem[atlas[outputs]] : adjusted_rgb;
  if(home_rgb!==expected_home)$fatal(1,"Home palette alignment pixel=%0d got=%h expected=%h",outputs,home_rgb,expected_home);
  outputs=outputs+1;
 end
end
// Load another frame concurrently, as B preloads after picture 1 is visible.
initial begin
 wait(!rst);repeat(500)@(negedge udp_clk);write_abort=0;write_req=1;
 wait(write_ack);@(negedge udp_clk);write_req=0;
 for(i=0;i<307200;i=i+1)begin
  write_valid=1;write_data=i;
  do @(posedge udp_clk);while(!write_ready);
  @(negedge udp_clk);write_valid=0;
  @(negedge udp_clk);
 end
 wait(write_finish);$display("Concurrent preload committed 307200 writes.");
end
initial begin
 $readmemh("home_reference_indices.hex",atlas);
 repeat(10)@(negedge video_clk);rst=0;
 repeat(50)@(negedge video_clk);vs=1;read_req=1;
 wait(read_ack);@(negedge video_clk);read_req=0;
 repeat(50)@(negedge video_clk);vs=0;
 repeat(500)@(negedge video_clk);
 for(row=0;row<480;row=row+1)begin
  de=1;repeat(640)@(negedge video_clk);de=0;repeat(160)@(negedge video_clk);
 end
 repeat(40)@(negedge video_clk);
 if(outputs!=307200 || raw_count!=307200 || reads!=307200 || underflows!=0 || writes!=307200)
  $fatal(1,"Coverage mismatch outputs=%0d raw=%0d read=%0d underflow=%0d concurrent_writes=%0d",outputs,raw_count,reads,underflows,writes);
 $display("PASS native home read: 307200 RGB/tags and palette pixels, concurrent preload, refresh stalls, no FIFO underflow");$finish;
end
initial begin #30000000;$fatal(1,"Native home read timeout");end
endmodule
