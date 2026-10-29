`timescale 1ns/1ps

module tb_sd_card_bmp_playback;

reg clk = 1'b0;
reg rst = 1'b1;
reg key_next = 1'b1;
reg key_auto = 1'b1;
reg write_finish_toggle = 1'b0;
reg warning_hold = 1'b0;
wire warning_ready;

wire display_valid;
wire [3:0] image_number;
wire [1:0] write_buf_idx;
wire [1:0] disp_buf_idx;

always #5 clk = ~clk;

sd_card_bmp #(
    .CLK_FREQ_HZ         (1000),
    .SCAN_TARGET_COUNT   (3'd4),
    .SCAN_TIMEOUT_CYCLES (10000),
    .LOAD_TIMEOUT_CYCLES (10000),
    .ABORT_HOLD_CYCLES   (4),
    .AUTO_PLAY_DEFAULT   (1'b0)
) dut (
    .clk                 (clk),
    .rst                 (rst),
    .key_next            (key_next),
    .key_auto            (key_auto),
    .I_warning_hold      (warning_hold),
    .warning_image_ready (warning_ready),
    .bmp_width           (16'd640),
    .bmp_height          (16'd480),
    .audio_fifo_ready    (1'b1),
    .audio_pcm_wr_en     (),
    .audio_pcm_data      (),
    .audio_stream_enable (),
    .display_valid       (display_valid),
    .state_code          (),
    .image_number        (image_number),
    .write_finish_toggle (write_finish_toggle),
    .write_buf_idx       (write_buf_idx),
    .disp_buf_idx        (disp_buf_idx),
    .load_abort          (),
    .write_req           (),
    .write_req_ack       (1'b1),
    .write_en            (),
    .write_data          (),
    .SD_nCS              (),
    .SD_DCLK             (),
    .SD_MOSI             (),
    .SD_MISO             (1'b1)
);

task emit_found;
    input [31:0] sector;
    input [31:0] cluster;
    input        last_item;
    begin
        @(negedge clk);
        dut.bmp_read_m0.scan_found_sector  = sector;
        dut.bmp_read_m0.scan_found_cluster = cluster;
        dut.bmp_read_m0.scan_found_valid   = 1'b1;
        dut.bmp_read_m0.scan_done          = last_item;
        @(negedge clk);
        dut.bmp_read_m0.scan_found_valid   = 1'b0;
        dut.bmp_read_m0.scan_done          = 1'b0;
    end
endtask

task finish_current_load;
       begin
        // 调用任务时下一帧可能已经在后台启动，不能只等待单周期 start 脉冲。
        if (dut.load_busy !== 1'b1)
            wait (dut.load_start_pulse === 1'b1);
        @(negedge clk);
        dut.bmp_read_m0.ready = 1'b0;
        repeat (4) @(negedge clk);
        dut.bmp_read_m0.ready = 1'b1;
        write_finish_toggle = ~write_finish_toggle;
        wait (dut.load_busy === 1'b0);
        @(negedge clk);
    end
endtask

task press_next;
    begin
        @(negedge clk);
        key_next = 1'b0;
        repeat (20) @(negedge clk);
        key_next = 1'b1;
        repeat (20) @(negedge clk);
    end
endtask

task press_auto;
    begin
        @(negedge clk);
        key_auto = 1'b0;
        repeat (25) @(negedge clk);
        key_auto = 1'b1;
        repeat (25) @(negedge clk);
    end
endtask

initial begin
    // 由精简模型模拟 SD 卡初始化和 BMP 扫描。
    dut.sd_card_top_m0.sd_init_done = 1'b0;
    dut.bmp_read_m0.ready = 1'b1;
    dut.bmp_read_m0.scan_done = 1'b0;
    dut.bmp_read_m0.scan_found_valid = 1'b0;
    dut.bmp_read_m0.scan_found_sector = 32'd0;
    dut.bmp_read_m0.scan_found_cluster = 32'd0;

    repeat (5) @(negedge clk);
    rst = 1'b0;
    dut.sd_card_top_m0.sd_init_done = 1'b1;

    wait (dut.scan_start_pulse === 1'b1);
    emit_found(32'd100, 32'd10, 1'b0);
    // The real FAT scanner presents scan_done together with the final result.
    // This is the hardware timing that previously left preload permanently idle.
    emit_found(32'd200, 32'd20, 1'b1);

    // Power-up key transients during scan/preload must not queue a switch or
    // silently enable auto play before image 1 becomes visible.
    press_next();
    press_auto();
    if (dut.next_req_count !== 3'd0 || dut.auto_play_en !== 1'b0)
        $fatal(1, "startup key transient was not ignored");

    finish_current_load();
    repeat (4) @(negedge clk);
    if (!display_valid || image_number !== 4'd1 || disp_buf_idx !== 2'd0)
        $fatal(1, "first frame was not committed immediately: valid=%b num=%0d buf=%0d",
               display_valid, image_number, disp_buf_idx);
    if (dut.preload_done)
        $fatal(1, "first frame incorrectly waited for/finished all preload");

    finish_current_load();
    wait (dut.preload_done === 1'b1);
    if (image_number !== 4'd1)
        $fatal(1, "preload completion forced current image away from 1");

    press_next();
    if (image_number !== 4'd2 || disp_buf_idx !== 2'd1)
        $fatal(1, "manual switch failed: num=%0d buf=%0d", image_number, disp_buf_idx);

    press_auto();
    repeat (1010) @(negedge clk);
    // Freeze automatic selection and discard manual requests during danger.
    warning_hold=1;
    repeat (10) @(negedge clk);
    press_next();
    repeat (2100) @(negedge clk);
    if(image_number !== 4'd1 || dut.next_req_count !== 3'd0)
        $fatal(1,"warning hold did not pause manual/automatic selection");
    if(warning_ready !== 1'b0) $fatal(1,"absent image 4 reported ready");
    warning_hold=0;
    repeat (10) @(negedge clk);
    repeat (1010) @(negedge clk);
    if(image_number !== 4'd2) $fatal(1,"automatic playback did not resume");
    // Return to image 1 for the original regression assertion below.
    press_auto(); press_next();
    if (image_number !== 4'd1 || disp_buf_idx !== 2'd0)
        $fatal(1, "automatic rotation failed: num=%0d buf=%0d", image_number, disp_buf_idx);

    $display("PASS PLAYBACK first=1 manual=2 auto=1 background_preload=ok emergency_hold=ok");
    $finish;
end

initial begin
    #500000;
    $fatal(1, "timeout");
end

endmodule

// 只保留播放控制仿真需要的接口；底层 FAT/BMP 与 SPI 已有独立测试。
module bmp_read #(parameter ENABLE_RESAMPLE=0,FAST_AUDIO_START=0,PIPELINED_CLUSTER_ADDR=0,OUT_WIDTH=640,OUT_HEIGHT=480)(
    input clk,
    input rst,
    output reg ready,
    input scan_start,
    input [2:0] scan_target_count,
    output reg scan_done,
    output reg scan_found_valid,
    output reg [31:0] scan_found_sector,
    output reg [31:0] scan_found_cluster,
    output reg [2:0] scan_found_total,
    input load_start,
    input load_abort,
    input [31:0] load_sector,
    input [31:0] load_cluster,
    input audio_enable,
    input audio_fifo_ready,
    output audio_file_found,
    output [31:0] audio_file_bytes,
    output audio_data_valid,
    output [7:0] audio_data,
    input sd_init_done,
    output [3:0] state_code,
    input [15:0] bmp_width,
    input [15:0] bmp_height,
    output write_req,
    input write_req_ack,
    output sd_sec_read,
    output [31:0] sd_sec_read_addr,
    input [7:0] sd_sec_read_data,
    input sd_sec_read_data_valid,
    input sd_sec_read_end,
    output bmp_data_wr_en,
    output [23:0] bmp_data,
    output [15:0] source_width,source_height,
    output source_top_down,
    input write_pixel_ready
);
assign state_code = 4'd0;
assign audio_file_found = 1'b0;
assign audio_file_bytes = 32'd0;
assign audio_data_valid = 1'b0;
assign audio_data = 8'd0;
assign write_req = 1'b0;
assign sd_sec_read = 1'b0;
assign sd_sec_read_addr = 32'd0;
assign bmp_data_wr_en = 1'b0;
assign bmp_data = 24'd0;
assign source_width=16'd640;
assign source_height=16'd480;
assign source_top_down=1'b0;
endmodule

module sd_card_top (
    input clk,
    input rst,
    input io_abort,
    output SD_nCS,
    output SD_DCLK,
    output SD_MOSI,
    input SD_MISO,
    output reg sd_init_done,
    input sd_sec_read,
    input [31:0] sd_sec_read_addr,
    output [7:0] sd_sec_read_data,
    output sd_sec_read_data_valid,
    output sd_sec_read_end,
    input sd_sec_write,
    input [31:0] sd_sec_write_addr,
    input [7:0] sd_sec_write_data,
    output sd_sec_write_data_req,
    output sd_sec_write_end
);
assign SD_nCS = 1'b1;
assign SD_DCLK = 1'b0;
assign SD_MOSI = 1'b1;
assign sd_sec_read_data = 8'd0;
assign sd_sec_read_data_valid = 1'b0;
assign sd_sec_read_end = 1'b0;
assign sd_sec_write_data_req = 1'b0;
assign sd_sec_write_end = 1'b0;
endmodule
