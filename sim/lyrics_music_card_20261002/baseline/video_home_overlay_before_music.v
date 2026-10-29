// Picture-1-only car dashboard. All text comes from a 16x16 glyph ROM in
// block RAM; the background is the decoded TF-card image. No frame store/DSP.
module video_home_overlay_before_music #(
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

reg [2:0] card_id;
reg [10:0] card_left;
reg [7:0] card_width_minus1;
always @(*) begin
    card_id=3'd4;card_left=11'd0;card_width_minus1=8'd0;
    if (pixel_x >= 11'd16 && pixel_x < 11'd160) begin
        card_id=3'd0;card_left=11'd16;card_width_minus1=8'd143;
    end else if (pixel_x >= 11'd172 && pixel_x < 11'd344) begin
        card_id=3'd1;card_left=11'd172;card_width_minus1=8'd171;
    end else if (pixel_x >= 11'd356 && pixel_x < 11'd472) begin
        card_id=3'd2;card_left=11'd356;card_width_minus1=8'd115;
    end else if (pixel_x >= 11'd484 && pixel_x < 11'd624) begin
        card_id=3'd3;card_left=11'd484;card_width_minus1=8'd139;
    end
end
wire card_rect = I_enable && I_de && card_id != 3'd4 &&
                 pixel_y >= 10'd310 && pixel_y < 10'd410;
