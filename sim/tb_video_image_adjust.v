`timescale 1ns/1ps

module tb_video_image_adjust;

reg         clk;
reg         rst;
reg         hs;
reg         vs;
reg         de;
reg  [23:0] rgb;
reg  [1:0]  brightness_level;
reg  [1:0]  contrast_level;
wire        out_hs;
wire        out_vs;
wire        out_de;
wire [23:0] out_rgb;

integer errors;

video_image_adjust dut (
    .I_clk              (clk),
    .I_rst              (rst),
    .I_hs               (hs),
    .I_vs               (vs),
    .I_de               (de),
    .I_rgb              (rgb),
    .I_brightness_level (brightness_level),
    .I_contrast_level   (contrast_level),
    .O_hs               (out_hs),
    .O_vs               (out_vs),
    .O_de               (out_de),
    .O_rgb              (out_rgb)
);

always #5 clk = ~clk;

task wait_cycles;
    input integer count;
    integer i;
    begin
        for (i = 0; i < count; i = i + 1)
            @(posedge clk);
        #1;
    end
endtask

task latch_new_frame;
    begin
        @(negedge clk);
        vs = 1'b1;
        @(posedge clk);
        #1;
        @(negedge clk);
        vs = 1'b0;
        @(posedge clk);
        #1;
    end
endtask

task check_pixel;
    input [23:0] stimulus;
    input [23:0] expected;
    input [255:0] label_text;
    begin
        @(negedge clk);
        hs  = 1'b1;
        de  = 1'b1;
        rgb = stimulus;
        @(posedge clk);
        #1;
        if ((out_hs !== 1'b1) || (out_de !== 1'b1) ||
            (out_rgb !== expected)) begin
            $display("FAIL %-32s hs=%b de=%b rgb=%h expected=%h",
                     label_text, out_hs, out_de, out_rgb, expected);
            errors = errors + 1;
        end else begin
            $display("PASS %-32s rgb=%h", label_text, out_rgb);
        end

        @(negedge clk);
        hs  = 1'b0;
        de  = 1'b0;
        rgb = 24'hFFFFFF;
        @(posedge clk);
        #1;
        if ((out_hs !== 1'b0) || (out_de !== 1'b0) ||
            (out_rgb !== 24'h000000)) begin
            $display("FAIL blanking pipeline hs=%b de=%b rgb=%h",
                     out_hs, out_de, out_rgb);
            errors = errors + 1;
        end
    end
endtask

initial begin
    clk              = 1'b0;
    rst              = 1'b1;
    hs               = 1'b0;
    vs               = 1'b0;
    de               = 1'b0;
    rgb              = 24'd0;
    brightness_level = 2'd3;
    contrast_level   = 2'd0;
    errors           = 0;

    wait_cycles(3);
    @(negedge clk);
    rst = 1'b0;
    wait_cycles(2);

    // Reset defaults are BRI100/CON25.  The selected test colour already
    // lies on the RGB666 grid, so the natural path remains bit-exact.
    check_pixel(24'hC86428, 24'hC86428, "BRI100/CON25 natural path");

    // The synchronizer may settle, but settings must not change mid-frame.
    @(negedge clk);
    brightness_level = 2'd2;
    contrast_level   = 2'd2;
    wait_cycles(5);
    if ((dut.brightness_stable !== 2'd2) ||
        (dut.contrast_stable !== 2'd2)) begin
        $display("FAIL controls did not cross synchronizer");
        errors = errors + 1;
    end
    if ((dut.brightness_frame !== 2'd3) ||
        (dut.contrast_frame !== 2'd0)) begin
        $display("FAIL settings changed without a frame edge");
        errors = errors + 1;
    end
    check_pixel(24'hC86428, 24'hC86428, "no mid-frame setting tear");

    // BRI75 with CON75: contrast pulls dark/bright values apart and then
    // brightness scales them.  Output low two bits remain fixed at zero.
    latch_new_frame();
    if ((dut.brightness_frame !== 2'd2) ||
        (dut.contrast_frame !== 2'd2)) begin
        $display("FAIL 75/75 settings were not frame-latched");
        errors = errors + 1;
    end
    check_pixel(24'hC86428, 24'hB04000, "75/75 mapped channels");

    // BRI50/CON50 again remain old until the next frame boundary.
    @(negedge clk);
    brightness_level = 2'd1;
    contrast_level   = 2'd1;
    wait_cycles(5);
    check_pixel(24'hC86428, 24'hB04000, "50/50 pending until frame");
    latch_new_frame();
    check_pixel(24'hC86428, 24'h6C2C08, "50/50 mapped channels");

    // BRI25 with maximum contrast retains a visible image rather than
    // treating the lowest legal brightness setting as OFF.
    @(negedge clk);
    brightness_level = 2'd0;
    contrast_level   = 2'd3;
    wait_cycles(5);
    latch_new_frame();
    check_pixel(24'hC86428, 24'h401000, "25/100 mapped channels");

    // CON25 is the neutral/reference setting at BRI100.
    @(negedge clk);
    brightness_level = 2'd3;
    contrast_level   = 2'd0;
    wait_cycles(5);
    latch_new_frame();
    check_pixel(24'hC86428, 24'hC86428, "25 contrast natural image");

    // Maximum contrast darkens the lower channels and saturates highlights.
    @(negedge clk);
    contrast_level = 2'd3;
    wait_cycles(5);
    latch_new_frame();
    check_pixel(24'hC86428, 24'hFC4800, "100 contrast expanded image");

    // Non-grid input proves the two source-colour LSBs are deterministic.
    @(negedge clk);
    contrast_level = 2'd0;
    wait_cycles(5);
    latch_new_frame();
    check_pixel(24'h7F3B19, 24'h7C3818, "RGB666 dark-colour stabilization");

    if (errors == 0)
        $display("PASS tb_video_image_adjust: all checks passed");
    else
        $display("FAIL tb_video_image_adjust: %0d error(s)", errors);

    $finish;
end

endmodule
