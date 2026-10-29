`timescale 1ns/1ps
module tb_home_dashboard_combined;
reg clk = 0;
always #5 clk = ~clk;
reg rst = 1, vs = 0, de = 0;
reg [23:0] rgb = 24'h406080;
wire [23:0] with_status, out_rgb;
integer x, y, ppm, top_ink = 0, clock_ink = 0, home_ink = 0, errors = 0;

video_status_overlay status (
    .I_clk(clk), .I_rst(rst), .I_enable(1'b1), .I_vs(vs), .I_de(de),
    .I_rgb(rgb), .I_brightness_level(2'd3),
    .I_contrast_level(2'd0), .I_volume_level(4'd8),
    .O_rgb(with_status)
);
video_home_overlay home (
    .I_clk(clk), .I_rst(rst), .I_enable(1'b1), .I_vs(vs), .I_de(de),
    .I_rgb(with_status), .O_rgb(out_rgb)
);

initial begin
    ppm = $fopen("sim/home_dashboard_combined_preview.ppm", "wb");
    $fwrite(ppm, "P6\n640 480\n255\n");
    repeat (4) @(negedge clk);
    rst = 0; vs = 1;
    repeat (2) @(negedge clk);
    vs = 0;
    for (y = 0; y < 480; y = y + 1) begin
        for (x = 0; x < 640; x = x + 1) begin
            @(negedge clk); de = 1;
            @(posedge clk); #1;
            if (out_rgb !== rgb) begin
                if (y < 36) top_ink = top_ink + 1;
                if ((y >= 54 && y < 70 && x >= 504 && x < 624) ||
                    (y >= 74 && y < 106 && x >= 500 && x < 532) ||
                    (y >= 82 && y < 98 && x >= 544 && x < 624))
                    clock_ink = clock_ink + 1;
                if (y >= 322 && y < 408) home_ink = home_ink + 1;
                if (y >= 36 && y < 322 &&
                    !((y >= 54 && y < 70 && x >= 504 && x < 624) ||
                      (y >= 74 && y < 106 && x >= 500 && x < 532) ||
                      (y >= 82 && y < 98 && x >= 544 && x < 624)))
                    errors = errors + 1;
            end
            $fwrite(ppm, "%c%c%c", out_rgb[23:16], out_rgb[15:8], out_rgb[7:0]);
        end
        @(negedge clk); de = 0;
        repeat (4) @(negedge clk);
    end
    $fclose(ppm);
    if (errors == 0 && top_ink > 100 && clock_ink > 100 && home_ink > 1000)
        $display("PASS COMBINED DASHBOARD top=%0d clock=%0d cards=%0d", top_ink, clock_ink, home_ink);
    else
        $fatal(1,"FAIL COMBINED DASHBOARD top=%0d clock=%0d cards=%0d middle=%0d", top_ink, clock_ink, home_ink, errors);
    $finish;
end
endmodule
