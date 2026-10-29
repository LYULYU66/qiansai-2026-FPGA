`timescale 1ns/1ps

module tb_vehicle_hazard_overlay;

localparam integer H_ACTIVE     = 16;
localparam integer V_ACTIVE     = 12;
localparam integer BORDER_WIDTH = 2;

localparam [23:0] FRONT_BRIGHT = 24'hFF1838;
localparam [23:0] FRONT_DIM    = 24'h600008;
localparam [23:0] LEFT_BRIGHT  = 24'hFF6A00;
localparam [23:0] LEFT_DIM     = 24'h682000;
localparam [23:0] RIGHT_BRIGHT = 24'hFFD000;
localparam [23:0] RIGHT_DIM    = 24'h685000;

reg         clk;
reg         rst;
reg         vs;
reg         de;
reg  [23:0] rgb;
reg         hazard_front;
reg         hazard_left;
reg         hazard_right;
wire [23:0] rgb_out;

integer errors;
integer x;
integer y;
reg [23:0] expected;
reg [23:0] source_pixel;

vehicle_hazard_overlay #(
    .H_ACTIVE        (H_ACTIVE),
    .V_ACTIVE        (V_ACTIVE),
    .BORDER_WIDTH    (BORDER_WIDTH),
    // Short periods keep the self-checking simulation compact.
    .FRONT_FLASH_BIT (0),
    .SIDE_FLASH_BIT  (1),
    .FRONT_BRIGHT    (FRONT_BRIGHT),
    .FRONT_DIM       (FRONT_DIM),
    .LEFT_BRIGHT     (LEFT_BRIGHT),
    .LEFT_DIM        (LEFT_DIM),
    .RIGHT_BRIGHT    (RIGHT_BRIGHT),
    .RIGHT_DIM       (RIGHT_DIM)
) dut (
    .I_clk          (clk),
    .I_rst          (rst),
    .I_vs           (vs),
    .I_de           (de),
    .I_rgb          (rgb),
    .I_warning_page (1'b0),
    .I_hazard_front (hazard_front),
    .I_hazard_left  (hazard_left),
    .I_hazard_right (hazard_right),
    .I_hazard_rear  (1'b0),
    .O_rgb          (rgb_out)
);

always #5 clk = ~clk;

task tick;
    begin
        @(posedge clk);
        #1;
    end
endtask

task blank_tick;
    input [23:0] blank_rgb;
    begin
        de  = 1'b0;
        rgb = blank_rgb;
        tick;
        if (rgb_out !== blank_rgb) begin
            $display("FAIL blank pass-through got=%h expected=%h at %0t",
                     rgb_out, blank_rgb, $time);
            errors = errors + 1;
        end
    end
endtask

task wait_switch_sync;
    begin
        // Two stages plus margin, all outside active video.
        blank_tick(24'hA5_5A_3C);
        blank_tick(24'hA5_5A_3C);
        blank_tick(24'hA5_5A_3C);
        blank_tick(24'hA5_5A_3C);
    end
endtask

task pulse_frame_start;
    begin
        de  = 1'b0;
        rgb = 24'h12_34_56;
        vs  = 1'b1;
        tick;
        // Keeping VS high for another cycle must not create a second frame.
        tick;
        vs = 1'b0;
        tick;
    end
endtask

task check_frame;
    input exp_front;
    input exp_left;
    input exp_right;
    input exp_bright;
    begin
        pulse_frame_start;
        for (y = 0; y < V_ACTIVE; y = y + 1) begin
            for (x = 0; x < H_ACTIVE; x = x + 1) begin
                source_pixel = {8'h20 + y[7:0],
                                8'h30 + x[7:0],
                                8'h40 + x[7:0] + y[7:0]};
                de  = 1'b1;
                rgb = source_pixel;
                tick;

                if (exp_front && (y < BORDER_WIDTH))
                    expected = exp_bright ? FRONT_BRIGHT : FRONT_DIM;
                else if (exp_left && (x < BORDER_WIDTH))
                    expected = exp_bright ? LEFT_BRIGHT : LEFT_DIM;
                else if (exp_right && (x >= H_ACTIVE - BORDER_WIDTH))
                    expected = exp_bright ? RIGHT_BRIGHT : RIGHT_DIM;
                else
                    expected = source_pixel;

                if (rgb_out !== expected) begin
                    $display("FAIL pixel x=%0d y=%0d got=%h expected=%h F/L/R=%b%b%b bright=%b",
                             x, y, rgb_out, expected,
                             exp_front, exp_left, exp_right, exp_bright);
                    errors = errors + 1;
                end
            end
            blank_tick(24'h55_AA_0F);
        end
    end
endtask

task check_midframe_assertion;
    begin
        pulse_frame_start;
        for (y = 0; y < V_ACTIVE; y = y + 1) begin
            for (x = 0; x < H_ACTIVE; x = x + 1) begin
                if ((y == 4) && (x == 5))
                    hazard_front = 1'b1;

                source_pixel = {8'h70 + y[7:0],
                                8'h80 + x[7:0],
                                8'h10 + x[7:0] + y[7:0]};
                de  = 1'b1;
                rgb = source_pixel;
                tick;
                if (rgb_out !== source_pixel) begin
                    $display("FAIL mid-frame hazard changed current frame x=%0d y=%0d got=%h expected=%h",
                             x, y, rgb_out, source_pixel);
                    errors = errors + 1;
                end
            end
            blank_tick(24'hC3_3C_5A);
        end
    end
endtask

initial begin
    clk          = 1'b0;
    rst          = 1'b1;
    vs           = 1'b0;
    de           = 1'b0;
    rgb          = 24'h00_00_00;
    hazard_front = 1'b0;
    hazard_left  = 1'b0;
    hazard_right = 1'b0;
    errors       = 0;

    repeat (4) tick;
    rst = 1'b0;
    wait_switch_sync;

    // No warning must be a bit-exact transparent path.
    check_frame(1'b0, 1'b0, 1'b0, 1'b1);

    // An asynchronous change in active video is synchronized immediately but
    // may only become visible after the following VS frame boundary.
    check_midframe_assertion;
    wait_switch_sync;
    check_frame(1'b1, 1'b0, 1'b0, 1'b1);

    // With FRONT_FLASH_BIT=0, the next unchanged frame is the dim phase.
    check_frame(1'b1, 1'b0, 1'b0, 1'b0);

    // Simultaneous side warnings use the slower flash selection.  The first
    // two frames are bright, followed by a dim frame with SIDE_FLASH_BIT=1.
    hazard_front = 1'b0;
    hazard_left  = 1'b1;
    hazard_right = 1'b1;
    wait_switch_sync;
    check_frame(1'b0, 1'b1, 1'b1, 1'b1);
    check_frame(1'b0, 1'b1, 1'b1, 1'b1);
    check_frame(1'b0, 1'b1, 1'b1, 1'b0);

    // Front danger raises the shared rate while preserving both side bars.
    // The expected order also verifies front priority at both top corners.
    hazard_front = 1'b1;
    wait_switch_sync;
    check_frame(1'b1, 1'b1, 1'b1, 1'b1);
    check_frame(1'b1, 1'b1, 1'b1, 1'b0);

    // A black source still receives the warning; TF/image readiness is not an
    // enable condition.  Outside DE the same input remains strictly unchanged.
    pulse_frame_start;
    de  = 1'b1;
    rgb = 24'h00_00_00;
    tick;
    if (rgb_out !== FRONT_BRIGHT) begin
        $display("FAIL warning was not visible over black source got=%h", rgb_out);
        errors = errors + 1;
    end
    de  = 1'b0;
    rgb = 24'hDE_AD_BE;
    #1;
    if (rgb_out !== 24'hDE_AD_BE) begin
        $display("FAIL DE=0 combinational pass-through got=%h", rgb_out);
        errors = errors + 1;
    end

    // Clearing every warning is also committed atomically at a frame edge.
    hazard_front = 1'b0;
    hazard_left  = 1'b0;
    hazard_right = 1'b0;
    wait_switch_sync;
    check_frame(1'b0, 1'b0, 1'b0, 1'b1);

    if (errors == 0)
        $display("PASS vehicle_hazard_overlay: frame lock, priority, simultaneous borders and flash rates");
    else
        $fatal(1, "vehicle_hazard_overlay failed with %0d errors", errors);

    $finish;
end

endmodule
