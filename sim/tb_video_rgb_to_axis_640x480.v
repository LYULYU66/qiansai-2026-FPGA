`timescale 1ns/1ps

module tb_video_rgb_to_axis_640x480;

reg         clk = 1'b0;
reg         rst = 1'b1;
reg         vs  = 1'b0;
reg         de  = 1'b0;
reg  [23:0] rgb = 24'd0;

wire        user;
wire        valid;
wire        last;
wire [23:0] data;

integer source_x;
integer valid_count;
integer user_count;
integer last_count;
integer last_position;

always #5 clk = ~clk;

video_rgb_to_axis_640x480 dut (
    .I_clk         (clk),
    .I_rst         (rst),
    .I_vs          (vs),
    .I_de          (de),
    .I_rgb         (rgb),
    .O_video_user  (user),
    .O_video_valid (valid),
    .O_video_last  (last),
    .O_video_data  (data)
);

always @(posedge clk) begin
    #1;
    if (valid) begin
        valid_count = valid_count + 1;
        if (user)
            user_count = user_count + 1;
        if (last) begin
            last_count = last_count + 1;
            last_position = valid_count;
        end
        if (data !== (24'h120000 + valid_count - 1))
            $fatal(1, "pixel mismatch pos=%0d data=%h", valid_count, data);
    end else if (user || last) begin
        $fatal(1, "USER/LAST asserted without VALID");
    end
end

initial begin
    source_x     = 0;
    valid_count  = 0;
    user_count   = 0;
    last_count   = 0;
    last_position= 0;

    repeat (4) @(posedge clk);
    rst = 1'b0;

    // Arm the next active pixel as start-of-frame.
    @(negedge clk); vs = 1'b1;
    @(negedge clk); vs = 1'b0;
    repeat (3) @(negedge clk);

    de = 1'b1;
    for (source_x = 0; source_x < 640; source_x = source_x + 1) begin
        rgb = 24'h120000 + source_x;
        @(negedge clk);
    end
    de = 1'b0;
    rgb = 24'd0;
    repeat (3) @(negedge clk);

    if (valid_count != 640)
        $fatal(1, "expected 640 pixels, got %0d", valid_count);
    if (user_count != 1)
        $fatal(1, "expected one SOF USER, got %0d", user_count);
    if (last_count != 1 || last_position != 640)
        $fatal(1, "TLAST mismatch count=%0d position=%0d", last_count, last_position);

    $display("PASS AXIS_FRAME pixels=%0d user=%0d last_pos=%0d",
             valid_count, user_count, last_position);
    $finish;
end

endmodule
