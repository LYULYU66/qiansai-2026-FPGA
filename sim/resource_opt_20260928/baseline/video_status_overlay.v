// Compact top-left status card for brightness, contrast and UART volume.
// Uses the shared Noto Sans SC font source and shift-based alpha background.
// Control values are synchronized and committed at a frame edge.
module video_status_overlay_baseline_ref #(
    parameter integer H_ACTIVE = 640,
    parameter integer V_ACTIVE = 480
)(
    input  wire        I_clk,
    input  wire        I_rst,
    input  wire        I_enable,
    input  wire        I_vs,
    input  wire        I_de,
    input  wire [23:0] I_rgb,
    input  wire [1:0]  I_brightness_level,
    input  wire [1:0]  I_contrast_level,
    input  wire [3:0]  I_volume_level,
    output wire [23:0] O_rgb
);

localparam [10:0] CARD_LEFT   = 11'd16;
localparam [10:0] CARD_RIGHT  = 11'd212;
localparam [9:0]  CARD_TOP    = 10'd16;
localparam [9:0]  CARD_BOTTOM = 10'd88;
localparam [10:0] TEXT_LEFT   = 11'd28;
localparam [10:0] BAR_LEFT    = 11'd132;
localparam [10:0] BAR_RIGHT   = 11'd196;

reg [10:0] pixel_x;
reg [9:0]  pixel_y;
reg        de_d;
reg        vs_d;
reg        active_seen;

reg [1:0] brightness_meta, brightness_sync, brightness_stable;
reg [1:0] contrast_meta, contrast_sync, contrast_stable;
reg [3:0] volume_meta, volume_sync, volume_stable;
reg [1:0] brightness_frame, contrast_frame;
reg [3:0] volume_frame;

wire frame_start = I_vs & ~vs_d;
wire line_start  = I_de & ~de_d;

