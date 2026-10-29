`timescale 1ns/1ps

// Integration regression for the frame preload/write side. Continuous FIFO
// availability forces back-to-back bursts while the real SDRAM controller
// inserts periodic refresh operations.
module tb_sdram_write_refresh_arbiter;

reg         clk;
reg         clk_sft;
reg         rst;
reg         write_req;
reg         monitor_enable;

wire        init_done;
wire        init_ref_vld;
wire        sdr_busy;
wire        app_wr_en;
wire [20:0] app_wr_addr;
wire        write_req_ack;
wire        write_finish;
wire        fifo_aclr;
wire        sdr_rd_en;
wire [31:0] sdr_rd_dout;

wire        sdram_clk;
wire        sdram_ras;
wire        sdram_cas;
wire        sdram_we;
wire [1:0]  sdram_ba;
wire [10:0] sdram_addr;
wire [3:0]  sdram_dm;
tri  [31:0] sdram_dq;

integer monitor_cycles;
integer refresh_edges;
integer overlap_cycles;
integer busy_run;
integer max_busy_run;
integer app_write_pulses;
reg     prev_ref;

frame_fifo_write #(
    .ADDR_BITS     (21),
    .BURST_BITS    (9),
    .BURST_SIZE    (256),
    .WRITE_V_FLIP  (0),
    .FRAME_WIDTH   (640),
    .FRAME_HEIGHT  (480)
) writer (
    .rst              (rst),
    .mem_clk          (clk),
    .Sdr_init_done    (init_done),
    .Sdr_init_ref_vld (init_ref_vld),
    .Sdr_busy         (sdr_busy),
    .App_rd_busy      (1'b0),
    .O_wr_busy        (),
    .App_wr_en        (app_wr_en),
    .App_wr_addr      (app_wr_addr),
    .write_req        (write_req),
    .write_req_ack    (write_req_ack),
    .write_finish     (write_finish),
    .write_addr_0     (21'd0),
    .write_addr_1     (21'd0),
    .write_addr_2     (21'd0),
    .write_addr_3     (21'd0),
    .write_addr_index (2'd0),
    .write_len        (21'd307200),
    .fifo_aclr        (fifo_aclr),
    // Worst-case source availability: enough words for every burst.
    .rdusedw          (10'd511)
);

sdr_as_ram #(.self_refresh_open(1'b1)) controller (
    .Sdr_clk          (clk),
    .Sdr_clk_sft      (clk_sft),
    .Rst              (rst),
    .Sdr_init_done    (init_done),
    .Sdr_init_ref_vld (init_ref_vld),
    .Sdr_busy         (sdr_busy),
    .App_ref_req      (1'b0),
    .App_wr_en        (app_wr_en),
    .App_wr_addr      (app_wr_addr),
    .App_wr_dm        (4'd0),
    .App_wr_din       (32'h1234_5678),
    .App_rd_en        (1'b0),
    .App_rd_addr      (21'd0),
    .Sdr_rd_en        (sdr_rd_en),
    .Sdr_rd_dout      (sdr_rd_dout),
    .SDRAM_CLK        (sdram_clk),
    .SDR_RAS          (sdram_ras),
    .SDR_CAS          (sdram_cas),
    .SDR_WE           (sdram_we),
    .SDR_BA           (sdram_ba),
    .SDR_ADDR         (sdram_addr),
    .SDR_DM           (sdram_dm),
    .SDR_DQ           (sdram_dq)
);

initial begin
    clk = 1'b0;
    forever #5 clk = ~clk;
end

initial begin
    clk_sft = 1'b1;
    forever #5 clk_sft = ~clk_sft;
end

always @(posedge clk) begin
    if (rst || !monitor_enable) begin
        monitor_cycles  <= 0;
        refresh_edges   <= 0;
        overlap_cycles  <= 0;
        busy_run        <= 0;
        max_busy_run    <= 0;
        app_write_pulses <= 0;
        prev_ref        <= 1'b0;
    end else begin
        monitor_cycles <= monitor_cycles + 1;
        prev_ref       <= init_ref_vld;

        if (init_ref_vld && !prev_ref)
            refresh_edges <= refresh_edges + 1;
        if (app_wr_en)
            app_write_pulses <= app_write_pulses + 1;
        if (app_wr_en && init_ref_vld)
            overlap_cycles <= overlap_cycles + 1;

        if (sdr_busy) begin
            busy_run <= busy_run + 1;
            if ((busy_run + 1) > max_busy_run)
                max_busy_run <= busy_run + 1;
            if (busy_run > 600)
                $fatal(1, "SDRAM busy stuck for more than 600 clocks");
        end else begin
            busy_run <= 0;
        end

        if (monitor_cycles == 20000) begin
            if (refresh_edges < 5)
                $fatal(1, "only %0d refresh windows completed", refresh_edges);
            if (overlap_cycles != 0)
                $fatal(1, "%0d App_wr_en clocks overlapped refresh", overlap_cycles);
            if (app_write_pulses < 1000)
                $fatal(1, "write path made insufficient progress: %0d requests",
                       app_write_pulses);
            $display("PASS refresh_edges=%0d overlap=%0d max_busy=%0d writes=%0d",
                     refresh_edges, overlap_cycles, max_busy_run, app_write_pulses);
            $finish;
        end
    end
end

initial begin
    rst            = 1'b1;
    write_req      = 1'b0;
    monitor_enable = 1'b0;
    repeat (8) @(posedge clk);
    rst = 1'b0;

    wait (init_done);
    repeat (50) @(posedge clk);
    monitor_enable = 1'b1;
    write_req = 1'b1;
    wait (write_req_ack);
    @(posedge clk);
    write_req = 1'b0;

    repeat (24000) @(posedge clk);
    $fatal(1, "timeout waiting for write arbitration regression");
end

endmodule
