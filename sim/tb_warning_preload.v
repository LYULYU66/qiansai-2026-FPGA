`timescale 1ns/1ps
// Uses the same lightweight FAT/SPI stubs as tb_sd_card_bmp_playback.
module tb_warning_preload;
reg clk=0, rst=1, writer_done=0;
wire warning_ready, display_valid;
wire [1:0] displayed;
integer idx;
always #5 clk=~clk;
sd_card_bmp #(.CLK_FREQ_HZ(1000),.SCAN_TIMEOUT_CYCLES(10000),
 .LOAD_TIMEOUT_CYCLES(10000),.ABORT_HOLD_CYCLES(4)) dut(
 .clk(clk),.rst(rst),.key_next(1'b1),.key_auto(1'b1),
 .I_warning_hold(1'b1),.warning_image_ready(warning_ready),
 .bmp_width(16'd640),.bmp_height(16'd480),.audio_fifo_ready(1'b1),
 .display_valid(display_valid),.write_finish_toggle(writer_done),
 .disp_buf_idx(displayed),.write_req_ack(1'b1),.SD_MISO(1'b1),
 .audio_pcm_wr_en(),.audio_pcm_data(),.audio_stream_enable(),.audio_file_bytes(),.state_code(),
 .image_number(),.write_buf_idx(),.load_abort(),.write_req(),
 .write_en(),.write_data(),.SD_nCS(),.SD_DCLK(),.SD_MOSI());
initial begin
 dut.sd_card_top_m0.sd_init_done=0;
 dut.bmp_read_m0.ready=1;
 dut.bmp_read_m0.scan_done=0;
 dut.bmp_read_m0.scan_found_valid=0;
 dut.bmp_read_m0.scan_found_sector=0;
 dut.bmp_read_m0.scan_found_cluster=0;
 repeat(5) @(negedge clk); rst=0; dut.sd_card_top_m0.sd_init_done=1;
 wait(dut.scan_start_pulse);
 for(idx=0;idx<4;idx=idx+1) begin
  @(negedge clk);
  dut.bmp_read_m0.scan_found_sector=100*(idx+1);
  dut.bmp_read_m0.scan_found_cluster=10*(idx+1);
  dut.bmp_read_m0.scan_found_valid=1;
  dut.bmp_read_m0.scan_done=(idx==3);
  @(negedge clk); dut.bmp_read_m0.scan_found_valid=0; dut.bmp_read_m0.scan_done=0;
 end
 for(idx=0;idx<4;idx=idx+1) begin
  wait(dut.load_busy);
  @(negedge clk); dut.bmp_read_m0.ready=0;
  repeat(4) @(negedge clk); dut.bmp_read_m0.ready=1;
  repeat(8) @(negedge clk);
  if(warning_ready || dut.cache_valid[idx])
   $fatal(1,"buffer accepted before SDRAM writer completion idx=%0d",idx);
  writer_done=~writer_done;
  wait(!dut.load_busy); @(negedge clk);
  if(!dut.cache_valid[idx]) $fatal(1,"completed buffer not accepted");
  if(idx<3 && warning_ready) $fatal(1,"warning ready before fourth buffer");
 end
 wait(dut.preload_done); repeat(10) @(negedge clk);
 if(!warning_ready || !display_valid || displayed!==0)
  $fatal(1,"preload blocked by emergency hold or normal selection changed");
 $display("PASS warning preload: all four buffers load during danger, image 4 waits for writer completion");
 $finish;
end
initial begin #500000; $fatal(1,"warning preload timeout"); end
endmodule