always @(posedge I_clk or posedge I_rst) begin
    if (I_rst) begin
        pixel_x           <= 11'd0;
        pixel_y           <= 10'd0;
        de_d              <= 1'b0;
        vs_d              <= 1'b0;
        active_seen       <= 1'b0;
        brightness_meta   <= 2'd3;
        brightness_sync   <= 2'd3;
        brightness_stable <= 2'd3;
        brightness_frame  <= 2'd3;
        contrast_meta     <= 2'd0;
        contrast_sync     <= 2'd0;
        contrast_stable   <= 2'd0;
        contrast_frame    <= 2'd0;
        volume_meta       <= 4'd8;
        volume_sync       <= 4'd8;
        volume_stable     <= 4'd8;
        volume_frame      <= 4'd8;
    end else begin
        de_d <= I_de;
        vs_d <= I_vs;

        brightness_meta <= I_brightness_level;
        brightness_sync <= brightness_meta;
        if (brightness_sync == brightness_meta)
            brightness_stable <= brightness_sync;
        contrast_meta <= I_contrast_level;
        contrast_sync <= contrast_meta;
        if (contrast_sync == contrast_meta)
            contrast_stable <= contrast_sync;
        volume_meta <= I_volume_level;
        volume_sync <= volume_meta;
        if (volume_sync == volume_meta)
            volume_stable <= volume_sync;

        if (frame_start) begin
            pixel_x          <= 11'd0;
            pixel_y          <= 10'd0;
            active_seen      <= 1'b0;
            brightness_frame <= brightness_stable;
            contrast_frame   <= contrast_stable;
            volume_frame     <= (volume_stable > 4'd8) ? 4'd8 : volume_stable;
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

wire card_hit = I_enable && I_de &&
                (pixel_x >= CARD_LEFT) && (pixel_x < CARD_RIGHT) &&
                (pixel_y >= CARD_TOP) && (pixel_y < CARD_BOTTOM);
wire border_hit = card_hit &&
                  ((pixel_x == CARD_LEFT) || (pixel_x == CARD_RIGHT - 1) ||
                   (pixel_y == CARD_TOP) || (pixel_y == CARD_BOTTOM - 1));
wire accent_hit = card_hit && (pixel_x >= CARD_LEFT + 11'd3) &&
                  (pixel_x < CARD_LEFT + 11'd6) &&
                  (pixel_y >= CARD_TOP + 10'd5) &&
                  (pixel_y < CARD_BOTTOM - 10'd5);

reg [1:0] text_line;
reg [9:0] line_top;
reg       text_row_hit;
always @(*) begin
    text_line    = 2'd0;
    line_top     = 10'd25;
    text_row_hit = 1'b0;
    if ((pixel_y >= 10'd25) && (pixel_y < 10'd39)) begin
        text_line = 2'd0; line_top = 10'd25; text_row_hit = 1'b1;
    end else if ((pixel_y >= 10'd47) && (pixel_y < 10'd61)) begin
        text_line = 2'd1; line_top = 10'd47; text_row_hit = 1'b1;
    end else if ((pixel_y >= 10'd69) && (pixel_y < 10'd83)) begin
        text_line = 2'd2; line_top = 10'd69; text_row_hit = 1'b1;
    end
end

wire [10:0] text_rel_x = pixel_x - TEXT_LEFT;
reg  [2:0] char_index;
reg  [3:0] char_cell_x;
always @(*) begin
    char_index  = 3'd0;
    char_cell_x = text_rel_x[3:0];
    if (text_rel_x < 11'd12) begin
        char_index = 3'd0; char_cell_x = text_rel_x;
    end else if (text_rel_x < 11'd24) begin
        char_index = 3'd1; char_cell_x = text_rel_x - 11'd12;
    end else if (text_rel_x < 11'd36) begin
        char_index = 3'd2; char_cell_x = text_rel_x - 11'd24;
    end else if (text_rel_x < 11'd48) begin
        char_index = 3'd3; char_cell_x = text_rel_x - 11'd36;
    end else if (text_rel_x < 11'd60) begin
        char_index = 3'd4; char_cell_x = text_rel_x - 11'd48;
    end else if (text_rel_x < 11'd72) begin
        char_index = 3'd5; char_cell_x = text_rel_x - 11'd60;
    end else begin
        char_index = 3'd6; char_cell_x = text_rel_x - 11'd72;
    end
end

wire [3:0] font_col = char_cell_x;
wire [3:0] font_row_index = pixel_y - line_top;
wire [7:0] current_char = status_char(text_line, char_index,
                                      brightness_frame, contrast_frame,
                                      volume_frame);
wire [19:0] current_font_row = font_row_coverage(current_char, font_row_index);
wire [1:0] text_cov = current_font_row[(9-font_col)*2 +: 2];
wire text_hit = card_hit && text_row_hit &&
                (pixel_x >= TEXT_LEFT) && (pixel_x < TEXT_LEFT + 11'd84) &&
                (char_cell_x < 4'd10) && (text_cov != 2'd0);

reg [6:0] bar_width;
always @(*) begin
    case (text_line)
        2'd0: begin
            case (brightness_frame)
                2'd0: bar_width = 7'd16;
                2'd1: bar_width = 7'd32;
                2'd2: bar_width = 7'd48;
                default: bar_width = 7'd64;
            endcase
        end
        2'd1: begin
            case (contrast_frame)
                2'd0: bar_width = 7'd16;
                2'd1: bar_width = 7'd32;
                2'd2: bar_width = 7'd48;
                default: bar_width = 7'd64;
            endcase
        end
        default: bar_width = {volume_frame, 3'b000};
    endcase
end

wire bar_track = card_hit && text_row_hit &&
                 (pixel_x >= BAR_LEFT) && (pixel_x < BAR_RIGHT) &&
                 (pixel_y >= line_top + 10'd4) &&
                 (pixel_y < line_top + 10'd10);
wire bar_fill = bar_track &&
                (pixel_x < BAR_LEFT + {4'd0, bar_width});

wire [23:0] line_color = (text_line == 2'd0) ? 24'hFFD166 :
                         (text_line == 2'd1) ? 24'h4CC9F0 :
                                               24'h5CFF8A;
wire [7:0] card_r = 8'd10 + {2'b00, I_rgb[23:18]};
wire [7:0] card_g = 8'd18 + {2'b00, I_rgb[15:10]};
wire [7:0] card_b = 8'd28 + {2'b00, I_rgb[7:2]};

wire [23:0] label_color = (text_cov == 2'd3) ? 24'hEEF7FF :
                          (text_cov == 2'd2) ? 24'hB3CAD7 : 24'h718E9F;
wire [23:0] value_color = (text_cov == 2'd3) ? line_color :
                          (text_cov == 2'd2) ? {1'b0,line_color[23:17],1'b0,line_color[15:9],1'b0,line_color[7:1]} :
                                                24'h506F70;
assign O_rgb = text_hit ? ((char_index >= 3'd4) ? value_color : label_color) :
               bar_fill ? line_color :
               border_hit ? 24'h7EE8FF :
               accent_hit ? 24'h21C7E8 :
               bar_track ? 24'h294552 :
               card_hit ? {card_r, card_g, card_b} : I_rgb;

function [7:0] percent_char;
    input [1:0] level;
    input [1:0] digit;
    begin
        case (level)
            2'd0: percent_char = (digit == 2'd0) ? " " :
                                   (digit == 2'd1) ? "2" : "5";
            2'd1: percent_char = (digit == 2'd0) ? " " :
                                   (digit == 2'd1) ? "5" : "0";
            2'd2: percent_char = (digit == 2'd0) ? " " :
                                   (digit == 2'd1) ? "7" : "5";
            default: percent_char = (digit == 2'd0) ? "1" : "0";
        endcase
    end
endfunction

function [7:0] status_char;
    input [1:0] line;
    input [2:0] index;
    input [1:0] brightness;
    input [1:0] contrast;
    input [3:0] volume;
    begin
        status_char = " ";
        case (line)
            2'd0: begin
                case (index)
                    3'd0: status_char = "B";
                    3'd1: status_char = "R";
                    3'd2: status_char = "I";
                    3'd3: status_char = ":";
                    3'd4: status_char = percent_char(brightness, 2'd0);
                    3'd5: status_char = percent_char(brightness, 2'd1);
                    default: status_char = percent_char(brightness, 2'd2);
                endcase
            end
            2'd1: begin
                case (index)
                    3'd0: status_char = "C";
                    3'd1: status_char = "O";
                    3'd2: status_char = "N";
                    3'd3: status_char = ":";
                    3'd4: status_char = percent_char(contrast, 2'd0);
                    3'd5: status_char = percent_char(contrast, 2'd1);
                    default: status_char = percent_char(contrast, 2'd2);
                endcase
            end
            default: begin
                case (index)
                    3'd0: status_char = "V";
                    3'd1: status_char = "O";
                    3'd2: status_char = "L";
                    3'd3: status_char = ":";
                    3'd4: status_char = "0" + volume;
                    default: status_char = " ";
                endcase
            end
        endcase
    end
endfunction

// Noto Sans SC Medium, 10x14, two-bit antialias coverage.
// Generated from the same font source for all on-screen labels.
function [19:0] font_row_coverage;
    input [7:0] character;
    input [3:0] row;
    begin
        case ({character,row})
            12'h423: font_row_coverage = 20'h07F80; // B
            12'h424: font_row_coverage = 20'h075D0; // B
            12'h425: font_row_coverage = 20'h07090; // B
            12'h426: font_row_coverage = 20'h071D0; // B
            12'h427: font_row_coverage = 20'h07F80; // B
            12'h428: font_row_coverage = 20'h075E0; // B
            12'h429: font_row_coverage = 20'h07060; // B
            12'h42A: font_row_coverage = 20'h070A0; // B
            12'h42B: font_row_coverage = 20'h07AD0; // B
            12'h42C: font_row_coverage = 20'h06A40; // B
            12'h523: font_row_coverage = 20'h07F80; // R
            12'h524: font_row_coverage = 20'h075D0; // R
            12'h525: font_row_coverage = 20'h070A0; // R
            12'h526: font_row_coverage = 20'h070A0; // R
            12'h527: font_row_coverage = 20'h076D0; // R
            12'h528: font_row_coverage = 20'h07F80; // R
            12'h529: font_row_coverage = 20'h07240; // R
            12'h52A: font_row_coverage = 20'h071C0; // R
            12'h52B: font_row_coverage = 20'h070D0; // R
            12'h52C: font_row_coverage = 20'h06060; // R
            12'h493: font_row_coverage = 20'h00A00; // I
            12'h494: font_row_coverage = 20'h00A00; // I
            12'h495: font_row_coverage = 20'h00A00; // I
            12'h496: font_row_coverage = 20'h00A00; // I
            12'h497: font_row_coverage = 20'h00A00; // I
            12'h498: font_row_coverage = 20'h00A00; // I
            12'h499: font_row_coverage = 20'h00A00; // I
            12'h49A: font_row_coverage = 20'h00A00; // I
            12'h49B: font_row_coverage = 20'h00A00; // I
            12'h49C: font_row_coverage = 20'h00900; // I
            12'h432: font_row_coverage = 20'h00100; // C
            12'h433: font_row_coverage = 20'h01FD0; // C
            12'h434: font_row_coverage = 20'h03990; // C
            12'h435: font_row_coverage = 20'h07000; // C
            12'h436: font_row_coverage = 20'h0A000; // C
            12'h437: font_row_coverage = 20'h0A000; // C
            12'h438: font_row_coverage = 20'h0A000; // C
            12'h439: font_row_coverage = 20'h0A000; // C
            12'h43A: font_row_coverage = 20'h07000; // C
            12'h43B: font_row_coverage = 20'h02EE0; // C
            12'h43C: font_row_coverage = 20'h00B80; // C
            12'h4F2: font_row_coverage = 20'h00400; // O
            12'h4F3: font_row_coverage = 20'h02F80; // O
            12'h4F4: font_row_coverage = 20'h075D0; // O
            12'h4F5: font_row_coverage = 20'h0E0A0; // O
            12'h4F6: font_row_coverage = 20'h0D070; // O
            12'h4F7: font_row_coverage = 20'h0D070; // O
            12'h4F8: font_row_coverage = 20'h0D070; // O
            12'h4F9: font_row_coverage = 20'h0D070; // O
            12'h4FA: font_row_coverage = 20'h0A0A0; // O
            12'h4FB: font_row_coverage = 20'h07AD0; // O
            12'h4FC: font_row_coverage = 20'h01F40; // O
            12'h4E3: font_row_coverage = 20'h0A0A0; // N
            12'h4E4: font_row_coverage = 20'h0B4A0; // N
            12'h4E5: font_row_coverage = 20'h0B8A0; // N
            12'h4E6: font_row_coverage = 20'h0A8A0; // N
            12'h4E7: font_row_coverage = 20'h0A9A0; // N
            12'h4E8: font_row_coverage = 20'h0A6A0; // N
            12'h4E9: font_row_coverage = 20'h0A2A0; // N
            12'h4EA: font_row_coverage = 20'h0A2E0; // N
            12'h4EB: font_row_coverage = 20'h0A0E0; // N
            12'h4EC: font_row_coverage = 20'h05090; // N
            12'h563: font_row_coverage = 20'h090A0; // V
            12'h564: font_row_coverage = 20'h0A0A0; // V
            12'h565: font_row_coverage = 20'h070D0; // V
            12'h566: font_row_coverage = 20'h030C0; // V
            12'h567: font_row_coverage = 20'h035C0; // V
            12'h568: font_row_coverage = 20'h02580; // V
            12'h569: font_row_coverage = 20'h02A40; // V
            12'h56A: font_row_coverage = 20'h01E40; // V
            12'h56B: font_row_coverage = 20'h00F00; // V
            12'h56C: font_row_coverage = 20'h00A00; // V
            12'h4C3: font_row_coverage = 20'h02400; // L
            12'h4C4: font_row_coverage = 20'h03400; // L
            12'h4C5: font_row_coverage = 20'h02400; // L
            12'h4C6: font_row_coverage = 20'h02400; // L
            12'h4C7: font_row_coverage = 20'h02400; // L
            12'h4C8: font_row_coverage = 20'h02400; // L
            12'h4C9: font_row_coverage = 20'h02400; // L
            12'h4CA: font_row_coverage = 20'h02400; // L
            12'h4CB: font_row_coverage = 20'h02E90; // L
            12'h4CC: font_row_coverage = 20'h02A90; // L
            12'h3A5: font_row_coverage = 20'h00400; // :
            12'h3A6: font_row_coverage = 20'h00A00; // :
            12'h3A7: font_row_coverage = 20'h00A00; // :
            12'h3AB: font_row_coverage = 20'h00A00; // :
            12'h3AC: font_row_coverage = 20'h00A00; // :
            12'h303: font_row_coverage = 20'h01F40; // 0
            12'h304: font_row_coverage = 20'h035C0; // 0
            12'h305: font_row_coverage = 20'h030C0; // 0
            12'h306: font_row_coverage = 20'h070D0; // 0
            12'h307: font_row_coverage = 20'h070D0; // 0
            12'h308: font_row_coverage = 20'h070D0; // 0
            12'h309: font_row_coverage = 20'h070D0; // 0
            12'h30A: font_row_coverage = 20'h030C0; // 0
            12'h30B: font_row_coverage = 20'h02A80; // 0
            12'h30C: font_row_coverage = 20'h00A00; // 0
            12'h313: font_row_coverage = 20'h01A00; // 1
            12'h314: font_row_coverage = 20'h02E00; // 1
            12'h315: font_row_coverage = 20'h00600; // 1
            12'h316: font_row_coverage = 20'h00600; // 1
            12'h317: font_row_coverage = 20'h00600; // 1
            12'h318: font_row_coverage = 20'h00600; // 1
            12'h319: font_row_coverage = 20'h00600; // 1
            12'h31A: font_row_coverage = 20'h00600; // 1
            12'h31B: font_row_coverage = 20'h02B80; // 1
            12'h31C: font_row_coverage = 20'h02A80; // 1
            12'h322: font_row_coverage = 20'h00400; // 2
            12'h323: font_row_coverage = 20'h02F40; // 2
            12'h324: font_row_coverage = 20'h06680; // 2
            12'h325: font_row_coverage = 20'h001C0; // 2
            12'h326: font_row_coverage = 20'h001C0; // 2
            12'h327: font_row_coverage = 20'h00280; // 2
            12'h328: font_row_coverage = 20'h00340; // 2
            12'h329: font_row_coverage = 20'h00A00; // 2
            12'h32A: font_row_coverage = 20'h01C00; // 2
            12'h32B: font_row_coverage = 20'h03E90; // 2
            12'h32C: font_row_coverage = 20'h06A90; // 2
            12'h332: font_row_coverage = 20'h00400; // 3
            12'h333: font_row_coverage = 20'h02F40; // 3
            12'h334: font_row_coverage = 20'h026C0; // 3
            12'h335: font_row_coverage = 20'h001C0; // 3
            12'h336: font_row_coverage = 20'h00280; // 3
            12'h337: font_row_coverage = 20'h00F40; // 3
            12'h338: font_row_coverage = 20'h00680; // 3
            12'h339: font_row_coverage = 20'h000D0; // 3
            12'h33A: font_row_coverage = 20'h000D0; // 3
            12'h33B: font_row_coverage = 20'h076C0; // 3
            12'h33C: font_row_coverage = 20'h02E40; // 3
            12'h343: font_row_coverage = 20'h00380; // 4
            12'h344: font_row_coverage = 20'h00780; // 4
            12'h345: font_row_coverage = 20'h00A80; // 4
            12'h346: font_row_coverage = 20'h01A80; // 4
            12'h347: font_row_coverage = 20'h02680; // 4
            12'h348: font_row_coverage = 20'h07280; // 4
            12'h349: font_row_coverage = 20'h0BFD0; // 4
            12'h34A: font_row_coverage = 20'h01680; // 4
            12'h34B: font_row_coverage = 20'h00280; // 4
            12'h34C: font_row_coverage = 20'h00140; // 4
            12'h353: font_row_coverage = 20'h02F80; // 5
            12'h354: font_row_coverage = 20'h02940; // 5
            12'h355: font_row_coverage = 20'h02400; // 5
            12'h356: font_row_coverage = 20'h02900; // 5
            12'h357: font_row_coverage = 20'h02B80; // 5
            12'h358: font_row_coverage = 20'h001C0; // 5
            12'h359: font_row_coverage = 20'h000D0; // 5
            12'h35A: font_row_coverage = 20'h000D0; // 5
            12'h35B: font_row_coverage = 20'h07680; // 5
            12'h35C: font_row_coverage = 20'h02E40; // 5
            12'h362: font_row_coverage = 20'h00100; // 6
            12'h363: font_row_coverage = 20'h00B80; // 6
            12'h364: font_row_coverage = 20'h02980; // 6
            12'h365: font_row_coverage = 20'h03400; // 6
            12'h366: font_row_coverage = 20'h07100; // 6
            12'h367: font_row_coverage = 20'h07B80; // 6
            12'h368: font_row_coverage = 20'h074D0; // 6
            12'h369: font_row_coverage = 20'h07090; // 6
            12'h36A: font_row_coverage = 20'h034D0; // 6
            12'h36B: font_row_coverage = 20'h029C0; // 6
            12'h36C: font_row_coverage = 20'h00B40; // 6
            12'h373: font_row_coverage = 20'h07FD0; // 7
            12'h374: font_row_coverage = 20'h016C0; // 7
            12'h375: font_row_coverage = 20'h00280; // 7
            12'h376: font_row_coverage = 20'h00340; // 7
            12'h377: font_row_coverage = 20'h00600; // 7
            12'h378: font_row_coverage = 20'h00A00; // 7
            12'h379: font_row_coverage = 20'h00A00; // 7
            12'h37A: font_row_coverage = 20'h00900; // 7
            12'h37B: font_row_coverage = 20'h00D00; // 7
            12'h37C: font_row_coverage = 20'h00900; // 7
            12'h382: font_row_coverage = 20'h00100; // 8
            12'h383: font_row_coverage = 20'h01F40; // 8
            12'h384: font_row_coverage = 20'h035C0; // 8
            12'h385: font_row_coverage = 20'h030C0; // 8
            12'h386: font_row_coverage = 20'h02980; // 8
            12'h387: font_row_coverage = 20'h01F40; // 8
            12'h388: font_row_coverage = 20'h02680; // 8
            12'h389: font_row_coverage = 20'h070D0; // 8
            12'h38A: font_row_coverage = 20'h06090; // 8
            12'h38B: font_row_coverage = 20'h035C0; // 8
            12'h38C: font_row_coverage = 20'h01F40; // 8
            default: font_row_coverage = 20'd0;
        endcase
    end
endfunction

endmodule
