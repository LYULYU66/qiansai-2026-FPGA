`timescale 1ns/1ps

module tb_audio_waveform_analyzer;
    reg clk = 1'b0;
    reg rst = 1'b1;
    reg enable = 1'b0;
    reg audio_valid = 1'b0;
    reg [23:0] audio_left = 24'd0;
    reg [23:0] audio_right = 24'd0;
    wire [6:0] vu_left;
    wire [6:0] vu_right;
    wire [111:0] wave_samples;

    integer n;
    integer left_sample;
    integer right_sample;
    integer point_value;
    integer positive_count;
    integer negative_count;
    integer publication_count;
    integer max_publication_step;
    integer old_point_value;
    integer new_point_value;
    integer publication_step;
    integer p;
    reg [111:0] previous_wave_samples;
    real angle;

    always #5 clk = ~clk;

    audio_waveform_analyzer dut (
        .I_clk(clk),
        .I_rst(rst),
        .I_enable(enable),
        .I_audio_valid(audio_valid),
        .I_audio_left(audio_left),
        .I_audio_right(audio_right),
        .O_vu_left_level(vu_left),
        .O_vu_right_level(vu_right),
        .O_wave_samples(wave_samples)
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
            repeat (18) @(negedge clk);
        end
    endtask

    initial begin
        repeat (5) @(negedge clk);
        rst = 1'b0;
        enable = 1'b1;
        publication_count = 0;
        max_publication_step = 0;
        previous_wave_samples = 112'd0;

        // 1 kHz stereo tone, left amplitude twice right amplitude.
        for (n = 0; n < 768; n = n + 1) begin
            angle = 2.0 * 3.141592653589793 * 1000.0 * n / 48000.0;
            left_sample  = $rtoi(12000.0 * $sin(angle));
            right_sample = $rtoi( 6000.0 * $sin(angle));
            send_stereo_sample(left_sample, right_sample);
            if (wave_samples !== previous_wave_samples) begin
                publication_count = publication_count + 1;
                for (p = 0; p < 16; p = p + 1) begin
                    old_point_value = $signed(previous_wave_samples[p*7 +: 7]);
                    new_point_value = $signed(wave_samples[p*7 +: 7]);
                    publication_step = new_point_value - old_point_value;
                    if (publication_step < 0)
                        publication_step = -publication_step;
                    if (publication_step > max_publication_step)
                        max_publication_step = publication_step;
                end
                previous_wave_samples = wave_samples;
            end
        end

        repeat (20) @(negedge clk);
        positive_count = 0;
        negative_count = 0;
        for (n = 0; n < 16; n = n + 1) begin
            point_value = $signed(wave_samples[n*7 +: 7]);
            $display("WAVE[%0d]=%0d", n, point_value);
            if (point_value > 0) positive_count = positive_count + 1;
            if (point_value < 0) negative_count = negative_count + 1;
        end
        $display("VU_L=%0d VU_R=%0d POS=%0d NEG=%0d PUB=%0d MAX_STEP=%0d",
                 vu_left, vu_right, positive_count, negative_count,
                 publication_count, max_publication_step);

        if (!(vu_left > vu_right && vu_right > 0)) begin
            $display("FAIL stereo VU relationship is incorrect");
            $fatal(1);
        end
        if ((positive_count == 0) || (negative_count == 0)) begin
            $display("FAIL waveform does not cross the reference line");
            $fatal(1);
        end
        if (publication_count < 2) begin
            $display("FAIL waveform was not refreshed repeatedly");
            $fatal(1);
        end
        if (max_publication_step > 22) begin
            $display("FAIL temporal smoothing allowed a jump greater than 22");
            $fatal(1);
        end
        $display("PASS audio waveform analyser");
        $finish;
    end
endmodule
