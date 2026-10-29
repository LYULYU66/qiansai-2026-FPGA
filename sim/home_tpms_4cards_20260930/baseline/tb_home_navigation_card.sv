`timescale 1ns/1ps
module tb_home_navigation_card;
reg clk = 0;
always #5 clk = ~clk;
reg rst = 1, en = 0, vs = 0, de = 0;
reg [23:0] rgb = 24'h263D5A;
wire [23:0] actual, baseline;
integer x, y, changed = 0, outside_changed = 0;
integer nav_blue = 0, nav_arrow = 0, divider = 0;
integer dest_letters = 0, home_icon = 0, home_letters = 0;
integer office_icon = 0, office_letters = 0;
integer cover_pixels = 0, song_letters = 0;
integer prev_pixels = 0, play_pixels = 0, next_pixels = 0;
integer app_pixels [0:3], app_text = 0;
integer date_ink = 0, time_ink = 0, sun_pixels = 0;
integer shape_errors = 0;

video_home_overlay dut (
    .I_clk(clk), .I_rst(rst), .I_enable(en), .I_vs(vs), .I_de(de),
    .I_rgb(rgb), .O_rgb(actual)
);
video_home_overlay_before_light old (
    .I_clk(clk), .I_rst(rst), .I_enable(en), .I_vs(vs), .I_de(de),
    .I_rgb(rgb), .O_rgb(baseline)
);

initial begin
    for (integer n = 0; n < 4; n = n + 1) begin
        app_pixels[n] = 0;
    end
    repeat (4) @(negedge clk);
    rst = 0; en = 1; vs = 1;
    repeat (2) @(negedge clk);
    vs = 0;
    for (y = 0; y < 480; y = y + 1) begin
        for (x = 0; x < 640; x = x + 1) begin
            @(negedge clk); de = 1;
            @(posedge clk); #1;
            if (actual !== baseline) begin
                changed = changed + 1;
                if (!((x >= 16 && x < 624 && y >= 322 && y < 408) ||
                      (x >= 504 && x < 624 && y >= 54 && y < 70) ||
                      (x >= 500 && x < 532 && y >= 74 && y < 106) ||
                      (x >= 544 && x < 624 && y >= 82 && y < 98) ||
                      (y >= 416)))
                    outside_changed = outside_changed + 1;
            end
            if (x >= 45 && x < 68 && y >= 337 && y < 366) begin
                if (dut.nav_circle && actual[23:16]<100 &&
                    actual[15:8]>100 && actual[7:0]>180) nav_blue = nav_blue + 1;
                if (dut.nav_circle && actual[23:16]>240 &&
                    actual[15:8]>240 && actual[7:0]>240)
                    nav_arrow = nav_arrow + 1;
            end
            if (x == 104 && y >= 337 && y < 393 &&
                actual == 24'hD8E0E7) divider = divider + 1;
            if (dut.glyph_on && y >= 375 && y < 391) begin
                if (x >= 16 && x < 96) dest_letters = dest_letters + 1;
                if (x >= 112 && x < 144) home_letters = home_letters + 1;
                if (x >= 160 && x < 192) office_letters = office_letters + 1;
            end
            if (dut.glyph_on && dut.icon_text && y >= 341 && y < 357) begin
                if (x >= 120 && x < 136) home_icon = home_icon + 1;
                if (x >= 168 && x < 184) office_icon = office_icon + 1;
            end
            if (dut.cover_pixel) cover_pixels = cover_pixels + 1;
            if (dut.glyph_on && x >= 288 && x < 352 &&
                y >= 340 && y < 356) song_letters = song_letters + 1;
            if (dut.music_previous) prev_pixels = prev_pixels + 1;
            if (dut.music_pause) play_pixels = play_pixels + 1;
            if (dut.music_next) next_pixels = next_pixels + 1;
            if (x == 45 && y == 338 && dut.nav_circle) shape_errors = shape_errors + 1;
            if (x == 57 && y == 338 && !dut.nav_circle) shape_errors = shape_errors + 1;
            if (x == 57 && y == 361 && !dut.nav_circle) shape_errors = shape_errors + 1;
            if (x == 57 && y == 364 && dut.nav_circle) shape_errors = shape_errors + 1;
            if (x == 234 && y == 338 && dut.cover_pixel) shape_errors = shape_errors + 1;
            if (x == 254 && y == 358 && !dut.cover_pixel) shape_errors = shape_errors + 1;
            if (x == 405 && y == 383 &&
                actual !== {dut.card_r,dut.card_g,dut.card_b})
                shape_errors = shape_errors + 1;
            if (dut.glyph_on && x >= 430 && x < 624 &&
                y >= 322 && y < 408) app_text = app_text + 1;
            if (dut.glyph_on && x >= 504 && x < 624 &&
                y >= 54 && y < 70) date_ink = date_ink + 1;
            if (dut.glyph_on && x >= 544 && x < 624 &&
                y >= 82 && y < 98) time_ink = time_ink + 1;
            if (dut.sun_pixel) sun_pixels = sun_pixels + 1;
            if (dut.app_pixel && y >= 345 && y < 385) begin
                if (x >= 438 && x < 478) app_pixels[0] = app_pixels[0] + 1;
                if (x >= 484 && x < 524) app_pixels[1] = app_pixels[1] + 1;
                if (x >= 530 && x < 570) app_pixels[2] = app_pixels[2] + 1;
                if (x >= 576 && x < 616) app_pixels[3] = app_pixels[3] + 1;
            end
        end
        @(negedge clk); de = 0;
        repeat (4) @(negedge clk);
    end
    if (outside_changed || shape_errors || changed < 300 || nav_blue < 200 ||
        nav_arrow < 30 || divider != 56 || dest_letters < 150 ||
        home_icon < 20 || home_letters < 50 ||
        office_icon < 20 || office_letters < 50 ||
        cover_pixels < 1000 || song_letters < 100 ||
        prev_pixels < 20 || play_pixels < 20 || next_pixels < 20 ||
        app_text != 0 || date_ink < 70 || time_ink < 70 ||
        sun_pixels < 100 || app_pixels[0] < 1300 ||
        app_pixels[1] < 1300 || app_pixels[2] < 1300 || app_pixels[3] < 1300) begin
        $display("FAIL HOME CARDS changed=%0d outside=%0d shape=%0d blue=%0d arrow=%0d divider=%0d dest=%0d home=%0d/%0d office=%0d/%0d cover=%0d song=%0d controls=%0d/%0d/%0d apps=%0d,%0d,%0d,%0d apptext=%0d date=%0d time=%0d sun=%0d",
            changed, outside_changed, shape_errors, nav_blue, nav_arrow, divider,
            dest_letters, home_icon, home_letters, office_icon, office_letters,
            cover_pixels, song_letters, prev_pixels, play_pixels, next_pixels,
            app_pixels[0],app_pixels[1],app_pixels[2],app_pixels[3],app_text,
            date_ink,time_ink,sun_pixels);
        $fatal(1,"home cards regression failed");
    end else begin
        $display("PASS HOME CARDS changed=%0d outside=%0d shape=%0d blue=%0d arrow=%0d divider=%0d dest=%0d home=%0d/%0d office=%0d/%0d cover=%0d song=%0d controls=%0d/%0d/%0d apps=%0d,%0d,%0d,%0d apptext=%0d date=%0d time=%0d sun=%0d",
            changed, outside_changed, shape_errors, nav_blue, nav_arrow, divider,
            dest_letters, home_icon, home_letters, office_icon, office_letters,
            cover_pixels, song_letters, prev_pixels, play_pixels, next_pixels,
            app_pixels[0],app_pixels[1],app_pixels[2],app_pixels[3],app_text,
            date_ink,time_ink,sun_pixels);
    end
    $finish;
end
endmodule
