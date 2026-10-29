`timescale 1ns/1ps

// RTL regression for the real sdr_init_ref module used by the project.
// The test waits through SDRAM initialization, captures refresh requests,
// checks their cycle-to-cycle gap, and emits a VCD waveform for inspection.
module tb_sdram_refresh_timer;

localparam integer CLK_PERIOD_NS = 10;
localparam integer MAX_REFRESH_GAP_CLOCKS = 1562;

reg         clk;
reg         rst;
reg         sdr_init_req;
reg  [3:0]  sdr_init_mode;
reg         sdr_ref_ack;
reg         sdr_rw_vld;

wire        sdr_init_done;
wire        sdr_ref_req;
wire        sdr_init_ref_vld;
wire        sdr_init_ref_ras;
wire        sdr_init_ref_cas;
wire        sdr_init_ref_we;
wire [1:0]  sdr_init_ref_ba;
wire [11:0] sdr_init_ref_addr;

integer cycle_count;
integer last_refresh_cycle;
integer refresh_count;
integer refresh_gap;

sdr_init_ref #(
    .self_refresh_open(1)
) dut (
    .Sdr_clk           (clk),
    .Rst               (rst),
    .Sdr_init_req      (sdr_init_req),
    .Sdr_init_mode     (sdr_init_mode),
    .Sdr_init_done     (sdr_init_done),
    .App_ref_req       (1'b0),
    .Sdr_ref_req       (sdr_ref_req),
    .Sdr_ref_ack       (sdr_ref_ack),
    .Sdr_rw_vld        (sdr_rw_vld),
    .Sdr_init_ref_vld  (sdr_init_ref_vld),
    .Sdr_init_ref_ras  (sdr_init_ref_ras),
    .Sdr_init_ref_cas  (sdr_init_ref_cas),
    .Sdr_init_ref_we   (sdr_init_ref_we),
    .Sdr_init_ref_ba   (sdr_init_ref_ba),
    .Sdr_init_ref_addr (sdr_init_ref_addr)
);

initial begin
    clk = 1'b0;
    forever #(CLK_PERIOD_NS/2) clk = ~clk;
end

// Model a one-clock-late refresh acknowledgement from the SDRAM arbiter.
always @(posedge clk or posedge rst) begin
    if (rst)
        sdr_ref_ack <= 1'b0;
    else
        sdr_ref_ack <= sdr_ref_req;
end

always @(posedge clk) begin
    if (rst) begin
        cycle_count       <= 0;
        last_refresh_cycle <= -1;
        refresh_count     <= 0;
    end else begin
        cycle_count <= cycle_count + 1;

        if (sdr_ref_req) begin
            refresh_count <= refresh_count + 1;
            if (last_refresh_cycle >= 0) begin
                refresh_gap = cycle_count - last_refresh_cycle;
                $display("REFRESH pulse=%0d cycle=%0d gap=%0d clocks",
                         refresh_count + 1, cycle_count, refresh_gap);
                if (refresh_gap > MAX_REFRESH_GAP_CLOCKS)
                    $fatal(1, "refresh gap %0d exceeds %0d clocks",
                           refresh_gap, MAX_REFRESH_GAP_CLOCKS);
            end else begin
                $display("REFRESH pulse=1 cycle=%0d", cycle_count);
            end
            last_refresh_cycle <= cycle_count;

            if (refresh_count == 4) begin
                $display("PASS: five consecutive RTL refresh requests are within %0d clocks",
                         MAX_REFRESH_GAP_CLOCKS);
                $finish;
            end
        end
    end
end

initial begin
    rst           = 1'b1;
    sdr_init_req  = 1'b0;
    sdr_init_mode = 4'b0000;
    sdr_rw_vld    = 1'b0;

    repeat (8) @(posedge clk);
    rst = 1'b0;

    // Covers power-up counter, initialization sequence and five refresh gaps.
    repeat (180000) @(posedge clk);
    $fatal(1, "timeout waiting for five refresh requests");
end

endmodule
