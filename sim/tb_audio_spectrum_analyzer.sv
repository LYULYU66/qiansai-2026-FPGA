`timescale 1ns/1ps

module tb_audio_spectrum_analyzer;
    reg clk = 1'b0;
    reg rst = 1'b1;
    reg enable = 1'b0;
    reg audio_valid = 1'b0;
    reg [23:0] audio_left = 24'd0;
    reg [23:0] audio_right = 24'd0;
    wire [6:0] vu_left;
    wire [6:0] vu_right;
    wire [111:0] bands;

    integer n;
    integer left_sample;
    integer right_sample;
    integer max_band;
    integer max_level;
    integer second_level;
    integer level;
    real angle;

    always #5 clk = ~clk;

    audio_spectrum_analyzer dut (
        .I_clk(clk),
        .I_rst(rst),
        .I_enable(enable),
        .I_audio_valid(audio_valid),
        .I_audio_left(audio_left),
        .I_audio_right(audio_right),
        .O_vu_left_level(vu_left),
        .O_vu_right_level(vu_right),
        .O_band_levels(bands)
    );

    task send_stereo_sample;
        input integer sample_l;
        input integer sample_r;
        begin
            @(negedge clk);
            audio_left  = {sample_l[15:0], 8'd0};
            audio_right = {sample_r[15:0], 8'd0};
            audio_valid = 1'b1;
            @(negedge clk);
            audio_valid = 1'b0;
            // Actual 25MHz/48kHz cadence, not the earlier artificial 100 clocks.
            repeat (519) @(negedge clk);
        end
    endtask

    initial begin
        repeat (5) @(negedge clk);
        rst = 1'b0;
        enable = 1'b1;

        // Three 256-sample blocks at FFT bin 16 = 3 kHz.  The left channel
        // is exactly twice the right channel to exercise both VU outputs.
        for (n = 0; n < 768; n = n + 1) begin
            angle = 2.0 * 3.141592653589793 * 16.0 * n / 256.0;
            left_sample  = $rtoi(12000.0 * $sin(angle));
            right_sample = $rtoi( 6000.0 * $sin(angle));
            send_stereo_sample(left_sample, right_sample);
        end

        repeat (200) @(negedge clk);

        max_band = 0;
        max_level = 0;
        second_level = 0;
        for (n = 0; n < 16; n = n + 1) begin
            level = bands[n*7 +: 7];
            $display("BAND[%0d]=%0d", n, level);
            if (level > max_level) begin
                second_level = max_level;
                max_level = level;
                max_band = n;
            end else if (level > second_level) begin
                second_level = level;
            end
        end
        $display("VU_L=%0d VU_R=%0d MAX_BAND=%0d MAX=%0d SECOND=%0d",
                 vu_left, vu_right, max_band, max_level, second_level);

        if (max_band != 8) begin
            $display("FAIL expected 3 kHz at band 8");
            $fatal(1);
        end
        if (max_level < second_level + 10) begin
            $display("FAIL target band is not sufficiently dominant");
            $fatal(1);
        end
        if (!(vu_left > vu_right && vu_right > 0)) begin
            $display("FAIL stereo VU relationship is incorrect");
            $fatal(1);
        end

        $display("PASS audio spectrum analyser");
        $finish;
    end
endmodule
