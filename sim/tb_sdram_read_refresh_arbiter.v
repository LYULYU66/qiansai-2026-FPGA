`timescale 1ns/1ps

// Integration regression: the real protected SDRAM controller is driven by
// frame_fifo_read under continuous demand. A read burst may finish after a
// refresh request becomes pending, but the next burst must not start until
// controller busy/refresh have both cleared.
module tb_sdram_read_refresh_arbiter;

reg         clk;
reg         clk_sft;
reg         rst;
reg         read_req;
reg         monitor_enable;

wire        init_done;
wire        init_ref_vld;
wire        sdr_busy;
wire        app_rd_en;
wire [20:0] app_rd_addr;
wire        sdr_rd_en;
wire [31:0] sdr_rd_dout;
wire        read_req_ack;
wire        read_finish;
wire        fifo_aclr;

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
integer app_read_pulses;
reg     prev_ref;

frame_fifo_read #(
    .ADDR_BITS  (21),
    .BURST_BITS (9),
    .FIFO_DEPTH (512),
    .BURST_SIZE (256)
) reader (
    .rst              (rst),
    .mem_clk          (clk),
    .Sdr_init_done    (init_done),
    .Sdr_init_ref_vld (init_ref_vld),
    .Sdr_busy         (sdr_busy),
    .Sdr_rd_en        (sdr_rd_en),
    .App_wr_busy      (1'b0),
    .O_rd_busy        (),
    .I_rd_grant       (1'b1),
    .O_rd_want        (),
    .App_rd_en        (app_rd_en),
    .App_rd_addr      (app_rd_addr),
    .read_req         (read_req),
    .read_req_ack     (read_req_ack),
    .read_finish      (read_finish),
    .read_addr_0      (21'd0),
    .read_addr_1      (21'd0),
    .read_addr_2      (21'd0),
    .read_addr_3      (21'd0),
    .read_addr_index  (2'd0),
    .read_len         (21'd307200),
    .fifo_aclr        (fifo_aclr),
    // Worst-case continuous demand: report the read FIFO as always having room.
    .wrusedw          (10'd0)
);

sdr_as_ram #(.self_refresh_open(1'b1)) controller (
    .Sdr_clk          (clk),
    .Sdr_clk_sft      (clk_sft),
    .Rst              (rst),
    .Sdr_init_done    (init_done),
    .Sdr_init_ref_vld (init_ref_vld),
    .Sdr_busy         (sdr_busy),
    .App_ref_req      (1'b0),
    .App_wr_en        (1'b0),
    .App_wr_addr      (21'd0),
    .App_wr_dm        (4'd0),
    .App_wr_din       (32'd0),
    .App_rd_en        (app_rd_en),
    .App_rd_addr      (app_rd_addr),
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
        monitor_cycles <= 0;
        refresh_edges  <= 0;
        overlap_cycles <= 0;
        busy_run       <= 0;
        max_busy_run   <= 0;
        app_read_pulses <= 0;
        prev_ref       <= 1'b0;
    end else begin
        monitor_cycles <= monitor_cycles + 1;
        prev_ref       <= init_ref_vld;

        if (init_ref_vld && !prev_ref)
            refresh_edges <= refresh_edges + 1;
        if (app_rd_en)
            app_read_pulses <= app_read_pulses + 1;
        if (app_rd_en && init_ref_vld)
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
                $fatal(1, "%0d App_rd_en clocks overlapped refresh", overlap_cycles);
            if (app_read_pulses < 1000)
                $fatal(1, "read path made insufficient progress: %0d requests",
                       app_read_pulses);
            $display("PASS refresh_edges=%0d overlap=%0d max_busy=%0d reads=%0d",
                     refresh_edges, overlap_cycles, max_busy_run, app_read_pulses);
            $finish;
        end
    end
end

initial begin
    rst            = 1'b1;
    read_req       = 1'b0;
    monitor_enable = 1'b0;
    repeat (8) @(posedge clk);
    rst = 1'b0;

    wait (init_done);
    repeat (50) @(posedge clk);
    monitor_enable = 1'b1;
    read_req = 1'b1;
    wait (read_req_ack);
    @(posedge clk);
    read_req = 1'b0;

    repeat (24000) @(posedge clk);
    $fatal(1, "timeout waiting for arbitration regression");
end

endmodule
