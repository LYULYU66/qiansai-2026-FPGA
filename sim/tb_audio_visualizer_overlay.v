`timescale 1ns/1ps

module tb_audio_visualizer_overlay;
    reg clk = 1'b0;
    reg rst = 1'b1;
    reg enable = 1'b1;
    reg vs = 1'b0;
    reg de = 1'b0;
    reg [23:0] rgb = 24'h808080;
    reg [6:0] vu_left = 7'd96;
    reg [6:0] vu_right = 7'd48;
    reg [111:0] spectrum_levels = 112'd0;
    reg [111:0] wave_samples = 112'd0;
    reg [3:0] volume_level = 4'd8;
    reg hazard_front = 1'b0;
    reg hazard_left = 1'b0;
    reg hazard_right = 1'b0;
    wire [23:0] rgb_out;
    integer x;
    integer y;
    integer errors;

    always #5 clk = ~clk;

    audio_visualizer_overlay dut (
        .I_clk(clk),
        .I_rst(rst),
        .I_enable(enable),
        .I_vs(vs),
        .I_de(de),
        .I_rgb(rgb),
        .I_vu_left_level(vu_left),
        .I_vu_right_level(vu_right),
        .I_spectrum_levels(spectrum_levels),
        .I_wave_samples(wave_samples),
        .I_volume_level(volume_level),
        .I_hazard_front(hazard_front),
        .I_hazard_left(hazard_left),
        .I_hazard_right(hazard_right),
        .O_rgb(rgb_out)
    );

    task expect_rgb;
        input [23:0] expected;
        input [127:0] name;
        begin
            if (rgb_out !== expected) begin
                $display("FAIL %s x=%0d y=%0d got=%h expected=%h",
                         name, x, y, rgb_out, expected);
                errors = errors + 1;
            end
        end
    endtask

    task check_pixel;
        input [10:0] check_x;
        input [9:0] check_y;
        input [23:0] expected;
        input [127:0] name;
        begin
            force dut.pixel_x = check_x;
            force dut.pixel_y = check_y;
            de = 1'b1;
            #1;
            x = check_x;
            y = check_y;
            expect_rgb(expected, name);
            de = 1'b0;
            release dut.pixel_x;
            release dut.pixel_y;
            #1;
        end
    endtask

    task next_video_frame;
        begin
            @(negedge clk);
            vs = 1'b1;
            @(negedge clk);
            vs = 1'b0;
            // The low-resource smoother deliberately reuses one datapath for
            // all sixteen points during vertical blanking.
            repeat (20) @(negedge clk);
        end
    endtask

    initial begin
        errors = 0;
        spectrum_levels[6:0] = 7'd96;
        spectrum_levels[13:7] = 7'd48;
        // Broad positive/negative regions let the three-point spatial filter
        // preserve both lobes while rejecting isolated spikes.
        wave_samples[6:0]   = 7'sd44;
        wave_samples[13:7]  = 7'sd44;
        wave_samples[20:14] = 7'sd44;
        wave_samples[27:21] = 7'sd44;
        wave_samples[55:49] = -7'sd32;
        wave_samples[62:56] = -7'sd32;
        wave_samples[69:63] = -7'sd32;
        wave_samples[76:70] = -7'sd32;

        repeat (4) @(negedge clk);
        rst = 1'b0;
        next_video_frame;

        // Visual gain is intentionally linear and multiplier-free.  The
        // analyser input has already followed the audio gain, so these checks
        // guarantee a clearly visible second-stage 0..8 height separation.
        if ((dut.scale_unsigned_by_volume(7'd96, 4'd8) != 7'd96) ||
            (dut.scale_unsigned_by_volume(7'd96, 4'd4) != 7'd48) ||
            (dut.scale_unsigned_by_volume(7'd96, 4'd2) != 7'd24) ||
            (dut.scale_unsigned_by_volume(7'd96, 4'd0) != 7'd0))
            $fatal(1, "spectrum volume mapping failed");
        if (($signed(dut.scale_signed_by_volume(7'sd44, 4'd8)) != 44) ||
            ($signed(dut.scale_signed_by_volume(7'sd44, 4'd4)) != 22) ||
            ($signed(dut.scale_signed_by_volume(-7'sd32, 4'd2)) != -8) ||
            ($signed(dut.scale_signed_by_volume(7'sd44, 4'd0)) != 0))
            $fatal(1, "waveform volume mapping failed");

        if (($signed(dut.scale_wave_vertical(7'sd24, 4'd8)) != 21) ||
            ($signed(dut.scale_wave_vertical(7'sd24, 4'd7)) != 18) ||
            ($signed(dut.scale_wave_vertical(7'sd24, 4'd6)) != 15) ||
            ($signed(dut.scale_wave_vertical(7'sd44, 4'd8)) != 32) ||
            ($signed(dut.scale_wave_vertical(-7'sd44, 4'd8)) != -32))
            $fatal(1, "wave vertical boost/saturation failed");

        if (($signed(dut.wave_samples_frame[6:0]) != 3) ||
            ($signed(dut.wave_samples_frame[62:56]) != -3))
            $fatal(1, "first-frame slew limit failed pos=%0d neg=%0d",
                   $signed(dut.wave_samples_frame[6:0]),
                   $signed(dut.wave_samples_frame[62:56]));
        next_video_frame;
        next_video_frame;
        if (($signed(dut.wave_samples_frame[6:0]) != 9) ||
            ($signed(dut.wave_samples_frame[62:56]) != -8))
            $fatal(1, "frame-domain smoothing failed pos=%0d neg=%0d",
                   $signed(dut.wave_samples_frame[6:0]),
                   $signed(dut.wave_samples_frame[62:56]));

        for (y = 0; y < 436; y = y + 1) begin
            de = 1'b1;
            for (x = 0; x < 640; x = x + 1) begin
                @(negedge clk);
                if ((x == 200) && (y == 290))
                    expect_rgb(24'h808080, "no grey panel");
                if ((x == 40) && (y == 320))
                    expect_rgb(24'hFF3B30, "left VU red");
                if ((x == 594) && (y == 360))
                    expect_rgb(24'h25D366, "right VU green");
                if ((x == 72) && (y == 334))
                    expect_rgb(24'hD8FFFF, "spectrum bright tip");
                if ((x == 86) && (y == 360))
                    expect_rgb(24'h18C8FF, "spectrum cyan fill");
                if ((x == 334) && (y == 345))
                    expect_rgb(24'h39FF5A, "positive bright dash");
                if ((x == 346) && (y == 349))
                    expect_rgb(24'h808080, "wave dash gap");
                if ((x == 462) && (y == 362))
                    expect_rgb(24'h39FF5A, "negative bright dash");
                if ((x == 333) && (y == 347))
                    expect_rgb(24'h12C93D, "near green glow");
                if ((x == 333) && (y == 343))
                    expect_rgb(24'h064A1C, "far green glow");
                if ((x == 334) && (y == 348))
                    expect_rgb(24'h08752A, "previous-frame trail");
                if ((x == 585) && (y == 354))
                    expect_rgb(24'hFFFFFF, "white reference line");
                if ((x == 320) && (y == 330))
                    expect_rgb(24'hB8D7E5, "center separator");
                if ((x == 200) && (y == 435))
                    expect_rgb(24'h808080, "subtitle pass through");
            end
            de = 1'b0;
            @(negedge clk);
        end

        // A switch change cannot recolor part of the current frame.
        hazard_left = 1'b1;
        check_pixel(11'd40, 10'd320, 24'hFF3B30,
                    "left warning waits VS");
        next_video_frame;
        check_pixel(11'd40, 10'd320, 24'hFF6A00,
                    "left warning VU");
        check_pixel(11'd33, 10'd320, 24'hFF6A00,
                    "left warning outline");
        check_pixel(11'd594, 10'd320, 24'h14232B,
                    "right normal during left");

        hazard_left = 1'b0;
        hazard_right = 1'b1;
        next_video_frame;
        check_pixel(11'd594, 10'd320, 24'hFFD000,
                    "right warning VU");
        check_pixel(11'd605, 10'd320, 24'hFFD000,
                    "right warning outline");
        check_pixel(11'd40, 10'd320, 24'hFF3B30,
                    "left normal during right");

        hazard_front = 1'b1;
        next_video_frame;
        check_pixel(11'd40, 10'd320, 24'hFF1838,
                    "front warning left VU");
        check_pixel(11'd594, 10'd320, 24'hFF1838,
                    "front warning right VU");

        // Exhaustively compare the new pitch-16 decoder against the original
        // unrolled range equations at every horizontal pixel.
        for (x = 0; x < 640; x = x + 1) begin
            force dut.pixel_x = x;
            #1;
            if (dut.wave_x_hit !==
                ((x >= 334) && (x < 590) && ((x - 334) % 16 < 10))) begin
                $display("FAIL waveform core decoder x=%0d", x);
                errors = errors + 1;
            end
            if (dut.wave_x_glow_hit !==
                ((x >= 333) && (x < 589) && ((x - 333) % 16 < 12))) begin
                $display("FAIL waveform glow decoder x=%0d", x);
                errors = errors + 1;
            end
            if (dut.wave_x_glow_hit &&
                dut.wave_index !== ((x - 333) / 16)) begin
                $display("FAIL waveform point index x=%0d", x);
                errors = errors + 1;
            end
            release dut.pixel_x;
        end

        if (errors == 0)
            $display("PASS audio visualizer overlay geometry and hazards");
        else
            $fatal(1, "overlay errors=%0d", errors);
        $finish;
    end
endmodule
