module osd_alpha_overlay #(
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

// 下一拍的扫描位置与滚动相位。字模 ROM 为同步读，用下一拍坐标寻址，
// ROM 输出与 pixel_x/pixel_y 恰好对应同一像素。
reg [10:0] next_x;
reg [9:0]  next_y;
reg        next_seen;
reg [10:0] next_phase;
always @(*) begin
    next_x     = pixel_x;
    next_y     = pixel_y;
    next_seen  = active_seen;
    next_phase = scroll_phase;
    if (frame_start) begin
        next_x    = 11'd0;
        next_y    = 10'd0;
        next_seen = 1'b0;

        // 白色横条固定；文字每帧左移一个像素，完全离开左侧后
        // 从右侧画面外重新进入。
        if (scroll_phase >= SCROLL_LAST)
            next_phase = 11'd0;
        else
            next_phase = scroll_phase + 11'd1;
    end else if (I_de) begin
        if (line_start) begin
            next_x = 11'd0;
            if (!active_seen) begin
                next_y    = 10'd0;
                next_seen = 1'b1;
            end else if (pixel_y < V_ACTIVE - 1) begin
                next_y = pixel_y + 10'd1;
            end
        end else if (pixel_x < H_ACTIVE - 1) begin
            next_x = pixel_x + 11'd1;
        end
    end else begin
        next_x = 11'd0;
    end
end

always @(posedge I_clk or posedge I_rst) begin
    if (I_rst) begin
        pixel_x     <= 11'd0;
        pixel_y     <= 10'd0;
        de_d        <= 1'b0;
        vs_d        <= 1'b0;
        active_seen <= 1'b0;
        scroll_phase <= 11'd0;
    end else begin
        de_d         <= I_de;
        vs_d         <= I_vs;
        pixel_x      <= next_x;
        pixel_y      <= next_y;
        active_seen  <= next_seen;
        scroll_phase <= next_phase;
    end
end

wire panel_hit = I_enable && I_de &&
                 (pixel_y >= PANEL_Y) && (pixel_y < PANEL_Y + PANEL_HEIGHT);

// scroll_phase=0 时文字左边缘位于 x=640；随后逐帧向左移动。
// 用 x+scroll_phase 判定可见部分，避免带符号坐标和乘法器。
// 以下文字几何均按下一拍坐标计算，结果打一拍后与 ROM 输出对齐。
wire [10:0] scroll_sum    = next_x + next_phase;
wire [10:0] text_rel_x    = scroll_sum - H_ACTIVE;
wire [9:0]  text_rel_y    = next_y - 10'd430;

wire next_text_area = (scroll_sum >= H_ACTIVE) &&
                      (scroll_sum < H_ACTIVE + TEXT_WIDTH) &&
                      (next_y >= 10'd430) && (next_y < 10'd446);

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

// 文字区完全位于字幕条内，因此当前拍只需再与 panel_hit 相与。
// ROM 按 {字, 行, 列} 寻址并直接输出该像素的 2 位覆盖度。
reg text_area_hit_q;
reg glyph_gap_q;       // 每字 20 像素中后 4 列为字间距
always @(posedge I_clk or posedge I_rst) begin
    if (I_rst) begin
        text_area_hit_q <= 1'b0;
        glyph_gap_q     <= 1'b0;
    end else begin
        text_area_hit_q <= next_text_area;
        glyph_gap_q     <= small_glyph_col[4];
    end
end

wire [1:0] glyph_cov;
osd_glyph_rom u_glyph_rom (
    .I_clk(I_clk),
    .I_addr({small_char_index, text_rel_y[3:0], small_glyph_col[3:0]}),
    .O_cov(glyph_cov)
);
wire glyph_on = panel_hit && text_area_hit_q && !glyph_gap_q &&
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

endmodule

// Noto Sans SC Medium, 16x16, two-bit antialias coverage.
// Generated from the same font source for all on-screen labels.
module osd_glyph_rom (
    input  wire        I_clk,
    input  wire [11:0] I_addr,   // {glyph, row, column}
    output reg  [1:0]  O_cov
);
reg [1:0] rom [0:4095];
integer i;
// Rows are kept in the original 16-column, 2-bit-per-pixel notation.
task set_row;
    input [7:0]  row_addr;
    input [31:0] coverage;
    integer c;
    begin
        for (c = 0; c < 16; c = c + 1)
            rom[{row_addr, c[3:0]}] = coverage[(15-c)*2 +: 2];
    end
