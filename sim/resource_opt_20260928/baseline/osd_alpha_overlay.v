module osd_alpha_overlay_baseline_ref #(
    parameter integer H_ACTIVE = 640,
    parameter integer V_ACTIVE = 480
)(
    input  wire        I_clk,
    input  wire        I_rst,
    input  wire        I_enable,
    input  wire        I_vs,
    input  wire        I_de,
    input  wire [23:0] I_rgb,
    output wire [23:0] O_rgb
);

// 三层合成：原始图像 -> 75% Alpha 白底 -> 93.75% Alpha 黑字。
// 固定系数只需要移位和加法，不使用乘法器或额外 BRAM。
// 字幕条缩到 28 像素高，避免和上方音频可视化争抢画面空间。
localparam [9:0]  PANEL_Y      = 10'd424;
localparam [9:0]  PANEL_HEIGHT = 10'd28;
// 与主页同源的 16x16 Noto Sans SC 字模；每字占 20 像素。
localparam [10:0] TEXT_WIDTH   = 11'd200;
localparam [10:0] SCROLL_LAST  = H_ACTIVE + TEXT_WIDTH - 1;

reg [10:0] pixel_x;
reg [9:0]  pixel_y;
reg        de_d;
reg        vs_d;
reg        active_seen;

reg [10:0] scroll_phase;

wire frame_start = I_vs & ~vs_d;
wire line_start  = I_de & ~de_d;

always @(posedge I_clk or posedge I_rst) begin
    if (I_rst) begin
        pixel_x     <= 11'd0;
        pixel_y     <= 10'd0;
        de_d        <= 1'b0;
        vs_d        <= 1'b0;
        active_seen <= 1'b0;
        scroll_phase <= 11'd0;
    end else begin
        de_d <= I_de;
        vs_d <= I_vs;

        if (frame_start) begin
            pixel_x     <= 11'd0;
            pixel_y     <= 10'd0;
            active_seen <= 1'b0;

            // 白色横条固定；文字每帧左移一个像素，完全离开左侧后
            // 从右侧画面外重新进入。
            if (scroll_phase >= SCROLL_LAST) begin
                scroll_phase <= 11'd0;
            end else begin
                scroll_phase <= scroll_phase + 11'd1;
            end
        end else if (I_de) begin
            if (line_start) begin
                pixel_x <= 11'd0;
                if (!active_seen) begin
                    pixel_y     <= 10'd0;
                    active_seen <= 1'b1;
                end else if (pixel_y < V_ACTIVE - 1) begin
                    pixel_y <= pixel_y + 10'd1;
                end
            end else if (pixel_x < H_ACTIVE - 1) begin
                pixel_x <= pixel_x + 11'd1;
            end
        end else begin
            pixel_x <= 11'd0;
        end
    end
end

wire panel_hit = I_enable && I_de &&
                 (pixel_y >= PANEL_Y) && (pixel_y < PANEL_Y + PANEL_HEIGHT);

// scroll_phase=0 时文字左边缘位于 x=640；随后逐帧向左移动。
// 用 pixel_x+scroll_phase 判定可见部分，避免带符号坐标和乘法器。
wire [10:0] scroll_sum    = pixel_x + scroll_phase;
wire [10:0] text_rel_x    = scroll_sum - H_ACTIVE;
wire [9:0]  text_rel_y    = pixel_y - 10'd430;

wire text_area_hit = panel_hit &&
                     (scroll_sum >= H_ACTIVE) &&
                     (scroll_sum < H_ACTIVE + TEXT_WIDTH) &&
                     (pixel_y >= 10'd430) && (pixel_y < 10'd446);

