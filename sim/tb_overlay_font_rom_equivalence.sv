`timescale 1ns/1ps
// Cycle-by-cycle equivalence of the BRAM-font overlays against the original
// LUT-font RTL.  Real 640x480@60 raster (800x525, VS low for lines 10-11),
// pseudo-random background, enables toggled at random cycles (also mid-line),
// every brightness/contrast/volume value, and asynchronous reset pulses.
module tb_overlay_font_rom_equivalence;
reg clk = 1'b0, rst = 1'b1;
reg vs = 1'b1, de = 1'b0;
reg en_home = 1'b1, en_osd = 1'b1, en_status = 1'b1;
reg [23:0] rgb = 24'h13579B;
reg [1:0] bri = 2'd3, con = 2'd0;
reg [3:0] vol = 4'd8;
wire [23:0] home_new, home_ref, osd_new, osd_ref, st_new, st_ref;
integer frame, line, h, row, line_len, cycles = 0, active = 0;
reg full_frame;
integer seed = 20260928;
integer NFRAMES = 1000;
initial if ($value$plusargs("frames=%d", NFRAMES)) ;
always #20 clk = ~clk;

video_home_overlay dut_home (.I_clk(clk), .I_rst(rst), .I_enable(en_home), .I_vs(vs),
    .I_de(de), .I_music_page(1'b0), .I_rgb(rgb), .O_rgb(home_new));
video_home_overlay_baseline_ref ref_home (.I_clk(clk), .I_rst(rst), .I_enable(en_home),
    .I_vs(vs), .I_de(de), .I_rgb(rgb), .O_rgb(home_ref));
osd_alpha_overlay dut_osd (.I_clk(clk), .I_rst(rst), .I_enable(en_osd), .I_vs(vs),
    .I_de(de), .I_rgb(rgb), .O_rgb(osd_new));
osd_alpha_overlay_baseline_ref ref_osd (.I_clk(clk), .I_rst(rst), .I_enable(en_osd),
    .I_vs(vs), .I_de(de), .I_rgb(rgb), .O_rgb(osd_ref));
video_status_overlay dut_st (.I_clk(clk), .I_rst(rst), .I_enable(en_status), .I_vs(vs),
    .I_de(de), .I_rgb(rgb), .I_brightness_level(bri), .I_contrast_level(con),
    .I_volume_level(vol), .O_rgb(st_new));
video_status_overlay_baseline_ref ref_st (.I_clk(clk), .I_rst(rst), .I_enable(en_status),
    .I_vs(vs), .I_de(de), .I_rgb(rgb), .I_brightness_level(bri), .I_contrast_level(con),
    .I_volume_level(vol), .O_rgb(st_ref));

// Compare just before every rising edge: outputs are combinational from the
// registered raster state plus the current inputs.
always @(negedge clk) if (!rst) begin
    cycles = cycles + 1;
    if (home_new !== home_ref)
        $fatal(1, "HOME mismatch f=%0d line=%0d h=%0d new=%h ref=%h", frame, line, h, home_new, home_ref);
    if (osd_new !== osd_ref)
        $fatal(1, "OSD mismatch f=%0d line=%0d h=%0d new=%h ref=%h", frame, line, h, osd_new, osd_ref);
    if (st_new !== st_ref)
        $fatal(1, "STATUS mismatch f=%0d line=%0d h=%0d new=%h ref=%h", frame, line, h, st_new, st_ref);
end

task automatic step;
    begin
        @(posedge clk); #2;
        rgb = $random(seed);
        // Rare random enable changes; the top level only changes them at
        // frame edges, but equivalence must hold for any input sequence.
        if (($random(seed) & 16'hffff) == 16'd7) en_home = ~en_home;
        if (($random(seed) & 16'hffff) == 16'd9) en_osd = ~en_osd;
        if (($random(seed) & 16'hffff) == 16'd11) en_status = ~en_status;
        if (($random(seed) & 16'h3fff) == 16'd5) begin
            bri = $random(seed); con = $random(seed); vol = $unsigned($random(seed)) % 11;
        end
    end
endtask

initial begin
    repeat (5) @(posedge clk);
    #2 rst = 1'b0;
    // 1000 frames cover the full 840-frame subtitle scroll cycle.  Frames
    // 0-11 and every 97th frame use the complete raster.  The others keep
    // full-width lines only around the subtitle band and shorten all other
    // active lines, which is still a legal input sequence for all overlays.
    for (frame = 0; frame < NFRAMES; frame = frame + 1) begin
        if (frame % 100 == 0) $display("frame %0d at %t", frame, $realtime);
        full_frame = (frame < 12) || (frame % 97 == 0);
        if (frame == 3 || frame == 517) begin
            // asynchronous reset in the middle of a frame
            #7 rst = 1'b1; #50 rst = 1'b0;
        end
        for (line = 0; line < 525; line = line + 1) begin
            row = line - 45;
            line_len = (full_frame || (row >= 416 && row < 456)) ? 800 :
                       24;
            for (h = 0; h < line_len; h = h + 1) begin
                vs = !(line >= 10 && line < 12);
                de = (line >= 45) && (h >= line_len - ((line_len == 800) ? 640 : 16));
                if (de) active = active + 1;
                step;
            end
        end
    end
    $display("PASS FONT_ROM_EQ home/osd/status bit-identical over %0d cycles (%0d active pixels, %0d frames)", cycles, active, NFRAMES);
    $finish;
end
endmodule
