`timescale 1ns/1ps
module tb_video_status_overlay;
reg clk = 0;
always #5 clk = ~clk;
reg rst = 1, enable = 0, vs = 0, de = 0;
reg [23:0] rgb = 24'h607080;
reg [1:0] brightness_level = 2'd3, contrast_level = 2'd0;
reg [3:0] volume_level = 4'd8;
wire [23:0] out_rgb;
integer x, y, errors = 0;
integer bri_ink = 0, con_ink = 0, vol_ink = 0;

video_status_overlay dut (
    .I_clk(clk), .I_rst(rst), .I_enable(enable), .I_vs(vs), .I_de(de),
    .I_rgb(rgb), .I_brightness_level(brightness_level),
    .I_contrast_level(contrast_level), .I_volume_level(volume_level),
    .O_rgb(out_rgb)
);

initial begin
    repeat (4) @(negedge clk);
    rst = 0;
    @(negedge clk);
    brightness_level = 2'd1; contrast_level = 2'd2; volume_level = 4'd5;
    repeat (6) @(negedge clk);
    if (dut.brightness_stable !== 2'd1 ||
        dut.contrast_stable !== 2'd2 || dut.volume_stable !== 4'd5 ||
        dut.brightness_frame !== 2'd3 || dut.contrast_frame !== 2'd0 ||
        dut.volume_frame !== 4'd8) errors = errors + 1;
    enable = 1; vs = 1;
    repeat (2) @(negedge clk);
    vs = 0;
    if (dut.brightness_frame !== 2'd1 ||
        dut.contrast_frame !== 2'd2 || dut.volume_frame !== 4'd5 ||
        dut.status_code(2'd0,3'd5,2'd1,2'd2,4'd5) !== 5'd5 ||
        dut.status_code(2'd1,3'd5,2'd1,2'd2,4'd5) !== 5'd7 ||
        dut.status_code(2'd2,3'd4,2'd1,2'd2,4'd5) !== 5'd5)
        errors = errors + 1;

    for (y = 0; y < 90; y = y + 1) begin
        for (x = 0; x < 640; x = x + 1) begin
            @(negedge clk); de = 1;
            @(posedge clk); #1;
            if (dut.pixel_x !== x || dut.pixel_y !== y) errors = errors + 1;
            if (!(dut.text_hit || dut.shadow_hit) && out_rgb !== rgb)
                errors = errors + 1;
            if (dut.text_hit && out_rgb !== 24'hF4F9FC &&
                out_rgb !== 24'hD4E1E9 && out_rgb !== 24'hA8BAC6)
                errors = errors + 1;
            if (dut.text_hit) begin
                if (y < 16 || y >= 30) errors = errors + 1;
                if (x >= 18 && x < 102) bri_ink = bri_ink + 1;
                if (x >= 114 && x < 198) con_ink = con_ink + 1;
                if (x >= 210 && x < 270) vol_ink = vol_ink + 1;
            end
        end
        @(negedge clk); de = 0;
        repeat (4) @(negedge clk);
    end
    enable = 0;
    @(negedge clk); de = 1;
    @(posedge clk); #1;
    if (out_rgb !== rgb) errors = errors + 1;
    if (bri_ink < 25 || con_ink < 25 || vol_ink < 20) errors = errors + 1;
    if (errors == 0)
        $display("PASS FRAMELESS STATUS BRI=%0d CON=%0d VOL=%0d",
                 bri_ink, con_ink, vol_ink);
    else
        $display("FAIL INLINE STATUS errors=%0d BRI=%0d CON=%0d VOL=%0d",
                 errors, bri_ink, con_ink, vol_ink);
    $finish;
end
endmodule