reg [3:0] small_char_index;
reg [4:0] small_glyph_col;
always @(*) begin
    small_char_index = 4'd0;
    small_glyph_col  = text_rel_x[4:0];
    if (text_rel_x < 11'd20) begin
        small_char_index = 4'd0;
        small_glyph_col  = text_rel_x;
    end else if (text_rel_x < 11'd40) begin
        small_char_index = 4'd1;
        small_glyph_col  = text_rel_x - 11'd20;
    end else if (text_rel_x < 11'd60) begin
        small_char_index = 4'd2;
        small_glyph_col  = text_rel_x - 11'd40;
    end else if (text_rel_x < 11'd80) begin
        small_char_index = 4'd3;
        small_glyph_col  = text_rel_x - 11'd60;
    end else if (text_rel_x < 11'd100) begin
        small_char_index = 4'd4;
        small_glyph_col  = text_rel_x - 11'd80;
    end else if (text_rel_x < 11'd120) begin
        small_char_index = 4'd5;
        small_glyph_col  = text_rel_x - 11'd100;
    end else if (text_rel_x < 11'd140) begin
        small_char_index = 4'd6;
        small_glyph_col  = text_rel_x - 11'd120;
    end else if (text_rel_x < 11'd160) begin
        small_char_index = 4'd7;
        small_glyph_col  = text_rel_x - 11'd140;
    end else if (text_rel_x < 11'd180) begin
        small_char_index = 4'd8;
        small_glyph_col  = text_rel_x - 11'd160;
    end else begin
        small_char_index = 4'd9;
        small_glyph_col  = text_rel_x - 11'd180;
    end
end

wire [31:0] glyph_coverage = glyph_row_coverage(small_char_index, text_rel_y[3:0]);
wire [1:0] glyph_cov = glyph_coverage[(15-small_glyph_col[3:0])*2 +: 2];
wire glyph_on = text_area_hit && (small_glyph_col < 5'd16) &&
                (glyph_cov != 2'd0);

// 白色层：out = 3/4*255 + 1/4*src。
wire [7:0] panel_r = 8'd192 + {2'b00, I_rgb[23:18]};
wire [7:0] panel_g = 8'd192 + {2'b00, I_rgb[15:10]};
wire [7:0] panel_b = 8'd192 + {2'b00, I_rgb[7:2]};

// 黑色文字层：out = 1/16*panel + 15/16*0。
wire [7:0] text_r = {4'b0000, panel_r[7:4]};
wire [7:0] text_g = {4'b0000, panel_g[7:4]};
wire [7:0] text_b = {4'b0000, panel_b[7:4]};

wire [7:0] shade_r = (glyph_cov == 2'd3) ? text_r :
                     (glyph_cov == 2'd2) ? {1'b0,panel_r[7:1]} :
                                            {1'b0,panel_r[7:1]} + {2'b00,panel_r[7:2]};
wire [7:0] shade_g = (glyph_cov == 2'd3) ? text_g :
                     (glyph_cov == 2'd2) ? {1'b0,panel_g[7:1]} :
                                            {1'b0,panel_g[7:1]} + {2'b00,panel_g[7:2]};
wire [7:0] shade_b = (glyph_cov == 2'd3) ? text_b :
                     (glyph_cov == 2'd2) ? {1'b0,panel_b[7:1]} :
                                            {1'b0,panel_b[7:1]} + {2'b00,panel_b[7:2]};
assign O_rgb = glyph_on ? {shade_r, shade_g, shade_b} :
               panel_hit ? {panel_r, panel_g, panel_b} : I_rgb;

// Noto Sans SC Medium, 16x16, two-bit antialias coverage.
// Generated from the same font source for all on-screen labels.
function [31:0] glyph_row_coverage;
    input [3:0] glyph;
    input [3:0] row;
    begin
        case ({glyph,row})
            8'h003: glyph_row_coverage = 32'h001AA900; // F
            8'h004: glyph_row_coverage = 32'h003FFE00; // F
            8'h005: glyph_row_coverage = 32'h002C0000; // F
            8'h006: glyph_row_coverage = 32'h002C0000; // F
            8'h007: glyph_row_coverage = 32'h002C0000; // F
            8'h008: glyph_row_coverage = 32'h002EA800; // F
            8'h009: glyph_row_coverage = 32'h002EA800; // F
            8'h00A: glyph_row_coverage = 32'h002C0000; // F
            8'h00B: glyph_row_coverage = 32'h002C0000; // F
            8'h00C: glyph_row_coverage = 32'h002C0000; // F
            8'h00D: glyph_row_coverage = 32'h003C0000; // F
            8'h00E: glyph_row_coverage = 32'h00180000; // F
            8'h013: glyph_row_coverage = 32'h006A9000; // P
            8'h014: glyph_row_coverage = 32'h00BFFD00; // P
            8'h015: glyph_row_coverage = 32'h00B41E00; // P
            8'h016: glyph_row_coverage = 32'h00B40B00; // P
            8'h017: glyph_row_coverage = 32'h00B40B00; // P
            8'h018: glyph_row_coverage = 32'h00B42E00; // P
            8'h019: glyph_row_coverage = 32'h00BFF800; // P
            8'h01A: glyph_row_coverage = 32'h00B95000; // P
            8'h01B: glyph_row_coverage = 32'h00B40000; // P
            8'h01C: glyph_row_coverage = 32'h00B40000; // P
            8'h01D: glyph_row_coverage = 32'h00B40000; // P
            8'h01E: glyph_row_coverage = 32'h00600000; // P
            8'h023: glyph_row_coverage = 32'h0006A400; // G
            8'h024: glyph_row_coverage = 32'h002FFE00; // G
            8'h025: glyph_row_coverage = 32'h00780500; // G
            8'h026: glyph_row_coverage = 32'h00F00000; // G
            8'h027: glyph_row_coverage = 32'h01E00000; // G
            8'h028: glyph_row_coverage = 32'h01D06500; // G
            8'h029: glyph_row_coverage = 32'h01D0BF40; // G
            8'h02A: glyph_row_coverage = 32'h01E00740; // G
            8'h02B: glyph_row_coverage = 32'h00F00740; // G
            8'h02C: glyph_row_coverage = 32'h00B80B40; // G
            8'h02D: glyph_row_coverage = 32'h002FFF40; // G
            8'h02E: glyph_row_coverage = 32'h0006A400; // G
            8'h033: glyph_row_coverage = 32'h00028000; // A
            8'h034: glyph_row_coverage = 32'h0007D000; // A
            8'h035: glyph_row_coverage = 32'h000AE000; // A
            8'h036: glyph_row_coverage = 32'h000DB000; // A
            8'h037: glyph_row_coverage = 32'h001C7400; // A
            8'h038: glyph_row_coverage = 32'h002C3800; // A
            8'h039: glyph_row_coverage = 32'h00382C00; // A
            8'h03A: glyph_row_coverage = 32'h007FFD00; // A
            8'h03B: glyph_row_coverage = 32'h00B56E00; // A
            8'h03C: glyph_row_coverage = 32'h00E00F00; // A
            8'h03D: glyph_row_coverage = 32'h02D00B40; // A
            8'h03E: glyph_row_coverage = 32'h01800640; // A
            8'h041: glyph_row_coverage = 32'h00100000; // 创
            8'h042: glyph_row_coverage = 32'h00740074; // 创
            8'h043: glyph_row_coverage = 32'h00B80974; // 创
            8'h044: glyph_row_coverage = 32'h02DE0D74; // 创
            8'h045: glyph_row_coverage = 32'h07878D74; // 创
            8'h046: glyph_row_coverage = 32'h1E01DD74; // 创
            8'h047: glyph_row_coverage = 32'h2EBA9D74; // 创
            8'h048: glyph_row_coverage = 32'h07AB4D74; // 创
            8'h049: glyph_row_coverage = 32'h07070D74; // 创
            8'h04A: glyph_row_coverage = 32'h07070D74; // 创
            8'h04B: glyph_row_coverage = 32'h076E0D74; // 创
            8'h04C: glyph_row_coverage = 32'h07144074; // 创
            8'h04D: glyph_row_coverage = 32'h0700D074; // 创
            8'h04E: glyph_row_coverage = 32'h07ABC6B4; // 创
            8'h04F: glyph_row_coverage = 32'h01AA47A0; // 创
            8'h051: glyph_row_coverage = 32'h00400000; // 新
            8'h052: glyph_row_coverage = 32'h00D005A0; // 新
            8'h053: glyph_row_coverage = 32'h1AFA7F90; // 新
            8'h054: glyph_row_coverage = 32'h1AAE7400; // 新
            8'h055: glyph_row_coverage = 32'h061C7000; // 新
            8'h056: glyph_row_coverage = 32'h1B6D7554; // 新
            8'h057: glyph_row_coverage = 32'h2FFFBFF8; // 新
            8'h058: glyph_row_coverage = 32'h00D075D0; // 新
            8'h059: glyph_row_coverage = 32'h2AFA70D0; // 新
            8'h05A: glyph_row_coverage = 32'h1AEA70D0; // 新
            8'h05B: glyph_row_coverage = 32'h09A870D0; // 新
            8'h05C: glyph_row_coverage = 32'h1DDAA0D0; // 新
            8'h05D: glyph_row_coverage = 32'h28E2E0D0; // 新
            8'h05E: glyph_row_coverage = 32'h02D1C0D0; // 新
            8'h05F: glyph_row_coverage = 32'h01404090; // 新
            8'h062: glyph_row_coverage = 32'h0601AA80; // 设
            8'h063: glyph_row_coverage = 32'h0781EB80; // 设
            8'h064: glyph_row_coverage = 32'h01D1C280; // 设
            8'h065: glyph_row_coverage = 32'h0002C280; // 设
            8'h066: glyph_row_coverage = 32'h1A4B42E8; // 设
            8'h067: glyph_row_coverage = 32'h2F8D0064; // 设
            8'h068: glyph_row_coverage = 32'h038AAA90; // 设
            8'h069: glyph_row_coverage = 32'h038BFEF0; // 设
            8'h06A: glyph_row_coverage = 32'h038381D0; // 设
            8'h06B: glyph_row_coverage = 32'h0381D380; // 设
            8'h06C: glyph_row_coverage = 32'h03B4BE00; // 设
            8'h06D: glyph_row_coverage = 32'h03E1BE40; // 设
            8'h06E: glyph_row_coverage = 32'h075BD7F4; // 设
            8'h06F: glyph_row_coverage = 32'h01190064; // 设
            8'h071: glyph_row_coverage = 32'h00000400; // 计
            8'h072: glyph_row_coverage = 32'h06401D00; // 计
            8'h073: glyph_row_coverage = 32'h07D01D00; // 计
            8'h074: glyph_row_coverage = 32'h00E01D00; // 计
            8'h075: glyph_row_coverage = 32'h00001D00; // 计
            8'h076: glyph_row_coverage = 32'h1A456D54; // 计
            8'h077: glyph_row_coverage = 32'h2FCFFFFC; // 计
            8'h078: glyph_row_coverage = 32'h02C55D54; // 计
            8'h079: glyph_row_coverage = 32'h02C01D00; // 计
            8'h07A: glyph_row_coverage = 32'h02C01D00; // 计
            8'h07B: glyph_row_coverage = 32'h02C41D00; // 计
            8'h07C: glyph_row_coverage = 32'h02EC1D00; // 计
            8'h07D: glyph_row_coverage = 32'h02F41D00; // 计
            8'h07E: glyph_row_coverage = 32'h03801D00; // 计
            8'h07F: glyph_row_coverage = 32'h01001900; // 计
            8'h081: glyph_row_coverage = 32'h00014000; // 竞
            8'h082: glyph_row_coverage = 32'h0557D550; // 竞
            8'h083: glyph_row_coverage = 32'h0FFFFFF0; // 竞
            8'h084: glyph_row_coverage = 32'h00A00A00; // 竞
            8'h085: glyph_row_coverage = 32'h15B55E54; // 竞
            8'h086: glyph_row_coverage = 32'h2FAFFAF8; // 竞
            8'h087: glyph_row_coverage = 32'h016AA940; // 竞
            8'h088: glyph_row_coverage = 32'h02EFFB80; // 竞
            8'h089: glyph_row_coverage = 32'h02800280; // 竞
            8'h08A: glyph_row_coverage = 32'h02EAABC0; // 竞
            8'h08B: glyph_row_coverage = 32'h02BEBA80; // 竞
            8'h08C: glyph_row_coverage = 32'h002C7414; // 竞
            8'h08D: glyph_row_coverage = 32'h00B47428; // 竞
            8'h08E: glyph_row_coverage = 32'h1BD07EB8; // 竞
            8'h08F: glyph_row_coverage = 32'h19001AA0; // 竞
            8'h091: glyph_row_coverage = 32'h00014000; // 赛
            8'h092: glyph_row_coverage = 32'h0557D550; // 赛
            8'h093: glyph_row_coverage = 32'h1EBEBEB8; // 赛
            8'h094: glyph_row_coverage = 32'h1D696978; // 赛
            8'h095: glyph_row_coverage = 32'h06BAAE90; // 赛
            8'h096: glyph_row_coverage = 32'h01BAAE40; // 赛
            8'h097: glyph_row_coverage = 32'h01796D40; // 赛
            8'h098: glyph_row_coverage = 32'h2EFEBFB8; // 赛
            8'h099: glyph_row_coverage = 32'h01E55B90; // 赛
            8'h09A: glyph_row_coverage = 32'h1FFFFFF8; // 赛
            8'h09B: glyph_row_coverage = 32'h19D28754; // 赛
            8'h09C: glyph_row_coverage = 32'h01C38340; // 赛
            8'h09D: glyph_row_coverage = 32'h009E7B40; // 赛
            8'h09E: glyph_row_coverage = 32'h1AB81AE4; // 赛
            8'h09F: glyph_row_coverage = 32'h1A400064; // 赛
            default: glyph_row_coverage = 32'd0;
        endcase
    end
endfunction

endmodule
