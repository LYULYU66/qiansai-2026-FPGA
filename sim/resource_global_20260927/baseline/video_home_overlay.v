// Picture-1-only car dashboard. All text is a tiny combinational 16x16 ROM;
// the background is the decoded TF-card image. No frame store, DSP, or BRAM.
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
always @(posedge I_clk or posedge I_rst) begin
    if (I_rst) begin
        pixel_x <= 11'd0; pixel_y <= 10'd0;
        de_d <= 1'b0; vs_d <= 1'b0; active_seen <= 1'b0;
    end else begin
        de_d <= I_de; vs_d <= I_vs;
        if (frame_start) begin
            pixel_x <= 11'd0; pixel_y <= 10'd0; active_seen <= 1'b0;
        end else if (I_de) begin
            if (line_start) begin
                pixel_x <= 11'd0;
                if (!active_seen) begin
                    pixel_y <= 10'd0; active_seen <= 1'b1;
                end else if (pixel_y < V_ACTIVE-1) pixel_y <= pixel_y + 10'd1;
            end else if (pixel_x < H_ACTIVE-1) pixel_x <= pixel_x + 11'd1;
        end else pixel_x <= 11'd0;
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
wire card_hit = I_enable && I_de && (card_id != 2'd3) &&
                pixel_y >= 10'd322 && pixel_y < 10'd408;
wire card_top = card_hit && pixel_y < 10'd325;
wire card_border = card_hit &&
                   (pixel_y == 10'd407 ||
                    pixel_x == 11'd16 || pixel_x == 11'd209 ||
                    pixel_x == 11'd222 || pixel_x == 11'd417 ||
                    pixel_x == 11'd430 || pixel_x == 11'd623);
wire nav_hit = I_enable && I_de && pixel_y >= 10'd416;
wire nav_top = nav_hit && pixel_y < 10'd418;
wire home_tab = nav_hit && pixel_x >= 11'd45 && pixel_x < 11'd99 &&
                pixel_y >= 10'd425 && pixel_y < 10'd468;

// Three card headings and values; weather is user-supplied demo content.
reg [4:0] glyph_id;
reg [3:0] glyph_col, glyph_y;
reg text_valid, forecast_text;
reg [2:0] glyph_cell;
always @(*) begin
    glyph_id = 5'd31; glyph_col = 4'd0; glyph_y = 4'd0;
    glyph_cell = 3'd0; text_valid = 1'b0; forecast_text = 1'b0;
    if (card_hit && card_id == 2'd0) begin
        if (pixel_x >= 11'd64 && pixel_x < 11'd112 &&
            pixel_y >= 10'd338 && pixel_y < 10'd354) begin
            glyph_cell = pixel_x[6:4] - 3'd4;
            glyph_col = pixel_x[3:0]; glyph_y = pixel_y[3:0] - 4'd2;
            case (glyph_cell)
                    3'd0: glyph_id = 5'd0;
                    3'd1: glyph_id = 5'd1;
                    3'd2: glyph_id = 5'd2;
                default: glyph_id = 5'd31;
            endcase
            text_valid = 1'b1;
        end else if (pixel_x >= 11'd64 && pixel_x < 11'd96 &&
                     pixel_y >= 10'd371 && pixel_y < 10'd387) begin
            glyph_cell = pixel_x[6:4] - 3'd4;
            glyph_col = pixel_x[3:0]; glyph_y = pixel_y[3:0] - 4'd3;
            case (glyph_cell)
                    3'd0: glyph_id = 5'd3;
                    3'd1: glyph_id = 5'd4;
                default: glyph_id = 5'd31;
            endcase
            text_valid = 1'b1;
        end
    end else if (card_hit && card_id == 2'd1) begin
        if (pixel_x >= 11'd272 && pixel_x < 11'd304 &&
            pixel_y >= 10'd338 && pixel_y < 10'd354) begin
            glyph_cell = pixel_x[6:4] - 3'd1;
            glyph_col = pixel_x[3:0]; glyph_y = pixel_y[3:0] - 4'd2;
            case (glyph_cell)
                    3'd0: glyph_id = 5'd5;
                    3'd1: glyph_id = 5'd6;
                default: glyph_id = 5'd31;
            endcase
            text_valid = 1'b1;
        end else if (pixel_x >= 11'd272 && pixel_x < 11'd336 &&
                     pixel_y >= 10'd371 && pixel_y < 10'd387) begin
            glyph_cell = pixel_x[6:4] - 3'd1;
            glyph_col = pixel_x[3:0]; glyph_y = pixel_y[3:0] - 4'd3;
            case (glyph_cell)
                    3'd0: glyph_id = 5'd7;
                    3'd1: glyph_id = 5'd8;
                    3'd2: glyph_id = 5'd9;
                    3'd3: glyph_id = 5'd10;
                default: glyph_id = 5'd31;
            endcase
            text_valid = 1'b1;
        end
    end else if (card_hit && card_id == 2'd2) begin
        if (pixel_x >= 11'd480 && pixel_x < 11'd560 &&
            pixel_y >= 10'd330 && pixel_y < 10'd346) begin
            glyph_cell = pixel_x[6:4] - 3'd6;
            glyph_col = pixel_x[3:0]; glyph_y = pixel_y[3:0] - 4'd10;
            case (glyph_cell)
                    3'd0: glyph_id = 5'd3;
                    3'd1: glyph_id = 5'd4;
                    3'd2: glyph_id = 5'd11;
                    3'd3: glyph_id = 5'd12;
                    3'd4: glyph_id = 5'd9;
                default: glyph_id = 5'd31;
            endcase
            text_valid = 1'b1;
        end else if (pixel_x >= 11'd480 && pixel_x < 11'd576 &&
                     pixel_y >= 10'd354 && pixel_y < 10'd370) begin
            glyph_cell = pixel_x[6:4] - 3'd6;
            glyph_col = pixel_x[3:0]; glyph_y = pixel_y[3:0] - 4'd2;
            case (glyph_cell)
                    3'd0: glyph_id = 5'd22; // 今
                    3'd1: glyph_id = 5'd12; // 天
                    3'd2: glyph_id = 5'd13; // 晴
                    3'd3: glyph_id = 5'd14; // 2
                    3'd4: glyph_id = 5'd15; // 9
                    3'd5: glyph_id = 5'd16; // 摄氏度符号
                default: glyph_id = 5'd31;
            endcase
            text_valid = 1'b1;
        end else if (pixel_x >= 11'd448 && pixel_x < 11'd512 &&
                     pixel_y >= 10'd383 && pixel_y < 10'd399) begin
            glyph_cell = pixel_x[6:4] - 3'd4;
            glyph_col = pixel_x[3:0]; glyph_y = pixel_y[3:0] - 4'd15;
            case (glyph_cell)
                    3'd0: glyph_id = 5'd17;
                    3'd1: glyph_id = 5'd18;
                    3'd2: glyph_id = 5'd19;
                    3'd3: glyph_id = 5'd20;
                default: glyph_id = 5'd31;
            endcase
            text_valid = 1'b1; forecast_text = 1'b1;
        end else if (pixel_x >= 11'd528 && pixel_x < 11'd592 &&
                     pixel_y >= 10'd383 && pixel_y < 10'd399) begin
            glyph_cell = pixel_x[6:4] - 3'd1;
            glyph_col = pixel_x[3:0]; glyph_y = pixel_y[3:0] - 4'd15;
            case (glyph_cell)
                    3'd0: glyph_id = 5'd17;
                    3'd1: glyph_id = 5'd21;
                    3'd2: glyph_id = 5'd19;
                    3'd3: glyph_id = 5'd20;
                default: glyph_id = 5'd31;
            endcase
            text_valid = 1'b1; forecast_text = 1'b1;
        end
    end
end
wire [15:0] row_bits = glyph_row(glyph_id, glyph_y);
wire glyph_on = text_valid && row_bits[15-glyph_col];

// Card symbols echo the reference: destination pin, album/music, sun/cloud.
wire dest_icon = card_hit && card_id == 2'd0 &&
    (((pixel_x >= 11'd34 && pixel_x <= 11'd50 &&
       pixel_y >= 10'd344 && pixel_y <= 10'd360 &&
       ((pixel_x == 11'd34 || pixel_x == 11'd50) ||
        pixel_y == 10'd344 || pixel_y == 10'd360))) ||
     (pixel_x >= 11'd40 && pixel_x <= 11'd44 &&
      pixel_y >= 10'd361 && pixel_y <= 10'd369));
wire music_icon = card_hit && card_id == 2'd1 &&
    ((pixel_x >= 11'd238 && pixel_x <= 11'd259 &&
      pixel_y >= 10'd341 && pixel_y <= 10'd368 &&
      (pixel_x == 11'd238 || pixel_x == 11'd259 ||
       pixel_y == 10'd341 || pixel_y == 10'd368)) ||
     (pixel_x >= 11'd246 && pixel_x < 11'd250 &&
      pixel_y >= 10'd348 && pixel_y < 10'd362) ||
     (pixel_x >= 11'd246 && pixel_x < 11'd256 &&
      pixel_y >= 10'd348 && pixel_y < 10'd351) ||
     (pixel_x >= 11'd242 && pixel_x < 11'd249 &&
      pixel_y >= 10'd359 && pixel_y < 10'd364));
wire weather_icon = card_hit && card_id == 2'd2 &&
    ((pixel_x >= 11'd439 && pixel_x < 11'd470 &&
      pixel_y >= 10'd352 && pixel_y < 10'd362) ||
     (pixel_x >= 11'd446 && pixel_x < 11'd464 &&
      pixel_y >= 10'd347 && pixel_y < 10'd360) ||
     (pixel_x >= 11'd452 && pixel_x < 11'd458 &&
      pixel_y >= 10'd342 && pixel_y < 10'd357));

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
                     pixel_y >= 10'd437 && pixel_y < 10'd461;
wire [4:0] ix = pixel_x - nav_left;
wire [4:0] iy = pixel_y - 10'd437;
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
wire [7:0] card_r = 8'd9 + {2'b00,I_rgb[23:18]};
wire [7:0] card_g = 8'd15 + {2'b00,I_rgb[15:10]};
wire [7:0] card_b = 8'd25 + {2'b00,I_rgb[7:2]};
wire [7:0] nav_r = 8'd6 + {3'b000,I_rgb[23:19]};
wire [7:0] nav_g = 8'd12 + {3'b000,I_rgb[15:11]};
wire [7:0] nav_b = 8'd22 + {3'b000,I_rgb[7:3]};
assign O_rgb =
    !I_enable || !I_de ? I_rgb :
    glyph_on ? (forecast_text ? 24'hC5D9E6 : 24'hF5FAFF) :
    dest_icon ? 24'h57D8FF :
    music_icon ? 24'hFF709E :
    weather_icon ? 24'h83DDF9 :
    nav_icon ? ((nav_id == 3'd0) ? 24'h6BE7FF : 24'hDAE8F2) :
    card_top ? 24'h4EB6D1 :
    card_border ? 24'h416275 :
    card_hit ? {card_r,card_g,card_b} :
    nav_top ? 24'h4A9FBA :
    home_tab ? 24'h16445D :
    nav_hit ? {nav_r,nav_g,nav_b} : I_rgb;

function [15:0] glyph_row;
    input [4:0] glyph;
    input [3:0] row;
    begin
        glyph_row = 16'h0000;
        case ({glyph,row})
            9'h000: glyph_row = 16'h0FFF; // 目
            9'h001: glyph_row = 16'h0C03; // 目
            9'h002: glyph_row = 16'h0C03; // 目
            9'h003: glyph_row = 16'h0C03; // 目
            9'h004: glyph_row = 16'h0FFF; // 目
            9'h005: glyph_row = 16'h0C03; // 目
            9'h006: glyph_row = 16'h0C03; // 目
            9'h007: glyph_row = 16'h0C03; // 目
            9'h008: glyph_row = 16'h0FFF; // 目
            9'h009: glyph_row = 16'h0C03; // 目
            9'h00A: glyph_row = 16'h0C03; // 目
            9'h00B: glyph_row = 16'h0C03; // 目
            9'h00C: glyph_row = 16'h0FFF; // 目
            9'h00D: glyph_row = 16'h0C03; // 目
            9'h010: glyph_row = 16'h061C; // 的
            9'h011: glyph_row = 16'h0618; // 的
            9'h012: glyph_row = 16'h1FFF; // 的
            9'h013: glyph_row = 16'h1FF1; // 的
            9'h014: glyph_row = 16'h19F1; // 的
            9'h015: glyph_row = 16'h19E1; // 的
            9'h016: glyph_row = 16'h19D9; // 的
            9'h017: glyph_row = 16'h1FDD; // 的
            9'h018: glyph_row = 16'h19CD; // 的
            9'h019: glyph_row = 16'h19CD; // 的
            9'h01A: glyph_row = 16'h19C1; // 的
            9'h01B: glyph_row = 16'h19C1; // 的
            9'h01C: glyph_row = 16'h1FC1; // 的
            9'h01D: glyph_row = 16'h19CF; // 的
            9'h01E: glyph_row = 16'h000C; // 的
            9'h020: glyph_row = 16'h0C1C; // 地
            9'h021: glyph_row = 16'h0CFC; // 地
            9'h022: glyph_row = 16'h0CFC; // 地
            9'h023: glyph_row = 16'h0CFF; // 地
            9'h024: glyph_row = 16'h3FFF; // 地
            9'h025: glyph_row = 16'h0DFD; // 地
            9'h026: glyph_row = 16'h0DFD; // 地
            9'h027: glyph_row = 16'h0CFD; // 地
            9'h028: glyph_row = 16'h0CFD; // 地
            9'h029: glyph_row = 16'h0CFF; // 地
            9'h02A: glyph_row = 16'h0FFC; // 地
            9'h02B: glyph_row = 16'h3EE0; // 地
            9'h02C: glyph_row = 16'h30E0; // 地
            9'h02D: glyph_row = 16'h007F; // 地
            9'h030: glyph_row = 16'h0060; // 青
            9'h031: glyph_row = 16'h1FFF; // 青
            9'h032: glyph_row = 16'h0060; // 青
            9'h033: glyph_row = 16'h0FFF; // 青
            9'h034: glyph_row = 16'h0060; // 青
            9'h035: glyph_row = 16'h3FFF; // 青
            9'h037: glyph_row = 16'h0FFF; // 青
            9'h038: glyph_row = 16'h0E03; // 青
            9'h039: glyph_row = 16'h0FFF; // 青
            9'h03A: glyph_row = 16'h0E03; // 青
            9'h03B: glyph_row = 16'h0FFF; // 青
            9'h03C: glyph_row = 16'h0E03; // 青
            9'h03D: glyph_row = 16'h0E0F; // 青
            9'h03E: glyph_row = 16'h0E00; // 青
            9'h040: glyph_row = 16'h00C0; // 岛
            9'h041: glyph_row = 16'h0FFF; // 岛
            9'h042: glyph_row = 16'h0F87; // 岛
            9'h043: glyph_row = 16'h0FC7; // 岛
            9'h044: glyph_row = 16'h0EE6; // 岛
            9'h045: glyph_row = 16'h0ECE; // 岛
            9'h046: glyph_row = 16'h0FFF; // 岛
            9'h047: glyph_row = 16'h0FFF; // 岛
            9'h048: glyph_row = 16'h0181; // 岛
            9'h049: glyph_row = 16'h199D; // 岛
            9'h04A: glyph_row = 16'h1999; // 岛
            9'h04B: glyph_row = 16'h1FF9; // 岛
            9'h04C: glyph_row = 16'h001D; // 岛
            9'h04D: glyph_row = 16'h0007; // 岛
            9'h050: glyph_row = 16'h0060; // 音
            9'h051: glyph_row = 16'h1FFF; // 音
            9'h052: glyph_row = 16'h030C; // 音
            9'h053: glyph_row = 16'h030C; // 音
            9'h054: glyph_row = 16'h039C; // 音
            9'h055: glyph_row = 16'h3FFF; // 音
            9'h057: glyph_row = 16'h0FFF; // 音
            9'h058: glyph_row = 16'h0606; // 音
            9'h059: glyph_row = 16'h0606; // 音
            9'h05A: glyph_row = 16'h07FE; // 音
            9'h05B: glyph_row = 16'h0606; // 音
            9'h05C: glyph_row = 16'h0606; // 音
            9'h05D: glyph_row = 16'h0FFF; // 音
            9'h05E: glyph_row = 16'h0E07; // 音
            9'h060: glyph_row = 16'h007F; // 乐
            9'h061: glyph_row = 16'h0FE0; // 乐
            9'h062: glyph_row = 16'h0C70; // 乐
            9'h063: glyph_row = 16'h0C70; // 乐
            9'h064: glyph_row = 16'h0C70; // 乐
            9'h065: glyph_row = 16'h1C70; // 乐
            9'h066: glyph_row = 16'h1FFF; // 乐
            9'h067: glyph_row = 16'h0070; // 乐
            9'h068: glyph_row = 16'h0370; // 乐
            9'h069: glyph_row = 16'h077E; // 乐
            9'h06A: glyph_row = 16'h0E77; // 乐
            9'h06B: glyph_row = 16'h1C73; // 乐
            9'h06C: glyph_row = 16'h1871; // 乐
            9'h06D: glyph_row = 16'h01F0; // 乐
            9'h06E: glyph_row = 16'h01C0; // 乐
            9'h070: glyph_row = 16'h0770; // 告
            9'h071: glyph_row = 16'h0E70; // 告
            9'h072: glyph_row = 16'h0FFF; // 告
            9'h073: glyph_row = 16'h1C70; // 告
            9'h074: glyph_row = 16'h0070; // 告
            9'h075: glyph_row = 16'h0070; // 告
            9'h076: glyph_row = 16'h3FFF; // 告
            9'h078: glyph_row = 16'h0FFF; // 告
            9'h079: glyph_row = 16'h0E07; // 告
            9'h07A: glyph_row = 16'h0E07; // 告
            9'h07B: glyph_row = 16'h0E07; // 告
            9'h07C: glyph_row = 16'h0FFF; // 告
            9'h07D: glyph_row = 16'h0E07; // 告
            9'h07E: glyph_row = 16'h0007; // 告
            9'h080: glyph_row = 16'h01C0; // 白
            9'h081: glyph_row = 16'h0180; // 白
            9'h082: glyph_row = 16'h0FFF; // 白
            9'h083: glyph_row = 16'h0C03; // 白
            9'h084: glyph_row = 16'h0C03; // 白
            9'h085: glyph_row = 16'h0C03; // 白
            9'h086: glyph_row = 16'h0C03; // 白
            9'h087: glyph_row = 16'h0FFF; // 白
            9'h088: glyph_row = 16'h0C03; // 白
            9'h089: glyph_row = 16'h0C03; // 白
            9'h08A: glyph_row = 16'h0C03; // 白
            9'h08B: glyph_row = 16'h0FFF; // 白
            9'h08C: glyph_row = 16'h0FFF; // 白
            9'h08D: glyph_row = 16'h0C03; // 白
            9'h090: glyph_row = 16'h0700; // 气
            9'h091: glyph_row = 16'h0FFF; // 气
            9'h092: glyph_row = 16'h0C00; // 气
            9'h093: glyph_row = 16'h1CFF; // 气
            9'h094: glyph_row = 16'h3FFF; // 气
            9'h096: glyph_row = 16'h1FFE; // 气
            9'h097: glyph_row = 16'h0006; // 气
            9'h098: glyph_row = 16'h0006; // 气
            9'h099: glyph_row = 16'h0006; // 气
            9'h09A: glyph_row = 16'h0006; // 气
            9'h09B: glyph_row = 16'h0006; // 气
            9'h09C: glyph_row = 16'h0007; // 气
            9'h09D: glyph_row = 16'h0003; // 气
            9'h09E: glyph_row = 16'h0001; // 气
            9'h0A0: glyph_row = 16'h001F; // 球
            9'h0A1: glyph_row = 16'h3F1F; // 球
            9'h0A2: glyph_row = 16'h3FFF; // 球
            9'h0A3: glyph_row = 16'h0C1C; // 球
            9'h0A4: glyph_row = 16'h0C1C; // 球
            9'h0A5: glyph_row = 16'h0CFD; // 球
            9'h0A6: glyph_row = 16'h3F7F; // 球
            9'h0A7: glyph_row = 16'h0C1F; // 球
            9'h0A8: glyph_row = 16'h0C3E; // 球
            9'h0A9: glyph_row = 16'h0C7F; // 球
            9'h0AA: glyph_row = 16'h0F7F; // 球
            9'h0AB: glyph_row = 16'h1EDD; // 球
            9'h0AC: glyph_row = 16'h38DC; // 球
            9'h0AD: glyph_row = 16'h003C; // 球
            9'h0AE: glyph_row = 16'h0030; // 球
            9'h0B0: glyph_row = 16'h00E0; // 市
            9'h0B1: glyph_row = 16'h0060; // 市
            9'h0B2: glyph_row = 16'h3FFF; // 市
            9'h0B3: glyph_row = 16'h0060; // 市
            9'h0B4: glyph_row = 16'h0060; // 市
            9'h0B5: glyph_row = 16'h0FFF; // 市
            9'h0B6: glyph_row = 16'h0C63; // 市
            9'h0B7: glyph_row = 16'h0C63; // 市
            9'h0B8: glyph_row = 16'h0C63; // 市
            9'h0B9: glyph_row = 16'h0C63; // 市
            9'h0BA: glyph_row = 16'h0C63; // 市
            9'h0BB: glyph_row = 16'h0C6F; // 市
            9'h0BC: glyph_row = 16'h0C6F; // 市
            9'h0BD: glyph_row = 16'h0060; // 市
            9'h0BE: glyph_row = 16'h0060; // 市
            9'h0C0: glyph_row = 16'h0FFF; // 天
            9'h0C1: glyph_row = 16'h0060; // 天
            9'h0C2: glyph_row = 16'h0060; // 天
            9'h0C3: glyph_row = 16'h0060; // 天
            9'h0C4: glyph_row = 16'h0060; // 天
            9'h0C5: glyph_row = 16'h1FFF; // 天
            9'h0C6: glyph_row = 16'h0070; // 天
            9'h0C7: glyph_row = 16'h00F0; // 天
            9'h0C8: glyph_row = 16'h00F8; // 天
            9'h0C9: glyph_row = 16'h01D8; // 天
            9'h0CA: glyph_row = 16'h039C; // 天
            9'h0CB: glyph_row = 16'h070E; // 天
            9'h0CC: glyph_row = 16'h1E07; // 天
            9'h0CD: glyph_row = 16'h3C01; // 天
            9'h0D0: glyph_row = 16'h000C; // 晴
            9'h0D1: glyph_row = 16'h3FFF; // 晴
            9'h0D2: glyph_row = 16'h37FF; // 晴
            9'h0D3: glyph_row = 16'h37FF; // 晴
            9'h0D4: glyph_row = 16'h370C; // 晴
            9'h0D5: glyph_row = 16'h3FFF; // 晴
            9'h0D6: glyph_row = 16'h3700; // 晴
            9'h0D7: glyph_row = 16'h377F; // 晴
            9'h0D8: glyph_row = 16'h3761; // 晴
            9'h0D9: glyph_row = 16'h377F; // 晴
            9'h0DA: glyph_row = 16'h3F61; // 晴
            9'h0DB: glyph_row = 16'h377F; // 晴
            9'h0DC: glyph_row = 16'h3061; // 晴
            9'h0DD: glyph_row = 16'h0063; // 晴
            9'h0DE: glyph_row = 16'h0063; // 晴
            9'h0E1: glyph_row = 16'h1F00; // 2
            9'h0E2: glyph_row = 16'h3F80; // 2
            9'h0E3: glyph_row = 16'h3180; // 2
            9'h0E4: glyph_row = 16'h0180; // 2
            9'h0E5: glyph_row = 16'h0180; // 2
            9'h0E6: glyph_row = 16'h0380; // 2
            9'h0E7: glyph_row = 16'h0700; // 2
            9'h0E8: glyph_row = 16'h0600; // 2
            9'h0E9: glyph_row = 16'h0C00; // 2
            9'h0EA: glyph_row = 16'h1800; // 2
            9'h0EB: glyph_row = 16'h3FC0; // 2
            9'h0EC: glyph_row = 16'h3FC0; // 2
            9'h0F1: glyph_row = 16'h1F00; // 9
            9'h0F2: glyph_row = 16'h3B80; // 9
            9'h0F3: glyph_row = 16'h3180; // 9
            9'h0F4: glyph_row = 16'h7180; // 9
            9'h0F5: glyph_row = 16'h7180; // 9
            9'h0F6: glyph_row = 16'h3380; // 9
            9'h0F7: glyph_row = 16'h3F80; // 9
            9'h0F8: glyph_row = 16'h0700; // 9
            9'h0F9: glyph_row = 16'h0700; // 9
            9'h0FA: glyph_row = 16'h0E00; // 9
            9'h0FB: glyph_row = 16'h0C00; // 9
            9'h0FC: glyph_row = 16'h1C00; // 9
            9'h100: glyph_row = 16'h3C00; // ℃
            9'h101: glyph_row = 16'h3C3C; // ℃
            9'h102: glyph_row = 16'h1CFF; // ℃
            9'h103: glyph_row = 16'h01C3; // ℃
            9'h104: glyph_row = 16'h0181; // ℃
            9'h105: glyph_row = 16'h0180; // ℃
            9'h106: glyph_row = 16'h0380; // ℃
            9'h107: glyph_row = 16'h0380; // ℃
            9'h108: glyph_row = 16'h0380; // ℃
            9'h109: glyph_row = 16'h0381; // ℃
            9'h10A: glyph_row = 16'h0181; // ℃
            9'h10B: glyph_row = 16'h01C3; // ℃
            9'h10C: glyph_row = 16'h007E; // ℃
            9'h110: glyph_row = 16'h0FFF; // 周
            9'h111: glyph_row = 16'h0C61; // 周
            9'h112: glyph_row = 16'h0C61; // 周
            9'h113: glyph_row = 16'h0FFD; // 周
            9'h114: glyph_row = 16'h0C61; // 周
            9'h115: glyph_row = 16'h0C61; // 周
            9'h116: glyph_row = 16'h0FFF; // 周
            9'h117: glyph_row = 16'h0C01; // 周
            9'h118: glyph_row = 16'h0FFD; // 周
            9'h119: glyph_row = 16'h1D9D; // 周
            9'h11A: glyph_row = 16'h1D9D; // 周
            9'h11B: glyph_row = 16'h1BFD; // 周
            9'h11C: glyph_row = 16'h3801; // 周
            9'h11D: glyph_row = 16'h380F; // 周
            9'h11E: glyph_row = 16'h000E; // 周
            9'h121: glyph_row = 16'h1FFF; // 三
            9'h126: glyph_row = 16'h0FFE; // 三
            9'h12C: glyph_row = 16'h3FFF; // 三
            9'h12D: glyph_row = 16'h3000; // 三
            9'h130: glyph_row = 16'h0180; // 多
            9'h131: glyph_row = 16'h03FE; // 多
            9'h132: glyph_row = 16'h0E0E; // 多
            9'h133: glyph_row = 16'h1D9C; // 多
            9'h134: glyph_row = 16'h00F8; // 多
            9'h135: glyph_row = 16'h00F0; // 多
            9'h136: glyph_row = 16'h07B8; // 多
            9'h137: glyph_row = 16'h1C7F; // 多
            9'h138: glyph_row = 16'h01C1; // 多
            9'h139: glyph_row = 16'h07E3; // 多
            9'h13A: glyph_row = 16'h0637; // 多
            9'h13B: glyph_row = 16'h001E; // 多
            9'h13C: glyph_row = 16'h0078; // 多
            9'h13D: glyph_row = 16'h1FE0; // 多
            9'h13E: glyph_row = 16'h1E00; // 多
            9'h140: glyph_row = 16'h0FFF; // 云
            9'h141: glyph_row = 16'h0FFF; // 云
            9'h145: glyph_row = 16'h3FFF; // 云
            9'h146: glyph_row = 16'h00C0; // 云
            9'h147: glyph_row = 16'h01C0; // 云
            9'h148: glyph_row = 16'h0180; // 云
            9'h149: glyph_row = 16'h039C; // 云
            9'h14A: glyph_row = 16'h070E; // 云
            9'h14B: glyph_row = 16'h0607; // 云
            9'h14C: glyph_row = 16'h1FFF; // 云
            9'h14D: glyph_row = 16'h0F01; // 云
            9'h150: glyph_row = 16'h1FFF; // 四
            9'h151: glyph_row = 16'h19F9; // 四
            9'h152: glyph_row = 16'h19F9; // 四
            9'h153: glyph_row = 16'h19B9; // 四
            9'h154: glyph_row = 16'h19B9; // 四
            9'h155: glyph_row = 16'h19B9; // 四
            9'h156: glyph_row = 16'h1BB9; // 四
            9'h157: glyph_row = 16'h1B39; // 四
            9'h158: glyph_row = 16'h1F1F; // 四
            9'h159: glyph_row = 16'h1E01; // 四
            9'h15A: glyph_row = 16'h1801; // 四
            9'h15B: glyph_row = 16'h1801; // 四
            9'h15C: glyph_row = 16'h1FFF; // 四
            9'h15D: glyph_row = 16'h1801; // 四
            9'h160: glyph_row = 16'h00E0; // 今
            9'h161: glyph_row = 16'h00F0;
            9'h162: glyph_row = 16'h0198;
            9'h163: glyph_row = 16'h039C;
            9'h164: glyph_row = 16'h07CE;
            9'h165: glyph_row = 16'h0EE7;
            9'h166: glyph_row = 16'h3871;
            9'h168: glyph_row = 16'h07FF;
            9'h169: glyph_row = 16'h0006;
            9'h16A: glyph_row = 16'h000E;
            9'h16B: glyph_row = 16'h001C;
            9'h16C: glyph_row = 16'h0038;
            9'h16D: glyph_row = 16'h0030;
            9'h16E: glyph_row = 16'h0030;
            default: glyph_row = 16'h0000;
        endcase
    end
endfunction

endmodule
