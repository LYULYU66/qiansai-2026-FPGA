`timescale 1ns/1ps

module tb_video_frame_valid_gate;
reg clk = 1'b0;
reg rst = 1'b1;
reg frame_vs = 1'b0;
reg async_valid = 1'b0;
wire frame_valid;

always #5 clk = ~clk;

video_frame_valid_gate dut (
    .I_clk        (clk),
    .I_async_rst  (rst),
    .I_frame_vs   (frame_vs),
    .I_async_valid(async_valid),
    .O_frame_valid(frame_valid)
);

task falling_frame_boundary;
begin
    @(negedge clk);
    frame_vs = 1'b1;
    repeat (2) @(negedge clk);
    frame_vs = 1'b0;
    repeat (2) @(negedge clk);
end
endtask

initial begin
    repeat (4) @(negedge clk);
    rst = 1'b0;
    repeat (5) @(negedge clk);

    // Becoming valid halfway through a frame must not expose image pixels.
    async_valid = 1'b1;
    repeat (6) @(negedge clk);
    if (frame_valid)
        $fatal(1, "valid flag escaped before the frame boundary");

    falling_frame_boundary;
    if (!frame_valid)
        $fatal(1, "valid flag was not committed at the frame boundary");

    // Card loss or reload is also hidden until a clean boundary.
    async_valid = 1'b0;
    repeat (6) @(negedge clk);
    if (!frame_valid)
        $fatal(1, "frame was blanked in the middle of active video");

    falling_frame_boundary;
    if (frame_valid)
        $fatal(1, "invalid flag was not committed at the frame boundary");

    $display("PASS VIDEO_VALID frame_boundary_only startup_image1_safe");
    $finish;
end

endmodule
