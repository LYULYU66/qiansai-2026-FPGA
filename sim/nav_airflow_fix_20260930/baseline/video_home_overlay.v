// Picture-1-only car dashboard. All text comes from a 16x16 glyph ROM in
// block RAM; the background is the decoded TF-card image. No frame store/DSP.
module video_home_overlay #(
    parameter integer H_ACTIVE = 640,
    parameter integer V_ACTIVE = 480
)(
    input wire I_clk, I_rst, I_enable, I_vs, I_de,
    input wire [23:0] I_rgb,
    output wire [23:0] O_rgb
);
reg [10:0] pixel_x;
reg [9:0] pixel_y;
reg de_d, vs_d, active_seen;
wire frame_start = I_vs && !vs_d;
wire line_start = I_de && !de_d;
// Next raster position. The glyph ROM read is synchronous, so it is
// addressed with the position that pixel_x/pixel_y take on the next clock.
reg [10:0] next_x;
reg [9:0] next_y;
reg next_seen;
always @(*) begin
    next_x = pixel_x; next_y = pixel_y; next_seen = active_seen;
    if (frame_start) begin
        next_x = 11'd0; next_y = 10'd0; next_seen = 1'b0;
    end else if (I_de) begin
        if (line_start) begin
            next_x = 11'd0;
            if (!active_seen) begin
                next_y = 10'd0; next_seen = 1'b1;
            end else if (pixel_y < V_ACTIVE-1) next_y = pixel_y + 10'd1;
        end else if (pixel_x < H_ACTIVE-1) next_x = pixel_x + 11'd1;
    end else next_x = 11'd0;
end
always @(posedge I_clk or posedge I_rst) begin
    if (I_rst) begin
        pixel_x <= 11'd0; pixel_y <= 10'd0;
        de_d <= 1'b0; vs_d <= 1'b0; active_seen <= 1'b0;
    end else begin
        de_d <= I_de; vs_d <= I_vs;
        pixel_x <= next_x; pixel_y <= next_y; active_seen <= next_seen;
    end
end

reg [1:0] card_id;
always @(*) begin
    card_id = 2'd3;
    if (pixel_x >= 11'd16 && pixel_x < 11'd210) begin
        card_id = 2'd0;
    end else if (pixel_x >= 11'd222 && pixel_x < 11'd418) begin
        card_id = 2'd1;
    end else if (pixel_x >= 11'd430 && pixel_x < 11'd624) begin
        card_id = 2'd2;
    end