endtask
initial begin
    for (i = 0; i < 4096; i = i + 1) rom[i] = 2'd0;
    set_row(8'h003, 32'h001AA900); // F
    set_row(8'h004, 32'h003FFE00); // F
    set_row(8'h005, 32'h002C0000); // F
    set_row(8'h006, 32'h002C0000); // F
    set_row(8'h007, 32'h002C0000); // F
    set_row(8'h008, 32'h002EA800); // F
    set_row(8'h009, 32'h002EA800); // F
    set_row(8'h00A, 32'h002C0000); // F
    set_row(8'h00B, 32'h002C0000); // F
    set_row(8'h00C, 32'h002C0000); // F
    set_row(8'h00D, 32'h003C0000); // F
    set_row(8'h00E, 32'h00180000); // F
    set_row(8'h013, 32'h006A9000); // P
    set_row(8'h014, 32'h00BFFD00); // P
    set_row(8'h015, 32'h00B41E00); // P
    set_row(8'h016, 32'h00B40B00); // P
    set_row(8'h017, 32'h00B40B00); // P
    set_row(8'h018, 32'h00B42E00); // P
    set_row(8'h019, 32'h00BFF800); // P
    set_row(8'h01A, 32'h00B95000); // P
    set_row(8'h01B, 32'h00B40000); // P
    set_row(8'h01C, 32'h00B40000); // P
    set_row(8'h01D, 32'h00B40000); // P
    set_row(8'h01E, 32'h00600000); // P
    set_row(8'h023, 32'h0006A400); // G
    set_row(8'h024, 32'h002FFE00); // G
    set_row(8'h025, 32'h00780500); // G
    set_row(8'h026, 32'h00F00000); // G
    set_row(8'h027, 32'h01E00000); // G
    set_row(8'h028, 32'h01D06500); // G
    set_row(8'h029, 32'h01D0BF40); // G
    set_row(8'h02A, 32'h01E00740); // G
    set_row(8'h02B, 32'h00F00740); // G
    set_row(8'h02C, 32'h00B80B40); // G
    set_row(8'h02D, 32'h002FFF40); // G
    set_row(8'h02E, 32'h0006A400); // G
    set_row(8'h033, 32'h00028000); // A
    set_row(8'h034, 32'h0007D000); // A
    set_row(8'h035, 32'h000AE000); // A
    set_row(8'h036, 32'h000DB000); // A
    set_row(8'h037, 32'h001C7400); // A
    set_row(8'h038, 32'h002C3800); // A
    set_row(8'h039, 32'h00382C00); // A
    set_row(8'h03A, 32'h007FFD00); // A
    set_row(8'h03B, 32'h00B56E00); // A
    set_row(8'h03C, 32'h00E00F00); // A
    set_row(8'h03D, 32'h02D00B40); // A
    set_row(8'h03E, 32'h01800640); // A
    set_row(8'h041, 32'h00100000); // 创
    set_row(8'h042, 32'h00740074); // 创
    set_row(8'h043, 32'h00B80974); // 创
    set_row(8'h044, 32'h02DE0D74); // 创
    set_row(8'h045, 32'h07878D74); // 创
    set_row(8'h046, 32'h1E01DD74); // 创
    set_row(8'h047, 32'h2EBA9D74); // 创
    set_row(8'h048, 32'h07AB4D74); // 创
    set_row(8'h049, 32'h07070D74); // 创
    set_row(8'h04A, 32'h07070D74); // 创
    set_row(8'h04B, 32'h076E0D74); // 创
    set_row(8'h04C, 32'h07144074); // 创
    set_row(8'h04D, 32'h0700D074); // 创
    set_row(8'h04E, 32'h07ABC6B4); // 创
    set_row(8'h04F, 32'h01AA47A0); // 创
    set_row(8'h051, 32'h00400000); // 新
    set_row(8'h052, 32'h00D005A0); // 新
    set_row(8'h053, 32'h1AFA7F90); // 新
    set_row(8'h054, 32'h1AAE7400); // 新
    set_row(8'h055, 32'h061C7000); // 新
    set_row(8'h056, 32'h1B6D7554); // 新
    set_row(8'h057, 32'h2FFFBFF8); // 新
    set_row(8'h058, 32'h00D075D0); // 新
    set_row(8'h059, 32'h2AFA70D0); // 新
    set_row(8'h05A, 32'h1AEA70D0); // 新
    set_row(8'h05B, 32'h09A870D0); // 新
    set_row(8'h05C, 32'h1DDAA0D0); // 新
    set_row(8'h05D, 32'h28E2E0D0); // 新
    set_row(8'h05E, 32'h02D1C0D0); // 新
    set_row(8'h05F, 32'h01404090); // 新
    set_row(8'h062, 32'h0601AA80); // 设
    set_row(8'h063, 32'h0781EB80); // 设
    set_row(8'h064, 32'h01D1C280); // 设
    set_row(8'h065, 32'h0002C280); // 设
    set_row(8'h066, 32'h1A4B42E8); // 设
    set_row(8'h067, 32'h2F8D0064); // 设
    set_row(8'h068, 32'h038AAA90); // 设
    set_row(8'h069, 32'h038BFEF0); // 设
    set_row(8'h06A, 32'h038381D0); // 设
    set_row(8'h06B, 32'h0381D380); // 设
    set_row(8'h06C, 32'h03B4BE00); // 设
    set_row(8'h06D, 32'h03E1BE40); // 设
    set_row(8'h06E, 32'h075BD7F4); // 设
    set_row(8'h06F, 32'h01190064); // 设
    set_row(8'h071, 32'h00000400); // 计
    set_row(8'h072, 32'h06401D00); // 计
    set_row(8'h073, 32'h07D01D00); // 计
    set_row(8'h074, 32'h00E01D00); // 计
    set_row(8'h075, 32'h00001D00); // 计
    set_row(8'h076, 32'h1A456D54); // 计
    set_row(8'h077, 32'h2FCFFFFC); // 计
    set_row(8'h078, 32'h02C55D54); // 计
    set_row(8'h079, 32'h02C01D00); // 计
    set_row(8'h07A, 32'h02C01D00); // 计
    set_row(8'h07B, 32'h02C41D00); // 计
    set_row(8'h07C, 32'h02EC1D00); // 计
    set_row(8'h07D, 32'h02F41D00); // 计
    set_row(8'h07E, 32'h03801D00); // 计
    set_row(8'h07F, 32'h01001900); // 计
    set_row(8'h081, 32'h00014000); // 竞
    set_row(8'h082, 32'h0557D550); // 竞
    set_row(8'h083, 32'h0FFFFFF0); // 竞
    set_row(8'h084, 32'h00A00A00); // 竞
    set_row(8'h085, 32'h15B55E54); // 竞
    set_row(8'h086, 32'h2FAFFAF8); // 竞
    set_row(8'h087, 32'h016AA940); // 竞
    set_row(8'h088, 32'h02EFFB80); // 竞
    set_row(8'h089, 32'h02800280); // 竞
    set_row(8'h08A, 32'h02EAABC0); // 竞
    set_row(8'h08B, 32'h02BEBA80); // 竞
    set_row(8'h08C, 32'h002C7414); // 竞
    set_row(8'h08D, 32'h00B47428); // 竞
    set_row(8'h08E, 32'h1BD07EB8); // 竞
    set_row(8'h08F, 32'h19001AA0); // 竞
    set_row(8'h091, 32'h00014000); // 赛
    set_row(8'h092, 32'h0557D550); // 赛
    set_row(8'h093, 32'h1EBEBEB8); // 赛
    set_row(8'h094, 32'h1D696978); // 赛
    set_row(8'h095, 32'h06BAAE90); // 赛
    set_row(8'h096, 32'h01BAAE40); // 赛
    set_row(8'h097, 32'h01796D40); // 赛
    set_row(8'h098, 32'h2EFEBFB8); // 赛
    set_row(8'h099, 32'h01E55B90); // 赛
    set_row(8'h09A, 32'h1FFFFFF8); // 赛
    set_row(8'h09B, 32'h19D28754); // 赛
    set_row(8'h09C, 32'h01C38340); // 赛
    set_row(8'h09D, 32'h009E7B40); // 赛
    set_row(8'h09E, 32'h1AB81AE4); // 赛
    set_row(8'h09F, 32'h1A400064); // 赛
end
always @(posedge I_clk) O_cov <= rom[I_addr];
endmodule
