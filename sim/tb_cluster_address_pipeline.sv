`timescale 1ns/1ps
module tb_cluster_address_pipeline;
reg clk=0,rst=1,abort_load=0;
wire [31:0] address,found;
wire valid,read_request;
integer i,k,spc,calc,target,checks=0;
reg [31:0] cluster,base,expected;
always #5 clk=~clk;
bmp_read #(.PIPELINED_CLUSTER_ADDR(1)) dut(
 .clk(clk),.rst(rst),.ready(),.scan_start(1'b0),.scan_target_count(3'd4),
 .scan_done(),.scan_found_valid(valid),.scan_found_sector(found),.scan_found_cluster(),.scan_found_total(),
 .load_start(1'b0),.load_abort(abort_load),.load_sector(32'd0),.load_cluster(32'd0),
 .audio_enable(1'b0),.audio_fifo_ready(1'b1),.audio_file_found(),.audio_file_bytes(),.audio_data_valid(),.audio_data(),
 .sd_init_done(1'b1),.state_code(),.bmp_width(16'd640),.bmp_height(16'd480),
 .write_req(),.write_req_ack(1'b0),.sd_sec_read(read_request),.sd_sec_read_addr(address),
 .sd_sec_read_data(8'd0),.sd_sec_read_data_valid(1'b0),.sd_sec_read_end(1'b0),
 .bmp_data_wr_en(),.bmp_data(),.source_width(),.source_height(),.source_top_down(),.write_pixel_ready(1'b1));
initial begin
 for(i=0;i<1800;i=i+1)begin
  @(negedge clk);rst=1;@(negedge clk);rst=0;
  cluster=i<18 ? i%3 : $random;
  spc=1<<((i/6)%8);base=$random;
  expected=base+((cluster>=2 ? cluster-2:0)*spc);
  k=i%6;
  case(k)
   0:begin calc=7;target=8;end
   1:begin calc=16;target=17;end
   2:begin calc=13;target=14;end
   3:begin calc=19;target=20;end
   4:begin calc=22;target=23;end
   5:begin calc=27;target=28;end
  endcase
  dut.state=calc;dut.fs_root_cluster=cluster;dut.dir_cluster=cluster;
  dut.emit_cluster=cluster;dut.load_cluster_latched=cluster;dut.audio_current_cluster=cluster;
  dut.fs_sectors_per_cluster=spc;dut.first_data_sector=base;
  dut.volume_lba=base-32'd2;dut.fs_reserved_sectors=1;dut.fs_num_fats=1;dut.fs_fat_size=1;
  dut.emit_idx=0;dut.dir_candidate_count=1;
  @(posedge clk);#1;
  if(dut.state!==5'd31 || read_request) $fatal(1,"CALC must enter request-free SHIFT %d",k);
  @(posedge clk);#1;
  if(dut.state!==target || read_request) $fatal(1,"SHIFT return %d",k);
  if(dut.cluster_offset_q!==((cluster>=2 ? cluster-2:0)*spc)) $fatal(1,"offset %h",cluster);
  @(posedge clk);#1;
  if(k==0)begin @(posedge clk);#1;end
  if((k==2 ? found:address)!==expected) $fatal(1,"address case %d got %h expected %h",k,k==2?found:address,expected);
  checks=checks+1;
 end
 // Fragmented image rows can end mid-pixel at a FAT boundary. Preserve
 // both byte offset and partial BGR phase through the new wait cycle.
 @(negedge clk);dut.state=31;dut.cluster_return_state=20;
 dut.bmp_len_cnt=123;dut.bmp_byte_idx=2;
 @(posedge clk);#1;
 if(dut.bmp_len_cnt!==123 || dut.bmp_byte_idx!==2) $fatal(1,"BMP byte position lost in SHIFT");
 // A reset/abort while in the inserted stage must not issue a stale read.
 @(negedge clk);dut.state=31;abort_load=1;
 @(posedge clk);#1;if(dut.state!==0 || read_request) $fatal(1,"abort in SHIFT");
 @(negedge clk);abort_load=0;rst=1;
 @(posedge clk);#1;if(dut.state!==0 || read_request) $fatal(1,"reset in SHIFT");
 $display("PASS CLUSTER PIPELINE: %d randomized addresses, six CALC consumers, all eight FAT cluster sizes, invalid clusters, 32-bit wrap, abort/reset, no premature sector request",checks);
 $finish;
end
endmodule