end
wire card_rect = I_enable && I_de && (card_id != 2'd3) &&
                pixel_y >= 10'd322 && pixel_y < 10'd408;
wire [7:0] card_dx = pixel_x -
    ((card_id == 2'd0) ? 11'd16 : (card_id == 2'd1) ? 11'd222 : 11'd430);
wire [7:0] card_right_dx = ((card_id == 2'd1) ? 8'd195 : 8'd193) - card_dx;
wire [6:0] card_edge_y = (pixel_y < 10'd365) ?
                        pixel_y - 10'd322 : 10'd407 - pixel_y;
// A short row-inset table gives a symmetric rounded contour without squaring
// coordinates, multipliers, a new bitmap ROM, or an extra pixel pipeline.
function [3:0] corner_inset;
    input [6:0] edge_y;
    begin
        case (edge_y)
            7'd0: corner_inset=4'd8;
            7'd1: corner_inset=4'd5;
            7'd2: corner_inset=4'd4;
            7'd3: corner_inset=4'd3;
            7'd4: corner_inset=4'd2;
            7'd5,7'd6,7'd7: corner_inset=4'd1;
            default: corner_inset=4'd0;
        endcase
    end
endfunction
wire [3:0] card_inset = corner_inset(card_edge_y);
wire card_hit = card_rect && card_dx >= card_inset && card_right_dx >= card_inset;
wire card_border = card_hit &&
                   (card_edge_y == 7'd0 || card_dx == card_inset ||
                    card_right_dx == card_inset);
wire nav_hit = I_enable && I_de && pixel_y >= 10'd440;

// Card headings and the clock share the same glyph ROM. Freed app-label
// slots hold the fixed date/time, with no new font BRAM.
// The text boxes are disjoint and each lies inside its card, so they are
// decoded from the next raster position without the card/enable qualifiers.
// The ROM word, text flags and pixel_x[3:0] then all refer to the same pixel.
reg [4:0] glyph_id;
reg [3:0] glyph_y;
reg [2:0] glyph_cell;
reg next_text, next_icon, next_shift_icon, next_clock_text;
wire [6:0] date_local_x = next_x[6:0] + 7'd8;
always @(*) begin
    glyph_id = 5'd31; glyph_y = 4'd0; glyph_cell = 3'd0;
    next_text = 1'b0;
    next_icon = 1'b0; next_shift_icon = 1'b0;
    next_clock_text = 1'b0;
    // Navigation card: a broad destination action and two compact shortcuts.
    // Text cell origins stay 16-pixel aligned, sharing the existing glyph ROM.
    if (next_x >= 11'd16 && next_x < 11'd96 &&
        next_y >= 10'd375 && next_y < 10'd391) begin
        glyph_cell = next_x[6:4] - 3'd1; glyph_y = next_y[3:0] - 4'd7;
        case (glyph_cell)
            3'd0: glyph_id = 5'd23; // 搜
            3'd1: glyph_id = 5'd24; // 索
            3'd2: glyph_id = 5'd0;  // 目
            3'd3: glyph_id = 5'd1;  // 的
            3'd4: glyph_id = 5'd2;  // 地
            default: glyph_id = 5'd31;
        endcase
        next_text = 1'b1;
    end else if (next_x >= 11'd112 && next_x < 11'd144 &&
                 next_y >= 10'd375 && next_y < 10'd391) begin
        glyph_cell = next_x[6:4] - 3'd7; glyph_y = next_y[3:0] - 4'd7;
        case (glyph_cell)
            3'd0: glyph_id = 5'd25; // 回
            3'd1: glyph_id = 5'd26; // 家
            default: glyph_id = 5'd31;
        endcase
        next_text = 1'b1;
    end else if (next_x >= 11'd160 && next_x < 11'd192 &&
                 next_y >= 10'd375 && next_y < 10'd391) begin
        glyph_cell = next_x[6:4] - 3'd2; glyph_y = next_y[3:0] - 4'd7;
        case (glyph_cell)
            3'd0: glyph_id = 5'd27; // 公
            3'd1: glyph_id = 5'd28; // 司
            default: glyph_id = 5'd31;
        endcase
        next_text = 1'b1;
    end else if (next_x >= 11'd120 && next_x < 11'd136 &&
                 next_y >= 10'd341 && next_y < 10'd357) begin
        glyph_id = 5'd30; // home outline
        glyph_y = next_y[3:0] - 4'd5;
        next_text = 1'b1; next_icon = 1'b1; next_shift_icon = 1'b1;
    end else if (next_x >= 11'd168 && next_x < 11'd184 &&
                 next_y >= 10'd341 && next_y < 10'd357) begin
        glyph_id = 5'd31; // office / company outline
        glyph_y = next_y[3:0] - 4'd5;
        next_text = 1'b1; next_icon = 1'b1; next_shift_icon = 1'b1;
    end else if (next_x >= 11'd288 && next_x < 11'd352 &&
                 next_y >= 10'd340 && next_y < 10'd356) begin
        glyph_cell = next_x[6:4] - 3'd2; glyph_y = next_y[3:0] - 4'd4;
        case (glyph_cell)
            3'd0: glyph_id = 5'd7;
            3'd1: glyph_id = 5'd8;
            3'd2: glyph_id = 5'd9;
            3'd3: glyph_id = 5'd10;
            default: glyph_id = 5'd31;
        endcase
        next_text = 1'b1;
    end else if (next_x >= 11'd504 && next_x < 11'd584 &&
                 next_y >= 10'd54 && next_y < 10'd70) begin
        glyph_cell = date_local_x[6:4];
        glyph_y = next_y - 10'd54;
        case (glyph_cell)
            3'd0: glyph_id = 5'd3;  // 1
            3'd1: glyph_id = 5'd4;  // 0
            3'd2: glyph_id = 5'd5;  // 月
            3'd3: glyph_id = 5'd3;  // 1
            3'd4: glyph_id = 5'd6;  // 日
            default: glyph_id = 5'd31;
        endcase
        next_text = 1'b1; next_clock_text = 1'b1; next_shift_icon = 1'b1;
    end else if (next_x >= 11'd592 && next_x < 11'd624 &&
                 next_y >= 10'd54 && next_y < 10'd70) begin
        glyph_id = next_x[5] ? 5'd13 : 5'd17; // 周一, fixed original position
        glyph_y = next_y - 10'd54;
        next_text = 1'b1; next_clock_text = 1'b1;
    end else if (next_x >= 11'd544 && next_x < 11'd624 &&
                 next_y >= 10'd82 && next_y < 10'd98) begin
        glyph_cell = next_x[6:4] - 3'd2;
        glyph_y = next_y - 10'd82;
        case (glyph_cell)
            3'd0: glyph_id = 5'd4;  // 0
            3'd1: glyph_id = 5'd11; // 9
            3'd2: glyph_id = 5'd12; // :
            3'd3: glyph_id = 5'd4;  // 0
            3'd4: glyph_id = 5'd4;  // 0
            default: glyph_id = 5'd31;
        endcase
        next_text = 1'b1; next_clock_text = 1'b1;
    end
end
reg text_valid, icon_text, shift_icon, clock_text;
always @(posedge I_clk or posedge I_rst) begin
    if (I_rst) begin
        text_valid <= 1'b0;
        icon_text <= 1'b0; shift_icon <= 1'b0; clock_text <= 1'b0;
    end else begin
        text_valid <= next_text;
        icon_text <= next_icon; shift_icon <= next_shift_icon;
        clock_text <= next_clock_text;
    end
end
wire [31:0] row_coverage;
video_home_glyph_rom u_glyph_rom (
    .I_clk(I_clk), .I_addr({glyph_id, glyph_y}), .O_row(row_coverage)
);
wire [3:0] glyph_col = pixel_x[3:0] ^ {shift_icon, 3'b000};
wire [1:0] glyph_cov = row_coverage[(15-glyph_col)*2 +: 2];
wire glyph_on = I_enable && I_de && text_valid && (glyph_cov != 2'd0);
wire [1:0] glyph_left_cov = row_coverage[(16-glyph_col)*2 +: 2];
wire clock_shadow = I_enable && I_de && clock_text &&
                    glyph_col != 4'd0 && glyph_cov == 2'd0 &&
                    glyph_left_cov != 2'd0;
wire heading_text = (card_id == 2'd2) ? (pixel_y < 10'd346) :
                    (card_id == 2'd1) ? (pixel_y < 10'd356) :
                    (pixel_y < 10'd354);
wire [23:0] glyph_color = icon_text ?
    ((glyph_cov == 2'd3) ? 24'h1D2D3D :
     (glyph_cov == 2'd2) ? 24'h526778 : 24'h9BABBA) :
    clock_text ?
    ((glyph_cov == 2'd3) ? 24'hFFFFFF :
     (glyph_cov == 2'd2) ? 24'hF2F7FA : 24'hDCE9F0) :
    heading_text ?
    ((glyph_cov == 2'd3) ? 24'h1D3042 :
     (glyph_cov == 2'd2) ? 24'h596D80 : 24'hA7B4C0) :
    ((glyph_cov == 2'd3) ? 24'h24394B :
     (glyph_cov == 2'd2) ? 24'h617486 : 24'hADB9C5);

// The antialiased blue disk/arrow use spare words in the existing app ROM.
wire nav_circle;
wire nav_arrow;
wire first_card_separator = card_hit && card_id == 2'd0 &&
    pixel_x == 11'd104 && pixel_y >= 10'd337 && pixel_y < 10'd393;
// Card two: circular album art at left, title above three player controls.
wire cover_next = next_x >= 11'd234 && next_x < 11'd274 &&
                  next_y >= 10'd338 && next_y < 10'd378;
wire [5:0] cover_x = next_x - 11'd234;
wire [5:0] cover_y = next_y - 10'd338;
wire [10:0] cover_addr = ({5'd0,cover_y} << 5) +
                         ({5'd0,cover_y} << 3) + {5'd0,cover_x};
// The 20px music-service logo shares unused addresses of the cover BRAM.
wire qq_next = next_x >= 11'd384 && next_x < 11'd404 &&
               next_y >= 10'd338 && next_y < 10'd358;
wire [4:0] qq_x=next_x-11'd384, qq_y=next_y-10'd338;
wire [10:0] art_addr=qq_next ? 11'd1600+
    ({6'd0,qq_y} << 4)+({6'd0,qq_y} << 2)+{6'd0,qq_x} : cover_addr;
reg cover_valid, qq_valid;
always @(posedge I_clk or posedge I_rst) begin
    if (I_rst) begin cover_valid <= 1'b0; qq_valid <= 1'b0; end
    else begin cover_valid <= cover_next; qq_valid <= qq_next; end
end
wire [3:0] cover_index;
wire [23:0] cover_rgb;
video_album_cover_rom u_album_cover_rom (
    .I_clk(I_clk), .I_addr(art_addr),
    .O_index(cover_index), .O_rgb(cover_rgb)
);
wire cover_pixel = card_hit && card_id == 2'd1 &&
                   cover_valid && (cover_index != 4'd0);
wire qq_pixel = card_hit && card_id == 2'd1 && qq_valid && cover_index != 4'd0;
wire music_control_area = card_hit && card_id == 2'd1 &&
                          pixel_y >= 10'd378 && pixel_y < 10'd391;
wire [4:0] music_dy = (pixel_y >= 10'd384) ?
                      (pixel_y - 10'd384) : (10'd384 - pixel_y);
wire music_previous = music_control_area &&
    ((pixel_x >= 11'd294 && pixel_x < 11'd297) ||
     (pixel_x >= 11'd299 && pixel_x < 11'd310 &&
      music_dy <= ((pixel_x - 11'd299) >> 1)));
// Pause bars indicate that the music is currently playing.
wire music_pause = music_control_area &&
    ((pixel_x >= 11'd339 && pixel_x < 11'd342) ||
     (pixel_x >= 11'd346 && pixel_x < 11'd349));
wire music_next = music_control_area &&
    ((pixel_x >= 11'd390 && pixel_x < 11'd393) ||
     (pixel_x >= 11'd377 && pixel_x < 11'd389 &&
      music_dy <= ((11'd388 - pixel_x) >> 1)));
// Four sharpened 40x40 apps, 32x32 sun and antialiased navigation disk share
// one 2048x16 indexed ROM (four BRAM9Ks). Fifteen colors per app; constant
// shifts/adds calculate the compact row offset, without a multiplier/divider.
reg [2:0] sprite_id;
reg [10:0] sprite_left;
reg [9:0] sprite_top;
reg [10:0] sprite_base;
reg sprite_next;
always @(*) begin
    sprite_id = 3'd0;
    sprite_left = 11'd0;
    sprite_top = 10'd0;
    sprite_base = 11'd0;
    sprite_next = 1'b0;
    if (next_x >= 11'd45 && next_x < 11'd69 &&
        next_y >= 10'd338 && next_y < 10'd362) begin
        sprite_id=3'd5; sprite_left=11'd45; sprite_base=11'd1856;
        sprite_top=10'd338; sprite_next=1'b1;
    end else if (next_x >= 11'd500 && next_x < 11'd532 &&
        next_y >= 10'd74 && next_y < 10'd106) begin
        sprite_id = 3'd4; sprite_left = 11'd500; sprite_base = 11'd1600;
        sprite_top = 10'd74; sprite_next = 1'b1;
    end else if (next_y >= 10'd345 && next_y < 10'd385) begin
        sprite_top = 10'd345;
        if (next_x >= 11'd438 && next_x < 11'd478) begin
            sprite_id = 3'd0; sprite_left = 11'd438; sprite_next = 1'b1;
        end else if (next_x >= 11'd484 && next_x < 11'd524) begin
            sprite_id = 3'd1; sprite_left = 11'd484; sprite_base = 11'd400; sprite_next = 1'b1;
        end else if (next_x >= 11'd530 && next_x < 11'd570) begin
            sprite_id = 3'd2; sprite_left = 11'd530; sprite_base = 11'd800; sprite_next = 1'b1;
        end else if (next_x >= 11'd576 && next_x < 11'd616) begin
            sprite_id = 3'd3; sprite_left = 11'd576; sprite_base = 11'd1200; sprite_next = 1'b1;
        end
    end
end
wire [5:0] sprite_local_x = next_x - sprite_left;
wire [5:0] sprite_local_y = next_y - sprite_top;
wire [10:0] sprite_row = (sprite_id == 3'd5) ?
                       {3'd0,sprite_local_y,2'b00}+{4'd0,sprite_local_y,1'b0} :
                       {2'b00,sprite_local_y,3'b000} +
                       ((sprite_id == 3'd4) ? 11'd0 : {4'b0000,sprite_local_y,1'b0});
wire [10:0] sprite_addr = sprite_base + sprite_row + {7'b0000000,sprite_local_x[5:2]};
reg app_valid, sun_valid, nav_disk_valid;
always @(posedge I_clk or posedge I_rst) begin
    if (I_rst) begin
        app_valid <= 1'b0;
        sun_valid <= 1'b0;
        nav_disk_valid <= 1'b0;
    end else begin
        app_valid <= sprite_next && (sprite_id < 3'd4);
        sun_valid <= sprite_next && (sprite_id == 3'd4);
        nav_disk_valid <= sprite_next && (sprite_id == 3'd5);
    end
end
wire sprite_opaque;
wire [23:0] sprite_rgb;
video_app_icons_rom u_app_icons_rom (
    .I_clk(I_clk), .I_addr(sprite_addr), .I_lane(sprite_local_x[1:0]),
    .I_tile(sprite_id),
    .O_opaque(sprite_opaque), .O_rgb(sprite_rgb)
);
wire app_pixel = card_hit && card_id == 2'd2 && app_valid && sprite_opaque;
wire sun_pixel = I_enable && I_de && sun_valid && sprite_opaque;
assign nav_circle = card_hit && card_id == 2'd0 && nav_disk_valid && sprite_opaque;
assign nav_arrow = nav_circle && sprite_rgb == 24'hFFFFFF;


// Thirteen crisp reference-toolbar icons plus two shared temperature labels.
// 2-bit coverage, 1008/1024 words, two BRAM9Ks; all geometry is baked offline.
reg [3:0] next_nav_id;
reg [10:0] nav_left;
reg [9:0] nav_top;
reg nav_next;
always @(*) begin
    next_nav_id=4'd15; nav_left=11'd0; nav_top=10'd448; nav_next=1'b0;
    if (next_y >= 10'd448 && next_y < 10'd472) begin
        if (next_x >= 11'd20 && next_x < 11'd44) begin
            next_nav_id=4'd0; nav_left=11'd20;
            nav_next=1'b1;
        end else if (next_x >= 11'd62 && next_x < 11'd86) begin
            next_nav_id=4'd1; nav_left=11'd62;
            nav_next=1'b1;
        end else if (next_x >= 11'd104 && next_x < 11'd128) begin
            next_nav_id=4'd2; nav_left=11'd104;
            nav_next=1'b1;
        end else if (next_x >= 11'd140 && next_x < 11'd176) begin
            next_nav_id=4'd13; nav_left=11'd140;
            nav_next=next_y >= 10'd452 && next_y < 10'd468; nav_top=10'd452;
        end else if (next_x >= 11'd188 && next_x < 11'd212) begin
            next_nav_id=4'd3; nav_left=11'd188;
            nav_next=1'b1;
        end else if (next_x >= 11'd230 && next_x < 11'd254) begin
            next_nav_id=4'd4; nav_left=11'd230;
            nav_next=1'b1;
        end else if (next_x >= 11'd272 && next_x < 11'd296) begin
            next_nav_id=4'd5; nav_left=11'd272;
            nav_next=1'b1;
        end else if (next_x >= 11'd314 && next_x < 11'd338) begin
            next_nav_id=4'd6; nav_left=11'd314;
            nav_next=1'b1;
        end else if (next_x >= 11'd356 && next_x < 11'd380) begin
            next_nav_id=4'd7; nav_left=11'd356;
            nav_next=1'b1;
        end else if (next_x >= 11'd398 && next_x < 11'd422) begin
            next_nav_id=4'd8; nav_left=11'd398;
            nav_next=1'b1;
        end else if (next_x >= 11'd440 && next_x < 11'd464) begin
            next_nav_id=4'd9; nav_left=11'd440;
            nav_next=1'b1;
        end else if (next_x >= 11'd476 && next_x < 11'd512) begin
            next_nav_id=4'd13; nav_left=11'd476;
            nav_next=next_y >= 10'd452 && next_y < 10'd468; nav_top=10'd452;
        end else if (next_x >= 11'd524 && next_x < 11'd548) begin
            next_nav_id=4'd10; nav_left=11'd524;
            nav_next=1'b1;
        end else if (next_x >= 11'd566 && next_x < 11'd590) begin
            next_nav_id=4'd11; nav_left=11'd566;
            nav_next=1'b1;
        end else if (next_x >= 11'd608 && next_x < 11'd632) begin
            next_nav_id=4'd12; nav_left=11'd608;
            nav_next=1'b1;
        end
    end
end
wire [5:0] nav_x = next_x-nav_left;
wire [4:0] nav_y = next_y-nav_top;
wire [10:0] nav_offset = (next_nav_id == 4'd13) ?
    ({6'd0,nav_y} << 5)+({6'd0,nav_y} << 2)+{5'd0,nav_x} :
    ({6'd0,nav_y} << 4)+({6'd0,nav_y} << 3)+{5'd0,nav_x};
wire [9:0] nav_base = (next_nav_id == 4'd13) ? 10'd936 :
    ({6'd0,next_nav_id} << 6)+({6'd0,next_nav_id} << 3);
wire [9:0] nav_addr = nav_base+{2'd0,nav_offset[10:3]};
wire [1:0] nav_cov;
wire [23:0] nav_rgb;
video_bottom_nav_rom u_bottom_nav_rom(
    .I_clk(I_clk), .I_addr(nav_addr), .I_lane(nav_offset[2:0]),
    .I_fan(next_nav_id == 4'd6), .O_cov(nav_cov), .O_rgb(nav_rgb)
);
reg nav_valid;
reg [3:0] nav_id;
always @(posedge I_clk or posedge I_rst) begin
    if (I_rst) begin nav_valid<=1'b0; nav_id<=4'd15; end
    else begin nav_valid<=nav_next; nav_id<=next_nav_id; end
end
wire nav_icon_area = nav_hit && nav_valid;
wire nav_icon = nav_icon_area && nav_cov != 2'd0;
wire [7:0] card_r = 8'hFF, card_g = 8'hFF, card_b = 8'hFF;
// Bottom navigation intentionally stays rectangular, all the way to its
// four corners. Only the three floating cards above have rounded contours.
assign O_rgb =
    !I_enable || !I_de ? I_rgb :
    glyph_on ? glyph_color :
    clock_shadow ? 24'h07131C :
    sun_pixel ? sprite_rgb :
    nav_circle ? sprite_rgb :
    first_card_separator ? 24'hD8E0E7 :
    cover_pixel ? cover_rgb :
    qq_pixel ? cover_rgb :
    app_pixel ? sprite_rgb :
    music_pause ? 24'h256BB1 :
    (music_previous || music_next) ? 24'h334B5E :
    nav_icon_area ? nav_rgb :
    card_border ? 24'hDCE4EB :
    card_hit ? {card_r,card_g,card_b} :
    nav_hit ? 24'hFFFFFF : I_rgb;

endmodule

// Noto Sans SC Medium, 16x16, two-bit antialias coverage.
// Generated from the same font source for all on-screen labels.
module video_home_glyph_rom (
    input  wire        I_clk,
    input  wire [8:0]  I_addr,   // {glyph, row}
    output reg  [31:0] O_row
);
reg [31:0] rom [0:511];
integer i;
initial begin
    for (i = 0; i < 512; i = i + 1) rom[i] = 32'd0;
    rom[9'h002] = 32'h01555540; // 目
    rom[9'h003] = 32'h03FFFFC0; // 目
    rom[9'h004] = 32'h030001C0; // 目
    rom[9'h005] = 32'h030000C0; // 目
    rom[9'h006] = 32'h03FFFFC0; // 目
    rom[9'h007] = 32'h03AAAAC0; // 目
    rom[9'h008] = 32'h030000C0; // 目
    rom[9'h009] = 32'h034552C0; // 目
    rom[9'h00A] = 32'h03FFFFC0; // 目
    rom[9'h00B] = 32'h030001C0; // 目
    rom[9'h00C] = 32'h030000C0; // 目
    rom[9'h00D] = 32'h03FFFFC0; // 目
    rom[9'h00E] = 32'h03EEBBC0; // 目
    rom[9'h00F] = 32'h030000C0; // 目
    rom[9'h011] = 32'h00400000; // 的
    rom[9'h012] = 32'h00D03C00; // 的
    rom[9'h013] = 32'h01C03000; // 的
    rom[9'h014] = 32'h0FFC7FF4; // 的
    rom[9'h015] = 32'h0E6CFAB4; // 的
    rom[9'h016] = 32'h0C0EC034; // 的
    rom[9'h017] = 32'h0C0E8034; // 的
    rom[9'h018] = 32'h0FFC3834; // 的
    rom[9'h019] = 32'h0EAC2C30; // 的
    rom[9'h01A] = 32'h0C0C0F30; // 的
    rom[9'h01B] = 32'h0C0C0530; // 的
    rom[9'h01C] = 32'h0C0C0070; // 的
    rom[9'h01D] = 32'h0FFC00B0; // 的
    rom[9'h01E] = 32'h0C001FE0; // 的
    rom[9'h01F] = 32'h04000A40; // 的
    rom[9'h021] = 32'h00000400; // 地
    rom[9'h022] = 32'h03400D00; // 地
    rom[9'h023] = 32'h03430C00; // 地
    rom[9'h024] = 32'h03030C20; // 地
    rom[9'h025] = 32'h2BE30FF4; // 地
    rom[9'h026] = 32'h3FF3BF70; // 地
    rom[9'h027] = 32'h030BFC30; // 地
    rom[9'h028] = 32'h031F0C30; // 地
    rom[9'h029] = 32'h03030C30; // 地
    rom[9'h02A] = 32'h03B30DF0; // 地
    rom[9'h02B] = 32'h0BE30DD0; // 地
    rom[9'h02C] = 32'h3E030408; // 地
    rom[9'h02D] = 32'h1003002C; // 地
    rom[9'h02E] = 32'h0003FFF8; // 地
    rom[9'h02F] = 32'h0000AA90; // 地
    rom[9'h033] = 32'h00018000; // 1
    rom[9'h034] = 32'h002FC000; // 1
    rom[9'h035] = 32'h001AC000; // 1
    rom[9'h036] = 32'h0002C000; // 1
    rom[9'h037] = 32'h0002C000; // 1
    rom[9'h038] = 32'h0002C000; // 1
    rom[9'h039] = 32'h0002C000; // 1
    rom[9'h03A] = 32'h0002C000; // 1
    rom[9'h03B] = 32'h0002C000; // 1
    rom[9'h03C] = 32'h0002C000; // 1
    rom[9'h03D] = 32'h003FFD00; // 1
    rom[9'h03E] = 32'h002AA800; // 1
    rom[9'h043] = 32'h0007D000; // 0
    rom[9'h044] = 32'h001FF400; // 0
    rom[9'h045] = 32'h003C3C00; // 0
    rom[9'h046] = 32'h00740D00; // 0
    rom[9'h047] = 32'h00B00E00; // 0
    rom[9'h048] = 32'h00B00E00; // 0
    rom[9'h049] = 32'h00B00E00; // 0
    rom[9'h04A] = 32'h00700E00; // 0
    rom[9'h04B] = 32'h00740D00; // 0
    rom[9'h04C] = 32'h003C3C00; // 0
    rom[9'h04D] = 32'h001FF400; // 0
    rom[9'h04E] = 32'h0007D000; // 0
    rom[9'h052] = 32'h01AAAA80; // 月
    rom[9'h053] = 32'h02FFFFC0; // 月
    rom[9'h054] = 32'h02C002C0; // 月
    rom[9'h055] = 32'h02C002C0; // 月
    rom[9'h056] = 32'h02FFFFC0; // 月
    rom[9'h057] = 32'h02EAABC0; // 月
    rom[9'h058] = 32'h02C002C0; // 月
    rom[9'h059] = 32'h02C013C0; // 月
    rom[9'h05A] = 32'h03FFFFC0; // 月
    rom[9'h05B] = 32'h038002C0; // 月
    rom[9'h05C] = 32'h070002C0; // 月
    rom[9'h05D] = 32'h0F0002C0; // 月
    rom[9'h05E] = 32'h3C00BFC0; // 月
    rom[9'h05F] = 32'h14003A00; // 月
    rom[9'h062] = 32'h00000040; // 日
    rom[9'h063] = 32'h03FFFFC0; // 日
    rom[9'h064] = 32'h038002C0; // 日
    rom[9'h065] = 32'h038001C0; // 日
    rom[9'h066] = 32'h038001C0; // 日
    rom[9'h067] = 32'h038002C0; // 日
    rom[9'h068] = 32'h03FFFFC0; // 日
    rom[9'h069] = 32'h038002C0; // 日
    rom[9'h06A] = 32'h038001C0; // 日
    rom[9'h06B] = 32'h038002C0; // 日
    rom[9'h06C] = 32'h034001C0; // 日
    rom[9'h06D] = 32'h03FFFFC0; // 日
    rom[9'h06E] = 32'h03EAABC0; // 日
    rom[9'h06F] = 32'h02000080; // 日
    rom[9'h071] = 32'h00004000; // 告
    rom[9'h072] = 32'h00C1C000; // 告
    rom[9'h073] = 32'h02C2C040; // 告
    rom[9'h074] = 32'h03FFFFE0; // 告
    rom[9'h075] = 32'h0F01C000; // 告
    rom[9'h076] = 32'h0C00C000; // 告
    rom[9'h077] = 32'h2FFFFFF8; // 告
    rom[9'h078] = 32'h1EAAAAB4; // 告
    rom[9'h07A] = 32'h03FFFFC0; // 告
    rom[9'h07B] = 32'h03C552C0; // 告
    rom[9'h07C] = 32'h038001C0; // 告
    rom[9'h07D] = 32'h03C552C0; // 告
    rom[9'h07E] = 32'h03FFFFC0; // 告
    rom[9'h07F] = 32'h038001C0; // 告
    rom[9'h081] = 32'h00010000; // 白
    rom[9'h082] = 32'h00038000; // 白
    rom[9'h083] = 32'h000B0000; // 白
    rom[9'h084] = 32'h07FFFFD0; // 白
    rom[9'h085] = 32'h07AAAAE0; // 白
    rom[9'h086] = 32'h070000E0; // 白
    rom[9'h087] = 32'h070000E0; // 白
    rom[9'h088] = 32'h075555D0; // 白
    rom[9'h089] = 32'h07FFFFD0; // 白
    rom[9'h08A] = 32'h070000E0; // 白
    rom[9'h08B] = 32'h070000E0; // 白
    rom[9'h08C] = 32'h070000E0; // 白
    rom[9'h08D] = 32'h07FFFFD0; // 白
    rom[9'h08E] = 32'h07BFFFE0; // 白
    rom[9'h08F] = 32'h070000D0; // 白
    rom[9'h092] = 32'h00D00000; // 气
    rom[9'h093] = 32'h02FFFFF4; // 气
    rom[9'h094] = 32'h03955564; // 气
    rom[9'h095] = 32'h0F6AAA80; // 气
    rom[9'h096] = 32'h2C7FFFC0; // 气
    rom[9'h097] = 32'h3C000000; // 气
    rom[9'h098] = 32'h03FFFF00; // 气
    rom[9'h099] = 32'h00000300; // 气
    rom[9'h09A] = 32'h00000300; // 气
    rom[9'h09B] = 32'h00000340; // 气
    rom[9'h09C] = 32'h00000384; // 气
    rom[9'h09D] = 32'h000003CC; // 气
    rom[9'h09E] = 32'h000000FC; // 气
    rom[9'h09F] = 32'h00000070; // 气
    rom[9'h0A1] = 32'h00000400; // 球
    rom[9'h0A2] = 32'h15501CD0; // 球
    rom[9'h0A3] = 32'h3FF00C30; // 球
    rom[9'h0A4] = 32'h030FFFFC; // 球
    rom[9'h0A5] = 32'h030AAEA8; // 球
    rom[9'h0A6] = 32'h03010C10; // 球
    rom[9'h0A7] = 32'h3FE70C34; // 球
    rom[9'h0A8] = 32'h0743CEE0; // 球
    rom[9'h0A9] = 32'h03001F80; // 球
    rom[9'h0AA] = 32'h0300BF00; // 球
    rom[9'h0AB] = 32'h0353DEC0; // 球
    rom[9'h0AC] = 32'h1BFF0CF0; // 球
    rom[9'h0AD] = 32'h3E0C0C3C; // 球
    rom[9'h0AE] = 32'h0000BC04; // 球
    rom[9'h0AF] = 32'h0000F400; // 球
    rom[9'h0B3] = 32'h000BC000; // 9
    rom[9'h0B4] = 32'h003EF000; // 9
    rom[9'h0B5] = 32'h00743C00; // 9
    rom[9'h0B6] = 32'h00B01C00; // 9
    rom[9'h0B7] = 32'h00B00D00; // 9
    rom[9'h0B8] = 32'h00743E00; // 9
    rom[9'h0B9] = 32'h003FFE00; // 9
    rom[9'h0BA] = 32'h00060D00; // 9
    rom[9'h0BB] = 32'h00002C00; // 9
    rom[9'h0BC] = 32'h00103C00; // 9
    rom[9'h0BD] = 32'h007FF000; // 9
    rom[9'h0BE] = 32'h001F8000; // 9
    rom[9'h0C6] = 32'h00014000; // :
    rom[9'h0C7] = 32'h0003C000; // :
    rom[9'h0C8] = 32'h0003C000; // :
    rom[9'h0CC] = 32'h00028000; // :
    rom[9'h0CD] = 32'h0003C000; // :
    rom[9'h0CE] = 32'h00028000; // :
    rom[9'h0D8] = 32'h3FFFFFFC; // 一
    rom[9'h0D9] = 32'h05555554; // 一
    rom[9'h0E3] = 32'h000BD000; // 2
    rom[9'h0E4] = 32'h007FF400; // 2
    rom[9'h0E5] = 32'h00703C00; // 2
    rom[9'h0E6] = 32'h00002C00; // 2
    rom[9'h0E7] = 32'h00003C00; // 2
    rom[9'h0E8] = 32'h00003800; // 2
    rom[9'h0E9] = 32'h0000F000; // 2
    rom[9'h0EA] = 32'h0002D000; // 2
    rom[9'h0EB] = 32'h000B8000; // 2
    rom[9'h0EC] = 32'h002E0000; // 2
    rom[9'h0ED] = 32'h00BFFE00; // 2
    rom[9'h0EE] = 32'h006AA900; // 2
    rom[9'h0F3] = 32'h000BC000; // 9
    rom[9'h0F4] = 32'h003EF000; // 9
    rom[9'h0F5] = 32'h00743C00; // 9
    rom[9'h0F6] = 32'h00B01C00; // 9
    rom[9'h0F7] = 32'h00B00D00; // 9
    rom[9'h0F8] = 32'h00743E00; // 9
    rom[9'h0F9] = 32'h003FFE00; // 9
    rom[9'h0FA] = 32'h00060D00; // 9
    rom[9'h0FB] = 32'h00002C00; // 9
    rom[9'h0FC] = 32'h00103C00; // 9
    rom[9'h0FD] = 32'h007FF000; // 9
    rom[9'h0FE] = 32'h001F8000; // 9
    rom[9'h102] = 32'h01000000; // ℃
    rom[9'h103] = 32'h1FC01FD0; // ℃
    rom[9'h104] = 32'h34E0BFF8; // ℃
    rom[9'h105] = 32'h30B2F020; // ℃
    rom[9'h106] = 32'h2EC3C000; // ℃
    rom[9'h107] = 32'h06038000; // ℃
    rom[9'h108] = 32'h00078000; // ℃
    rom[9'h109] = 32'h00078000; // ℃
    rom[9'h10A] = 32'h00038000; // ℃
    rom[9'h10B] = 32'h0003C000; // ℃
    rom[9'h10C] = 32'h0002F028; // ℃
    rom[9'h10D] = 32'h0000BFFC; // ℃
    rom[9'h10E] = 32'h00000B90; // ℃
    rom[9'h112] = 32'h02AAAA90; // 周
    rom[9'h113] = 32'h07FFFFF0; // 周
    rom[9'h114] = 32'h070180B0; // 周
    rom[9'h115] = 32'h073FFCB0; // 周
    rom[9'h116] = 32'h0712C4B0; // 周
    rom[9'h117] = 32'h0713C4B0; // 周
    rom[9'h118] = 32'h077FFEB0; // 周
    rom[9'h119] = 32'h070000F0; // 周
    rom[9'h11A] = 32'h0B3FFCB0; // 周
    rom[9'h11B] = 32'h0F380CB0; // 周
    rom[9'h11C] = 32'h0E382CB0; // 周
    rom[9'h11D] = 32'h0C3FFCB0; // 周
    rom[9'h11E] = 32'h3C340AF0; // 周
    rom[9'h11F] = 32'h24000B80; // 周
    rom[9'h123] = 32'h0BFFFFE0; // 三
    rom[9'h124] = 32'h0BFFFFE0; // 三
    rom[9'h128] = 32'h03FFFF80; // 三
    rom[9'h129] = 32'h01AAAA40; // 三
    rom[9'h12D] = 32'h1FFFFFF4; // 三
    rom[9'h12E] = 32'h1FFFFFF4; // 三
    rom[9'h132] = 32'h000B4000; // 多
    rom[9'h133] = 32'h003FFF40; // 多
    rom[9'h134] = 32'h01F00F00; // 多
    rom[9'h135] = 32'h0BA43C00; // 多
    rom[9'h136] = 32'h000FF000; // 多
    rom[9'h137] = 32'h002F2800; // 多
    rom[9'h138] = 32'h0FF4BEA0; // 多
    rom[9'h139] = 32'h0E03FFF8; // 多
    rom[9'h13A] = 32'h003E00F0; // 多
    rom[9'h13B] = 32'h01F3C3C0; // 多
    rom[9'h13C] = 32'h0000FF00; // 多
    rom[9'h13D] = 32'h000BF400; // 多
    rom[9'h13E] = 32'h0FFF4000; // 多
    rom[9'h13F] = 32'h0E400000; // 多
    rom[9'h143] = 32'h03FFFFC0; // 云
    rom[9'h144] = 32'h01000040; // 云
    rom[9'h147] = 32'h3FFFFFFC; // 云
    rom[9'h148] = 32'h1AAFAAA4; // 云
    rom[9'h149] = 32'h002C0000; // 云
    rom[9'h14A] = 32'h00780E00; // 云
    rom[9'h14B] = 32'h00F00B00; // 云
    rom[9'h14C] = 32'h03C003C0; // 云
    rom[9'h14D] = 32'h0BFFFFE0; // 云
    rom[9'h14E] = 32'h0FFE94F0; // 云
    rom[9'h14F] = 32'h00000020; // 云
    rom[9'h153] = 32'h0FFFFFF0; // 四
    rom[9'h154] = 32'h0E6D75B0; // 四
    rom[9'h155] = 32'h0C1C3030; // 四
    rom[9'h156] = 32'h0C2C3070; // 四
    rom[9'h157] = 32'h0C2C3070; // 四
    rom[9'h158] = 32'h0C3C3030; // 四
    rom[9'h159] = 32'h0C3439B0; // 四
    rom[9'h15A] = 32'h0EF02FF0; // 四
    rom[9'h15B] = 32'h0D800030; // 四
    rom[9'h15C] = 32'h0D000070; // 四
    rom[9'h15D] = 32'h0FFFFFF0; // 四
    rom[9'h15E] = 32'h0C000070; // 四
    rom[9'h15F] = 32'h04000000; // 四
    rom[9'h162] = 32'h0003C000; // 今
    rom[9'h163] = 32'h000FF000; // 今
    rom[9'h164] = 32'h003C3C00; // 今
    rom[9'h165] = 32'h00F40F40; // 今
    rom[9'h166] = 32'h0BC743F4; // 今
    rom[9'h167] = 32'h3E02E078; // 今
    rom[9'h168] = 32'h00007000; // 今
    rom[9'h169] = 32'h03FFFFC0; // 今
    rom[9'h16A] = 32'h02AAABC0; // 今
    rom[9'h16B] = 32'h00000B00; // 今
    rom[9'h16C] = 32'h00002D00; // 今
    rom[9'h16D] = 32'h00007800; // 今
    rom[9'h16E] = 32'h0001F000; // 今
    rom[9'h16F] = 32'h0001C000; // 今
    rom[9'h171] = 32'h01000400; // 搜
    rom[9'h172] = 32'h0340AC00; // 搜
    rom[9'h173] = 32'h030BEEF0; // 搜
    rom[9'h174] = 32'h074E1C34; // 搜
    rom[9'h175] = 32'h3FEBEDF0; // 搜
    rom[9'h176] = 32'h030F1C30; // 搜
    rom[9'h177] = 32'h030F2D74; // 搜
    rom[9'h178] = 32'h03E7FFF0; // 搜
    rom[9'h179] = 32'h2FD01C00; // 搜
    rom[9'h17A] = 32'h3F0FFFF0; // 搜
    rom[9'h17B] = 32'h030380E0; // 搜
    rom[9'h17C] = 32'h0301D3C0; // 搜
    rom[9'h17D] = 32'h03007F00; // 搜
    rom[9'h17E] = 32'h1F1BFBF4; // 搜
    rom[9'h17F] = 32'h0E2E0074; // 搜
    rom[9'h181] = 32'h00004000; // 索
    rom[9'h182] = 32'h0003C000; // 索
    rom[9'h183] = 32'h1FFFFFF4; // 索
    rom[9'h184] = 32'h0003C000; // 索
    rom[9'h185] = 32'h16A7DA94; // 索
    rom[9'h186] = 32'h2FEFFBF8; // 索
    rom[9'h187] = 32'h2C1D083C; // 索
    rom[9'h188] = 32'h16F5FC14; // 索
    rom[9'h189] = 32'h02AFC300; // 索
    rom[9'h18A] = 32'h00BC1BC0; // 索
    rom[9'h18B] = 32'h0FFFF9F0; // 索
    rom[9'h18C] = 32'h0051C520; // 索
    rom[9'h18D] = 32'h02D1CBC0; // 索
    rom[9'h18E] = 32'h1F0BC0F4; // 索
    rom[9'h18F] = 32'h081F4010; // 索
    rom[9'h192] = 32'h0FFFFFF0; // 回
    rom[9'h193] = 32'h1FFFFFF4; // 回
    rom[9'h194] = 32'h0C000030; // 回
    rom[9'h195] = 32'h0C100030; // 回
    rom[9'h196] = 32'h0C3FFC30; // 回
    rom[9'h197] = 32'h0C342C30; // 回
    rom[9'h198] = 32'h0C342C30; // 回
    rom[9'h199] = 32'h0C301C30; // 回
    rom[9'h19A] = 32'h0C3FFC30; // 回
    rom[9'h19B] = 32'h0C2AA830; // 回
    rom[9'h19C] = 32'h0C000030; // 回
    rom[9'h19D] = 32'h0D555570; // 回
    rom[9'h19E] = 32'h1FFFFFF4; // 回
    rom[9'h19F] = 32'h0C000030; // 回
    rom[9'h1A1] = 32'h00010000; // 家
    rom[9'h1A2] = 32'h0003C000; // 家
    rom[9'h1A3] = 32'h1FFFFFF4; // 家
    rom[9'h1A4] = 32'h0C000034; // 家
    rom[9'h1A5] = 32'h1CA55634; // 家
    rom[9'h1A6] = 32'h05FFFF00; // 家
    rom[9'h1A7] = 32'h002F00C0; // 家
    rom[9'h1A8] = 32'h0BF387C0; // 家
    rom[9'h1A9] = 32'h0E0FEE00; // 家
    rom[9'h1AA] = 32'h00F8FE00; // 家
    rom[9'h1AB] = 32'h0F83D300; // 家
    rom[9'h1AC] = 32'h002EB3C0; // 家
    rom[9'h1AD] = 32'h07F0F0F4; // 家
    rom[9'h1AE] = 32'h1F0BD038; // 家
    rom[9'h1AF] = 32'h000F4000; // 家
    rom[9'h1B2] = 32'h00342C00; // 公
    rom[9'h1B3] = 32'h00741D00; // 公
    rom[9'h1B4] = 32'h00F00F00; // 公
    rom[9'h1B5] = 32'h02C003C0; // 公
    rom[9'h1B6] = 32'h078240F0; // 公
    rom[9'h1B7] = 32'h1F07807C; // 公
    rom[9'h1B8] = 32'h080F0020; // 公
    rom[9'h1B9] = 32'h002C0000; // 公
    rom[9'h1BA] = 32'h00381E00; // 公
    rom[9'h1BB] = 32'h00F00700; // 公
    rom[9'h1BC] = 32'h03C157C0; // 公
    rom[9'h1BD] = 32'h0BFFFFE0; // 公
    rom[9'h1BE] = 32'h025000B0; // 公
    rom[9'h1BF] = 32'h00000010; // 公
    rom[9'h1C2] = 32'h05555550; // 司
    rom[9'h1C3] = 32'h1FFFFFF0; // 司
    rom[9'h1C4] = 32'h000000B0; // 司
    rom[9'h1C5] = 32'h0AAAA8B0; // 司
    rom[9'h1C6] = 32'h0FFFFCB0; // 司
    rom[9'h1C7] = 32'h000000B0; // 司
    rom[9'h1C8] = 32'h03FFF0B0; // 司
    rom[9'h1C9] = 32'h0344B0B0; // 司
    rom[9'h1CA] = 32'h030070B0; // 司
    rom[9'h1CB] = 32'h0344B0B0; // 司
    rom[9'h1CC] = 32'h03FFF0B0; // 司
    rom[9'h1CD] = 32'h030000B0; // 司
    rom[9'h1CE] = 32'h01000FF0; // 司
    rom[9'h1CF] = 32'h00000F80; // 司
    rom[9'h1E2] = 32'h0003C000; // home shortcut
    rom[9'h1E3] = 32'h001E7400; // home shortcut
    rom[9'h1E4] = 32'h00741E00; // home shortcut
    rom[9'h1E5] = 32'h02D00380; // home shortcut
    rom[9'h1E6] = 32'h0B0000E0; // home shortcut
    rom[9'h1E7] = 32'h1F0000B8; // home shortcut
    rom[9'h1E8] = 32'h030000D0; // home shortcut
    rom[9'h1E9] = 32'h030EB0D0; // home shortcut
    rom[9'h1EA] = 32'h030C24D0; // home shortcut
    rom[9'h1EB] = 32'h030824D0; // home shortcut
    rom[9'h1EC] = 32'h030C24D0; // home shortcut
    rom[9'h1ED] = 32'h03FFFFC0; // home shortcut
    rom[9'h1F1] = 32'h002AA900; // vehicle shortcut
    rom[9'h1F2] = 32'h007FFE00; // vehicle shortcut
    rom[9'h1F3] = 32'h00700E00; // vehicle shortcut
    rom[9'h1F4] = 32'h00700E00; // vehicle shortcut
    rom[9'h1F5] = 32'h1BFFFFE4; // vehicle shortcut
    rom[9'h1F6] = 32'h2EBAAFB8; // vehicle shortcut
    rom[9'h1F7] = 32'h2AF28B68; // vehicle shortcut
    rom[9'h1F8] = 32'h2EF28BB8; // vehicle shortcut
    rom[9'h1F9] = 32'h2C700E38; // vehicle shortcut
    rom[9'h1FA] = 32'h2EF28BB8; // vehicle shortcut
    rom[9'h1FB] = 32'h2EF28BB8; // vehicle shortcut
    rom[9'h1FC] = 32'h2C300E38; // vehicle shortcut
    rom[9'h1FD] = 32'h2EBAAFB8; // vehicle shortcut
    rom[9'h1FE] = 32'h1BEFFAE4; // vehicle shortcut
end
always @(posedge I_clk) O_row <= rom[I_addr];
endmodule
// Supplied toolbar parsed/redrawn by sim/generate_bottom_nav_icons.py.
// Thirteen 24px icons + one shared 36x16 temperature: 1008 words.
module video_bottom_nav_rom (
    input wire I_clk, input wire [9:0] I_addr,
    input wire [2:0] I_lane, input wire I_fan,
    output wire [1:0] O_cov, output reg [23:0] O_rgb
);
reg [15:0] rom [0:1023]; /* fehdl force_ram=1, ram_style="bram" */
integer i;
initial begin
    for (i=0;i<1024;i=i+1) rom[i]=16'd0;
    rom[10'd10] = 16'h03D0;
    rom[10'd13] = 16'h1FB4;
    rom[10'd16] = 16'h7C2E;
    rom[10'd18] = 16'h0002;
    rom[10'd19] = 16'hE007;
    rom[10'd20] = 16'h8000;
    rom[10'd21] = 16'h000B;
    rom[10'd22] = 16'h4001;
    rom[10'd23] = 16'hF000;
    rom[10'd24] = 16'h003D;
    rom[10'd26] = 16'h3D00;
    rom[10'd27] = 16'h01F4;
    rom[10'd29] = 16'h0F40;
    rom[10'd30] = 16'h07F0;
    rom[10'd32] = 16'h0BE0;
    rom[10'd33] = 16'h0AB0;
    rom[10'd35] = 16'h0EB0;
    rom[10'd36] = 16'h00B0;
    rom[10'd38] = 16'h0F00;
    rom[10'd39] = 16'h00B0;
    rom[10'd40] = 16'h1AA4;
    rom[10'd41] = 16'h0F00;
    rom[10'd42] = 16'h00B0;
    rom[10'd43] = 16'h3FFD;
    rom[10'd44] = 16'h0F00;
    rom[10'd45] = 16'h00B0;
    rom[10'd46] = 16'h340D;
    rom[10'd47] = 16'h0F00;
    rom[10'd48] = 16'h00B0;
    rom[10'd49] = 16'h340D;
    rom[10'd50] = 16'h0F00;
    rom[10'd51] = 16'h00B0;
    rom[10'd52] = 16'h340D;
    rom[10'd53] = 16'h0F00;
    rom[10'd54] = 16'h00B0;
    rom[10'd55] = 16'h340D;
    rom[10'd56] = 16'h0F00;
    rom[10'd57] = 16'h00BA;
    rom[10'd58] = 16'hBAAE;
    rom[10'd59] = 16'hAF00;
    rom[10'd60] = 16'h007F;
    rom[10'd61] = 16'hFFFF;
    rom[10'd62] = 16'hFE00;
    rom[10'd87] = 16'h001A;
    rom[10'd88] = 16'hAAAA;
    rom[10'd89] = 16'hA400;
    rom[10'd90] = 16'h003F;
    rom[10'd91] = 16'hFFFF;
    rom[10'd92] = 16'hFD00;
    rom[10'd93] = 16'h0078;
    rom[10'd95] = 16'h1E00;
    rom[10'd96] = 16'h00B0;
    rom[10'd98] = 16'h0F00;
    rom[10'd99] = 16'h00F0;
    rom[10'd101] = 16'h0B00;
    rom[10'd102] = 16'h00E0;
    rom[10'd104] = 16'h0740;
    rom[10'd105] = 16'h01EA;
    rom[10'd106] = 16'hAAAA;
    rom[10'd107] = 16'hAB80;
    rom[10'd108] = 16'h02FF;
    rom[10'd109] = 16'hFFFF;
    rom[10'd110] = 16'hFFC0;
    rom[10'd111] = 16'h03C0;
    rom[10'd113] = 16'h02C0;
    rom[10'd114] = 16'h038A;
    rom[10'd115] = 16'h9002;
    rom[10'd116] = 16'hA6C0;
    rom[10'd117] = 16'h038F;
    rom[10'd118] = 16'hD003;
    rom[10'd119] = 16'hF6C0;
    rom[10'd120] = 16'h03C0;
    rom[10'd122] = 16'h02C0;
    rom[10'd123] = 16'h03EF;
    rom[10'd124] = 16'hFFFF;
    rom[10'd125] = 16'hFFC0;
    rom[10'd126] = 16'h01FF;
    rom[10'd127] = 16'hFFFF;
    rom[10'd128] = 16'hFFC0;
    rom[10'd129] = 16'h01E0;
    rom[10'd131] = 16'h0780;
    rom[10'd132] = 16'h01E0;
    rom[10'd134] = 16'h0780;
    rom[10'd135] = 16'h0040;
    rom[10'd137] = 16'h0100;
    rom[10'd154] = 16'h6AAA;
    rom[10'd155] = 16'hAA90;
    rom[10'd157] = 16'h7FFF;
    rom[10'd158] = 16'hFFF0;
    rom[10'd161] = 16'h00B0;
    rom[10'd164] = 16'h00B0;
    rom[10'd165] = 16'h001B;
    rom[10'd166] = 16'hFFFF;
    rom[10'd167] = 16'hE4B0;
    rom[10'd168] = 16'h002F;
    rom[10'd169] = 16'hFFFF;
    rom[10'd170] = 16'hFCB0;
    rom[10'd171] = 16'h002C;
    rom[10'd173] = 16'h3CB0;
    rom[10'd174] = 16'h002C;
    rom[10'd176] = 16'h3CB0;
    rom[10'd177] = 16'h002C;
    rom[10'd179] = 16'h3CB0;
    rom[10'd180] = 16'h002C;
    rom[10'd182] = 16'h3CB0;
    rom[10'd183] = 16'h002C;
    rom[10'd185] = 16'h3CB0;
    rom[10'd186] = 16'h002C;
    rom[10'd188] = 16'h3CB0;
    rom[10'd189] = 16'h002C;
    rom[10'd191] = 16'h3CB0;
    rom[10'd192] = 16'h002C;
    rom[10'd194] = 16'h3C60;
    rom[10'd195] = 16'h002C;
    rom[10'd197] = 16'h3C00;
    rom[10'd198] = 16'h002C;
    rom[10'd200] = 16'h3C00;
    rom[10'd201] = 16'h002E;
    rom[10'd202] = 16'hAAAA;
    rom[10'd203] = 16'hBC00;
    rom[10'd204] = 16'h001F;
    rom[10'd205] = 16'hFFFF;
    rom[10'd206] = 16'hF800;
    rom[10'd223] = 16'h0024;
    rom[10'd224] = 16'h9240;
    rom[10'd226] = 16'h002C;
    rom[10'd227] = 16'hB2C0;
    rom[10'd228] = 16'h00F0;
    rom[10'd229] = 16'hF00C;
    rom[10'd230] = 16'h30C0;
    rom[10'd231] = 16'h00F0;
    rom[10'd232] = 16'hF01C;
    rom[10'd233] = 16'h71C0;
    rom[10'd234] = 16'h00B0;
    rom[10'd235] = 16'hB438;
    rom[10'd236] = 16'hE380;
    rom[10'd237] = 16'h00B4;
    rom[10'd238] = 16'h7430;
    rom[10'd239] = 16'hC300;
    rom[10'd240] = 16'h0074;
    rom[10'd241] = 16'h7834;
    rom[10'd242] = 16'hD380;
    rom[10'd243] = 16'h0078;
    rom[10'd244] = 16'h3818;
    rom[10'd245] = 16'h6180;
    rom[10'd246] = 16'h0078;
    rom[10'd247] = 16'h3C00;
    rom[10'd249] = 16'h0038;
    rom[10'd250] = 16'h3EBE;
    rom[10'd251] = 16'hF000;
    rom[10'd252] = 16'h003C;
    rom[10'd253] = 16'h2FFF;
    rom[10'd254] = 16'hF000;
    rom[10'd255] = 16'h003C;
    rom[10'd256] = 16'h0F00;
    rom[10'd258] = 16'h003C;
    rom[10'd259] = 16'h07AA;
    rom[10'd260] = 16'hA900;
    rom[10'd261] = 16'h002E;
    rom[10'd262] = 16'h02FF;
    rom[10'd263] = 16'hFE00;
    rom[10'd264] = 16'h0007;
    rom[10'd265] = 16'hD000;
    rom[10'd268] = 16'hFFAA;
    rom[10'd269] = 16'hABC0;
    rom[10'd271] = 16'h2FFF;
    rom[10'd272] = 16'hFFC0;
    rom[10'd298] = 16'h001F;
    rom[10'd299] = 16'h4000;
    rom[10'd301] = 16'h003F;
    rom[10'd302] = 16'hC000;
    rom[10'd303] = 16'h0009;
    rom[10'd304] = 16'h003F;
    rom[10'd305] = 16'hD000;
    rom[10'd306] = 16'h0007;
    rom[10'd307] = 16'h401F;
    rom[10'd308] = 16'h8000;
    rom[10'd309] = 16'h06AA;
    rom[10'd310] = 16'hD001;
    rom[10'd312] = 16'h07FF;
    rom[10'd313] = 16'hD0F0;
    rom[10'd315] = 16'h0007;
    rom[10'd316] = 16'h40F4;
    rom[10'd318] = 16'h0006;
    rom[10'd319] = 16'h00F0;
    rom[10'd321] = 16'h0024;
    rom[10'd322] = 16'h01F0;
    rom[10'd324] = 16'h001D;
    rom[10'd325] = 16'h01E0;
    rom[10'd327] = 16'h06AB;
    rom[10'd328] = 16'h43FA;
    rom[10'd329] = 16'h9000;
    rom[10'd330] = 16'h07FF;
    rom[10'd331] = 16'h4BFF;
    rom[10'd332] = 16'hF400;
    rom[10'd333] = 16'h001D;
    rom[10'd334] = 16'h2F40;
    rom[10'd335] = 16'h7800;
    rom[10'd336] = 16'h0028;
    rom[10'd337] = 16'hBD00;
    rom[10'd338] = 16'h3C00;
    rom[10'd339] = 16'h0002;
    rom[10'd340] = 16'hF400;
    rom[10'd341] = 16'h2D00;
    rom[10'd342] = 16'h000F;
    rom[10'd343] = 16'hD000;
    rom[10'd344] = 16'h0F00;
    rom[10'd345] = 16'h000F;
    rom[10'd346] = 16'h4000;
    rom[10'd347] = 16'h0F00;
    rom[10'd381] = 16'h002A;
    rom[10'd382] = 16'hAAAA;
    rom[10'd383] = 16'hA900;
    rom[10'd384] = 16'h00FF;
    rom[10'd385] = 16'hFFFF;
    rom[10'd386] = 16'hFF00;
    rom[10'd387] = 16'h01C0;
    rom[10'd389] = 16'h0380;
    rom[10'd390] = 16'h0380;
    rom[10'd391] = 16'h2FA4;
    rom[10'd392] = 16'h01C0;
    rom[10'd393] = 16'h0701;
    rom[10'd394] = 16'hFABD;
    rom[10'd395] = 16'h00E0;
    rom[10'd396] = 16'h0E07;
    rom[10'd397] = 16'h401B;
    rom[10'd398] = 16'h4070;
    rom[10'd399] = 16'h0D09;
    rom[10'd400] = 16'h003F;
    rom[10'd401] = 16'h4034;
    rom[10'd402] = 16'h0D00;
    rom[10'd404] = 16'h0034;
    rom[10'd405] = 16'h0EBE;
    rom[10'd406] = 16'hAAAA;
    rom[10'd407] = 16'hBEB4;
    rom[10'd408] = 16'h0BFF;
    rom[10'd409] = 16'hFFFF;
    rom[10'd410] = 16'hFFE0;
    rom[10'd411] = 16'h003C;
    rom[10'd413] = 16'h3C00;
    rom[10'd414] = 16'h003C;
    rom[10'd416] = 16'h3C00;
    rom[10'd439] = 16'h0240;
    rom[10'd442] = 16'h0FD0;
    rom[10'd445] = 16'h2FF0;
    rom[10'd448] = 16'h3FF0;
    rom[10'd451] = 16'h3FF4;
    rom[10'd454] = 16'h3FF4;
    rom[10'd457] = 16'h2FF0;
    rom[10'd459] = 16'h0005;
    rom[10'd460] = 16'h1FD6;
    rom[10'd461] = 16'hFE00;
    rom[10'd462] = 16'h01FF;
    rom[10'd463] = 16'hEFEF;
    rom[10'd464] = 16'hFFC0;
    rom[10'd465] = 16'h07FF;
    rom[10'd466] = 16'hFFFF;
    rom[10'd467] = 16'hFFE0;
    rom[10'd468] = 16'h0BFF;
    rom[10'd469] = 16'hFFFF;
    rom[10'd470] = 16'hFFD0;
    rom[10'd471] = 16'h03FF;
    rom[10'd472] = 16'hFBD7;
    rom[10'd473] = 16'hFF40;
    rom[10'd474] = 16'h00BF;
    rom[10'd475] = 16'h97F4;
    rom[10'd476] = 16'h5000;
    rom[10'd478] = 16'h0FF8;
    rom[10'd481] = 16'h1FFC;
    rom[10'd484] = 16'h1FFC;
    rom[10'd487] = 16'h0FFC;
    rom[10'd490] = 16'h0FF8;
    rom[10'd493] = 16'h07F0;
    rom[10'd496] = 16'h0180;
    rom[10'd517] = 16'hBFFE;
    rom[10'd518] = 16'h4000;
    rom[10'd519] = 16'h001F;
    rom[10'd520] = 16'hFAAF;
    rom[10'd521] = 16'hF800;
    rom[10'd522] = 16'h00B9;
    rom[10'd524] = 16'h6E00;
    rom[10'd525] = 16'h02D0;
    rom[10'd527] = 16'h07C0;
    rom[10'd528] = 16'h0B40;
    rom[10'd530] = 16'h01E0;
    rom[10'd531] = 16'h0B00;
    rom[10'd533] = 16'h00B0;
    rom[10'd534] = 16'h0341;
    rom[10'd535] = 16'h4141;
    rom[10'd536] = 16'h40E0;
    rom[10'd537] = 16'h0383;
    rom[10'd538] = 16'hD3D3;
    rom[10'd539] = 16'hD0D0;
    rom[10'd540] = 16'h02CE;
    rom[10'd541] = 16'hFEFE;
    rom[10'd542] = 16'hF1C0;
    rom[10'd543] = 16'h01C4;
    rom[10'd544] = 16'hD4D4;
    rom[10'd545] = 16'hD2C0;
    rom[10'd546] = 16'h01D1;
    rom[10'd547] = 16'hC1C1;
    rom[10'd548] = 16'hC380;
    rom[10'd549] = 16'h00E2;
    rom[10'd550] = 16'h8282;
    rom[10'd551] = 16'h8340;
    rom[10'd552] = 16'h00F2;
    rom[10'd553] = 16'h4242;
    rom[10'd554] = 16'h8B00;
    rom[10'd555] = 16'h00B3;
    rom[10'd556] = 16'h0303;
    rom[10'd557] = 16'h0B00;
    rom[10'd558] = 16'h0003;
    rom[10'd559] = 16'h0303;
    rom[10'd561] = 16'h0003;
    rom[10'd562] = 16'h8383;
    rom[10'd563] = 16'h8000;
    rom[10'd564] = 16'h0001;
    rom[10'd565] = 16'h4141;
    rom[10'd566] = 16'h4000;
    rom[10'd591] = 16'h06AA;
    rom[10'd592] = 16'hAAAA;
    rom[10'd593] = 16'hAA90;
    rom[10'd594] = 16'h0BFF;
    rom[10'd595] = 16'hFFFF;
    rom[10'd596] = 16'hFFF0;
    rom[10'd597] = 16'h0B00;
    rom[10'd599] = 16'h00B0;
    rom[10'd600] = 16'h0B00;
    rom[10'd602] = 16'h00B0;
    rom[10'd603] = 16'h0B00;
    rom[10'd605] = 16'h00B0;
    rom[10'd606] = 16'h0B01;
    rom[10'd607] = 16'h4141;
    rom[10'd608] = 16'h40B0;
    rom[10'd609] = 16'h0B03;
    rom[10'd610] = 16'hD3D3;
    rom[10'd611] = 16'hD0B0;
    rom[10'd612] = 16'h0B0E;
    rom[10'd613] = 16'hFEFE;
    rom[10'd614] = 16'hF4B0;
    rom[10'd615] = 16'h0B04;
    rom[10'd616] = 16'hD4D4;
    rom[10'd617] = 16'hD0B0;
    rom[10'd618] = 16'h0B01;
    rom[10'd619] = 16'hC1C1;
    rom[10'd620] = 16'hC0B0;
    rom[10'd621] = 16'h0B02;
    rom[10'd622] = 16'h8282;
    rom[10'd623] = 16'h80B0;
    rom[10'd624] = 16'h0BAB;
    rom[10'd625] = 16'hEBEB;
    rom[10'd626] = 16'hEAF0;
    rom[10'd627] = 16'h06FF;
    rom[10'd628] = 16'hFFFF;
    rom[10'd629] = 16'hFFD0;
    rom[10'd630] = 16'h0003;
    rom[10'd631] = 16'h0303;
    rom[10'd633] = 16'h0003;
    rom[10'd634] = 16'h8383;
    rom[10'd635] = 16'h8000;
    rom[10'd636] = 16'h0001;
    rom[10'd637] = 16'h4141;
    rom[10'd638] = 16'h4000;
    rom[10'd654] = 16'h0186;
    rom[10'd655] = 16'h1800;
    rom[10'd657] = 16'h038E;
    rom[10'd658] = 16'h3800;
    rom[10'd660] = 16'h030C;
    rom[10'd661] = 16'h300F;
    rom[10'd662] = 16'h0F00;
    rom[10'd663] = 16'h034D;
    rom[10'd664] = 16'h340F;
    rom[10'd665] = 16'h0F00;
    rom[10'd666] = 16'h02CB;
    rom[10'd667] = 16'h2C1E;
    rom[10'd668] = 16'h0E00;
    rom[10'd669] = 16'h00C3;
    rom[10'd670] = 16'h0C1D;
    rom[10'd671] = 16'h1E00;
    rom[10'd672] = 16'h02C7;
    rom[10'd673] = 16'h1C2D;
    rom[10'd674] = 16'h1D00;
    rom[10'd675] = 16'h0249;
    rom[10'd676] = 16'h242C;
    rom[10'd677] = 16'h2D00;
    rom[10'd679] = 16'h003C;
    rom[10'd680] = 16'h2D00;
    rom[10'd681] = 16'h000F;
    rom[10'd682] = 16'hBEBC;
    rom[10'd683] = 16'h2C00;
    rom[10'd684] = 16'h000F;
    rom[10'd685] = 16'hFFF8;
    rom[10'd686] = 16'h3C00;
    rom[10'd688] = 16'h00F0;
    rom[10'd689] = 16'h3C00;
    rom[10'd690] = 16'h006A;
    rom[10'd691] = 16'hAAD0;
    rom[10'd692] = 16'h3C00;
    rom[10'd693] = 16'h00BF;
    rom[10'd694] = 16'hFF80;
    rom[10'd695] = 16'hB800;
    rom[10'd697] = 16'h0007;
    rom[10'd698] = 16'hD000;
    rom[10'd699] = 16'h03EA;
    rom[10'd700] = 16'hAAFF;
    rom[10'd702] = 16'h03FF;
    rom[10'd703] = 16'hFFF8;
    rom[10'd733] = 16'h0140;
    rom[10'd734] = 16'h2400;
    rom[10'd736] = 16'h0BC0;
    rom[10'd737] = 16'h1D00;
    rom[10'd739] = 16'h2FC0;
    rom[10'd740] = 16'h0700;
    rom[10'd741] = 16'h0001;
    rom[10'd742] = 16'hF2C5;
    rom[10'd743] = 16'h02C0;
    rom[10'd744] = 16'h06AB;
    rom[10'd745] = 16'hC2C7;
    rom[10'd746] = 16'h40D0;
    rom[10'd747] = 16'h0FFE;
    rom[10'd748] = 16'h02C1;
    rom[10'd749] = 16'hD0E0;
    rom[10'd750] = 16'h0F00;
    rom[10'd751] = 16'h02C0;
    rom[10'd752] = 16'hB0A0;
    rom[10'd753] = 16'h0F00;
    rom[10'd754] = 16'h02C0;
    rom[10'd755] = 16'h70B0;
    rom[10'd756] = 16'h0F00;
    rom[10'd757] = 16'h02C0;
    rom[10'd758] = 16'h70B0;
    rom[10'd759] = 16'h0F00;
    rom[10'd760] = 16'h02C0;
    rom[10'd761] = 16'hB0B0;
    rom[10'd762] = 16'h0FFD;
    rom[10'd763] = 16'h02C0;
    rom[10'd764] = 16'hD0E0;
    rom[10'd765] = 16'h06FF;
    rom[10'd766] = 16'h82C7;
    rom[10'd767] = 16'h80D0;
    rom[10'd768] = 16'h0001;
    rom[10'd769] = 16'hE2C6;
    rom[10'd770] = 16'h02C0;
    rom[10'd772] = 16'h7EC0;
    rom[10'd773] = 16'h0340;
    rom[10'd775] = 16'h0FC0;
    rom[10'd776] = 16'h1D00;
    rom[10'd778] = 16'h0280;
    rom[10'd779] = 16'h2800;
    rom[10'd801] = 16'h0006;
    rom[10'd802] = 16'hAAA9;
    rom[10'd804] = 16'h000B;
    rom[10'd805] = 16'hFFFF;
    rom[10'd806] = 16'h4000;
    rom[10'd807] = 16'h000F;
    rom[10'd808] = 16'h000B;
    rom[10'd809] = 16'hD000;
    rom[10'd810] = 16'h000F;
    rom[10'd811] = 16'h000A;
    rom[10'd812] = 16'h7400;
    rom[10'd813] = 16'h000F;
    rom[10'd814] = 16'h000B;
    rom[10'd815] = 16'hBD00;
    rom[10'd816] = 16'h000F;
    rom[10'd817] = 16'h0002;
    rom[10'd818] = 16'hEF00;
    rom[10'd819] = 16'h01BF;
    rom[10'd820] = 16'hFFFE;
    rom[10'd821] = 16'hAF40;
    rom[10'd822] = 16'h02FA;
    rom[10'd823] = 16'hFFFF;
    rom[10'd824] = 16'hFBC0;
    rom[10'd825] = 16'h02C0;
    rom[10'd827] = 16'h03C0;
    rom[10'd828] = 16'h02C0;
    rom[10'd830] = 16'h03C0;
    rom[10'd831] = 16'h02C1;
    rom[10'd832] = 16'hAAAA;
    rom[10'd833] = 16'h43C0;
    rom[10'd834] = 16'h02C1;
    rom[10'd835] = 16'hFFFF;
    rom[10'd836] = 16'h43C0;
    rom[10'd837] = 16'h02C0;
    rom[10'd839] = 16'h03C0;
    rom[10'd840] = 16'h02C0;
    rom[10'd842] = 16'h03C0;
    rom[10'd843] = 16'h02C0;
    rom[10'd845] = 16'h03C0;
    rom[10'd846] = 16'h02C0;
    rom[10'd848] = 16'h03C0;
    rom[10'd849] = 16'h02EA;
    rom[10'd850] = 16'hAAAA;
    rom[10'd851] = 16'hABC0;
    rom[10'd852] = 16'h01FF;
    rom[10'd853] = 16'hFFFF;
    rom[10'd854] = 16'hFF80;
    rom[10'd873] = 16'h06AA;
    rom[10'd874] = 16'hAAAA;
    rom[10'd875] = 16'hAA90;
    rom[10'd876] = 16'h0BFF;
    rom[10'd877] = 16'hFFFF;
    rom[10'd878] = 16'hFFF0;
    rom[10'd879] = 16'h0700;
    rom[10'd881] = 16'h00E0;
    rom[10'd882] = 16'h0740;
    rom[10'd884] = 16'h00E0;
    rom[10'd885] = 16'h0380;
    rom[10'd887] = 16'h01D0;
    rom[10'd888] = 16'h03C0;
    rom[10'd890] = 16'h02C0;
    rom[10'd891] = 16'h02C0;
    rom[10'd893] = 16'h03C0;
    rom[10'd894] = 16'h01D0;
    rom[10'd896] = 16'h0380;
    rom[10'd897] = 16'h00D0;
    rom[10'd899] = 16'h0340;
    rom[10'd900] = 16'h00FF;
    rom[10'd901] = 16'hFFBF;
    rom[10'd902] = 16'hFF00;
    rom[10'd903] = 16'h006F;
    rom[10'd904] = 16'hFFFF;
    rom[10'd905] = 16'hFD00;
    rom[10'd907] = 16'h02C0;
    rom[10'd910] = 16'h02C0;
    rom[10'd913] = 16'h02C0;
    rom[10'd916] = 16'h92C5;
    rom[10'd919] = 16'h76DE;
    rom[10'd922] = 16'h1FF8;
    rom[10'd925] = 16'h07E0;
    rom[10'd928] = 16'h0180;
    rom[10'd950] = 16'h2A40;
    rom[10'd951] = 16'h0180;
    rom[10'd952] = 16'h0001;
    rom[10'd953] = 16'hE400;
    rom[10'd954] = 16'h00FB;
    rom[10'd955] = 16'hE02F;
    rom[10'd956] = 16'hC000;
    rom[10'd957] = 16'h0BBD;
    rom[10'd959] = 16'h80B0;
    rom[10'd960] = 16'h1BC0;
    rom[10'd961] = 16'h001E;
    rom[10'd962] = 16'h0F00;
    rom[10'd964] = 16'h7403;
    rom[10'd965] = 16'hC000;
    rom[10'd966] = 16'h2C0B;
    rom[10'd968] = 16'h00B0;
    rom[10'd969] = 16'h03C0;
    rom[10'd970] = 16'h002C;
    rom[10'd971] = 16'h0740;
    rom[10'd973] = 16'hF003;
    rom[10'd974] = 16'hC000;
    rom[10'd975] = 16'h3C07;
    rom[10'd976] = 16'h4000;
    rom[10'd977] = 16'h02D0;
    rom[10'd978] = 16'h03C0;
    rom[10'd979] = 16'h003C;
    rom[10'd980] = 16'h0740;
    rom[10'd981] = 16'h0007;
    rom[10'd982] = 16'h8003;
    rom[10'd983] = 16'hC000;
    rom[10'd984] = 16'h2C07;
    rom[10'd985] = 16'h4000;
    rom[10'd986] = 16'h1E00;
    rom[10'd987] = 16'h03C0;
    rom[10'd988] = 16'h002C;
    rom[10'd989] = 16'h0B00;
    rom[10'd990] = 16'h0078;
    rom[10'd991] = 16'h0003;
    rom[10'd992] = 16'hC018;
    rom[10'd993] = 16'h1E0F;
    rom[10'd994] = 16'h0001;
    rom[10'd995] = 16'hFFFC;
    rom[10'd996] = 16'h7FFC;
    rom[10'd997] = 16'h3D0B;
    rom[10'd998] = 16'hBD00;
    rom[10'd999] = 16'h01AA;
    rom[10'd1000] = 16'hA42A;
    rom[10'd1001] = 16'hA818;
    rom[10'd1002] = 16'h01A4;
end
reg [15:0] word_d; reg [2:0] lane_d; reg fan_d;
always @(posedge I_clk) begin
    word_d <= rom[I_addr]; lane_d <= I_lane; fan_d <= I_fan;
end
assign O_cov = word_d[(7-lane_d)*2 +: 2];
always @(*) begin
    case (O_cov)
        2'd0: O_rgb=24'hFFFFFF;
        2'd1: O_rgb=fan_d ? 24'hDEF1EE : 24'hAEB8C1;
        2'd2: O_rgb=fan_d ? 24'h68CDBE : 24'h697785;
        default: O_rgb=fan_d ? 24'h14A68F : 24'h2B3B4A;
    endcase
end
endmodule
