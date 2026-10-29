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
    ((glyph_cov == 2'd3) ? 24'h26384A :
     (glyph_cov == 2'd2) ? 24'h6B7D8C : 24'hABB7C2) :
    clock_text ?
    ((glyph_cov == 2'd3) ? 24'hFFFFFF :
     (glyph_cov == 2'd2) ? 24'hF2F7FA : 24'hDCE9F0) :
    heading_text ?
    ((glyph_cov == 2'd3) ? 24'h263B4F :
     (glyph_cov == 2'd2) ? 24'h8897A5 : 24'hCAD1D8) :
    ((glyph_cov == 2'd3) ? 24'h354C5E :
     (glyph_cov == 2'd2) ? 24'h91A0AE : 24'hD2D8DE);

// Symmetric 24x24 blue disk with a crisp northeast arrow.
wire nav_circle = card_hit && card_id == 2'd0 &&
    (((pixel_y == 10'd338 || pixel_y == 10'd361) &&
      pixel_x >= 11'd54 && pixel_x < 11'd60) ||
     ((pixel_y == 10'd339 || pixel_y == 10'd360) &&
      pixel_x >= 11'd51 && pixel_x < 11'd63) ||
     ((pixel_y == 10'd340 || pixel_y == 10'd359) &&
      pixel_x >= 11'd50 && pixel_x < 11'd64) ||
     ((pixel_y == 10'd341 || pixel_y == 10'd358) &&
      pixel_x >= 11'd49 && pixel_x < 11'd65) ||
     ((pixel_y == 10'd342 || pixel_y == 10'd357) &&
      pixel_x >= 11'd48 && pixel_x < 11'd66) ||
     ((pixel_y == 10'd343 || pixel_y == 10'd356) &&
      pixel_x >= 11'd47 && pixel_x < 11'd67) ||
     (((pixel_y >= 10'd344 && pixel_y < 10'd347) ||
       (pixel_y >= 10'd353 && pixel_y < 10'd356)) &&
      pixel_x >= 11'd46 && pixel_x < 11'd68) ||
     (pixel_y >= 10'd347 && pixel_y < 10'd353 &&
      pixel_x >= 11'd45 && pixel_x < 11'd69));
wire nav_arrow = nav_circle &&
    (((pixel_x >= 11'd52 && pixel_x <= 11'd62) &&
      (pixel_y >= 10'd344 && pixel_y <= 10'd354) &&
      (pixel_x + pixel_y >= 11'd406) &&
      (pixel_x + pixel_y <= 11'd407)) ||
     (pixel_y >= 10'd343 && pixel_y <= 10'd344 &&
      pixel_x >= 11'd58 && pixel_x <= 11'd63) ||
     (pixel_x >= 11'd62 && pixel_x <= 11'd63 &&
      pixel_y >= 10'd343 && pixel_y <= 10'd349));
wire first_card_separator = card_hit && card_id == 2'd0 &&
    pixel_x == 11'd104 && pixel_y >= 10'd337 && pixel_y < 10'd393;
// Card two: circular album art at left, title above three player controls.
wire cover_next = next_x >= 11'd234 && next_x < 11'd274 &&
                  next_y >= 10'd338 && next_y < 10'd378;
wire [5:0] cover_x = next_x - 11'd234;
wire [5:0] cover_y = next_y - 10'd338;
wire [10:0] cover_addr = ({5'd0,cover_y} << 5) +
                         ({5'd0,cover_y} << 3) + {5'd0,cover_x};
reg cover_valid;
always @(posedge I_clk or posedge I_rst) begin
    if (I_rst) cover_valid <= 1'b0;
    else cover_valid <= cover_next;
end
wire [3:0] cover_index;
wire [23:0] cover_rgb;
video_album_cover_rom u_album_cover_rom (
    .I_clk(I_clk), .I_addr(cover_addr),
    .O_index(cover_index), .O_rgb(cover_rgb)
);
wire cover_pixel = card_hit && card_id == 2'd1 &&
                   cover_valid && (cover_index != 4'd0);
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
// Four higher-detail 40x40 apps plus the unchanged 32x32 sunny icon share
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
    if (next_x >= 11'd500 && next_x < 11'd532 &&
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
wire [10:0] sprite_row = {2'b00,sprite_local_y,3'b000} +
                       ((sprite_id == 3'd4) ? 11'd0 : {4'b0000,sprite_local_y,1'b0});
wire [10:0] sprite_addr = sprite_base + sprite_row + {7'b0000000,sprite_local_x[5:2]};
reg app_valid, sun_valid;
always @(posedge I_clk or posedge I_rst) begin
    if (I_rst) begin
        app_valid <= 1'b0;
        sun_valid <= 1'b0;
    end else begin
        app_valid <= sprite_next && (sprite_id != 3'd4);
        sun_valid <= sprite_next && (sprite_id == 3'd4);
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


// Six bottom navigation pictograms: home, apps, route, music, phone, speaker.
reg [2:0] nav_id;
reg [10:0] nav_left;
always @(*) begin
    nav_id = 3'd7; nav_left = 11'd0;
    if (pixel_x >= 11'd60 && pixel_x < 11'd84) begin
        nav_id = 3'd0; nav_left = 11'd60;
    end else if (pixel_x >= 11'd160 && pixel_x < 11'd184) begin
        nav_id = 3'd1; nav_left = 11'd160;
    end else if (pixel_x >= 11'd260 && pixel_x < 11'd284) begin
        nav_id = 3'd2; nav_left = 11'd260;
    end else if (pixel_x >= 11'd360 && pixel_x < 11'd384) begin
        nav_id = 3'd3; nav_left = 11'd360;
    end else if (pixel_x >= 11'd460 && pixel_x < 11'd484) begin
        nav_id = 3'd4; nav_left = 11'd460;
    end else if (pixel_x >= 11'd560 && pixel_x < 11'd584) begin
        nav_id = 3'd5; nav_left = 11'd560;
    end
end
wire nav_icon_area = nav_hit && nav_id != 3'd7 &&
                     pixel_y >= 10'd448 && pixel_y < 10'd472;
wire [4:0] ix = pixel_x - nav_left;
wire [4:0] iy = pixel_y - 10'd448;
reg nav_icon;
always @(*) begin
    nav_icon = 1'b0;
    if (nav_icon_area) begin
        case (nav_id)
            3'd0: nav_icon =
                ((ix >= 5'd3 && ix <= 5'd12 && ix+iy >= 5'd12 &&
                  ix+iy <= 5'd14 && iy <= 5'd10) ||
                 (ix >= 5'd12 && ix <= 5'd21 && ix >= iy+5'd10 &&
                  ix <= iy+5'd12 && iy <= 5'd10) ||
                 (ix >= 5'd6 && ix <= 5'd18 && iy >= 5'd11 && iy <= 5'd21 &&
                  (ix == 5'd6 || ix == 5'd18 || iy == 5'd21 ||
                   (ix >= 5'd11 && ix <= 5'd13 && iy >= 5'd15))));
            3'd1: nav_icon =
                (((ix >= 5'd3 && ix <= 5'd9) ||
                   (ix >= 5'd14 && ix <= 5'd20)) &&
                 ((iy >= 5'd3 && iy <= 5'd9) ||
                  (iy >= 5'd14 && iy <= 5'd20)) &&
                 (ix == 5'd3 || ix == 5'd9 || ix == 5'd14 || ix == 5'd20 ||
                  iy == 5'd3 || iy == 5'd9 || iy == 5'd14 || iy == 5'd20));
            3'd2: nav_icon =
                ((iy >= 5'd2 && iy <= 5'd17 &&
                  ((ix >= 5'd5 && ix <= 5'd7) ||
                   (ix >= 5'd17 && ix <= 5'd19))) ||
                 (iy >= 5'd17 && iy <= 5'd20 &&
                  ix >= 5'd5 && ix <= 5'd19) ||
                 (ix >= 5'd10 && ix <= 5'd14 &&
                  iy >= 5'd7 && iy <= 5'd12));
            3'd3: nav_icon =
                ((ix >= 5'd11 && ix <= 5'd13 && iy >= 5'd3 && iy <= 5'd18) ||
                 (ix >= 5'd11 && ix <= 5'd20 && iy >= 5'd3 && iy <= 5'd6) ||
                 (ix >= 5'd6 && ix <= 5'd13 && iy >= 5'd17 && iy <= 5'd21));
            3'd4: nav_icon =
                ((ix >= 5'd5 && ix <= 5'd8 && iy >= 5'd4 && iy <= 5'd13) ||
                 (ix >= 5'd8 && ix <= 5'd16 && iy >= 5'd12 && iy <= 5'd17) ||
                 (ix >= 5'd16 && ix <= 5'd20 && iy >= 5'd15 && iy <= 5'd20));
            3'd5: nav_icon =
                ((ix >= 5'd4 && ix <= 5'd8 && iy >= 5'd9 && iy <= 5'd15) ||
                 (ix >= 5'd9 && ix <= 5'd13 && iy >= 5'd7 && iy <= 5'd17) ||
                 (ix >= 5'd16 && ix <= 5'd18 &&
                  iy >= 5'd7 && iy <= 5'd17));
            default: nav_icon = 1'b0;
        endcase
    end
end
wire [7:0] card_r = 8'hFF, card_g = 8'hFF, card_b = 8'hFF;
// Bottom navigation intentionally stays rectangular, all the way to its
// four corners. Only the three floating cards above have rounded contours.
assign O_rgb =
    !I_enable || !I_de ? I_rgb :
    glyph_on ? glyph_color :
    clock_shadow ? 24'h07131C :
    sun_pixel ? sprite_rgb :
    nav_arrow ? 24'hFFFFFF :
    nav_circle ? 24'h168BDC :
    first_card_separator ? 24'hD8E0E7 :
    cover_pixel ? cover_rgb :
    app_pixel ? sprite_rgb :
    music_pause ? 24'h256BB1 :
    (music_previous || music_next) ? 24'h334B5E :
    nav_icon ? ((nav_id == 3'd0) ? 24'h1673D4 : 24'h344556) :
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
    rom[9'h003] = 32'h07FFFFD0; // 目
    rom[9'h004] = 32'h074001D0; // 目
    rom[9'h005] = 32'h074001D0; // 目
    rom[9'h006] = 32'h07FFFFD0; // 目
    rom[9'h007] = 32'h07AAAAD0; // 目
    rom[9'h008] = 32'h070001C0; // 目
    rom[9'h009] = 32'h079556D0; // 目
    rom[9'h00A] = 32'h07FFFFD0; // 目
    rom[9'h00B] = 32'h074412D0; // 目
    rom[9'h00C] = 32'h074001D0; // 目
    rom[9'h00D] = 32'h07FFFFD0; // 目
    rom[9'h00E] = 32'h07AAAAD0; // 目
    rom[9'h00F] = 32'h06000180; // 目
    rom[9'h011] = 32'h00401000; // 的
    rom[9'h012] = 32'h01D03800; // 的
    rom[9'h013] = 32'h01C07400; // 的
    rom[9'h014] = 32'h1BE8BFE4; // 的
    rom[9'h015] = 32'h1EADEAB8; // 的
    rom[9'h016] = 32'h1C1EC034; // 的
    rom[9'h017] = 32'h1C1E9034; // 的
    rom[9'h018] = 32'h1EBC3834; // 的
    rom[9'h019] = 32'h1EAD2D34; // 的
    rom[9'h01A] = 32'h1C0D0E34; // 的
    rom[9'h01B] = 32'h1C1D0574; // 的
    rom[9'h01C] = 32'h1D1D0070; // 的
    rom[9'h01D] = 32'h1FFD00B0; // 的
    rom[9'h01E] = 32'h1D541EE0; // 的
    rom[9'h01F] = 32'h04000A80; // 的
    rom[9'h021] = 32'h00000400; // 地
    rom[9'h022] = 32'h03401D00; // 地
    rom[9'h023] = 32'h03424D00; // 地
    rom[9'h024] = 32'h03474D20; // 地
    rom[9'h025] = 32'h2BA74EF4; // 地
    rom[9'h026] = 32'h2FE3AFB4; // 地
    rom[9'h027] = 32'h034BED34; // 地
    rom[9'h028] = 32'h035F4D34; // 地
    rom[9'h029] = 32'h03474D34; // 地
    rom[9'h02A] = 32'h03A74DB4; // 地
    rom[9'h02B] = 32'h1BE74D90; // 地
    rom[9'h02C] = 32'h3E474418; // 地
    rom[9'h02D] = 32'h1407402C; // 地
    rom[9'h02E] = 32'h0003EEB8; // 地
    rom[9'h02F] = 32'h0001AA90; // 地
    rom[9'h033] = 32'h00018000; // 1
    rom[9'h034] = 32'h001FD000; // 1
    rom[9'h035] = 32'h001AD000; // 1
    rom[9'h036] = 32'h0002D000; // 1
    rom[9'h037] = 32'h0002D000; // 1
    rom[9'h038] = 32'h0002D000; // 1
    rom[9'h039] = 32'h0002D000; // 1
    rom[9'h03A] = 32'h0002D000; // 1
    rom[9'h03B] = 32'h0002D000; // 1
    rom[9'h03C] = 32'h0002D000; // 1
    rom[9'h03D] = 32'h003FFD00; // 1
    rom[9'h03E] = 32'h002AA900; // 1
    rom[9'h043] = 32'h00069000; // 0
    rom[9'h044] = 32'h001EB800; // 0
    rom[9'h045] = 32'h00382C00; // 0
    rom[9'h046] = 32'h00741D00; // 0
    rom[9'h047] = 32'h00B41E00; // 0
    rom[9'h048] = 32'h00B40E00; // 0
    rom[9'h049] = 32'h00B40E00; // 0
    rom[9'h04A] = 32'h00B41E00; // 0
    rom[9'h04B] = 32'h00741D00; // 0
    rom[9'h04C] = 32'h00382C00; // 0
    rom[9'h04D] = 32'h001EB800; // 0
    rom[9'h04E] = 32'h00069000; // 0
    rom[9'h052] = 32'h01AAAA40; // 月
    rom[9'h053] = 32'h02FFFFC0; // 月
    rom[9'h054] = 32'h02C002C0; // 月
    rom[9'h055] = 32'h02C002C0; // 月
    rom[9'h056] = 32'h02FFFFC0; // 月
    rom[9'h057] = 32'h02EAABC0; // 月
    rom[9'h058] = 32'h02C002C0; // 月
    rom[9'h059] = 32'h02D556C0; // 月
    rom[9'h05A] = 32'h02FFFFC0; // 月
    rom[9'h05B] = 32'h038556C0; // 月
    rom[9'h05C] = 32'h074002C0; // 月
    rom[9'h05D] = 32'h0E0002C0; // 月
    rom[9'h05E] = 32'h2D00AB80; // 月
    rom[9'h05F] = 32'h14006A40; // 月
    rom[9'h062] = 32'h01555540; // 日
    rom[9'h063] = 32'h03FFFFC0; // 日
    rom[9'h064] = 32'h039556C0; // 日
    rom[9'h065] = 32'h038002C0; // 日
    rom[9'h066] = 32'h038002C0; // 日
    rom[9'h067] = 32'h039556C0; // 日
    rom[9'h068] = 32'h03FFFFC0; // 日
    rom[9'h069] = 32'h039556C0; // 日
    rom[9'h06A] = 32'h038001C0; // 日
    rom[9'h06B] = 32'h038002C0; // 日
    rom[9'h06C] = 32'h038002C0; // 日
    rom[9'h06D] = 32'h03FFFFC0; // 日
    rom[9'h06E] = 32'h03AAAAC0; // 日
    rom[9'h06F] = 32'h02400180; // 日
    rom[9'h071] = 32'h00004000; // 告
    rom[9'h072] = 32'h01D1C000; // 告
    rom[9'h073] = 32'h02D6D550; // 告
    rom[9'h074] = 32'h07FFFFE0; // 告
    rom[9'h075] = 32'h0F02D000; // 告
    rom[9'h076] = 32'h0901C000; // 告
    rom[9'h077] = 32'h1AFFFFB8; // 告
    rom[9'h078] = 32'h1AAAAAA4; // 告
    rom[9'h07A] = 32'h02FFFFC0; // 告
    rom[9'h07B] = 32'h029556C0; // 告
    rom[9'h07C] = 32'h028002C0; // 告
    rom[9'h07D] = 32'h029556C0; // 告
    rom[9'h07E] = 32'h02FFFFC0; // 告
    rom[9'h07F] = 32'h028002C0; // 告
    rom[9'h081] = 32'h00010000; // 白
    rom[9'h082] = 32'h00078000; // 白
    rom[9'h083] = 32'h000B4000; // 白
    rom[9'h084] = 32'h07FFFFD0; // 白
    rom[9'h085] = 32'h0BAAAAE0; // 白
    rom[9'h086] = 32'h0B0000E0; // 白
    rom[9'h087] = 32'h0B0000E0; // 白
    rom[9'h088] = 32'h075555E0; // 白
    rom[9'h089] = 32'h07FFFFE0; // 白
    rom[9'h08A] = 32'h0B0000E0; // 白
    rom[9'h08B] = 32'h0B0000E0; // 白
    rom[9'h08C] = 32'h0B0000E0; // 白
    rom[9'h08D] = 32'h07AAAAE0; // 白
    rom[9'h08E] = 32'h0BAAAAE0; // 白
    rom[9'h08F] = 32'h06000090; // 白
    rom[9'h091] = 32'h00400000; // 气
    rom[9'h092] = 32'h00D00000; // 气
    rom[9'h093] = 32'h02FAAAA4; // 气
    rom[9'h094] = 32'h03AAAAA4; // 气
    rom[9'h095] = 32'h0B6AAA80; // 气
    rom[9'h096] = 32'h2D6AAA90; // 气
    rom[9'h097] = 32'h29555500; // 气
    rom[9'h098] = 32'h07FFFF40; // 气
    rom[9'h099] = 32'h00000740; // 气
    rom[9'h09A] = 32'h00000740; // 气
    rom[9'h09B] = 32'h00000340; // 气
    rom[9'h09C] = 32'h00000384; // 气
    rom[9'h09D] = 32'h00000288; // 气
    rom[9'h09E] = 32'h000001F8; // 气
    rom[9'h09F] = 32'h00000064; // 气
    rom[9'h0A1] = 32'h00000400; // 球
    rom[9'h0A2] = 32'h15501DD0; // 球
    rom[9'h0A3] = 32'h2FE01C70; // 球
    rom[9'h0A4] = 32'h074BBFB8; // 球
    rom[9'h0A5] = 32'h034AAEA8; // 球
    rom[9'h0A6] = 32'h07451C14; // 球
    rom[9'h0A7] = 32'h2FE75D74; // 球
    rom[9'h0A8] = 32'h17929EE0; // 球
    rom[9'h0A9] = 32'h03416F80; // 球
    rom[9'h0AA] = 32'h0740BF40; // 球
    rom[9'h0AB] = 32'h0352EEC0; // 球
    rom[9'h0AC] = 32'h1BFF5CF0; // 球
    rom[9'h0AD] = 32'h3E5D1C38; // 球
    rom[9'h0AE] = 32'h0000AC14; // 球
    rom[9'h0AF] = 32'h0000A400; // 球
    rom[9'h0B3] = 32'h000A9000; // 9
    rom[9'h0B4] = 32'h002EF400; // 9
    rom[9'h0B5] = 32'h00742C00; // 9
    rom[9'h0B6] = 32'h00B01D00; // 9
    rom[9'h0B7] = 32'h00B01D00; // 9
    rom[9'h0B8] = 32'h00742E00; // 9
    rom[9'h0B9] = 32'h002FEE00; // 9
    rom[9'h0BA] = 32'h00065D00; // 9
    rom[9'h0BB] = 32'h00002D00; // 9
    rom[9'h0BC] = 32'h00107800; // 9
    rom[9'h0BD] = 32'h007EF400; // 9
    rom[9'h0BE] = 32'h001A8000; // 9
    rom[9'h0C6] = 32'h00014000; // :
    rom[9'h0C7] = 32'h0007C000; // :
    rom[9'h0C8] = 32'h00028000; // :
    rom[9'h0CC] = 32'h00028000; // :
    rom[9'h0CD] = 32'h0007D000; // :
    rom[9'h0CE] = 32'h00028000; // :
    rom[9'h0D7] = 32'h15555554; // 一
    rom[9'h0D8] = 32'h3FFFFFFC; // 一
    rom[9'h0D9] = 32'h15555554; // 一
    rom[9'h0E3] = 32'h001A9000; // 2
    rom[9'h0E4] = 32'h007EF400; // 2
    rom[9'h0E5] = 32'h00603C00; // 2
    rom[9'h0E6] = 32'h00002C00; // 2
    rom[9'h0E7] = 32'h00002C00; // 2
    rom[9'h0E8] = 32'h00007800; // 2
    rom[9'h0E9] = 32'h0000B000; // 2
    rom[9'h0EA] = 32'h0002D000; // 2
    rom[9'h0EB] = 32'h000B8000; // 2
    rom[9'h0EC] = 32'h002E0000; // 2
    rom[9'h0ED] = 32'h00BFFE00; // 2
    rom[9'h0EE] = 32'h006AA900; // 2
    rom[9'h0F3] = 32'h000A9000; // 9
    rom[9'h0F4] = 32'h002EF400; // 9
    rom[9'h0F5] = 32'h00742C00; // 9
    rom[9'h0F6] = 32'h00B01D00; // 9
    rom[9'h0F7] = 32'h00B01D00; // 9
    rom[9'h0F8] = 32'h00742E00; // 9
    rom[9'h0F9] = 32'h002FEE00; // 9
    rom[9'h0FA] = 32'h00065D00; // 9
    rom[9'h0FB] = 32'h00002D00; // 9
    rom[9'h0FC] = 32'h00107800; // 9
    rom[9'h0FD] = 32'h007EF400; // 9
    rom[9'h0FE] = 32'h001A8000; // 9
    rom[9'h102] = 32'h01000000; // ℃
    rom[9'h103] = 32'h1E801A90; // ℃
    rom[9'h104] = 32'h34A0BEF8; // ℃
    rom[9'h105] = 32'h34A2E014; // ℃
    rom[9'h106] = 32'h2ED3C000; // ℃
    rom[9'h107] = 32'h06478000; // ℃
    rom[9'h108] = 32'h00078000; // ℃
    rom[9'h109] = 32'h00078000; // ℃
    rom[9'h10A] = 32'h00078000; // ℃
    rom[9'h10B] = 32'h0003C000; // ℃
    rom[9'h10C] = 32'h0002E028; // ℃
    rom[9'h10D] = 32'h0000BFF8; // ℃
    rom[9'h10E] = 32'h00001A90; // ℃
    rom[9'h112] = 32'h06AAAA90; // 周
    rom[9'h113] = 32'h07FFFFF0; // 周
    rom[9'h114] = 32'h070280B0; // 周
    rom[9'h115] = 32'h076FEDB0; // 周
    rom[9'h116] = 32'h0716D4B0; // 周
    rom[9'h117] = 32'h0757D5B0; // 周
    rom[9'h118] = 32'h076AAAB0; // 周
    rom[9'h119] = 32'h0B0000B0; // 周
    rom[9'h11A] = 32'h0B2FFCB0; // 周
    rom[9'h11B] = 32'h0A381CB0; // 周
    rom[9'h11C] = 32'h0E296CB0; // 周
    rom[9'h11D] = 32'h1D3FF8B0; // 周
    rom[9'h11E] = 32'h2C240AE0; // 周
    rom[9'h11F] = 32'h14000B90; // 周
    rom[9'h123] = 32'h0AAAAAA0; // 三
    rom[9'h124] = 32'h0AAAAAA0; // 三
    rom[9'h128] = 32'h02FFFF80; // 三
    rom[9'h129] = 32'h01AAAA40; // 三
    rom[9'h12D] = 32'h1AAAAAA4; // 三
    rom[9'h12E] = 32'h1AAAAAA4; // 三
    rom[9'h131] = 32'h00010000; // 多
    rom[9'h132] = 32'h000B4000; // 多
    rom[9'h133] = 32'h002FFF40; // 多
    rom[9'h134] = 32'h01E55F00; // 多
    rom[9'h135] = 32'h0BA42C00; // 多
    rom[9'h136] = 32'h001EE000; // 多
    rom[9'h137] = 32'h006F6800; // 多
    rom[9'h138] = 32'h0BF4BEA4; // 多
    rom[9'h139] = 32'h0A47EAF4; // 多
    rom[9'h13A] = 32'h006E00E0; // 多
    rom[9'h13B] = 32'h01E687C0; // 多
    rom[9'h13C] = 32'h0001FE00; // 多
    rom[9'h13D] = 32'h001AF400; // 多
    rom[9'h13E] = 32'h1BFE4000; // 多
    rom[9'h13F] = 32'h0A900000; // 多
    rom[9'h142] = 32'h01555540; // 云
    rom[9'h143] = 32'h03FFFFD0; // 云
    rom[9'h144] = 32'h01555540; // 云
    rom[9'h147] = 32'h2FFFFFF8; // 云
    rom[9'h148] = 32'h1AAEAAA4; // 云
    rom[9'h149] = 32'h002D0000; // 云
    rom[9'h14A] = 32'h00781E00; // 云
    rom[9'h14B] = 32'h00F00B40; // 云
    rom[9'h14C] = 32'h02C007C0; // 云
    rom[9'h14D] = 32'h0BEFFFE0; // 云
    rom[9'h14E] = 32'h0BEA95B4; // 云
    rom[9'h14F] = 32'h00000060; // 云
    rom[9'h153] = 32'h1FFFFFF4; // 四
    rom[9'h154] = 32'h1E6DB9B4; // 四
    rom[9'h155] = 32'h1D1C3474; // 四
    rom[9'h156] = 32'h1D2C7474; // 四
    rom[9'h157] = 32'h1D2C7474; // 四
    rom[9'h158] = 32'h1D387074; // 四
    rom[9'h159] = 32'h1D747AB4; // 四
    rom[9'h15A] = 32'h1EE02AF4; // 四
    rom[9'h15B] = 32'h1D800074; // 四
    rom[9'h15C] = 32'h1D5555B4; // 四
    rom[9'h15D] = 32'h1FFFFFF4; // 四
    rom[9'h15E] = 32'h1D100474; // 四
    rom[9'h15F] = 32'h04000010; // 四
    rom[9'h161] = 32'h00004000; // 今
    rom[9'h162] = 32'h0002C000; // 今
    rom[9'h163] = 32'h000BE000; // 今
    rom[9'h164] = 32'h002D7800; // 今
    rom[9'h165] = 32'h01F41F40; // 今
    rom[9'h166] = 32'h1BD742E4; // 今
    rom[9'h167] = 32'h2E02E078; // 今
    rom[9'h168] = 32'h0400A000; // 今
    rom[9'h169] = 32'h03FFFFD0; // 今
    rom[9'h16A] = 32'h02AAAB80; // 今
    rom[9'h16B] = 32'h00000B00; // 今
    rom[9'h16C] = 32'h00002D00; // 今
    rom[9'h16D] = 32'h00007800; // 今
    rom[9'h16E] = 32'h0001E000; // 今
    rom[9'h16F] = 32'h00018000; // 今
    rom[9'h171] = 32'h01000400;
    rom[9'h172] = 32'h0741AC00;
    rom[9'h173] = 32'h034BAAF4;
    rom[9'h174] = 32'h179A1C74;
    rom[9'h175] = 32'h2FEBA9B4;
    rom[9'h176] = 32'h074A6C74;
    rom[9'h177] = 32'h034A6D74;
    rom[9'h178] = 32'h03AABEA4;
    rom[9'h179] = 32'h2FD02C00;
    rom[9'h17A] = 32'h2B4BFFF0;
    rom[9'h17B] = 32'h034795E0;
    rom[9'h17C] = 32'h0741D680;
    rom[9'h17D] = 32'h0340BF00;
    rom[9'h17E] = 32'h1B5BEBE4;
    rom[9'h17F] = 32'h1E2A4064;
    rom[9'h181] = 32'h00014000;
    rom[9'h182] = 32'h0003C000;
    rom[9'h183] = 32'h1FFFFFF4;
    rom[9'h184] = 32'h0557D550;
    rom[9'h185] = 32'h1AABEAA4;
    rom[9'h186] = 32'h2EAFAAB8;
    rom[9'h187] = 32'h2C190838;
    rom[9'h188] = 32'h16F9B814;
    rom[9'h189] = 32'h02AF9600;
    rom[9'h18A] = 32'h01B95BD0;
    rom[9'h18B] = 32'h0BFBEAB0;
    rom[9'h18C] = 32'h0552C520;
    rom[9'h18D] = 32'h02E1CB80;
    rom[9'h18E] = 32'h1F5AC1B4;
    rom[9'h18F] = 32'h081E4010;
    rom[9'h192] = 32'h1AAAAAA4;
    rom[9'h193] = 32'h1FBFFEF4;
    rom[9'h194] = 32'h1D000074;
    rom[9'h195] = 32'h1D155474;
    rom[9'h196] = 32'h1D3FFC74;
    rom[9'h197] = 32'h1D342C74;
    rom[9'h198] = 32'h1D342C74;
    rom[9'h199] = 32'h1D342C74;
    rom[9'h19A] = 32'h1D3EBC74;
    rom[9'h19B] = 32'h1D2AA474;
    rom[9'h19C] = 32'h1D000074;
    rom[9'h19D] = 32'h1E5555B4;
    rom[9'h19E] = 32'h1FFFFFF4;
    rom[9'h19F] = 32'h1D000074;
    rom[9'h1A1] = 32'h00010000;
    rom[9'h1A2] = 32'h00038000;
    rom[9'h1A3] = 32'h1FFFFFF4;
    rom[9'h1A4] = 32'h1D555574;
    rom[9'h1A5] = 32'h1DA56A74;
    rom[9'h1A6] = 32'h05AFFE50;
    rom[9'h1A7] = 32'h002F0180;
    rom[9'h1A8] = 32'h0BE78780;
    rom[9'h1A9] = 32'h0A1BEE00;
    rom[9'h1AA] = 32'h01B9FE00;
    rom[9'h1AB] = 32'h1F87E740;
    rom[9'h1AC] = 32'h046EA3C0;
    rom[9'h1AD] = 32'h16E4E1F4;
    rom[9'h1AE] = 32'h1E5AD078;
    rom[9'h1AF] = 32'h001F4000;
    rom[9'h1B2] = 32'h00241800;
    rom[9'h1B3] = 32'h00741D00;
    rom[9'h1B4] = 32'h00E00B40;
    rom[9'h1B5] = 32'h02D003C0;
    rom[9'h1B6] = 32'h078241E0;
    rom[9'h1B7] = 32'h1E078078;
    rom[9'h1B8] = 32'h180F0014;
    rom[9'h1B9] = 32'h002D0400;
    rom[9'h1BA] = 32'h00781E00;
    rom[9'h1BB] = 32'h00F00B40;
    rom[9'h1BC] = 32'h02D55BC0;
    rom[9'h1BD] = 32'h0BFFFEE0;
    rom[9'h1BE] = 32'h065500B4;
    rom[9'h1BF] = 32'h00000010;
    rom[9'h1C2] = 32'h05555550;
    rom[9'h1C3] = 32'h1FFFFFF0;
    rom[9'h1C4] = 32'h000000B0;
    rom[9'h1C5] = 32'h0AAAA8B0;
    rom[9'h1C6] = 32'h0AAAA8B0;
    rom[9'h1C7] = 32'h000000B0;
    rom[9'h1C8] = 32'h07FFE0B0;
    rom[9'h1C9] = 32'h0755B0B0;
    rom[9'h1CA] = 32'h0700B0B0;
    rom[9'h1CB] = 32'h0755B0B0;
    rom[9'h1CC] = 32'h07FFE0B0;
    rom[9'h1CD] = 32'h074000B0;
    rom[9'h1CE] = 32'h01000AE0;
    rom[9'h1CF] = 32'h00000B90;
    rom[9'h1D2] = 32'h00000FC0;
    rom[9'h1D3] = 32'h00003FC0;
    rom[9'h1D4] = 32'h0000FFC0;
    rom[9'h1D5] = 32'h03FFFFC0;
    rom[9'h1D6] = 32'h00FFFC00;
    rom[9'h1D7] = 32'h003FF000;
    rom[9'h1D8] = 32'h000FC000;
    rom[9'h1D9] = 32'h000FC000;
    rom[9'h1DA] = 32'h003CF000;
    rom[9'h1DB] = 32'h00F03C00;
    rom[9'h1DC] = 32'h03C00F00;
    rom[9'h1E1] = 32'h0003C000;
    rom[9'h1E2] = 32'h000FF000;
    rom[9'h1E3] = 32'h003C3C00;
    rom[9'h1E4] = 32'h00F00F00;
    rom[9'h1E5] = 32'h03C003C0;
    rom[9'h1E6] = 32'h0F0000F0;
    rom[9'h1E7] = 32'h3FFFFFFC;
    rom[9'h1E8] = 32'h0F0000F0;
    rom[9'h1E9] = 32'h0F0FF0F0;
    rom[9'h1EA] = 32'h0F0C30F0;
    rom[9'h1EB] = 32'h0F0C30F0;
    rom[9'h1EC] = 32'h0F0C30F0;
    rom[9'h1ED] = 32'h0FFFFFF0;
    rom[9'h1F1] = 32'h003FFC00;
    rom[9'h1F2] = 32'h00300C00;
    rom[9'h1F3] = 32'h00300C00;
    rom[9'h1F4] = 32'h0FFFFFF0;
    rom[9'h1F5] = 32'h0F0000F0;
    rom[9'h1F6] = 32'h0F3C3CF0;
    rom[9'h1F7] = 32'h0F3C3CF0;
    rom[9'h1F8] = 32'h0F3C3CF0;
    rom[9'h1F9] = 32'h0F3C3CF0;
    rom[9'h1FA] = 32'h0F0000F0;
    rom[9'h1FB] = 32'h0F03C0F0;
    rom[9'h1FC] = 32'h0F03C0F0;
    rom[9'h1FD] = 32'h0FFFFFF0;
end
always @(posedge I_clk) O_row <= rom[I_addr];
endmodule
