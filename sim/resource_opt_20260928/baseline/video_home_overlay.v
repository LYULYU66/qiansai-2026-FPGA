// Picture-1-only car dashboard. All text is a tiny combinational 16x16 ROM;
// the background is the decoded TF-card image. No frame store, DSP, or BRAM.
module video_home_overlay_baseline_ref #(
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
wire [31:0] row_coverage = glyph_row_coverage(glyph_id, glyph_y);
wire [1:0] glyph_cov = row_coverage[(15-glyph_col)*2 +: 2];
wire glyph_on = text_valid && (glyph_cov != 2'd0);
wire heading_text = (card_id == 2'd2) ? (pixel_y < 10'd346) :
                    (pixel_y < 10'd354);
wire [23:0] glyph_color = forecast_text ?
    ((glyph_cov == 2'd3) ? 24'hD5E4EF :
     (glyph_cov == 2'd2) ? 24'h9FB9C9 : 24'h66899C) :
    heading_text ?
    ((glyph_cov == 2'd3) ? 24'hAAECFA :
     (glyph_cov == 2'd2) ? 24'h75B7CA : 24'h487D91) :
    ((glyph_cov == 2'd3) ? 24'hF6FAFC :
     (glyph_cov == 2'd2) ? 24'hB9CDD8 : 24'h6E91A3);

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
    glyph_on ? glyph_color :
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

// Noto Sans SC Medium, 16x16, two-bit antialias coverage.
// Generated from the same font source for all on-screen labels.
function [31:0] glyph_row_coverage;
    input [4:0] glyph;
    input [3:0] row;
    begin
        case ({glyph,row})
            9'h002: glyph_row_coverage = 32'h01555540; // 目
            9'h003: glyph_row_coverage = 32'h07FFFFD0; // 目
            9'h004: glyph_row_coverage = 32'h074001D0; // 目
            9'h005: glyph_row_coverage = 32'h074001D0; // 目
            9'h006: glyph_row_coverage = 32'h07FFFFD0; // 目
            9'h007: glyph_row_coverage = 32'h07AAAAD0; // 目
            9'h008: glyph_row_coverage = 32'h070001C0; // 目
            9'h009: glyph_row_coverage = 32'h079556D0; // 目
            9'h00A: glyph_row_coverage = 32'h07FFFFD0; // 目
            9'h00B: glyph_row_coverage = 32'h074412D0; // 目
            9'h00C: glyph_row_coverage = 32'h074001D0; // 目
            9'h00D: glyph_row_coverage = 32'h07FFFFD0; // 目
            9'h00E: glyph_row_coverage = 32'h07AAAAD0; // 目
            9'h00F: glyph_row_coverage = 32'h06000180; // 目
            9'h011: glyph_row_coverage = 32'h00401000; // 的
            9'h012: glyph_row_coverage = 32'h01D03800; // 的
            9'h013: glyph_row_coverage = 32'h01C07400; // 的
            9'h014: glyph_row_coverage = 32'h1BE8BFE4; // 的
            9'h015: glyph_row_coverage = 32'h1EADEAB8; // 的
            9'h016: glyph_row_coverage = 32'h1C1EC034; // 的
            9'h017: glyph_row_coverage = 32'h1C1E9034; // 的
            9'h018: glyph_row_coverage = 32'h1EBC3834; // 的
            9'h019: glyph_row_coverage = 32'h1EAD2D34; // 的
            9'h01A: glyph_row_coverage = 32'h1C0D0E34; // 的
            9'h01B: glyph_row_coverage = 32'h1C1D0574; // 的
            9'h01C: glyph_row_coverage = 32'h1D1D0070; // 的
            9'h01D: glyph_row_coverage = 32'h1FFD00B0; // 的
            9'h01E: glyph_row_coverage = 32'h1D541EE0; // 的
            9'h01F: glyph_row_coverage = 32'h04000A80; // 的
            9'h021: glyph_row_coverage = 32'h00000400; // 地
            9'h022: glyph_row_coverage = 32'h03401D00; // 地
            9'h023: glyph_row_coverage = 32'h03424D00; // 地
            9'h024: glyph_row_coverage = 32'h03474D20; // 地
            9'h025: glyph_row_coverage = 32'h2BA74EF4; // 地
            9'h026: glyph_row_coverage = 32'h2FE3AFB4; // 地
            9'h027: glyph_row_coverage = 32'h034BED34; // 地
            9'h028: glyph_row_coverage = 32'h035F4D34; // 地
            9'h029: glyph_row_coverage = 32'h03474D34; // 地
            9'h02A: glyph_row_coverage = 32'h03A74DB4; // 地
            9'h02B: glyph_row_coverage = 32'h1BE74D90; // 地
            9'h02C: glyph_row_coverage = 32'h3E474418; // 地
            9'h02D: glyph_row_coverage = 32'h1407402C; // 地
            9'h02E: glyph_row_coverage = 32'h0003EEB8; // 地
            9'h02F: glyph_row_coverage = 32'h0001AA90; // 地
            9'h031: glyph_row_coverage = 32'h00014000; // 青
            9'h032: glyph_row_coverage = 32'h0557D550; // 青
            9'h033: glyph_row_coverage = 32'h0AABEAA0; // 青
            9'h034: glyph_row_coverage = 32'h01579540; // 青
            9'h035: glyph_row_coverage = 32'h02ABEA80; // 青
            9'h036: glyph_row_coverage = 32'h1557D554; // 青
            9'h037: glyph_row_coverage = 32'h1AAAAAA4; // 青
            9'h038: glyph_row_coverage = 32'h01AAAA40; // 青
            9'h039: glyph_row_coverage = 32'h02EAAB80; // 青
            9'h03A: glyph_row_coverage = 32'h02EAAB80; // 青
            9'h03B: glyph_row_coverage = 32'h02EAAB80; // 青
            9'h03C: glyph_row_coverage = 32'h02EAAB80; // 青
            9'h03D: glyph_row_coverage = 32'h02D55780; // 青
            9'h03E: glyph_row_coverage = 32'h02C01780; // 青
            9'h03F: glyph_row_coverage = 32'h02802E40; // 青
            9'h041: glyph_row_coverage = 32'h00014000; // 岛
            9'h042: glyph_row_coverage = 32'h00074000; // 岛
            9'h043: glyph_row_coverage = 32'h02FFFF80; // 岛
            9'h044: glyph_row_coverage = 32'h03955780; // 岛
            9'h045: glyph_row_coverage = 32'h039E0380; // 岛
            9'h046: glyph_row_coverage = 32'h0387DB40; // 岛
            9'h047: glyph_row_coverage = 32'h03801A00; // 岛
            9'h048: glyph_row_coverage = 32'h03EAAAA4; // 岛
            9'h049: glyph_row_coverage = 32'h01AAAAB4; // 岛
            9'h04A: glyph_row_coverage = 32'h04181434; // 岛
            9'h04B: glyph_row_coverage = 32'h0E1C2C74; // 岛
            9'h04C: glyph_row_coverage = 32'h0D1C2870; // 岛
            9'h04D: glyph_row_coverage = 32'h0FBFB8B0; // 岛
            9'h04E: glyph_row_coverage = 32'h0696AEE0; // 岛
            9'h04F: glyph_row_coverage = 32'h00000B90; // 岛
            9'h051: glyph_row_coverage = 32'h00014000; // 音
            9'h052: glyph_row_coverage = 32'h0003C000; // 音
            9'h053: glyph_row_coverage = 32'h0BFFFFF0; // 音
            9'h054: glyph_row_coverage = 32'h05A55B50; // 音
            9'h055: glyph_row_coverage = 32'h00700E00; // 音
            9'h056: glyph_row_coverage = 32'h1ABAAEA4; // 音
            9'h057: glyph_row_coverage = 32'h2EAAAAB8; // 音
            9'h059: glyph_row_coverage = 32'h02FFFF80; // 音
            9'h05A: glyph_row_coverage = 32'h028002C0; // 音
            9'h05B: glyph_row_coverage = 32'h02EAABC0; // 音
            9'h05C: glyph_row_coverage = 32'h02EAABC0; // 音
            9'h05D: glyph_row_coverage = 32'h028002C0; // 音
            9'h05E: glyph_row_coverage = 32'h02FFFFC0; // 音
            9'h05F: glyph_row_coverage = 32'h02955680; // 音
            9'h062: glyph_row_coverage = 32'h0156ABD0; // 乐
            9'h063: glyph_row_coverage = 32'h03FFAA50; // 乐
            9'h064: glyph_row_coverage = 32'h03404000; // 乐
            9'h065: glyph_row_coverage = 32'h0742C000; // 乐
            9'h066: glyph_row_coverage = 32'h0701C000; // 乐
            9'h067: glyph_row_coverage = 32'h0B56D550; // 乐
            9'h068: glyph_row_coverage = 32'h0BFFFFF4; // 乐
            9'h069: glyph_row_coverage = 32'h0516D450; // 乐
            9'h06A: glyph_row_coverage = 32'h0181C240; // 乐
            9'h06B: glyph_row_coverage = 32'h03C1C2C0; // 乐
            9'h06C: glyph_row_coverage = 32'h0B41C0E0; // 乐
            9'h06D: glyph_row_coverage = 32'h2D01C078; // 乐
            9'h06E: glyph_row_coverage = 32'h182BC014; // 乐
            9'h06F: glyph_row_coverage = 32'h001A4000; // 乐
            9'h071: glyph_row_coverage = 32'h00004000; // 告
            9'h072: glyph_row_coverage = 32'h01D1C000; // 告
            9'h073: glyph_row_coverage = 32'h02D6D550; // 告
            9'h074: glyph_row_coverage = 32'h07FFFFE0; // 告
            9'h075: glyph_row_coverage = 32'h0F02D000; // 告
            9'h076: glyph_row_coverage = 32'h0901C000; // 告
            9'h077: glyph_row_coverage = 32'h1AFFFFB8; // 告
            9'h078: glyph_row_coverage = 32'h1AAAAAA4; // 告
            9'h07A: glyph_row_coverage = 32'h02FFFFC0; // 告
            9'h07B: glyph_row_coverage = 32'h029556C0; // 告
            9'h07C: glyph_row_coverage = 32'h028002C0; // 告
            9'h07D: glyph_row_coverage = 32'h029556C0; // 告
            9'h07E: glyph_row_coverage = 32'h02FFFFC0; // 告
            9'h07F: glyph_row_coverage = 32'h028002C0; // 告
            9'h081: glyph_row_coverage = 32'h00010000; // 白
            9'h082: glyph_row_coverage = 32'h00078000; // 白
            9'h083: glyph_row_coverage = 32'h000B4000; // 白
            9'h084: glyph_row_coverage = 32'h07FFFFD0; // 白
            9'h085: glyph_row_coverage = 32'h0BAAAAE0; // 白
            9'h086: glyph_row_coverage = 32'h0B0000E0; // 白
            9'h087: glyph_row_coverage = 32'h0B0000E0; // 白
            9'h088: glyph_row_coverage = 32'h075555E0; // 白
            9'h089: glyph_row_coverage = 32'h07FFFFE0; // 白
            9'h08A: glyph_row_coverage = 32'h0B0000E0; // 白
            9'h08B: glyph_row_coverage = 32'h0B0000E0; // 白
            9'h08C: glyph_row_coverage = 32'h0B0000E0; // 白
            9'h08D: glyph_row_coverage = 32'h07AAAAE0; // 白
            9'h08E: glyph_row_coverage = 32'h0BAAAAE0; // 白
            9'h08F: glyph_row_coverage = 32'h06000090; // 白
            9'h091: glyph_row_coverage = 32'h00400000; // 气
            9'h092: glyph_row_coverage = 32'h00D00000; // 气
            9'h093: glyph_row_coverage = 32'h02FAAAA4; // 气
            9'h094: glyph_row_coverage = 32'h03AAAAA4; // 气
            9'h095: glyph_row_coverage = 32'h0B6AAA80; // 气
            9'h096: glyph_row_coverage = 32'h2D6AAA90; // 气
            9'h097: glyph_row_coverage = 32'h29555500; // 气
            9'h098: glyph_row_coverage = 32'h07FFFF40; // 气
            9'h099: glyph_row_coverage = 32'h00000740; // 气
            9'h09A: glyph_row_coverage = 32'h00000740; // 气
            9'h09B: glyph_row_coverage = 32'h00000340; // 气
            9'h09C: glyph_row_coverage = 32'h00000384; // 气
            9'h09D: glyph_row_coverage = 32'h00000288; // 气
            9'h09E: glyph_row_coverage = 32'h000001F8; // 气
            9'h09F: glyph_row_coverage = 32'h00000064; // 气
            9'h0A1: glyph_row_coverage = 32'h00000400; // 球
            9'h0A2: glyph_row_coverage = 32'h15501DD0; // 球
            9'h0A3: glyph_row_coverage = 32'h2FE01C70; // 球
            9'h0A4: glyph_row_coverage = 32'h074BBFB8; // 球
            9'h0A5: glyph_row_coverage = 32'h034AAEA8; // 球
            9'h0A6: glyph_row_coverage = 32'h07451C14; // 球
            9'h0A7: glyph_row_coverage = 32'h2FE75D74; // 球
            9'h0A8: glyph_row_coverage = 32'h17929EE0; // 球
            9'h0A9: glyph_row_coverage = 32'h03416F80; // 球
            9'h0AA: glyph_row_coverage = 32'h0740BF40; // 球
            9'h0AB: glyph_row_coverage = 32'h0352EEC0; // 球
            9'h0AC: glyph_row_coverage = 32'h1BFF5CF0; // 球
            9'h0AD: glyph_row_coverage = 32'h3E5D1C38; // 球
            9'h0AE: glyph_row_coverage = 32'h0000AC14; // 球
            9'h0AF: glyph_row_coverage = 32'h0000A400; // 球
            9'h0B1: glyph_row_coverage = 32'h00010000; // 市
            9'h0B2: glyph_row_coverage = 32'h00078000; // 市
            9'h0B3: glyph_row_coverage = 32'h0556D550; // 市
            9'h0B4: glyph_row_coverage = 32'h2FFFFFF8; // 市
            9'h0B5: glyph_row_coverage = 32'h15579554; // 市
            9'h0B6: glyph_row_coverage = 32'h00038000; // 市
            9'h0B7: glyph_row_coverage = 32'h07FFFFD0; // 市
            9'h0B8: glyph_row_coverage = 32'h07ABEAE0; // 市
            9'h0B9: glyph_row_coverage = 32'h070280E0; // 市
            9'h0BA: glyph_row_coverage = 32'h070380E0; // 市
            9'h0BB: glyph_row_coverage = 32'h070380E0; // 市
            9'h0BC: glyph_row_coverage = 32'h070385E0; // 市
            9'h0BD: glyph_row_coverage = 32'h07038F90; // 市
            9'h0BE: glyph_row_coverage = 32'h00038000; // 市
            9'h0BF: glyph_row_coverage = 32'h00028000; // 市
            9'h0C2: glyph_row_coverage = 32'h05555550; // 天
            9'h0C3: glyph_row_coverage = 32'h0FFFFFF0; // 天
            9'h0C4: glyph_row_coverage = 32'h05579550; // 天
            9'h0C5: glyph_row_coverage = 32'h00038000; // 天
            9'h0C6: glyph_row_coverage = 32'h00038000; // 天
            9'h0C7: glyph_row_coverage = 32'h1AABAAA4; // 天
            9'h0C8: glyph_row_coverage = 32'h1FFFFFF8; // 天
            9'h0C9: glyph_row_coverage = 32'h0007D000; // 天
            9'h0CA: glyph_row_coverage = 32'h000FA000; // 天
            9'h0CB: glyph_row_coverage = 32'h002D7800; // 天
            9'h0CC: glyph_row_coverage = 32'h00B82E00; // 天
            9'h0CD: glyph_row_coverage = 32'h06E00B90; // 天
            9'h0CE: glyph_row_coverage = 32'h2F4001F8; // 天
            9'h0CF: glyph_row_coverage = 32'h18000024; // 天
            9'h0D1: glyph_row_coverage = 32'h00000400; // 晴
            9'h0D2: glyph_row_coverage = 32'h05401D00; // 晴
            9'h0D3: glyph_row_coverage = 32'h1FE7BFB8; // 晴
            9'h0D4: glyph_row_coverage = 32'h1CA16E54; // 晴
            9'h0D5: glyph_row_coverage = 32'h1CA2AEA4; // 晴
            9'h0D6: glyph_row_coverage = 32'h1CA56E54; // 晴
            9'h0D7: glyph_row_coverage = 32'h1EEAAAA8; // 晴
            9'h0D8: glyph_row_coverage = 32'h1EE1AAA0; // 晴
            9'h0D9: glyph_row_coverage = 32'h1CA3AAB0; // 晴
            9'h0DA: glyph_row_coverage = 32'h1CA3AAB0; // 晴
            9'h0DB: glyph_row_coverage = 32'h1EE3AAB0; // 晴
            9'h0DC: glyph_row_coverage = 32'h1E93EAB0; // 晴
            9'h0DD: glyph_row_coverage = 32'h180395B0; // 晴
            9'h0DE: glyph_row_coverage = 32'h000381B0; // 晴
            9'h0DF: glyph_row_coverage = 32'h000242E0; // 晴
            9'h0E3: glyph_row_coverage = 32'h001A9000; // 2
            9'h0E4: glyph_row_coverage = 32'h007EF400; // 2
            9'h0E5: glyph_row_coverage = 32'h00603C00; // 2
            9'h0E6: glyph_row_coverage = 32'h00002C00; // 2
            9'h0E7: glyph_row_coverage = 32'h00002C00; // 2
            9'h0E8: glyph_row_coverage = 32'h00007800; // 2
            9'h0E9: glyph_row_coverage = 32'h0000B000; // 2
            9'h0EA: glyph_row_coverage = 32'h0002D000; // 2
            9'h0EB: glyph_row_coverage = 32'h000B8000; // 2
            9'h0EC: glyph_row_coverage = 32'h002E0000; // 2
            9'h0ED: glyph_row_coverage = 32'h00BFFE00; // 2
            9'h0EE: glyph_row_coverage = 32'h006AA900; // 2
            9'h0F3: glyph_row_coverage = 32'h000A9000; // 9
            9'h0F4: glyph_row_coverage = 32'h002EF400; // 9
            9'h0F5: glyph_row_coverage = 32'h00742C00; // 9
            9'h0F6: glyph_row_coverage = 32'h00B01D00; // 9
            9'h0F7: glyph_row_coverage = 32'h00B01D00; // 9
            9'h0F8: glyph_row_coverage = 32'h00742E00; // 9
            9'h0F9: glyph_row_coverage = 32'h002FEE00; // 9
            9'h0FA: glyph_row_coverage = 32'h00065D00; // 9
            9'h0FB: glyph_row_coverage = 32'h00002D00; // 9
            9'h0FC: glyph_row_coverage = 32'h00107800; // 9
            9'h0FD: glyph_row_coverage = 32'h007EF400; // 9
            9'h0FE: glyph_row_coverage = 32'h001A8000; // 9
            9'h102: glyph_row_coverage = 32'h01000000; // ℃
            9'h103: glyph_row_coverage = 32'h1E801A90; // ℃
            9'h104: glyph_row_coverage = 32'h34A0BEF8; // ℃
            9'h105: glyph_row_coverage = 32'h34A2E014; // ℃
            9'h106: glyph_row_coverage = 32'h2ED3C000; // ℃
            9'h107: glyph_row_coverage = 32'h06478000; // ℃
            9'h108: glyph_row_coverage = 32'h00078000; // ℃
            9'h109: glyph_row_coverage = 32'h00078000; // ℃
            9'h10A: glyph_row_coverage = 32'h00078000; // ℃
            9'h10B: glyph_row_coverage = 32'h0003C000; // ℃
            9'h10C: glyph_row_coverage = 32'h0002E028; // ℃
            9'h10D: glyph_row_coverage = 32'h0000BFF8; // ℃
            9'h10E: glyph_row_coverage = 32'h00001A90; // ℃
            9'h112: glyph_row_coverage = 32'h06AAAA90; // 周
            9'h113: glyph_row_coverage = 32'h07FFFFF0; // 周
            9'h114: glyph_row_coverage = 32'h070280B0; // 周
            9'h115: glyph_row_coverage = 32'h076FEDB0; // 周
            9'h116: glyph_row_coverage = 32'h0716D4B0; // 周
            9'h117: glyph_row_coverage = 32'h0757D5B0; // 周
            9'h118: glyph_row_coverage = 32'h076AAAB0; // 周
            9'h119: glyph_row_coverage = 32'h0B0000B0; // 周
            9'h11A: glyph_row_coverage = 32'h0B2FFCB0; // 周
            9'h11B: glyph_row_coverage = 32'h0A381CB0; // 周
            9'h11C: glyph_row_coverage = 32'h0E296CB0; // 周
            9'h11D: glyph_row_coverage = 32'h1D3FF8B0; // 周
            9'h11E: glyph_row_coverage = 32'h2C240AE0; // 周
            9'h11F: glyph_row_coverage = 32'h14000B90; // 周
            9'h123: glyph_row_coverage = 32'h0AAAAAA0; // 三
            9'h124: glyph_row_coverage = 32'h0AAAAAA0; // 三
            9'h128: glyph_row_coverage = 32'h02FFFF80; // 三
            9'h129: glyph_row_coverage = 32'h01AAAA40; // 三
            9'h12D: glyph_row_coverage = 32'h1AAAAAA4; // 三
            9'h12E: glyph_row_coverage = 32'h1AAAAAA4; // 三
            9'h131: glyph_row_coverage = 32'h00010000; // 多
            9'h132: glyph_row_coverage = 32'h000B4000; // 多
            9'h133: glyph_row_coverage = 32'h002FFF40; // 多
            9'h134: glyph_row_coverage = 32'h01E55F00; // 多
            9'h135: glyph_row_coverage = 32'h0BA42C00; // 多
            9'h136: glyph_row_coverage = 32'h001EE000; // 多
            9'h137: glyph_row_coverage = 32'h006F6800; // 多
            9'h138: glyph_row_coverage = 32'h0BF4BEA4; // 多
            9'h139: glyph_row_coverage = 32'h0A47EAF4; // 多
            9'h13A: glyph_row_coverage = 32'h006E00E0; // 多
            9'h13B: glyph_row_coverage = 32'h01E687C0; // 多
            9'h13C: glyph_row_coverage = 32'h0001FE00; // 多
            9'h13D: glyph_row_coverage = 32'h001AF400; // 多
            9'h13E: glyph_row_coverage = 32'h1BFE4000; // 多
            9'h13F: glyph_row_coverage = 32'h0A900000; // 多
            9'h142: glyph_row_coverage = 32'h01555540; // 云
            9'h143: glyph_row_coverage = 32'h03FFFFD0; // 云
            9'h144: glyph_row_coverage = 32'h01555540; // 云
            9'h147: glyph_row_coverage = 32'h2FFFFFF8; // 云
            9'h148: glyph_row_coverage = 32'h1AAEAAA4; // 云
            9'h149: glyph_row_coverage = 32'h002D0000; // 云
            9'h14A: glyph_row_coverage = 32'h00781E00; // 云
            9'h14B: glyph_row_coverage = 32'h00F00B40; // 云
            9'h14C: glyph_row_coverage = 32'h02C007C0; // 云
            9'h14D: glyph_row_coverage = 32'h0BEFFFE0; // 云
            9'h14E: glyph_row_coverage = 32'h0BEA95B4; // 云
            9'h14F: glyph_row_coverage = 32'h00000060; // 云
            9'h153: glyph_row_coverage = 32'h1FFFFFF4; // 四
            9'h154: glyph_row_coverage = 32'h1E6DB9B4; // 四
            9'h155: glyph_row_coverage = 32'h1D1C3474; // 四
            9'h156: glyph_row_coverage = 32'h1D2C7474; // 四
            9'h157: glyph_row_coverage = 32'h1D2C7474; // 四
            9'h158: glyph_row_coverage = 32'h1D387074; // 四
            9'h159: glyph_row_coverage = 32'h1D747AB4; // 四
            9'h15A: glyph_row_coverage = 32'h1EE02AF4; // 四
            9'h15B: glyph_row_coverage = 32'h1D800074; // 四
            9'h15C: glyph_row_coverage = 32'h1D5555B4; // 四
            9'h15D: glyph_row_coverage = 32'h1FFFFFF4; // 四
            9'h15E: glyph_row_coverage = 32'h1D100474; // 四
            9'h15F: glyph_row_coverage = 32'h04000010; // 四
            9'h161: glyph_row_coverage = 32'h00004000; // 今
            9'h162: glyph_row_coverage = 32'h0002C000; // 今
            9'h163: glyph_row_coverage = 32'h000BE000; // 今
            9'h164: glyph_row_coverage = 32'h002D7800; // 今
            9'h165: glyph_row_coverage = 32'h01F41F40; // 今
            9'h166: glyph_row_coverage = 32'h1BD742E4; // 今
            9'h167: glyph_row_coverage = 32'h2E02E078; // 今
            9'h168: glyph_row_coverage = 32'h0400A000; // 今
            9'h169: glyph_row_coverage = 32'h03FFFFD0; // 今
            9'h16A: glyph_row_coverage = 32'h02AAAB80; // 今
            9'h16B: glyph_row_coverage = 32'h00000B00; // 今
            9'h16C: glyph_row_coverage = 32'h00002D00; // 今
            9'h16D: glyph_row_coverage = 32'h00007800; // 今
            9'h16E: glyph_row_coverage = 32'h0001E000; // 今
            9'h16F: glyph_row_coverage = 32'h00018000; // 今
            default: glyph_row_coverage = 32'd0;
        endcase
    end
endfunction

endmodule