wire [7:0] card_dx=pixel_x-card_left;
wire [7:0] card_right_dx=card_width_minus1-card_dx;
wire [6:0] card_edge_y=(pixel_y < 10'd360) ?
                       pixel_y-10'd310 : 10'd409-pixel_y;
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
// Fixed reference TPMS data; no real sensor is implied by these values.
function [3:0] tyre_code;
    input [1:0] corner;
    input pressure;
    input [2:0] char_cell;
    begin
        if (pressure) begin
            case (char_cell)
                3'd0: tyre_code=4'd2; // 2
                3'd1: tyre_code=4'd5; // 6
                3'd2: tyre_code=(corner==2'd1) ? 4'd3 :
                    (corner==2'd2) ? 4'd5 : 4'd1; // 4 / 6 / 1
                3'd3: tyre_code=4'd6; // k
                3'd4: tyre_code=4'd7; // P
                default: tyre_code=4'd8; // a
            endcase
        end else begin
            case (char_cell)
                3'd0: tyre_code=4'd1; // 1
                3'd1: tyre_code=(corner==2'd1) ? 4'd1 :
                    (corner==2'd2) ? 4'd4 : 4'd0; // 1 / 5 / 0
                default: tyre_code=4'd9; // Celsius
            endcase
        end
    end
endfunction
wire tyre_temp_y=(next_y>=10'd326 && next_y<10'd338) ||
                  (next_y>=10'd368 && next_y<10'd380);
wire tyre_pressure_next=(next_y>=10'd341 && next_y<10'd353) ||
                         (next_y>=10'd383 && next_y<10'd395);
wire tyre_temp_x=(next_x>=11'd500 && next_x<11'd524) ||
                  (next_x>=11'd584 && next_x<11'd608);
wire tyre_pressure_x=(next_x>=11'd488 && next_x<11'd536) ||
                      (next_x>=11'd572 && next_x<11'd620);
wire tyre_data_next=(tyre_temp_y && tyre_temp_x) ||
                    (tyre_pressure_next && tyre_pressure_x);
wire tyre_right_next=next_x>=11'd572;
wire tyre_rear_next=next_y>=10'd368;
wire [10:0] tyre_left_next=tyre_pressure_next ?
    (tyre_right_next ? 11'd572 : 11'd488) :
    (tyre_right_next ? 11'd584 : 11'd500);
wire [9:0] tyre_top_next=tyre_pressure_next ?
    (tyre_rear_next ? 10'd383 : 10'd341) :
    (tyre_rear_next ? 10'd368 : 10'd326);
wire [5:0] tyre_rel_x=next_x-tyre_left_next;
wire [3:0] tyre_rel_y=next_y-tyre_top_next;
wire [3:0] tyre_code_next=tyre_code({tyre_rear_next,tyre_right_next},
                                  tyre_pressure_next,tyre_rel_x[5:3]);
wire tyre_car_next=next_x>=11'd540 && next_x<11'd572 &&
                   next_y>=10'd327 && next_y<10'd391;
wire [5:0] tyre_car_y=next_y-10'd327;
wire [4:0] tyre_car_x=next_x-11'd540;
reg next_tyre_text,next_tyre_half;
reg [2:0] next_tyre_col;
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
    next_tyre_text=1'b0;next_tyre_half=1'b0;next_tyre_col=3'd0;
    // Navigation card: a broad destination action and two compact shortcuts.
    // Text cell origins stay 16-pixel aligned, sharing the existing glyph ROM.
    if (next_x >= 11'd64 && next_x < 11'd144 &&
        next_y >= 10'd340 && next_y < 10'd356) begin
        glyph_cell=(next_x-11'd64)>>4;glyph_y=next_y-10'd340;
        case (glyph_cell)
            3'd0: glyph_id=5'd23; // search
            3'd1: glyph_id=5'd24;
            3'd2: glyph_id=5'd0;
            3'd3: glyph_id=5'd1;
            3'd4: glyph_id=5'd2;
            default: glyph_id=5'd31;
        endcase
        next_text=1'b1;
    end else if (next_x >= 11'd48 && next_x < 11'd80 &&
                 next_y >= 10'd375 && next_y < 10'd391) begin
        glyph_id=next_x[4] ? 5'd25 : 5'd26; // home
        glyph_y=next_y-10'd375;next_text=1'b1;
    end else if (next_x >= 11'd112 && next_x < 11'd144 &&
                 next_y >= 10'd375 && next_y < 10'd391) begin
        glyph_id=next_x[4] ? 5'd27 : 5'd28; // company
        glyph_y=next_y-10'd375;next_text=1'b1;
    end else if (next_x >= 11'd24 && next_x < 11'd40 &&
                 next_y >= 10'd375 && next_y < 10'd391) begin
        glyph_id=5'd30;glyph_y=next_y-10'd375;
        next_text=1'b1;next_icon=1'b1;next_shift_icon=1'b1;
    end else if (next_x >= 11'd88 && next_x < 11'd104 &&
                 next_y >= 10'd375 && next_y < 10'd391) begin
        glyph_id=5'd31;glyph_y=next_y-10'd375;
        next_text=1'b1;next_icon=1'b1;next_shift_icon=1'b1;
    end else if (next_x >= 11'd240 && next_x < 11'd304 &&
                 next_y >= 10'd338 && next_y < 10'd354) begin
        glyph_cell=(next_x-11'd240)>>4;glyph_y=next_y-10'd338;
        case (glyph_cell)
            3'd0: glyph_id=5'd7;
            3'd1: glyph_id=5'd8;
            3'd2: glyph_id=5'd9;
            3'd3: glyph_id=5'd10;
            default: glyph_id=5'd31;
        endcase
        next_text=1'b1;
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
    end else if (tyre_data_next) begin
        case (tyre_code_next[3:1])
            3'd0: glyph_id=5'd14;
            3'd1: glyph_id=5'd15;
            3'd2: glyph_id=5'd16;
            3'd3: glyph_id=5'd18;
            default: glyph_id=5'd19;
        endcase
        glyph_y=tyre_rel_y;
        next_tyre_text=1'b1;next_tyre_half=tyre_code_next[0];
        next_tyre_col=tyre_rel_x[2:0];
    end
end
reg tyre_text,tyre_car,tyre_half,tyre_pressure;
reg [2:0] tyre_col;
reg text_valid, icon_text, shift_icon, clock_text;
always @(posedge I_clk or posedge I_rst) begin
    if (I_rst) begin
        text_valid <= 1'b0;
        icon_text <= 1'b0; shift_icon <= 1'b0; clock_text <= 1'b0;
        tyre_text<=1'b0;tyre_car<=1'b0;tyre_half<=1'b0;
        tyre_pressure<=1'b0;tyre_col<=3'd0;
    end else begin
        text_valid <= next_text;
        icon_text <= next_icon; shift_icon <= next_shift_icon;
        clock_text <= next_clock_text;
        tyre_text<=next_tyre_text;tyre_car<=tyre_car_next;
        tyre_half<=next_tyre_half;tyre_pressure<=tyre_pressure_next;
        tyre_col<=next_tyre_col;
    end
end
wire [31:0] row_coverage;
video_home_glyph_rom u_glyph_rom (
    .I_clk(I_clk), .I_addr({glyph_id, glyph_y}), .O_row(row_coverage)
);
wire [3:0] tyre_font_col={tyre_half,tyre_col[2:0]};
wire [1:0] tyre_cov=row_coverage[(15-tyre_font_col)*2 +: 2];
wire tyre_text_on=card_hit && card_id==3'd3 && tyre_text && tyre_cov!=2'd0;
wire [3:0] tyre_car_index;
wire [23:0] tyre_car_rgb;
video_tpms_car_rom u_tpms_car_rom (
    .I_clk(I_clk), .I_addr({tyre_car_y,tyre_car_x}),
    .O_index(tyre_car_index), .O_rgb(tyre_car_rgb)
);
wire tyre_car_on=card_hit && card_id==3'd3 && tyre_car && tyre_car_index!=4'd0;
wire [23:0] tyre_text_color=tyre_pressure ?
    ((tyre_cov==2'd3) ? 24'h24394B : (tyre_cov==2'd2) ? 24'h617486 : 24'hADB9C5) :
    ((tyre_cov==2'd3) ? 24'h667789 : (tyre_cov==2'd2) ? 24'h99A7B5 : 24'hC7CFD7);
wire [3:0] glyph_col = pixel_x[3:0] ^ {shift_icon, 3'b000};
wire [1:0] glyph_cov = row_coverage[(15-glyph_col)*2 +: 2];
wire glyph_on = I_enable && I_de && text_valid && (glyph_cov != 2'd0);
wire [1:0] glyph_left_cov = row_coverage[(16-glyph_col)*2 +: 2];
wire clock_shadow = I_enable && I_de && clock_text &&
                    glyph_col != 4'd0 && glyph_cov == 2'd0 &&
                    glyph_left_cov != 2'd0;
wire heading_text = (card_id == 2'd2) ? (pixel_y < 10'd346) :
                    (card_id == 2'd1) ? (pixel_y < 10'd356) :
                    (pixel_y < 10'd356);
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
    pixel_x == 11'd84 && pixel_y >= 10'd372 && pixel_y < 10'd395;
// Card two: circular album art at left, title above three player controls.
wire cover_next = next_x >= 11'd184 && next_x < 11'd224 &&
                  next_y >= 10'd336 && next_y < 10'd376;
wire [5:0] cover_x = next_x - 11'd184;
wire [5:0] cover_y = next_y - 10'd336;
wire [10:0] cover_addr = ({5'd0,cover_y} << 5) +
                         ({5'd0,cover_y} << 3) + {5'd0,cover_x};
// The 20px music-service logo shares unused addresses of the cover BRAM.
wire qq_next = next_x >= 11'd316 && next_x < 11'd336 &&
               next_y >= 10'd336 && next_y < 10'd356;
wire [4:0] qq_x=next_x-11'd316, qq_y=next_y-10'd336;
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
    ((pixel_x >= 11'd234 && pixel_x < 11'd237) ||
     (pixel_x >= 11'd239 && pixel_x < 11'd250 &&
      music_dy <= ((pixel_x - 11'd239) >> 1)));
// Pause bars indicate that the music is currently playing.
wire music_pause = music_control_area &&
    ((pixel_x >= 11'd279 && pixel_x < 11'd282) ||
     (pixel_x >= 11'd286 && pixel_x < 11'd289));
wire music_next = music_control_area &&
    ((pixel_x >= 11'd330 && pixel_x < 11'd333) ||
     (pixel_x >= 11'd317 && pixel_x < 11'd329 &&
      music_dy <= ((11'd328 - pixel_x) >> 1)));
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
    if (next_x >= 11'd28 && next_x < 11'd52 &&
        next_y >= 10'd336 && next_y < 10'd360) begin
        sprite_id=3'd5; sprite_left=11'd28; sprite_base=11'd1856;
        sprite_top=10'd336; sprite_next=1'b1;
    end else if (next_x >= 11'd500 && next_x < 11'd532 &&
        next_y >= 10'd74 && next_y < 10'd106) begin
        sprite_id = 3'd4; sprite_left = 11'd500; sprite_base = 11'd1600;
        sprite_top = 10'd74; sprite_next = 1'b1;
    end else if (next_x >= 11'd368 && next_x < 11'd408) begin
        sprite_left=11'd368;
        if (next_y>=10'd316 && next_y<10'd356) begin
            sprite_id=3'd0;sprite_top=10'd316;sprite_next=1'b1;
        end else if (next_y>=10'd364 && next_y<10'd404) begin
            sprite_id=3'd2;sprite_base=11'd800;sprite_top=10'd364;sprite_next=1'b1;
        end
    end else if (next_x >= 11'd420 && next_x < 11'd460) begin
        sprite_left=11'd420;
        if (next_y>=10'd316 && next_y<10'd356) begin
            sprite_id=3'd1;sprite_base=11'd400;sprite_top=10'd316;sprite_next=1'b1;
        end else if (next_y>=10'd364 && next_y<10'd404) begin
            sprite_id=3'd3;sprite_base=11'd1200;sprite_top=10'd364;sprite_next=1'b1;
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
// four corners. Only the four floating cards above have rounded contours.
assign O_rgb =
    !I_enable || !I_de ? I_rgb :
    glyph_on ? glyph_color :
    tyre_text_on ? tyre_text_color :
    tyre_car_on ? tyre_car_rgb :
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
