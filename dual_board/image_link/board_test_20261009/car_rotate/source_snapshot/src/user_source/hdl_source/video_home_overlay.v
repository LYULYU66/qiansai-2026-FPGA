// Shared picture-1 dashboard and picture-2 music card. All home text uses
// block RAM; the background is the decoded TF-card image. No frame store/DSP.
module video_home_overlay #(
    parameter integer H_ACTIVE = 640,
    parameter integer V_ACTIVE = 480,
    parameter EXTERNAL_CLOCK = 0
)(
    input wire I_clk, I_rst, I_enable, I_vs, I_de,
    input wire I_music_page,
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
reg [8:0] card_width_minus1;
always @(*) begin
    card_id=3'd4;card_left=11'd0;card_width_minus1=8'd0;
    if (I_music_page) begin
        if(pixel_x>=11'd144 && pixel_x<11'd496) begin
            card_id=3'd1;card_left=11'd144;card_width_minus1=9'd351;
        end
    end else if (pixel_x >= 11'd16 && pixel_x < 11'd160) begin
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
                 (I_music_page ? (pixel_y>=128 && pixel_y<212) :
                                  (pixel_y>=310 && pixel_y<410));
wire [8:0] card_dx=pixel_x-card_left;
wire [8:0] card_right_dx=card_width_minus1-card_dx;
wire [6:0] card_edge_y=I_music_page ?
    ((pixel_y<170)?pixel_y-128:211-pixel_y) :
    ((pixel_y<360)?pixel_y-310:409-pixel_y);
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
wire nav_hit = I_enable && !I_music_page && I_de && pixel_y >= 10'd440;

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
    end else if (!EXTERNAL_CLOCK && next_x >= 11'd544 && next_x < 11'd624 &&
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
wire glyph_on = I_enable && !I_music_page && I_de && text_valid && (glyph_cov != 2'd0);
wire [1:0] glyph_left_cov = row_coverage[(16-glyph_col)*2 +: 2];
wire clock_shadow = I_enable && !I_music_page && I_de && clock_text &&
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
wire cover_next = I_music_page ?
    (next_x>=160 && next_x<224 && next_y>=136 && next_y<200) :
    (next_x>=184 && next_x<224 && next_y>=336 && next_y<376);
wire [5:0] cover_local_x=next_x-(I_music_page?11'd160:11'd184);
wire [5:0] cover_local_y=next_y-(I_music_page?10'd136:10'd336);
// 40 -> 64px uses floor(local*5/8), shifts only; the same album ROM is read.
wire [8:0] cover_scaled_x={1'b0,cover_local_x,2'd0}+{3'd0,cover_local_x};
wire [8:0] cover_scaled_y={1'b0,cover_local_y,2'd0}+{3'd0,cover_local_y};
wire [5:0] cover_x=I_music_page?cover_scaled_x[8:3]:cover_local_x;
wire [5:0] cover_y=I_music_page?cover_scaled_y[8:3]:cover_local_y;
wire [10:0] cover_addr = ({5'd0,cover_y} << 5) +
                         ({5'd0,cover_y} << 3) + {5'd0,cover_x};
// The 20px music-service logo shares unused addresses of the cover BRAM.
wire qq_next = I_music_page ?
    (next_x>=392 && next_x<412 && next_y>=146 && next_y<166) :
    (next_x>=316 && next_x<336 && next_y>=336 && next_y<356);
wire [4:0] qq_x=next_x-(I_music_page?11'd392:11'd316);
wire [4:0] qq_y=next_y-(I_music_page?10'd146:10'd336);
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
    (I_music_page?(pixel_y>=180 && pixel_y<193):(pixel_y>=378 && pixel_y<391));
wire [9:0] music_center_y=I_music_page?10'd186:10'd384;
wire [4:0] music_dy=(pixel_y>=music_center_y)?pixel_y-music_center_y:music_center_y-pixel_y;
wire [10:0] previous_x=pixel_x-(I_music_page?11'd248:11'd234);
wire [10:0] pause_x=pixel_x-(I_music_page?11'd328:11'd279);
wire [10:0] next_control_x=pixel_x-(I_music_page?11'd400:11'd317);
wire music_previous = music_control_area &&
    (previous_x<3 || (previous_x>=5 && previous_x<16 && music_dy<=((previous_x-11'd5)>>1)));
// Pause bars indicate that the music is currently playing.
wire music_pause = music_control_area &&
    (pause_x<3 || (pause_x>=7 && pause_x<10));
wire music_next = music_control_area &&
    ((next_control_x>=13 && next_control_x<16) ||
     (next_control_x<12 && music_dy<=((11'd11-next_control_x)>>1)));
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
wire sun_pixel = I_enable && !I_music_page && I_de && sun_valid && sprite_opaque;
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
    rom[9'h0E2] = 32'h02800040; // TPMS packed
    rom[9'h0E3] = 32'h07D007C0; // TPMS packed
    rom[9'h0E4] = 32'h0C3001C0; // TPMS packed
    rom[9'h0E5] = 32'h0C3001C0; // TPMS packed
    rom[9'h0E6] = 32'h0C3001C0; // TPMS packed
    rom[9'h0E7] = 32'h0C3001C0; // TPMS packed
    rom[9'h0E8] = 32'h0C3001C0; // TPMS packed
    rom[9'h0E9] = 32'h0AA002C0; // TPMS packed
    rom[9'h0EA] = 32'h03C00BF0; // TPMS packed
    rom[9'h0F2] = 32'h03400040; // TPMS packed
    rom[9'h0F3] = 32'h0FD000D0; // TPMS packed
    rom[9'h0F4] = 32'h006002C0; // TPMS packed
    rom[9'h0F5] = 32'h00600390; // TPMS packed
    rom[9'h0F6] = 32'h00D00890; // TPMS packed
    rom[9'h0F7] = 32'h00C00DE0; // TPMS packed
    rom[9'h0F8] = 32'h03400FF0; // TPMS packed
    rom[9'h0F9] = 32'h07100090; // TPMS packed
    rom[9'h0FA] = 32'h0FF00090; // TPMS packed
    rom[9'h102] = 32'h019001C0; // TPMS packed
    rom[9'h103] = 32'h07E003F0; // TPMS packed
    rom[9'h104] = 32'h09000A00; // TPMS packed
    rom[9'h105] = 32'h0B400C00; // TPMS packed
    rom[9'h106] = 32'h0BD00FD0; // TPMS packed
    rom[9'h107] = 32'h00300C30; // TPMS packed
    rom[9'h108] = 32'h00300C30; // TPMS packed
    rom[9'h109] = 32'h0CB00A30; // TPMS packed
    rom[9'h10A] = 32'h0BC003C0; // TPMS packed
    rom[9'h122] = 32'h0D000640; // TPMS packed
    rom[9'h123] = 32'h0D000FF0; // TPMS packed
    rom[9'h124] = 32'h0D100C30; // TPMS packed
    rom[9'h125] = 32'h0CB00C30; // TPMS packed
    rom[9'h126] = 32'h09C00DB0; // TPMS packed
    rom[9'h127] = 32'h0B800FC0; // TPMS packed
    rom[9'h128] = 32'h0FC00C00; // TPMS packed
    rom[9'h129] = 32'h0CA00C00; // TPMS packed
    rom[9'h12A] = 32'h0D300C00; // TPMS packed
    rom[9'h132] = 32'h00003438; // TPMS packed
    rom[9'h133] = 32'h000088FD; // TPMS packed
    rom[9'h134] = 32'h024065C0; // TPMS packed
    rom[9'h135] = 32'h0BD03340; // TPMS packed
    rom[9'h136] = 32'h00A00340; // TPMS packed
    rom[9'h137] = 32'h03E00340; // TPMS packed
    rom[9'h138] = 32'h0C600380; // TPMS packed
    rom[9'h139] = 32'h0CE000C9; // TPMS packed
    rom[9'h13A] = 32'h0BE000BC; // TPMS packed
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
    rom[10'd525] = 16'h02E0;
    rom[10'd527] = 16'h07C0;
    rom[10'd528] = 16'h0B42;
    rom[10'd529] = 16'hC2C2;
    rom[10'd530] = 16'hC1E0;
    rom[10'd531] = 16'h0B03;
    rom[10'd532] = 16'h8383;
    rom[10'd533] = 16'h80B0;
    rom[10'd534] = 16'h034B;
    rom[10'd535] = 16'h0B0B;
    rom[10'd536] = 16'h00E0;
    rom[10'd537] = 16'h038B;
    rom[10'd538] = 16'h0B0B;
    rom[10'd539] = 16'h00D0;
    rom[10'd540] = 16'h02CB;
    rom[10'd541] = 16'h0B0B;
    rom[10'd542] = 16'h01C0;
    rom[10'd543] = 16'h01C3;
    rom[10'd544] = 16'h4747;
    rom[10'd545] = 16'h42C0;
    rom[10'd546] = 16'h01D3;
    rom[10'd547] = 16'hC3C3;
    rom[10'd548] = 16'hC380;
    rom[10'd549] = 16'h00E1;
    rom[10'd550] = 16'hD1D1;
    rom[10'd551] = 16'hC340;
    rom[10'd552] = 16'h00F0;
    rom[10'd553] = 16'hE0E0;
    rom[10'd554] = 16'hD700;
    rom[10'd555] = 16'h00B0;
    rom[10'd556] = 16'hE0E0;
    rom[10'd557] = 16'hEB00;
    rom[10'd559] = 16'hE0E0;
    rom[10'd560] = 16'hE000;
    rom[10'd561] = 16'h0001;
    rom[10'd562] = 16'hD1D1;
    rom[10'd563] = 16'hD000;
    rom[10'd564] = 16'h0002;
    rom[10'd565] = 16'hC2C2;
    rom[10'd566] = 16'hC000;
    rom[10'd567] = 16'h0001;
    rom[10'd568] = 16'h4141;
    rom[10'd569] = 16'h4000;
    rom[10'd591] = 16'h06AA;
    rom[10'd592] = 16'hAAAA;
    rom[10'd593] = 16'hAA90;
    rom[10'd594] = 16'h0BFF;
    rom[10'd595] = 16'hFFFF;
    rom[10'd596] = 16'hFFF0;
    rom[10'd597] = 16'h0B00;
    rom[10'd599] = 16'h00B0;
    rom[10'd600] = 16'h0B02;
    rom[10'd601] = 16'hC2C2;
    rom[10'd602] = 16'hC0B0;
    rom[10'd603] = 16'h0B03;
    rom[10'd604] = 16'h8383;
    rom[10'd605] = 16'h80B0;
    rom[10'd606] = 16'h0B0B;
    rom[10'd607] = 16'h0B0B;
    rom[10'd608] = 16'h00B0;
    rom[10'd609] = 16'h0B0B;
    rom[10'd610] = 16'h0B0B;
    rom[10'd611] = 16'h00B0;
    rom[10'd612] = 16'h0B0B;
    rom[10'd613] = 16'h0B0B;
    rom[10'd614] = 16'h00B0;
    rom[10'd615] = 16'h0B07;
    rom[10'd616] = 16'h4747;
    rom[10'd617] = 16'h40B0;
    rom[10'd618] = 16'h0B03;
    rom[10'd619] = 16'hC3C3;
    rom[10'd620] = 16'hC0B0;
    rom[10'd621] = 16'h0B01;
    rom[10'd622] = 16'hC1C1;
    rom[10'd623] = 16'hC0B0;
    rom[10'd624] = 16'h0BAA;
    rom[10'd625] = 16'hFAFA;
    rom[10'd626] = 16'hFAF0;
    rom[10'd627] = 16'h06FF;
    rom[10'd628] = 16'hFFFF;
    rom[10'd629] = 16'hFFD0;
    rom[10'd631] = 16'hE0E0;
    rom[10'd632] = 16'hE000;
    rom[10'd633] = 16'h0001;
    rom[10'd634] = 16'hD1D1;
    rom[10'd635] = 16'hD000;
    rom[10'd636] = 16'h0002;
    rom[10'd637] = 16'hC2C2;
    rom[10'd638] = 16'hC000;
    rom[10'd639] = 16'h0001;
    rom[10'd640] = 16'h4141;
    rom[10'd641] = 16'h4000;
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

// Realistic top-view car: 32x64, 4-bit palette index, one BRAM9K.
// Generated by sim/generate_tpms_assets.py; all scaling is offline.
module video_tpms_car_rom (
    input wire I_clk, input wire [10:0] I_addr,
    output reg [3:0] O_index, output reg [23:0] O_rgb
);
reg [3:0] car_rom [0:2047];
integer i;
initial begin
    for (i=0; i<2048; i=i+1) car_rom[i]=4'd0;
    car_rom[11'd74]=4'd6;
    car_rom[11'd75]=4'd9;
    car_rom[11'd76]=4'd9;
    car_rom[11'd77]=4'd10;
    car_rom[11'd78]=4'd10;
    car_rom[11'd79]=4'd10;
    car_rom[11'd80]=4'd10;
    car_rom[11'd81]=4'd10;
    car_rom[11'd82]=4'd10;
    car_rom[11'd83]=4'd9;
    car_rom[11'd84]=4'd9;
    car_rom[11'd85]=4'd6;
    car_rom[11'd103]=4'd5;
    car_rom[11'd104]=4'd7;
    car_rom[11'd105]=4'd9;
    car_rom[11'd106]=4'd8;
    car_rom[11'd107]=4'd8;
    car_rom[11'd108]=4'd9;
    car_rom[11'd109]=4'd9;
    car_rom[11'd110]=4'd9;
    car_rom[11'd111]=4'd9;
    car_rom[11'd112]=4'd9;
    car_rom[11'd113]=4'd9;
    car_rom[11'd114]=4'd9;
    car_rom[11'd115]=4'd9;
    car_rom[11'd116]=4'd8;
    car_rom[11'd117]=4'd8;
    car_rom[11'd118]=4'd9;
    car_rom[11'd119]=4'd7;
    car_rom[11'd120]=4'd3;
    car_rom[11'd134]=4'd9;
    car_rom[11'd135]=4'd10;
    car_rom[11'd136]=4'd10;
    car_rom[11'd137]=4'd7;
    car_rom[11'd138]=4'd9;
    car_rom[11'd139]=4'd9;
    car_rom[11'd140]=4'd9;
    car_rom[11'd141]=4'd9;
    car_rom[11'd142]=4'd9;
    car_rom[11'd143]=4'd9;
    car_rom[11'd144]=4'd9;
    car_rom[11'd145]=4'd9;
    car_rom[11'd146]=4'd9;
    car_rom[11'd147]=4'd9;
    car_rom[11'd148]=4'd9;
    car_rom[11'd149]=4'd9;
    car_rom[11'd150]=4'd7;
    car_rom[11'd151]=4'd10;
    car_rom[11'd152]=4'd10;
    car_rom[11'd153]=4'd9;
    car_rom[11'd165]=4'd10;
    car_rom[11'd166]=4'd9;
    car_rom[11'd167]=4'd10;
    car_rom[11'd168]=4'd7;
    car_rom[11'd169]=4'd7;
    car_rom[11'd170]=4'd8;
    car_rom[11'd171]=4'd7;
    car_rom[11'd172]=4'd8;
    car_rom[11'd173]=4'd9;
    car_rom[11'd174]=4'd9;
    car_rom[11'd175]=4'd9;
    car_rom[11'd176]=4'd9;
    car_rom[11'd177]=4'd9;
    car_rom[11'd178]=4'd9;
    car_rom[11'd179]=4'd8;
    car_rom[11'd180]=4'd7;
    car_rom[11'd181]=4'd8;
    car_rom[11'd182]=4'd8;
    car_rom[11'd183]=4'd7;
    car_rom[11'd184]=4'd10;
    car_rom[11'd185]=4'd9;
    car_rom[11'd186]=4'd10;
    car_rom[11'd196]=4'd6;
    car_rom[11'd197]=4'd8;
    car_rom[11'd198]=4'd11;
    car_rom[11'd199]=4'd9;
    car_rom[11'd200]=4'd4;
    car_rom[11'd201]=4'd7;
    car_rom[11'd202]=4'd6;
    car_rom[11'd203]=4'd5;
    car_rom[11'd204]=4'd8;
    car_rom[11'd205]=4'd9;
    car_rom[11'd206]=4'd8;
    car_rom[11'd207]=4'd9;
    car_rom[11'd208]=4'd9;
    car_rom[11'd209]=4'd9;
    car_rom[11'd210]=4'd9;
    car_rom[11'd211]=4'd8;
    car_rom[11'd212]=4'd5;
    car_rom[11'd213]=4'd6;
    car_rom[11'd214]=4'd7;
    car_rom[11'd215]=4'd5;
    car_rom[11'd216]=4'd9;
    car_rom[11'd217]=4'd11;
    car_rom[11'd218]=4'd8;
    car_rom[11'd219]=4'd6;
    car_rom[11'd228]=4'd8;
    car_rom[11'd229]=4'd9;
    car_rom[11'd230]=4'd11;
    car_rom[11'd231]=4'd1;
    car_rom[11'd232]=4'd7;
    car_rom[11'd233]=4'd6;
    car_rom[11'd234]=4'd5;
    car_rom[11'd235]=4'd5;
    car_rom[11'd236]=4'd8;
    car_rom[11'd237]=4'd8;
    car_rom[11'd238]=4'd8;
    car_rom[11'd239]=4'd8;
    car_rom[11'd240]=4'd8;
    car_rom[11'd241]=4'd8;
    car_rom[11'd242]=4'd8;
    car_rom[11'd243]=4'd8;
    car_rom[11'd244]=4'd5;
    car_rom[11'd245]=4'd5;
    car_rom[11'd246]=4'd6;
    car_rom[11'd247]=4'd7;
    car_rom[11'd248]=4'd1;
    car_rom[11'd249]=4'd11;
    car_rom[11'd250]=4'd10;
    car_rom[11'd251]=4'd8;
    car_rom[11'd260]=4'd10;
    car_rom[11'd261]=4'd10;
    car_rom[11'd262]=4'd8;
    car_rom[11'd263]=4'd1;
    car_rom[11'd264]=4'd7;
    car_rom[11'd265]=4'd6;
    car_rom[11'd266]=4'd5;
    car_rom[11'd267]=4'd5;
    car_rom[11'd268]=4'd8;
    car_rom[11'd269]=4'd8;
    car_rom[11'd270]=4'd8;
    car_rom[11'd271]=4'd8;
    car_rom[11'd272]=4'd8;
    car_rom[11'd273]=4'd8;
    car_rom[11'd274]=4'd8;
    car_rom[11'd275]=4'd8;
    car_rom[11'd276]=4'd5;
    car_rom[11'd277]=4'd5;
    car_rom[11'd278]=4'd6;
    car_rom[11'd279]=4'd8;
    car_rom[11'd280]=4'd4;
    car_rom[11'd281]=4'd7;
    car_rom[11'd282]=4'd10;
    car_rom[11'd283]=4'd10;
    car_rom[11'd291]=4'd1;
    car_rom[11'd292]=4'd10;
    car_rom[11'd293]=4'd10;
    car_rom[11'd294]=4'd1;
    car_rom[11'd295]=4'd6;
    car_rom[11'd296]=4'd6;
    car_rom[11'd297]=4'd5;
    car_rom[11'd298]=4'd5;
    car_rom[11'd299]=4'd6;
    car_rom[11'd300]=4'd7;
    car_rom[11'd301]=4'd7;
    car_rom[11'd302]=4'd8;
    car_rom[11'd303]=4'd8;
    car_rom[11'd304]=4'd8;
    car_rom[11'd305]=4'd8;
    car_rom[11'd306]=4'd8;
    car_rom[11'd307]=4'd8;
    car_rom[11'd308]=4'd6;
    car_rom[11'd309]=4'd5;
    car_rom[11'd310]=4'd6;
    car_rom[11'd311]=4'd7;
    car_rom[11'd312]=4'd6;
    car_rom[11'd313]=4'd1;
    car_rom[11'd314]=4'd10;
    car_rom[11'd315]=4'd11;
    car_rom[11'd316]=4'd1;
    car_rom[11'd322]=4'd7;
    car_rom[11'd323]=4'd12;
    car_rom[11'd324]=4'd9;
    car_rom[11'd325]=4'd7;
    car_rom[11'd326]=4'd4;
    car_rom[11'd327]=4'd6;
    car_rom[11'd328]=4'd6;
    car_rom[11'd329]=4'd5;
    car_rom[11'd330]=4'd5;
    car_rom[11'd331]=4'd6;
    car_rom[11'd332]=4'd7;
    car_rom[11'd333]=4'd7;
    car_rom[11'd334]=4'd8;
    car_rom[11'd335]=4'd8;
    car_rom[11'd336]=4'd8;
    car_rom[11'd337]=4'd8;
    car_rom[11'd338]=4'd8;
    car_rom[11'd339]=4'd8;
    car_rom[11'd340]=4'd7;
    car_rom[11'd341]=4'd5;
    car_rom[11'd342]=4'd6;
    car_rom[11'd343]=4'd6;
    car_rom[11'd344]=4'd7;
    car_rom[11'd345]=4'd5;
    car_rom[11'd346]=4'd8;
    car_rom[11'd347]=4'd9;
    car_rom[11'd348]=4'd12;
    car_rom[11'd349]=4'd6;
    car_rom[11'd354]=4'd10;
    car_rom[11'd355]=4'd12;
    car_rom[11'd356]=4'd5;
    car_rom[11'd357]=4'd6;
    car_rom[11'd358]=4'd6;
    car_rom[11'd359]=4'd6;
    car_rom[11'd360]=4'd6;
    car_rom[11'd361]=4'd6;
    car_rom[11'd362]=4'd5;
    car_rom[11'd363]=4'd7;
    car_rom[11'd364]=4'd7;
    car_rom[11'd365]=4'd7;
    car_rom[11'd366]=4'd7;
    car_rom[11'd367]=4'd8;
    car_rom[11'd368]=4'd8;
    car_rom[11'd369]=4'd8;
    car_rom[11'd370]=4'd8;
    car_rom[11'd371]=4'd8;
    car_rom[11'd372]=4'd7;
    car_rom[11'd373]=4'd6;
    car_rom[11'd374]=4'd6;
    car_rom[11'd375]=4'd6;
    car_rom[11'd376]=4'd7;
    car_rom[11'd377]=4'd6;
    car_rom[11'd378]=4'd6;
    car_rom[11'd379]=4'd6;
    car_rom[11'd380]=4'd13;
    car_rom[11'd381]=4'd10;
    car_rom[11'd386]=4'd10;
    car_rom[11'd387]=4'd11;
    car_rom[11'd388]=4'd5;
    car_rom[11'd389]=4'd7;
    car_rom[11'd390]=4'd6;
    car_rom[11'd391]=4'd6;
    car_rom[11'd392]=4'd6;
    car_rom[11'd393]=4'd6;
    car_rom[11'd394]=4'd6;
    car_rom[11'd395]=4'd7;
    car_rom[11'd396]=4'd7;
    car_rom[11'd397]=4'd7;
    car_rom[11'd398]=4'd7;
    car_rom[11'd399]=4'd8;
    car_rom[11'd400]=4'd8;
    car_rom[11'd401]=4'd8;
    car_rom[11'd402]=4'd8;
    car_rom[11'd403]=4'd8;
    car_rom[11'd404]=4'd7;
    car_rom[11'd405]=4'd6;
    car_rom[11'd406]=4'd6;
    car_rom[11'd407]=4'd6;
    car_rom[11'd408]=4'd7;
    car_rom[11'd409]=4'd6;
    car_rom[11'd410]=4'd7;
    car_rom[11'd411]=4'd6;
    car_rom[11'd412]=4'd11;
    car_rom[11'd413]=4'd10;
    car_rom[11'd418]=4'd11;
    car_rom[11'd419]=4'd10;
    car_rom[11'd420]=4'd5;
    car_rom[11'd421]=4'd7;
    car_rom[11'd422]=4'd5;
    car_rom[11'd423]=4'd6;
    car_rom[11'd424]=4'd6;
    car_rom[11'd425]=4'd4;
    car_rom[11'd426]=4'd4;
    car_rom[11'd427]=4'd4;
    car_rom[11'd428]=4'd4;
    car_rom[11'd429]=4'd5;
    car_rom[11'd430]=4'd5;
    car_rom[11'd431]=4'd6;
    car_rom[11'd432]=4'd6;
    car_rom[11'd433]=4'd6;
    car_rom[11'd434]=4'd5;
    car_rom[11'd435]=4'd5;
    car_rom[11'd436]=4'd5;
    car_rom[11'd437]=4'd5;
    car_rom[11'd438]=4'd5;
    car_rom[11'd439]=4'd6;
    car_rom[11'd440]=4'd6;
    car_rom[11'd441]=4'd6;
    car_rom[11'd442]=4'd7;
    car_rom[11'd443]=4'd6;
    car_rom[11'd444]=4'd11;
    car_rom[11'd445]=4'd10;
    car_rom[11'd450]=4'd11;
    car_rom[11'd451]=4'd10;
    car_rom[11'd452]=4'd5;
    car_rom[11'd453]=4'd7;
    car_rom[11'd454]=4'd5;
    car_rom[11'd455]=4'd4;
    car_rom[11'd456]=4'd1;
    car_rom[11'd457]=4'd6;
    car_rom[11'd458]=4'd9;
    car_rom[11'd459]=4'd10;
    car_rom[11'd460]=4'd11;
    car_rom[11'd461]=4'd12;
    car_rom[11'd462]=4'd12;
    car_rom[11'd463]=4'd13;
    car_rom[11'd464]=4'd12;
    car_rom[11'd465]=4'd12;
    car_rom[11'd466]=4'd11;
    car_rom[11'd467]=4'd11;
    car_rom[11'd468]=4'd10;
    car_rom[11'd469]=4'd9;
    car_rom[11'd470]=4'd6;
    car_rom[11'd471]=4'd1;
    car_rom[11'd472]=4'd5;
    car_rom[11'd473]=4'd6;
    car_rom[11'd474]=4'd8;
    car_rom[11'd475]=4'd5;
    car_rom[11'd476]=4'd11;
    car_rom[11'd477]=4'd11;
    car_rom[11'd482]=4'd11;
    car_rom[11'd483]=4'd11;
    car_rom[11'd484]=4'd5;
    car_rom[11'd485]=4'd7;
    car_rom[11'd486]=4'd1;
    car_rom[11'd487]=4'd8;
    car_rom[11'd488]=4'd11;
    car_rom[11'd489]=4'd14;
    car_rom[11'd490]=4'd14;
    car_rom[11'd491]=4'd14;
    car_rom[11'd492]=4'd14;
    car_rom[11'd493]=4'd14;
    car_rom[11'd494]=4'd14;
    car_rom[11'd495]=4'd14;
    car_rom[11'd496]=4'd14;
    car_rom[11'd497]=4'd14;
    car_rom[11'd498]=4'd14;
    car_rom[11'd499]=4'd14;
    car_rom[11'd500]=4'd14;
    car_rom[11'd501]=4'd14;
    car_rom[11'd502]=4'd14;
    car_rom[11'd503]=4'd11;
    car_rom[11'd504]=4'd7;
    car_rom[11'd505]=4'd1;
    car_rom[11'd506]=4'd8;
    car_rom[11'd507]=4'd5;
    car_rom[11'd508]=4'd11;
    car_rom[11'd509]=4'd11;
    car_rom[11'd514]=4'd11;
    car_rom[11'd515]=4'd11;
    car_rom[11'd516]=4'd5;
    car_rom[11'd517]=4'd5;
    car_rom[11'd518]=4'd9;
    car_rom[11'd519]=4'd14;
    car_rom[11'd520]=4'd14;
    car_rom[11'd521]=4'd13;
    car_rom[11'd522]=4'd12;
    car_rom[11'd523]=4'd12;
    car_rom[11'd524]=4'd12;
    car_rom[11'd525]=4'd12;
    car_rom[11'd526]=4'd13;
    car_rom[11'd527]=4'd13;
    car_rom[11'd528]=4'd13;
    car_rom[11'd529]=4'd13;
    car_rom[11'd530]=4'd13;
    car_rom[11'd531]=4'd13;
    car_rom[11'd532]=4'd13;
    car_rom[11'd533]=4'd13;
    car_rom[11'd534]=4'd14;
    car_rom[11'd535]=4'd14;
    car_rom[11'd536]=4'd14;
    car_rom[11'd537]=4'd8;
    car_rom[11'd538]=4'd6;
    car_rom[11'd539]=4'd6;
    car_rom[11'd540]=4'd12;
    car_rom[11'd541]=4'd11;
    car_rom[11'd546]=4'd11;
    car_rom[11'd547]=4'd11;
    car_rom[11'd548]=4'd4;
    car_rom[11'd549]=4'd5;
    car_rom[11'd550]=4'd14;
    car_rom[11'd551]=4'd13;
    car_rom[11'd552]=4'd11;
    car_rom[11'd553]=4'd11;
    car_rom[11'd554]=4'd11;
    car_rom[11'd555]=4'd11;
    car_rom[11'd556]=4'd11;
    car_rom[11'd557]=4'd12;
    car_rom[11'd558]=4'd12;
    car_rom[11'd559]=4'd13;
    car_rom[11'd560]=4'd13;
    car_rom[11'd561]=4'd12;
    car_rom[11'd562]=4'd12;
    car_rom[11'd563]=4'd12;
    car_rom[11'd564]=4'd12;
    car_rom[11'd565]=4'd12;
    car_rom[11'd566]=4'd12;
    car_rom[11'd567]=4'd12;
    car_rom[11'd568]=4'd14;
    car_rom[11'd569]=4'd13;
    car_rom[11'd570]=4'd4;
    car_rom[11'd571]=4'd5;
    car_rom[11'd572]=4'd12;
    car_rom[11'd573]=4'd11;
    car_rom[11'd578]=4'd10;
    car_rom[11'd579]=4'd12;
    car_rom[11'd580]=4'd7;
    car_rom[11'd581]=4'd6;
    car_rom[11'd582]=4'd12;
    car_rom[11'd583]=4'd11;
    car_rom[11'd584]=4'd11;
    car_rom[11'd585]=4'd11;
    car_rom[11'd586]=4'd12;
    car_rom[11'd587]=4'd12;
    car_rom[11'd588]=4'd12;
    car_rom[11'd589]=4'd12;
    car_rom[11'd590]=4'd12;
    car_rom[11'd591]=4'd12;
    car_rom[11'd592]=4'd12;
    car_rom[11'd593]=4'd12;
    car_rom[11'd594]=4'd12;
    car_rom[11'd595]=4'd12;
    car_rom[11'd596]=4'd12;
    car_rom[11'd597]=4'd12;
    car_rom[11'd598]=4'd11;
    car_rom[11'd599]=4'd11;
    car_rom[11'd600]=4'd12;
    car_rom[11'd601]=4'd11;
    car_rom[11'd602]=4'd6;
    car_rom[11'd603]=4'd8;
    car_rom[11'd604]=4'd13;
    car_rom[11'd605]=4'd10;
    car_rom[11'd610]=4'd4;
    car_rom[11'd611]=4'd10;
    car_rom[11'd612]=4'd10;
    car_rom[11'd613]=4'd7;
    car_rom[11'd614]=4'd11;
    car_rom[11'd615]=4'd11;
    car_rom[11'd616]=4'd11;
    car_rom[11'd617]=4'd12;
    car_rom[11'd618]=4'd11;
    car_rom[11'd619]=4'd12;
    car_rom[11'd620]=4'd12;
    car_rom[11'd621]=4'd13;
    car_rom[11'd622]=4'd12;
    car_rom[11'd623]=4'd12;
    car_rom[11'd624]=4'd12;
    car_rom[11'd625]=4'd12;
    car_rom[11'd626]=4'd13;
    car_rom[11'd627]=4'd12;
    car_rom[11'd628]=4'd12;
    car_rom[11'd629]=4'd12;
    car_rom[11'd630]=4'd12;
    car_rom[11'd631]=4'd11;
    car_rom[11'd632]=4'd12;
    car_rom[11'd633]=4'd10;
    car_rom[11'd634]=4'd9;
    car_rom[11'd635]=4'd10;
    car_rom[11'd636]=4'd10;
    car_rom[11'd637]=4'd1;
    car_rom[11'd643]=4'd1;
    car_rom[11'd644]=4'd10;
    car_rom[11'd645]=4'd9;
    car_rom[11'd646]=4'd10;
    car_rom[11'd647]=4'd13;
    car_rom[11'd648]=4'd12;
    car_rom[11'd649]=4'd12;
    car_rom[11'd650]=4'd12;
    car_rom[11'd651]=4'd12;
    car_rom[11'd652]=4'd12;
    car_rom[11'd653]=4'd13;
    car_rom[11'd654]=4'd13;
    car_rom[11'd655]=4'd13;
    car_rom[11'd656]=4'd13;
    car_rom[11'd657]=4'd13;
    car_rom[11'd658]=4'd13;
    car_rom[11'd659]=4'd13;
    car_rom[11'd660]=4'd13;
    car_rom[11'd661]=4'd12;
    car_rom[11'd662]=4'd12;
    car_rom[11'd663]=4'd12;
    car_rom[11'd664]=4'd13;
    car_rom[11'd665]=4'd10;
    car_rom[11'd666]=4'd10;
    car_rom[11'd667]=4'd10;
    car_rom[11'd668]=4'd4;
    car_rom[11'd673]=4'd4;
    car_rom[11'd674]=4'd4;
    car_rom[11'd675]=4'd6;
    car_rom[11'd676]=4'd14;
    car_rom[11'd677]=4'd10;
    car_rom[11'd678]=4'd9;
    car_rom[11'd679]=4'd14;
    car_rom[11'd680]=4'd12;
    car_rom[11'd681]=4'd12;
    car_rom[11'd682]=4'd12;
    car_rom[11'd683]=4'd12;
    car_rom[11'd684]=4'd13;
    car_rom[11'd685]=4'd13;
    car_rom[11'd686]=4'd13;
    car_rom[11'd687]=4'd13;
    car_rom[11'd688]=4'd13;
    car_rom[11'd689]=4'd13;
    car_rom[11'd690]=4'd13;
    car_rom[11'd691]=4'd12;
    car_rom[11'd692]=4'd12;
    car_rom[11'd693]=4'd12;
    car_rom[11'd694]=4'd12;
    car_rom[11'd695]=4'd12;
    car_rom[11'd696]=4'd14;
    car_rom[11'd697]=4'd8;
    car_rom[11'd698]=4'd10;
    car_rom[11'd699]=4'd14;
    car_rom[11'd700]=4'd5;
    car_rom[11'd701]=4'd4;
    car_rom[11'd702]=4'd4;
    car_rom[11'd705]=4'd7;
    car_rom[11'd706]=4'd9;
    car_rom[11'd707]=4'd12;
    car_rom[11'd708]=4'd14;
    car_rom[11'd709]=4'd11;
    car_rom[11'd710]=4'd7;
    car_rom[11'd711]=4'd14;
    car_rom[11'd712]=4'd12;
    car_rom[11'd713]=4'd12;
    car_rom[11'd714]=4'd12;
    car_rom[11'd715]=4'd12;
    car_rom[11'd716]=4'd12;
    car_rom[11'd717]=4'd13;
    car_rom[11'd718]=4'd13;
    car_rom[11'd719]=4'd13;
    car_rom[11'd720]=4'd13;
    car_rom[11'd721]=4'd13;
    car_rom[11'd722]=4'd13;
    car_rom[11'd723]=4'd12;
    car_rom[11'd724]=4'd12;
    car_rom[11'd725]=4'd12;
    car_rom[11'd726]=4'd12;
    car_rom[11'd727]=4'd12;
    car_rom[11'd728]=4'd14;
    car_rom[11'd729]=4'd5;
    car_rom[11'd730]=4'd11;
    car_rom[11'd731]=4'd14;
    car_rom[11'd732]=4'd12;
    car_rom[11'd733]=4'd9;
    car_rom[11'd734]=4'd7;
    car_rom[11'd737]=4'd10;
    car_rom[11'd738]=4'd10;
    car_rom[11'd739]=4'd6;
    car_rom[11'd740]=4'd10;
    car_rom[11'd741]=4'd12;
    car_rom[11'd742]=4'd5;
    car_rom[11'd743]=4'd14;
    car_rom[11'd744]=4'd12;
    car_rom[11'd745]=4'd12;
    car_rom[11'd746]=4'd13;
    car_rom[11'd747]=4'd13;
    car_rom[11'd748]=4'd13;
    car_rom[11'd749]=4'd13;
    car_rom[11'd750]=4'd13;
    car_rom[11'd751]=4'd13;
    car_rom[11'd752]=4'd13;
    car_rom[11'd753]=4'd13;
    car_rom[11'd754]=4'd13;
    car_rom[11'd755]=4'd12;
    car_rom[11'd756]=4'd12;
    car_rom[11'd757]=4'd12;
    car_rom[11'd758]=4'd12;
    car_rom[11'd759]=4'd12;
    car_rom[11'd760]=4'd13;
    car_rom[11'd761]=4'd4;
    car_rom[11'd762]=4'd14;
    car_rom[11'd763]=4'd10;
    car_rom[11'd764]=4'd7;
    car_rom[11'd765]=4'd10;
    car_rom[11'd766]=4'd10;
    car_rom[11'd771]=4'd6;
    car_rom[11'd772]=4'd10;
    car_rom[11'd773]=4'd13;
    car_rom[11'd774]=4'd3;
    car_rom[11'd775]=4'd13;
    car_rom[11'd776]=4'd13;
    car_rom[11'd777]=4'd14;
    car_rom[11'd778]=4'd14;
    car_rom[11'd779]=4'd14;
    car_rom[11'd780]=4'd14;
    car_rom[11'd781]=4'd14;
    car_rom[11'd782]=4'd14;
    car_rom[11'd783]=4'd14;
    car_rom[11'd784]=4'd14;
    car_rom[11'd785]=4'd14;
    car_rom[11'd786]=4'd14;
    car_rom[11'd787]=4'd14;
    car_rom[11'd788]=4'd14;
    car_rom[11'd789]=4'd14;
    car_rom[11'd790]=4'd14;
    car_rom[11'd791]=4'd13;
    car_rom[11'd792]=4'd12;
    car_rom[11'd793]=4'd5;
    car_rom[11'd794]=4'd14;
    car_rom[11'd795]=4'd10;
    car_rom[11'd796]=4'd5;
    car_rom[11'd803]=4'd6;
    car_rom[11'd804]=4'd10;
    car_rom[11'd805]=4'd14;
    car_rom[11'd806]=4'd5;
    car_rom[11'd807]=4'd11;
    car_rom[11'd808]=4'd12;
    car_rom[11'd809]=4'd11;
    car_rom[11'd810]=4'd10;
    car_rom[11'd811]=4'd10;
    car_rom[11'd812]=4'd10;
    car_rom[11'd813]=4'd10;
    car_rom[11'd814]=4'd10;
    car_rom[11'd815]=4'd10;
    car_rom[11'd816]=4'd10;
    car_rom[11'd817]=4'd10;
    car_rom[11'd818]=4'd10;
    car_rom[11'd819]=4'd10;
    car_rom[11'd820]=4'd10;
    car_rom[11'd821]=4'd11;
    car_rom[11'd822]=4'd11;
    car_rom[11'd823]=4'd13;
    car_rom[11'd824]=4'd11;
    car_rom[11'd825]=4'd6;
    car_rom[11'd826]=4'd14;
    car_rom[11'd827]=4'd10;
    car_rom[11'd828]=4'd7;
    car_rom[11'd835]=4'd6;
    car_rom[11'd836]=4'd10;
    car_rom[11'd837]=4'd14;
    car_rom[11'd838]=4'd7;
    car_rom[11'd839]=4'd10;
    car_rom[11'd840]=4'd4;
    car_rom[11'd841]=4'd4;
    car_rom[11'd842]=4'd5;
    car_rom[11'd843]=4'd5;
    car_rom[11'd844]=4'd5;
    car_rom[11'd845]=4'd6;
    car_rom[11'd846]=4'd6;
    car_rom[11'd847]=4'd6;
    car_rom[11'd848]=4'd7;
    car_rom[11'd849]=4'd6;
    car_rom[11'd850]=4'd6;
    car_rom[11'd851]=4'd6;
    car_rom[11'd852]=4'd5;
    car_rom[11'd853]=4'd5;
    car_rom[11'd854]=4'd4;
    car_rom[11'd855]=4'd5;
    car_rom[11'd856]=4'd9;
    car_rom[11'd857]=4'd9;
    car_rom[11'd858]=4'd14;
    car_rom[11'd859]=4'd10;
    car_rom[11'd860]=4'd6;
    car_rom[11'd867]=4'd6;
    car_rom[11'd868]=4'd10;
    car_rom[11'd869]=4'd14;
    car_rom[11'd870]=4'd9;
    car_rom[11'd871]=4'd9;
    car_rom[11'd872]=4'd6;
    car_rom[11'd873]=4'd6;
    car_rom[11'd874]=4'd7;
    car_rom[11'd875]=4'd7;
    car_rom[11'd876]=4'd8;
    car_rom[11'd877]=4'd8;
    car_rom[11'd878]=4'd8;
    car_rom[11'd879]=4'd8;
    car_rom[11'd880]=4'd8;
    car_rom[11'd881]=4'd8;
    car_rom[11'd882]=4'd8;
    car_rom[11'd883]=4'd8;
    car_rom[11'd884]=4'd7;
    car_rom[11'd885]=4'd7;
    car_rom[11'd886]=4'd6;
    car_rom[11'd887]=4'd7;
    car_rom[11'd888]=4'd9;
    car_rom[11'd889]=4'd9;
    car_rom[11'd890]=4'd14;
    car_rom[11'd891]=4'd10;
    car_rom[11'd892]=4'd7;
    car_rom[11'd899]=4'd7;
    car_rom[11'd900]=4'd10;
    car_rom[11'd901]=4'd14;
    car_rom[11'd902]=4'd9;
    car_rom[11'd903]=4'd9;
    car_rom[11'd904]=4'd6;
    car_rom[11'd905]=4'd6;
    car_rom[11'd906]=4'd6;
    car_rom[11'd907]=4'd7;
    car_rom[11'd908]=4'd7;
    car_rom[11'd909]=4'd8;
    car_rom[11'd910]=4'd8;
    car_rom[11'd911]=4'd8;
    car_rom[11'd912]=4'd8;
    car_rom[11'd913]=4'd8;
    car_rom[11'd914]=4'd8;
    car_rom[11'd915]=4'd7;
    car_rom[11'd916]=4'd7;
    car_rom[11'd917]=4'd7;
    car_rom[11'd918]=4'd6;
    car_rom[11'd919]=4'd7;
    car_rom[11'd920]=4'd9;
    car_rom[11'd921]=4'd10;
    car_rom[11'd922]=4'd14;
    car_rom[11'd923]=4'd10;
    car_rom[11'd924]=4'd8;
    car_rom[11'd930]=4'd5;
    car_rom[11'd931]=4'd6;
    car_rom[11'd932]=4'd11;
    car_rom[11'd933]=4'd14;
    car_rom[11'd934]=4'd10;
    car_rom[11'd935]=4'd9;
    car_rom[11'd936]=4'd7;
    car_rom[11'd937]=4'd6;
    car_rom[11'd938]=4'd6;
    car_rom[11'd939]=4'd7;
    car_rom[11'd940]=4'd7;
    car_rom[11'd941]=4'd8;
    car_rom[11'd942]=4'd8;
    car_rom[11'd943]=4'd8;
    car_rom[11'd944]=4'd8;
    car_rom[11'd945]=4'd8;
    car_rom[11'd946]=4'd8;
    car_rom[11'd947]=4'd7;
    car_rom[11'd948]=4'd7;
    car_rom[11'd949]=4'd6;
    car_rom[11'd950]=4'd5;
    car_rom[11'd951]=4'd7;
    car_rom[11'd952]=4'd9;
    car_rom[11'd953]=4'd10;
    car_rom[11'd954]=4'd14;
    car_rom[11'd955]=4'd11;
    car_rom[11'd956]=4'd6;
    car_rom[11'd962]=4'd6;
    car_rom[11'd963]=4'd6;
    car_rom[11'd964]=4'd11;
    car_rom[11'd965]=4'd13;
    car_rom[11'd966]=4'd10;
    car_rom[11'd967]=4'd9;
    car_rom[11'd968]=4'd7;
    car_rom[11'd969]=4'd6;
    car_rom[11'd970]=4'd6;
    car_rom[11'd971]=4'd7;
    car_rom[11'd972]=4'd7;
    car_rom[11'd973]=4'd8;
    car_rom[11'd974]=4'd8;
    car_rom[11'd975]=4'd8;
    car_rom[11'd976]=4'd8;
    car_rom[11'd977]=4'd8;
    car_rom[11'd978]=4'd8;
    car_rom[11'd979]=4'd7;
    car_rom[11'd980]=4'd7;
    car_rom[11'd981]=4'd6;
    car_rom[11'd982]=4'd5;
    car_rom[11'd983]=4'd8;
    car_rom[11'd984]=4'd9;
    car_rom[11'd985]=4'd10;
    car_rom[11'd986]=4'd14;
    car_rom[11'd987]=4'd11;
    car_rom[11'd988]=4'd7;
    car_rom[11'd989]=4'd6;
    car_rom[11'd994]=4'd5;
    car_rom[11'd995]=4'd6;
    car_rom[11'd996]=4'd11;
    car_rom[11'd997]=4'd13;
    car_rom[11'd998]=4'd10;
    car_rom[11'd999]=4'd9;
    car_rom[11'd1000]=4'd7;
    car_rom[11'd1001]=4'd6;
    car_rom[11'd1002]=4'd6;
    car_rom[11'd1003]=4'd7;
    car_rom[11'd1004]=4'd7;
    car_rom[11'd1005]=4'd8;
    car_rom[11'd1006]=4'd8;
    car_rom[11'd1007]=4'd8;
    car_rom[11'd1008]=4'd8;
    car_rom[11'd1009]=4'd8;
    car_rom[11'd1010]=4'd8;
    car_rom[11'd1011]=4'd7;
    car_rom[11'd1012]=4'd7;
    car_rom[11'd1013]=4'd7;
    car_rom[11'd1014]=4'd5;
    car_rom[11'd1015]=4'd8;
    car_rom[11'd1016]=4'd9;
    car_rom[11'd1017]=4'd10;
    car_rom[11'd1018]=4'd14;
    car_rom[11'd1019]=4'd11;
    car_rom[11'd1020]=4'd6;
    car_rom[11'd1021]=4'd6;
    car_rom[11'd1027]=4'd6;
    car_rom[11'd1028]=4'd11;
    car_rom[11'd1029]=4'd14;
    car_rom[11'd1030]=4'd10;
    car_rom[11'd1031]=4'd9;
    car_rom[11'd1032]=4'd7;
    car_rom[11'd1033]=4'd6;
    car_rom[11'd1034]=4'd6;
    car_rom[11'd1035]=4'd7;
    car_rom[11'd1036]=4'd7;
    car_rom[11'd1037]=4'd8;
    car_rom[11'd1038]=4'd8;
    car_rom[11'd1039]=4'd8;
    car_rom[11'd1040]=4'd8;
    car_rom[11'd1041]=4'd8;
    car_rom[11'd1042]=4'd8;
    car_rom[11'd1043]=4'd7;
    car_rom[11'd1044]=4'd7;
    car_rom[11'd1045]=4'd6;
    car_rom[11'd1046]=4'd5;
    car_rom[11'd1047]=4'd8;
    car_rom[11'd1048]=4'd9;
    car_rom[11'd1049]=4'd10;
    car_rom[11'd1050]=4'd14;
    car_rom[11'd1051]=4'd11;
    car_rom[11'd1052]=4'd7;
    car_rom[11'd1059]=4'd7;
    car_rom[11'd1060]=4'd11;
    car_rom[11'd1061]=4'd13;
    car_rom[11'd1062]=4'd10;
    car_rom[11'd1063]=4'd9;
    car_rom[11'd1064]=4'd7;
    car_rom[11'd1065]=4'd6;
    car_rom[11'd1066]=4'd6;
    car_rom[11'd1067]=4'd7;
    car_rom[11'd1068]=4'd7;
    car_rom[11'd1069]=4'd8;
    car_rom[11'd1070]=4'd8;
    car_rom[11'd1071]=4'd8;
    car_rom[11'd1072]=4'd8;
    car_rom[11'd1073]=4'd8;
    car_rom[11'd1074]=4'd8;
    car_rom[11'd1075]=4'd8;
    car_rom[11'd1076]=4'd7;
    car_rom[11'd1077]=4'd6;
    car_rom[11'd1078]=4'd5;
    car_rom[11'd1079]=4'd8;
    car_rom[11'd1080]=4'd9;
    car_rom[11'd1081]=4'd10;
    car_rom[11'd1082]=4'd14;
    car_rom[11'd1083]=4'd11;
    car_rom[11'd1084]=4'd8;
    car_rom[11'd1091]=4'd7;
    car_rom[11'd1092]=4'd11;
    car_rom[11'd1093]=4'd14;
    car_rom[11'd1094]=4'd10;
    car_rom[11'd1095]=4'd9;
    car_rom[11'd1096]=4'd7;
    car_rom[11'd1097]=4'd6;
    car_rom[11'd1098]=4'd6;
    car_rom[11'd1099]=4'd7;
    car_rom[11'd1100]=4'd7;
    car_rom[11'd1101]=4'd8;
    car_rom[11'd1102]=4'd8;
    car_rom[11'd1103]=4'd8;
    car_rom[11'd1104]=4'd8;
    car_rom[11'd1105]=4'd8;
    car_rom[11'd1106]=4'd8;
    car_rom[11'd1107]=4'd7;
    car_rom[11'd1108]=4'd7;
    car_rom[11'd1109]=4'd6;
    car_rom[11'd1110]=4'd5;
    car_rom[11'd1111]=4'd7;
    car_rom[11'd1112]=4'd9;
    car_rom[11'd1113]=4'd10;
    car_rom[11'd1114]=4'd14;
    car_rom[11'd1115]=4'd11;
    car_rom[11'd1116]=4'd7;
    car_rom[11'd1123]=4'd6;
    car_rom[11'd1124]=4'd11;
    car_rom[11'd1125]=4'd14;
    car_rom[11'd1126]=4'd10;
    car_rom[11'd1127]=4'd9;
    car_rom[11'd1128]=4'd7;
    car_rom[11'd1129]=4'd6;
    car_rom[11'd1130]=4'd6;
    car_rom[11'd1131]=4'd7;
    car_rom[11'd1132]=4'd7;
    car_rom[11'd1133]=4'd8;
    car_rom[11'd1134]=4'd8;
    car_rom[11'd1135]=4'd8;
    car_rom[11'd1136]=4'd8;
    car_rom[11'd1137]=4'd8;
    car_rom[11'd1138]=4'd8;
    car_rom[11'd1139]=4'd8;
    car_rom[11'd1140]=4'd7;
    car_rom[11'd1141]=4'd6;
    car_rom[11'd1142]=4'd5;
    car_rom[11'd1143]=4'd7;
    car_rom[11'd1144]=4'd9;
    car_rom[11'd1145]=4'd10;
    car_rom[11'd1146]=4'd14;
    car_rom[11'd1147]=4'd11;
    car_rom[11'd1148]=4'd7;
    car_rom[11'd1155]=4'd6;
    car_rom[11'd1156]=4'd11;
    car_rom[11'd1157]=4'd14;
    car_rom[11'd1158]=4'd10;
    car_rom[11'd1159]=4'd9;
    car_rom[11'd1160]=4'd7;
    car_rom[11'd1161]=4'd6;
    car_rom[11'd1162]=4'd6;
    car_rom[11'd1163]=4'd7;
    car_rom[11'd1164]=4'd7;
    car_rom[11'd1165]=4'd8;
    car_rom[11'd1166]=4'd8;
    car_rom[11'd1167]=4'd8;
    car_rom[11'd1168]=4'd8;
    car_rom[11'd1169]=4'd8;
    car_rom[11'd1170]=4'd8;
    car_rom[11'd1171]=4'd8;
    car_rom[11'd1172]=4'd7;
    car_rom[11'd1173]=4'd6;
    car_rom[11'd1174]=4'd5;
    car_rom[11'd1175]=4'd7;
    car_rom[11'd1176]=4'd9;
    car_rom[11'd1177]=4'd10;
    car_rom[11'd1178]=4'd14;
    car_rom[11'd1179]=4'd11;
    car_rom[11'd1180]=4'd7;
    car_rom[11'd1187]=4'd6;
    car_rom[11'd1188]=4'd11;
    car_rom[11'd1189]=4'd14;
    car_rom[11'd1190]=4'd10;
    car_rom[11'd1191]=4'd9;
    car_rom[11'd1192]=4'd7;
    car_rom[11'd1193]=4'd6;
    car_rom[11'd1194]=4'd7;
    car_rom[11'd1195]=4'd7;
    car_rom[11'd1196]=4'd7;
    car_rom[11'd1197]=4'd8;
    car_rom[11'd1198]=4'd8;
    car_rom[11'd1199]=4'd8;
    car_rom[11'd1200]=4'd9;
    car_rom[11'd1201]=4'd8;
    car_rom[11'd1202]=4'd8;
    car_rom[11'd1203]=4'd8;
    car_rom[11'd1204]=4'd7;
    car_rom[11'd1205]=4'd7;
    car_rom[11'd1206]=4'd6;
    car_rom[11'd1207]=4'd7;
    car_rom[11'd1208]=4'd9;
    car_rom[11'd1209]=4'd10;
    car_rom[11'd1210]=4'd14;
    car_rom[11'd1211]=4'd11;
    car_rom[11'd1212]=4'd7;
    car_rom[11'd1219]=4'd6;
    car_rom[11'd1220]=4'd11;
    car_rom[11'd1221]=4'd14;
    car_rom[11'd1222]=4'd9;
    car_rom[11'd1223]=4'd9;
    car_rom[11'd1224]=4'd7;
    car_rom[11'd1225]=4'd6;
    car_rom[11'd1226]=4'd7;
    car_rom[11'd1227]=4'd7;
    car_rom[11'd1228]=4'd8;
    car_rom[11'd1229]=4'd8;
    car_rom[11'd1230]=4'd8;
    car_rom[11'd1231]=4'd9;
    car_rom[11'd1232]=4'd9;
    car_rom[11'd1233]=4'd8;
    car_rom[11'd1234]=4'd8;
    car_rom[11'd1235]=4'd8;
    car_rom[11'd1236]=4'd7;
    car_rom[11'd1237]=4'd7;
    car_rom[11'd1238]=4'd6;
    car_rom[11'd1239]=4'd7;
    car_rom[11'd1240]=4'd9;
    car_rom[11'd1241]=4'd10;
    car_rom[11'd1242]=4'd14;
    car_rom[11'd1243]=4'd11;
    car_rom[11'd1244]=4'd7;
    car_rom[11'd1251]=4'd6;
    car_rom[11'd1252]=4'd11;
    car_rom[11'd1253]=4'd14;
    car_rom[11'd1254]=4'd9;
    car_rom[11'd1255]=4'd9;
    car_rom[11'd1256]=4'd6;
    car_rom[11'd1257]=4'd6;
    car_rom[11'd1258]=4'd7;
    car_rom[11'd1259]=4'd7;
    car_rom[11'd1260]=4'd8;
    car_rom[11'd1261]=4'd8;
    car_rom[11'd1262]=4'd8;
    car_rom[11'd1263]=4'd9;
    car_rom[11'd1264]=4'd9;
    car_rom[11'd1265]=4'd9;
    car_rom[11'd1266]=4'd8;
    car_rom[11'd1267]=4'd8;
    car_rom[11'd1268]=4'd7;
    car_rom[11'd1269]=4'd7;
    car_rom[11'd1270]=4'd6;
    car_rom[11'd1271]=4'd7;
    car_rom[11'd1272]=4'd9;
    car_rom[11'd1273]=4'd10;
    car_rom[11'd1274]=4'd14;
    car_rom[11'd1275]=4'd10;
    car_rom[11'd1276]=4'd7;
    car_rom[11'd1283]=4'd7;
    car_rom[11'd1284]=4'd10;
    car_rom[11'd1285]=4'd14;
    car_rom[11'd1286]=4'd8;
    car_rom[11'd1287]=4'd10;
    car_rom[11'd1288]=4'd6;
    car_rom[11'd1289]=4'd7;
    car_rom[11'd1290]=4'd7;
    car_rom[11'd1291]=4'd8;
    car_rom[11'd1292]=4'd8;
    car_rom[11'd1293]=4'd8;
    car_rom[11'd1294]=4'd8;
    car_rom[11'd1295]=4'd9;
    car_rom[11'd1296]=4'd9;
    car_rom[11'd1297]=4'd9;
    car_rom[11'd1298]=4'd8;
    car_rom[11'd1299]=4'd8;
    car_rom[11'd1300]=4'd8;
    car_rom[11'd1301]=4'd7;
    car_rom[11'd1302]=4'd6;
    car_rom[11'd1303]=4'd7;
    car_rom[11'd1304]=4'd9;
    car_rom[11'd1305]=4'd9;
    car_rom[11'd1306]=4'd14;
    car_rom[11'd1307]=4'd10;
    car_rom[11'd1308]=4'd7;
    car_rom[11'd1314]=4'd5;
    car_rom[11'd1315]=4'd7;
    car_rom[11'd1316]=4'd10;
    car_rom[11'd1317]=4'd14;
    car_rom[11'd1318]=4'd7;
    car_rom[11'd1319]=4'd10;
    car_rom[11'd1320]=4'd6;
    car_rom[11'd1321]=4'd7;
    car_rom[11'd1322]=4'd7;
    car_rom[11'd1323]=4'd8;
    car_rom[11'd1324]=4'd8;
    car_rom[11'd1325]=4'd8;
    car_rom[11'd1326]=4'd9;
    car_rom[11'd1327]=4'd9;
    car_rom[11'd1328]=4'd9;
    car_rom[11'd1329]=4'd9;
    car_rom[11'd1330]=4'd9;
    car_rom[11'd1331]=4'd8;
    car_rom[11'd1332]=4'd8;
    car_rom[11'd1333]=4'd7;
    car_rom[11'd1334]=4'd7;
    car_rom[11'd1335]=4'd7;
    car_rom[11'd1336]=4'd9;
    car_rom[11'd1337]=4'd9;
    car_rom[11'd1338]=4'd14;
    car_rom[11'd1339]=4'd10;
    car_rom[11'd1340]=4'd9;
    car_rom[11'd1346]=4'd5;
    car_rom[11'd1347]=4'd7;
    car_rom[11'd1348]=4'd10;
    car_rom[11'd1349]=4'd14;
    car_rom[11'd1350]=4'd6;
    car_rom[11'd1351]=4'd10;
    car_rom[11'd1352]=4'd6;
    car_rom[11'd1353]=4'd7;
    car_rom[11'd1354]=4'd7;
    car_rom[11'd1355]=4'd8;
    car_rom[11'd1356]=4'd8;
    car_rom[11'd1357]=4'd9;
    car_rom[11'd1358]=4'd9;
    car_rom[11'd1359]=4'd9;
    car_rom[11'd1360]=4'd9;
    car_rom[11'd1361]=4'd9;
    car_rom[11'd1362]=4'd9;
    car_rom[11'd1363]=4'd8;
    car_rom[11'd1364]=4'd8;
    car_rom[11'd1365]=4'd8;
    car_rom[11'd1366]=4'd7;
    car_rom[11'd1367]=4'd7;
    car_rom[11'd1368]=4'd10;
    car_rom[11'd1369]=4'd7;
    car_rom[11'd1370]=4'd14;
    car_rom[11'd1371]=4'd10;
    car_rom[11'd1372]=4'd7;
    car_rom[11'd1373]=4'd5;
    car_rom[11'd1378]=4'd5;
    car_rom[11'd1379]=4'd7;
    car_rom[11'd1380]=4'd10;
    car_rom[11'd1381]=4'd13;
    car_rom[11'd1382]=4'd4;
    car_rom[11'd1383]=4'd10;
    car_rom[11'd1384]=4'd4;
    car_rom[11'd1385]=4'd7;
    car_rom[11'd1386]=4'd8;
    car_rom[11'd1387]=4'd8;
    car_rom[11'd1388]=4'd9;
    car_rom[11'd1389]=4'd9;
    car_rom[11'd1390]=4'd9;
    car_rom[11'd1391]=4'd9;
    car_rom[11'd1392]=4'd9;
    car_rom[11'd1393]=4'd9;
    car_rom[11'd1394]=4'd9;
    car_rom[11'd1395]=4'd9;
    car_rom[11'd1396]=4'd9;
    car_rom[11'd1397]=4'd8;
    car_rom[11'd1398]=4'd7;
    car_rom[11'd1399]=4'd5;
    car_rom[11'd1400]=4'd10;
    car_rom[11'd1401]=4'd5;
    car_rom[11'd1402]=4'd14;
    car_rom[11'd1403]=4'd10;
    car_rom[11'd1404]=4'd8;
    car_rom[11'd1405]=4'd5;
    car_rom[11'd1410]=4'd4;
    car_rom[11'd1411]=4'd6;
    car_rom[11'd1412]=4'd11;
    car_rom[11'd1413]=4'd12;
    car_rom[11'd1414]=4'd1;
    car_rom[11'd1415]=4'd11;
    car_rom[11'd1416]=4'd8;
    car_rom[11'd1417]=4'd6;
    car_rom[11'd1418]=4'd6;
    car_rom[11'd1419]=4'd6;
    car_rom[11'd1420]=4'd6;
    car_rom[11'd1421]=4'd7;
    car_rom[11'd1422]=4'd7;
    car_rom[11'd1423]=4'd6;
    car_rom[11'd1424]=4'd8;
    car_rom[11'd1425]=4'd7;
    car_rom[11'd1426]=4'd7;
    car_rom[11'd1427]=4'd6;
    car_rom[11'd1428]=4'd6;
    car_rom[11'd1429]=4'd6;
    car_rom[11'd1430]=4'd7;
    car_rom[11'd1431]=4'd9;
    car_rom[11'd1432]=4'd11;
    car_rom[11'd1433]=4'd1;
    car_rom[11'd1434]=4'd13;
    car_rom[11'd1435]=4'd10;
    car_rom[11'd1436]=4'd7;
    car_rom[11'd1437]=4'd1;
    car_rom[11'd1442]=4'd7;
    car_rom[11'd1443]=4'd8;
    car_rom[11'd1444]=4'd10;
    car_rom[11'd1445]=4'd11;
    car_rom[11'd1446]=4'd1;
    car_rom[11'd1447]=4'd13;
    car_rom[11'd1448]=4'd14;
    car_rom[11'd1449]=4'd13;
    car_rom[11'd1450]=4'd12;
    car_rom[11'd1451]=4'd11;
    car_rom[11'd1452]=4'd11;
    car_rom[11'd1453]=4'd11;
    car_rom[11'd1454]=4'd11;
    car_rom[11'd1455]=4'd11;
    car_rom[11'd1456]=4'd11;
    car_rom[11'd1457]=4'd11;
    car_rom[11'd1458]=4'd11;
    car_rom[11'd1459]=4'd11;
    car_rom[11'd1460]=4'd11;
    car_rom[11'd1461]=4'd12;
    car_rom[11'd1462]=4'd13;
    car_rom[11'd1463]=4'd14;
    car_rom[11'd1464]=4'd13;
    car_rom[11'd1465]=4'd1;
    car_rom[11'd1466]=4'd11;
    car_rom[11'd1467]=4'd10;
    car_rom[11'd1468]=4'd9;
    car_rom[11'd1469]=4'd8;
    car_rom[11'd1474]=4'd11;
    car_rom[11'd1475]=4'd9;
    car_rom[11'd1476]=4'd10;
    car_rom[11'd1477]=4'd9;
    car_rom[11'd1478]=4'd5;
    car_rom[11'd1479]=4'd13;
    car_rom[11'd1480]=4'd11;
    car_rom[11'd1481]=4'd13;
    car_rom[11'd1482]=4'd13;
    car_rom[11'd1483]=4'd14;
    car_rom[11'd1484]=4'd14;
    car_rom[11'd1485]=4'd14;
    car_rom[11'd1486]=4'd14;
    car_rom[11'd1487]=4'd14;
    car_rom[11'd1488]=4'd14;
    car_rom[11'd1489]=4'd14;
    car_rom[11'd1490]=4'd14;
    car_rom[11'd1491]=4'd14;
    car_rom[11'd1492]=4'd14;
    car_rom[11'd1493]=4'd14;
    car_rom[11'd1494]=4'd13;
    car_rom[11'd1495]=4'd12;
    car_rom[11'd1496]=4'd13;
    car_rom[11'd1497]=4'd4;
    car_rom[11'd1498]=4'd10;
    car_rom[11'd1499]=4'd10;
    car_rom[11'd1500]=4'd10;
    car_rom[11'd1501]=4'd11;
    car_rom[11'd1506]=4'd11;
    car_rom[11'd1507]=4'd10;
    car_rom[11'd1508]=4'd7;
    car_rom[11'd1509]=4'd7;
    car_rom[11'd1510]=4'd7;
    car_rom[11'd1511]=4'd13;
    car_rom[11'd1512]=4'd11;
    car_rom[11'd1513]=4'd12;
    car_rom[11'd1514]=4'd13;
    car_rom[11'd1515]=4'd13;
    car_rom[11'd1516]=4'd13;
    car_rom[11'd1517]=4'd13;
    car_rom[11'd1518]=4'd13;
    car_rom[11'd1519]=4'd13;
    car_rom[11'd1520]=4'd13;
    car_rom[11'd1521]=4'd13;
    car_rom[11'd1522]=4'd13;
    car_rom[11'd1523]=4'd13;
    car_rom[11'd1524]=4'd13;
    car_rom[11'd1525]=4'd13;
    car_rom[11'd1526]=4'd13;
    car_rom[11'd1527]=4'd12;
    car_rom[11'd1528]=4'd13;
    car_rom[11'd1529]=4'd6;
    car_rom[11'd1530]=4'd9;
    car_rom[11'd1531]=4'd7;
    car_rom[11'd1532]=4'd10;
    car_rom[11'd1533]=4'd11;
    car_rom[11'd1538]=4'd11;
    car_rom[11'd1539]=4'd9;
    car_rom[11'd1540]=4'd6;
    car_rom[11'd1541]=4'd7;
    car_rom[11'd1542]=4'd9;
    car_rom[11'd1543]=4'd13;
    car_rom[11'd1544]=4'd11;
    car_rom[11'd1545]=4'd12;
    car_rom[11'd1546]=4'd13;
    car_rom[11'd1547]=4'd13;
    car_rom[11'd1548]=4'd13;
    car_rom[11'd1549]=4'd13;
    car_rom[11'd1550]=4'd13;
    car_rom[11'd1551]=4'd13;
    car_rom[11'd1552]=4'd13;
    car_rom[11'd1553]=4'd13;
    car_rom[11'd1554]=4'd13;
    car_rom[11'd1555]=4'd13;
    car_rom[11'd1556]=4'd13;
    car_rom[11'd1557]=4'd13;
    car_rom[11'd1558]=4'd13;
    car_rom[11'd1559]=4'd12;
    car_rom[11'd1560]=4'd13;
    car_rom[11'd1561]=4'd8;
    car_rom[11'd1562]=4'd9;
    car_rom[11'd1563]=4'd6;
    car_rom[11'd1564]=4'd10;
    car_rom[11'd1565]=4'd11;
    car_rom[11'd1570]=4'd11;
    car_rom[11'd1571]=4'd9;
    car_rom[11'd1572]=4'd6;
    car_rom[11'd1573]=4'd6;
    car_rom[11'd1574]=4'd10;
    car_rom[11'd1575]=4'd13;
    car_rom[11'd1576]=4'd11;
    car_rom[11'd1577]=4'd12;
    car_rom[11'd1578]=4'd13;
    car_rom[11'd1579]=4'd13;
    car_rom[11'd1580]=4'd13;
    car_rom[11'd1581]=4'd13;
    car_rom[11'd1582]=4'd13;
    car_rom[11'd1583]=4'd13;
    car_rom[11'd1584]=4'd13;
    car_rom[11'd1585]=4'd13;
    car_rom[11'd1586]=4'd13;
    car_rom[11'd1587]=4'd13;
    car_rom[11'd1588]=4'd13;
    car_rom[11'd1589]=4'd13;
    car_rom[11'd1590]=4'd13;
    car_rom[11'd1591]=4'd12;
    car_rom[11'd1592]=4'd14;
    car_rom[11'd1593]=4'd9;
    car_rom[11'd1594]=4'd8;
    car_rom[11'd1595]=4'd6;
    car_rom[11'd1596]=4'd10;
    car_rom[11'd1597]=4'd11;
    car_rom[11'd1602]=4'd12;
    car_rom[11'd1603]=4'd10;
    car_rom[11'd1604]=4'd5;
    car_rom[11'd1605]=4'd6;
    car_rom[11'd1606]=4'd10;
    car_rom[11'd1607]=4'd13;
    car_rom[11'd1608]=4'd11;
    car_rom[11'd1609]=4'd12;
    car_rom[11'd1610]=4'd13;
    car_rom[11'd1611]=4'd13;
    car_rom[11'd1612]=4'd13;
    car_rom[11'd1613]=4'd13;
    car_rom[11'd1614]=4'd13;
    car_rom[11'd1615]=4'd13;
    car_rom[11'd1616]=4'd13;
    car_rom[11'd1617]=4'd13;
    car_rom[11'd1618]=4'd13;
    car_rom[11'd1619]=4'd13;
    car_rom[11'd1620]=4'd13;
    car_rom[11'd1621]=4'd13;
    car_rom[11'd1622]=4'd13;
    car_rom[11'd1623]=4'd12;
    car_rom[11'd1624]=4'd13;
    car_rom[11'd1625]=4'd10;
    car_rom[11'd1626]=4'd7;
    car_rom[11'd1627]=4'd5;
    car_rom[11'd1628]=4'd10;
    car_rom[11'd1629]=4'd12;
    car_rom[11'd1634]=4'd13;
    car_rom[11'd1635]=4'd10;
    car_rom[11'd1636]=4'd1;
    car_rom[11'd1637]=4'd5;
    car_rom[11'd1638]=4'd10;
    car_rom[11'd1639]=4'd13;
    car_rom[11'd1640]=4'd11;
    car_rom[11'd1641]=4'd12;
    car_rom[11'd1642]=4'd13;
    car_rom[11'd1643]=4'd13;
    car_rom[11'd1644]=4'd13;
    car_rom[11'd1645]=4'd13;
    car_rom[11'd1646]=4'd13;
    car_rom[11'd1647]=4'd13;
    car_rom[11'd1648]=4'd13;
    car_rom[11'd1649]=4'd13;
    car_rom[11'd1650]=4'd13;
    car_rom[11'd1651]=4'd13;
    car_rom[11'd1652]=4'd13;
    car_rom[11'd1653]=4'd13;
    car_rom[11'd1654]=4'd12;
    car_rom[11'd1655]=4'd11;
    car_rom[11'd1656]=4'd13;
    car_rom[11'd1657]=4'd10;
    car_rom[11'd1658]=4'd6;
    car_rom[11'd1659]=4'd4;
    car_rom[11'd1660]=4'd10;
    car_rom[11'd1661]=4'd13;
    car_rom[11'd1666]=4'd13;
    car_rom[11'd1667]=4'd10;
    car_rom[11'd1668]=4'd1;
    car_rom[11'd1669]=4'd4;
    car_rom[11'd1670]=4'd11;
    car_rom[11'd1671]=4'd14;
    car_rom[11'd1672]=4'd11;
    car_rom[11'd1673]=4'd12;
    car_rom[11'd1674]=4'd12;
    car_rom[11'd1675]=4'd13;
    car_rom[11'd1676]=4'd13;
    car_rom[11'd1677]=4'd13;
    car_rom[11'd1678]=4'd13;
    car_rom[11'd1679]=4'd13;
    car_rom[11'd1680]=4'd13;
    car_rom[11'd1681]=4'd13;
    car_rom[11'd1682]=4'd13;
    car_rom[11'd1683]=4'd13;
    car_rom[11'd1684]=4'd13;
    car_rom[11'd1685]=4'd12;
    car_rom[11'd1686]=4'd12;
    car_rom[11'd1687]=4'd12;
    car_rom[11'd1688]=4'd14;
    car_rom[11'd1689]=4'd10;
    car_rom[11'd1690]=4'd5;
    car_rom[11'd1691]=4'd1;
    car_rom[11'd1692]=4'd11;
    car_rom[11'd1693]=4'd12;
    car_rom[11'd1698]=4'd13;
    car_rom[11'd1699]=4'd11;
    car_rom[11'd1700]=4'd4;
    car_rom[11'd1701]=4'd4;
    car_rom[11'd1702]=4'd9;
    car_rom[11'd1703]=4'd11;
    car_rom[11'd1704]=4'd13;
    car_rom[11'd1705]=4'd14;
    car_rom[11'd1706]=4'd14;
    car_rom[11'd1707]=4'd14;
    car_rom[11'd1708]=4'd14;
    car_rom[11'd1709]=4'd14;
    car_rom[11'd1710]=4'd14;
    car_rom[11'd1711]=4'd14;
    car_rom[11'd1712]=4'd14;
    car_rom[11'd1713]=4'd14;
    car_rom[11'd1714]=4'd14;
    car_rom[11'd1715]=4'd14;
    car_rom[11'd1716]=4'd14;
    car_rom[11'd1717]=4'd14;
    car_rom[11'd1718]=4'd14;
    car_rom[11'd1719]=4'd13;
    car_rom[11'd1720]=4'd11;
    car_rom[11'd1721]=4'd8;
    car_rom[11'd1722]=4'd4;
    car_rom[11'd1723]=4'd5;
    car_rom[11'd1724]=4'd12;
    car_rom[11'd1725]=4'd12;
    car_rom[11'd1730]=4'd10;
    car_rom[11'd1731]=4'd12;
    car_rom[11'd1732]=4'd15;
    car_rom[11'd1733]=4'd1;
    car_rom[11'd1734]=4'd6;
    car_rom[11'd1735]=4'd4;
    car_rom[11'd1736]=4'd7;
    car_rom[11'd1737]=4'd9;
    car_rom[11'd1738]=4'd10;
    car_rom[11'd1739]=4'd11;
    car_rom[11'd1740]=4'd11;
    car_rom[11'd1741]=4'd11;
    car_rom[11'd1742]=4'd12;
    car_rom[11'd1743]=4'd12;
    car_rom[11'd1744]=4'd12;
    car_rom[11'd1745]=4'd12;
    car_rom[11'd1746]=4'd11;
    car_rom[11'd1747]=4'd11;
    car_rom[11'd1748]=4'd11;
    car_rom[11'd1749]=4'd10;
    car_rom[11'd1750]=4'd9;
    car_rom[11'd1751]=4'd6;
    car_rom[11'd1752]=4'd4;
    car_rom[11'd1753]=4'd6;
    car_rom[11'd1754]=4'd1;
    car_rom[11'd1755]=4'd15;
    car_rom[11'd1756]=4'd12;
    car_rom[11'd1757]=4'd9;
    car_rom[11'd1763]=4'd7;
    car_rom[11'd1764]=4'd15;
    car_rom[11'd1765]=4'd3;
    car_rom[11'd1766]=4'd4;
    car_rom[11'd1767]=4'd6;
    car_rom[11'd1768]=4'd7;
    car_rom[11'd1769]=4'd6;
    car_rom[11'd1770]=4'd6;
    car_rom[11'd1771]=4'd6;
    car_rom[11'd1772]=4'd6;
    car_rom[11'd1773]=4'd6;
    car_rom[11'd1774]=4'd7;
    car_rom[11'd1775]=4'd7;
    car_rom[11'd1776]=4'd7;
    car_rom[11'd1777]=4'd7;
    car_rom[11'd1778]=4'd6;
    car_rom[11'd1779]=4'd6;
    car_rom[11'd1780]=4'd6;
    car_rom[11'd1781]=4'd6;
    car_rom[11'd1782]=4'd6;
    car_rom[11'd1783]=4'd7;
    car_rom[11'd1784]=4'd6;
    car_rom[11'd1785]=4'd4;
    car_rom[11'd1786]=4'd15;
    car_rom[11'd1787]=4'd15;
    car_rom[11'd1788]=4'd6;
    car_rom[11'd1795]=4'd4;
    car_rom[11'd1796]=4'd15;
    car_rom[11'd1797]=4'd15;
    car_rom[11'd1798]=4'd6;
    car_rom[11'd1799]=4'd1;
    car_rom[11'd1800]=4'd6;
    car_rom[11'd1801]=4'd7;
    car_rom[11'd1802]=4'd8;
    car_rom[11'd1803]=4'd8;
    car_rom[11'd1804]=4'd9;
    car_rom[11'd1805]=4'd9;
    car_rom[11'd1806]=4'd9;
    car_rom[11'd1807]=4'd9;
    car_rom[11'd1808]=4'd9;
    car_rom[11'd1809]=4'd9;
    car_rom[11'd1810]=4'd9;
    car_rom[11'd1811]=4'd9;
    car_rom[11'd1812]=4'd8;
    car_rom[11'd1813]=4'd8;
    car_rom[11'd1814]=4'd7;
    car_rom[11'd1815]=4'd5;
    car_rom[11'd1816]=4'd1;
    car_rom[11'd1817]=4'd7;
    car_rom[11'd1818]=4'd15;
    car_rom[11'd1819]=4'd15;
    car_rom[11'd1820]=4'd4;
    car_rom[11'd1828]=4'd10;
    car_rom[11'd1829]=4'd15;
    car_rom[11'd1830]=4'd15;
    car_rom[11'd1831]=4'd15;
    car_rom[11'd1832]=4'd6;
    car_rom[11'd1833]=4'd5;
    car_rom[11'd1834]=4'd5;
    car_rom[11'd1835]=4'd6;
    car_rom[11'd1836]=4'd6;
    car_rom[11'd1837]=4'd7;
    car_rom[11'd1838]=4'd7;
    car_rom[11'd1839]=4'd8;
    car_rom[11'd1840]=4'd8;
    car_rom[11'd1841]=4'd7;
    car_rom[11'd1842]=4'd7;
    car_rom[11'd1843]=4'd6;
    car_rom[11'd1844]=4'd6;
    car_rom[11'd1845]=4'd6;
    car_rom[11'd1846]=4'd5;
    car_rom[11'd1847]=4'd7;
    car_rom[11'd1848]=4'd15;
    car_rom[11'd1849]=4'd15;
    car_rom[11'd1850]=4'd15;
    car_rom[11'd1851]=4'd10;
    car_rom[11'd1860]=4'd9;
    car_rom[11'd1861]=4'd4;
    car_rom[11'd1862]=4'd15;
    car_rom[11'd1863]=4'd15;
    car_rom[11'd1864]=4'd15;
    car_rom[11'd1865]=4'd11;
    car_rom[11'd1866]=4'd10;
    car_rom[11'd1867]=4'd10;
    car_rom[11'd1868]=4'd9;
    car_rom[11'd1869]=4'd9;
    car_rom[11'd1870]=4'd9;
    car_rom[11'd1871]=4'd9;
    car_rom[11'd1872]=4'd9;
    car_rom[11'd1873]=4'd9;
    car_rom[11'd1874]=4'd9;
    car_rom[11'd1875]=4'd10;
    car_rom[11'd1876]=4'd10;
    car_rom[11'd1877]=4'd10;
    car_rom[11'd1878]=4'd11;
    car_rom[11'd1879]=4'd15;
    car_rom[11'd1880]=4'd15;
    car_rom[11'd1881]=4'd10;
    car_rom[11'd1882]=4'd5;
    car_rom[11'd1883]=4'd9;
    car_rom[11'd1892]=4'd5;
    car_rom[11'd1893]=4'd10;
    car_rom[11'd1894]=4'd7;
    car_rom[11'd1895]=4'd5;
    car_rom[11'd1896]=4'd8;
    car_rom[11'd1897]=4'd9;
    car_rom[11'd1898]=4'd9;
    car_rom[11'd1899]=4'd10;
    car_rom[11'd1900]=4'd10;
    car_rom[11'd1901]=4'd10;
    car_rom[11'd1902]=4'd10;
    car_rom[11'd1903]=4'd10;
    car_rom[11'd1904]=4'd10;
    car_rom[11'd1905]=4'd10;
    car_rom[11'd1906]=4'd10;
    car_rom[11'd1907]=4'd10;
    car_rom[11'd1908]=4'd10;
    car_rom[11'd1909]=4'd9;
    car_rom[11'd1910]=4'd9;
    car_rom[11'd1911]=4'd8;
    car_rom[11'd1912]=4'd6;
    car_rom[11'd1913]=4'd9;
    car_rom[11'd1914]=4'd10;
    car_rom[11'd1915]=4'd3;
    car_rom[11'd1925]=4'd1;
    car_rom[11'd1926]=4'd15;
    car_rom[11'd1927]=4'd10;
    car_rom[11'd1928]=4'd10;
    car_rom[11'd1929]=4'd9;
    car_rom[11'd1930]=4'd8;
    car_rom[11'd1931]=4'd8;
    car_rom[11'd1932]=4'd8;
    car_rom[11'd1933]=4'd8;
    car_rom[11'd1934]=4'd9;
    car_rom[11'd1935]=4'd9;
    car_rom[11'd1936]=4'd9;
    car_rom[11'd1937]=4'd9;
    car_rom[11'd1938]=4'd8;
    car_rom[11'd1939]=4'd8;
    car_rom[11'd1940]=4'd8;
    car_rom[11'd1941]=4'd9;
    car_rom[11'd1942]=4'd10;
    car_rom[11'd1943]=4'd10;
    car_rom[11'd1944]=4'd15;
    car_rom[11'd1945]=4'd15;
    car_rom[11'd1960]=4'd7;
    car_rom[11'd1961]=4'd10;
    car_rom[11'd1962]=4'd11;
    car_rom[11'd1963]=4'd11;
    car_rom[11'd1964]=4'd11;
    car_rom[11'd1965]=4'd11;
    car_rom[11'd1966]=4'd11;
    car_rom[11'd1967]=4'd11;
    car_rom[11'd1968]=4'd11;
    car_rom[11'd1969]=4'd11;
    car_rom[11'd1970]=4'd11;
    car_rom[11'd1971]=4'd11;
    car_rom[11'd1972]=4'd11;
    car_rom[11'd1973]=4'd11;
    car_rom[11'd1974]=4'd10;
    car_rom[11'd1975]=4'd7;
end
always @(posedge I_clk) O_index <= car_rom[I_addr];
always @(*) begin
    case (O_index)
        4'd1: O_rgb=24'hFFFFFF;
        4'd2: O_rgb=24'hFFFFF9;
        4'd3: O_rgb=24'hFFFBFC;
        4'd4: O_rgb=24'hFBFDFE;
        4'd5: O_rgb=24'hEDF0F2;
        4'd6: O_rgb=24'hDCE0E4;
        4'd7: O_rgb=24'hCDD2D6;
        4'd8: O_rgb=24'hC1C6CB;
        4'd9: O_rgb=24'hB7BCC0;
        4'd10: O_rgb=24'h888B8F;
        4'd11: O_rgb=24'h3E444A;
        4'd12: O_rgb=24'h2B282F;
        4'd13: O_rgb=24'h121D26;
        4'd14: O_rgb=24'h01060E;
        4'd15: O_rgb=24'hB54548;
        default: O_rgb=24'hFFFFFF;
    endcase
end
endmodule
