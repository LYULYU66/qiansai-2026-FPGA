`timescale 1ns/1ps

module tb_hdmi_audio_chain;

reg audio_mclk = 1'b0;
reg video_clk = 1'b0;
reg rst = 1'b1;

wire i2s_bclk;
wire i2s_lrck;
wire i2s_dout;
wire audio_valid;
wire [23:0] audio_left_data;
wire [23:0] audio_right_data;
wire acr_valid;
wire [19:0] acr_cts;
wire [19:0] acr_n;

integer video_cycles = 0;
integer sample_count = 0;
integer nonzero_count = 0;
integer acr_count = 0;
integer last_sample_cycle = -1;
integer sample_gap;

// 精确仿真 12.288 MHz 音频主时钟和 25 MHz HDMI 像素时钟。
always #40.690104 audio_mclk = ~audio_mclk;
always #20.000000 video_clk = ~video_clk;

hdmi_audio_tone_i2s_64fs #(
    .NOTE_HOLD_FRAMES (32)
) u_tone (
    .I_mclk       (audio_mclk),
    .I_rst        (rst),
    .O_i2s_BCLK   (i2s_bclk),
    .O_i2s_LRCK   (i2s_lrck),
    .O_i2s_DOUT   (i2s_dout)
);

I2S_receiver u_receiver (
    .I_clk              (video_clk),
    .I_rst              (rst),
    .I_i2s_BCLK         (i2s_bclk),
    .I_i2s_LRCK         (i2s_lrck),
    .I_i2s_DOUT         (i2s_dout),
    .O_audio_valid      (audio_valid),
    .O_audio_left_data  (audio_left_data),
    .O_audio_right_data (audio_right_data)
);

audio_arc_calculate #(
    .ACR_N (6144)
) u_acr (
    .I_clk         (video_clk),
    .I_rst         (rst),
    .I_audio_valid (audio_valid),
    .O_acr_valid   (acr_valid),
    .O_acr_cts     (acr_cts),
    .O_acr_n       (acr_n)
);

always @(posedge video_clk) begin
    video_cycles <= video_cycles + 1;

    if (audio_valid) begin
        sample_count <= sample_count + 1;

        if (audio_left_data !== audio_right_data)
            $fatal(1, "left/right mismatch: left=%h right=%h", audio_left_data, audio_right_data);

        if (audio_left_data != 24'd0)
            nonzero_count <= nonzero_count + 1;

        if (last_sample_cycle >= 0) begin
            sample_gap = video_cycles - last_sample_cycle;
            // 25 MHz / 48 kHz = 520.833 拍；CDC 边沿量化允许少量抖动。
            if ((sample_gap < 518) || (sample_gap > 524))
                $fatal(1, "invalid audio sample gap: %0d video clocks", sample_gap);
        end
        last_sample_cycle <= video_cycles;
    end

    if (acr_valid) begin
        acr_count <= acr_count + 1;
        if (acr_n !== 20'd6144)
            $fatal(1, "invalid ACR N: %0d", acr_n);
        if ((acr_count > 0) && ((acr_cts < 20'd24900) || (acr_cts > 20'd25100)))
            $fatal(1, "invalid steady-state ACR CTS: %0d", acr_cts);
    end
end

initial begin
    #1000;
    rst = 1'b0;

    wait (acr_count >= 3);
    if (sample_count < 140)
        $fatal(1, "too few 48 kHz samples: %0d", sample_count);
    if (nonzero_count < 100)
        $fatal(1, "test tone did not produce enough non-zero samples: %0d", nonzero_count);

    $display("PASS samples=%0d nonzero=%0d acr=%0d last_cts=%0d n=%0d",
             sample_count, nonzero_count, acr_count, acr_cts, acr_n);
    $finish;
end

initial begin
    #5000000;
    $fatal(1, "timeout waiting for three ACR packets");
end

endmodule
