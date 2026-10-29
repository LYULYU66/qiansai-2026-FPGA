`timescale 1ns/1ps

module tb_audio_alarm_mixer;

reg clk = 1'b0;
reg rst = 1'b1;
reg audio_valid = 1'b0;
reg [23:0] audio_left = 24'd0;
reg [23:0] audio_right = 24'd0;
reg hazard_front = 1'b0;
reg hazard_left = 1'b0;
reg hazard_right = 1'b0;
wire output_valid;
wire [23:0] output_left;
wire [23:0] output_right;

integer valid_outputs = 0;
integer nonzero_left = 0;
integer nonzero_right = 0;
integer directional_good = 0;
integer sample_index;
reg signed [23:0] signed_left;
reg signed [23:0] signed_right;

always #20 clk = ~clk; // representative 25 MHz processing clock

audio_alarm_mixer dut (
    .I_clk(clk),
    .I_rst(rst),
    .I_audio_valid(audio_valid),
    .I_audio_left(audio_left),
    .I_audio_right(audio_right),
    .I_hazard_front(hazard_front),
    .I_hazard_left(hazard_left),
    .I_hazard_right(hazard_right),
    .O_audio_valid(output_valid),
    .O_audio_left(output_left),
    .O_audio_right(output_right)
);

task send_sample;
    input [23:0] left_value;
    input [23:0] right_value;
    begin
        @(negedge clk);
        audio_left  = left_value;
        audio_right = right_value;
        audio_valid = 1'b1;
        @(negedge clk);
        audio_valid = 1'b0;
        audio_left  = 24'd0;
        audio_right = 24'd0;
        // Leave several processing clocks between 48 kHz-equivalent samples.
        repeat (3) @(negedge clk);
    end
endtask

task expect_sample;
    input [23:0] expected_left;
    input [23:0] expected_right;
    begin
        wait (output_valid);
        #1;
        if ((output_left !== expected_left) ||
            (output_right !== expected_right))
            $fatal(1, "sample mismatch L=%h/%h R=%h/%h",
                   output_left, expected_left, output_right, expected_right);
        wait (!output_valid);
    end
endtask

initial begin
    repeat (5) @(posedge clk);
    rst = 1'b0;

    // Normal mode is transparent for positive and negative signed PCM.
    fork
        send_sample(24'h400000, 24'hc00000);
        expect_sample(24'h400000, 24'hc00000);
    join

    // Duck ratios can be checked before the 2 ms alarm envelope rises.
    hazard_right = 1'b1;
    fork
        send_sample(24'h400000, 24'hc00000);
        expect_sample(24'h200000, 24'he00000); // single side = 1/2
    join

    hazard_left = 1'b1; // left+right = both, above either single-side mode
    fork
        send_sample(24'h400000, 24'hc00000);
        expect_sample(24'h100000, 24'hf00000); // both = 1/4
    join

    hazard_front = 1'b1; // front overrides both side inputs
    fork
        send_sample(24'h400000, 24'hc00000);
        expect_sample(24'h080000, 24'hf80000); // front = 1/8
    join

    // Let the front tone ramp up.  A muted programme must still produce a
    // centered audible alarm, proving independence from the music volume.
    audio_left = 24'd0;
    audio_right = 24'd0;
    for (sample_index = 0; sample_index < 180; sample_index = sample_index + 1) begin
        send_sample(24'd0, 24'd0);
        if (output_valid) begin
            $fatal(1, "testbench sampled valid at unexpected phase");
        end
        if ((output_left != 24'd0) || (output_right != 24'd0)) begin
            nonzero_left = nonzero_left + (output_left != 24'd0);
            nonzero_right = nonzero_right + (output_right != 24'd0);
            if (output_left !== output_right)
                $fatal(1, "front alarm is not centered L=%h R=%h",
                       output_left, output_right);
        end
    end
    if ((nonzero_left == 0) || (nonzero_right == 0))
        $fatal(1, "front alarm remained silent over muted programme");

    // Remove front and right: left must win and be four times stronger than
    // the opposite channel once its envelope reaches full level.
    hazard_front = 1'b0;
    hazard_right = 1'b0;
    nonzero_left = 0;
    nonzero_right = 0;
    directional_good = 0;
    for (sample_index = 0; sample_index < 180; sample_index = sample_index + 1) begin
        send_sample(24'd0, 24'd0);
        signed_left = output_left;
        signed_right = output_right;
        if ((signed_left != 0) || (signed_right != 0)) begin
            nonzero_left = nonzero_left + (signed_left != 0);
            nonzero_right = nonzero_right + (signed_right != 0);
            if (signed_left == (signed_right <<< 2))
                directional_good = directional_good + 1;
        end
    end
    if ((nonzero_left == 0) || (nonzero_right == 0) ||
        (directional_good == 0))
        $fatal(1, "left directional alarm missing L=%0d R=%0d ratio=%0d",
               nonzero_left, nonzero_right, directional_good);

    // Directly exercise the defensive 25-to-24-bit saturator with values
    // beyond both rails.  The normal configured mix stays below these rails.
    if (dut.saturate_24(25'sd9000000) !== 24'h7fffff)
        $fatal(1, "positive saturation failed");
    if (dut.saturate_24(-25'sd9000000) !== 24'h800000)
        $fatal(1, "negative saturation failed");

    // Right-only mode must mirror the channel emphasis.
    hazard_left = 1'b0;
    hazard_right = 1'b1;
    directional_good = 0;
    for (sample_index = 0; sample_index < 180; sample_index = sample_index + 1) begin
        send_sample(24'd0, 24'd0);
        signed_left = output_left;
        signed_right = output_right;
        if ((signed_left != 0) || (signed_right != 0)) begin
            if (signed_right == (signed_left <<< 2))
                directional_good = directional_good + 1;
        end
    end
    if (directional_good == 0)
        $fatal(1, "right directional alarm missing");

    $display("PASS audio_alarm_mixer priority=ok duck=ok muted_alarm=ok stereo=ok saturation=ok");
    $finish;
end

always @(posedge clk)
    if (output_valid)
        valid_outputs <= valid_outputs + 1;

initial begin
    #10000000;
    $fatal(1, "timeout valid_outputs=%0d", valid_outputs);
end

endmodule
