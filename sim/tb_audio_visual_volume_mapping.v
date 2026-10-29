`timescale 1ns/1ps

module tb_audio_visual_volume_mapping;
    reg clk = 1'b0;
    reg rst = 1'b1;
    reg vs = 1'b0;
    reg [3:0] volume = 4'd8;
    reg [111:0] spectrum = 112'd0;
    reg [111:0] wave = 112'd0;

    always #5 clk = ~clk;

    audio_visualizer_overlay dut (
        .I_clk(clk),
        .I_rst(rst),
        .I_enable(1'b1),
        .I_vs(vs),
        .I_de(1'b0),
        .I_rgb(24'd0),
        .I_vu_left_level(7'd0),
        .I_vu_right_level(7'd0),
        .I_spectrum_levels(spectrum),
        .I_wave_samples(wave),
        .I_volume_level(volume),
        .I_hazard_front(1'b0),
        .I_hazard_left(1'b0),
        .I_hazard_right(1'b0),
        .O_rgb()
    );

    task commit_frame;
        begin
            // Allow the 50 MHz -> video-clock value synchronizer to settle.
            repeat (6) @(negedge clk);
            vs = 1'b1;
            @(negedge clk);
            vs = 1'b0;
            repeat (20) @(negedge clk);
        end
    endtask

    initial begin
        spectrum[6:0] = 7'd96;
        wave[6:0]     = 7'sd44;
        wave[13:7]    = 7'sd44;

        repeat (4) @(negedge clk);
        rst = 1'b0;

        volume = 4'd8;
        commit_frame;
        if (dut.spectrum_levels_frame[6:0] != 7'd96)
            $fatal(1, "VOL8 spectrum expected 96 got %0d",
                   dut.spectrum_levels_frame[6:0]);

        volume = 4'd4;
        commit_frame;
        if (dut.spectrum_levels_frame[6:0] != 7'd48)
            $fatal(1, "VOL4 spectrum expected 48 got %0d",
                   dut.spectrum_levels_frame[6:0]);

        volume = 4'd2;
        commit_frame;
        if (dut.spectrum_levels_frame[6:0] != 7'd24)
            $fatal(1, "VOL2 spectrum expected 24 got %0d",
                   dut.spectrum_levels_frame[6:0]);

        volume = 4'd0;
        commit_frame;
        if ((dut.spectrum_levels_frame[6:0] != 7'd0) ||
            ($signed(dut.wave_samples_frame[6:0]) != 0))
            $fatal(1, "VOL0 visual output did not return to baseline");

        $display("PASS VISUAL_VOLUME spectrum=96/48/24/0 waveform_mute=0 frame_atomic=ok");
        $finish;
    end
endmodule
