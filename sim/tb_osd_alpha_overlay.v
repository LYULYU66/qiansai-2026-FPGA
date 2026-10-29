`timescale 1ns/1ps

module tb_osd_alpha_overlay;

reg         clk = 1'b0;
reg         rst = 1'b1;
reg         enable = 1'b0;
reg         vs = 1'b0;
reg         de = 1'b0;
reg  [23:0] rgb_in = 24'h204060;
wire [23:0] rgb_out;

integer x;
integer y;
integer panel_checks = 0;
integer text_checks = 0;
integer ascii_pixels = 0;
integer chinese_pixels = 0;

always #20 clk = ~clk;

osd_alpha_overlay dut (
    .I_clk    (clk),
    .I_rst    (rst),
    .I_enable (enable),
    .I_vs     (vs),
    .I_de     (de),
    .I_rgb    (rgb_in),
    .O_rgb    (rgb_out)
);

task clock_input;
    input        de_value;
    input [23:0] rgb_value;
    begin
        @(negedge clk);
        de     = de_value;
        rgb_in = rgb_value;
        @(posedge clk);
        #1;
    end
endtask

task pulse_frame;
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

initial begin
    repeat (4) @(posedge clk);
    @(negedge clk);
    rst = 1'b0;

    // 关闭 OSD 时必须逐像素直通。
    clock_input(1'b1, 24'h123456);
    if (rgb_out !== 24'h123456)
        $fatal(1, "disabled OSD changed RGB: %h", rgb_out);
    clock_input(1'b0, 24'h204060);

    enable = 1'b1;
    // 文字从 x=640 开始向左滚动；200 帧后左边缘为 x=440。
    // 此时 ASCII 和第一个汉字都已进入画面，便于同时验证。
    repeat (200) pulse_frame();
    if (dut.scroll_phase !== 11'd200)
        $fatal(1, "scroll phase mismatch before pixel checks");

    // 跑到缩小后的标语区域，检查固定全宽白条、Alpha、ASCII 与中文字模。
    for (y = 0; y <= 452; y = y + 1) begin
        for (x = 0; x < 640; x = x + 1) begin
            clock_input(1'b1, 24'h204060);

            if ((y == 423) && (x == 0) && (rgb_out !== 24'h204060))
                $fatal(1, "pixel above fixed panel was modified: %h", rgb_out);

            if ((y == 424) && ((x == 0) || (x == 639))) begin
                panel_checks = panel_checks + 1;
                if (rgb_out !== 24'hC8D0D8)
                    $fatal(1, "full-width white alpha blend mismatch x=%0d: %h", x, rgb_out);
            end

            if ((y == 452) && (x == 0) && (rgb_out !== 24'h204060))
                $fatal(1, "pixel below fixed panel was modified: %h", rgb_out);

            // phase=200: F starts at x=440, 创 at x=520. Count solid
            // strokes over each glyph cell; exact bearings are font-specific.
            if ((y >= 430) && (y < 446) &&
                (rgb_out == 24'h0C0D0D)) begin
                if ((x >= 440) && (x < 456)) ascii_pixels = ascii_pixels + 1;
                if ((x >= 520) && (x < 536)) chinese_pixels = chinese_pixels + 1;
            end
        end
        clock_input(1'b0, 24'h204060);
    end

    // 下一帧继续左移，并验证完全离开左侧后从右侧重新开始。
    pulse_frame();
    if (dut.scroll_phase !== 11'd201)
        $fatal(1, "next left-scroll step mismatch");
    repeat (638) pulse_frame();
    if (dut.scroll_phase !== 11'd839)
        $fatal(1, "last scroll phase mismatch");
    pulse_frame();
    if (dut.scroll_phase !== 11'd0)
        $fatal(1, "scroll wrap mismatch");

    text_checks = ascii_pixels + chinese_pixels;
    if ((panel_checks != 2) || (ascii_pixels < 10) || (chinese_pixels < 10))
        $fatal(1, "coverage mismatch panel=%0d ASCII=%0d Chinese=%0d",
               panel_checks, ascii_pixels, chinese_pixels);

    $display("PASS OSD fixed_bar=%0d text=%0d phase=200->201 wrap=839->0", panel_checks, text_checks);
    $finish;
end

endmodule
