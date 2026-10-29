// Frameless, one-line brightness/contrast/volume readout over the image.
// Uses the existing Noto Sans SC font ROM without color-coded level bars.
// Control values are synchronized and committed at a frame edge.
module video_status_overlay #(
    parameter integer H_ACTIVE = 640,
    parameter integer V_ACTIVE = 480,
    parameter ENABLE_RESOLUTION = 0
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
    input  wire [15:0] I_source_width,
    input  wire [15:0] I_source_height,
    output wire [23:0] O_rgb
);

localparam [9:0]  TEXT_TOP    = 10'd16;
localparam [10:0] BRI_LEFT    = 11'd18;
localparam [10:0] CON_LEFT    = 11'd114;
localparam [10:0] VOL_LEFT    = 11'd210;
localparam [10:0] RES_LEFT    = 11'd282;

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

// Infrequent binary->decimal conversion, 16 clocks/image, no /10 dividers.
// The input bus is immutable once its SDRAM cache becomes display-valid.
reg [31:0] res_meta,res_sync,converted_size,conversion_size;
reg [35:0] width_shift,height_shift;
reg [19:0] width_bcd,height_bcd,width_frame_bcd,height_frame_bcd;
reg [2:0] width_digits,height_digits,width_frame_digits,height_frame_digits;
reg [4:0] bcd_count;
reg bcd_busy;
reg [35:0] width_add,height_add;
integer bcd_i;
always @(*) begin
    width_add=width_shift; height_add=height_shift;
    for(bcd_i=0;bcd_i<5;bcd_i=bcd_i+1) begin
        if(width_shift[16+bcd_i*4 +: 4]>=5)
            width_add[16+bcd_i*4 +: 4]=width_shift[16+bcd_i*4 +: 4]+4'd3;
        if(height_shift[16+bcd_i*4 +: 4]>=5)
            height_add[16+bcd_i*4 +: 4]=height_shift[16+bcd_i*4 +: 4]+4'd3;
    end
end
function [2:0] decimal_digits;
    input [15:0] value;
    begin decimal_digits=(value>=10000) ? 5 : (value>=1000) ? 4 :
        (value>=100) ? 3 : (value>=10) ? 2 : 1; end
endfunction
always @(posedge I_clk or posedge I_rst) begin
    if(I_rst) begin
        res_meta<=0; res_sync<=0; converted_size<=0; conversion_size<=0;
        width_shift<=0; height_shift<=0; bcd_count<=0; bcd_busy<=0;
        width_bcd<=0; height_bcd<=0; width_digits<=1; height_digits<=1;
        width_frame_bcd<=0; height_frame_bcd<=0;
        width_frame_digits<=1; height_frame_digits<=1;
    end else if(ENABLE_RESOLUTION) begin
        res_meta<={I_source_width,I_source_height}; res_sync<=res_meta;
        if(!bcd_busy && res_sync==res_meta && res_sync!=converted_size) begin
            conversion_size<=res_sync;
            width_shift<={20'd0,res_sync[31:16]}; height_shift<={20'd0,res_sync[15:0]};
            bcd_count<=16; bcd_busy<=1;
        end else if(bcd_busy) begin
            width_shift<=width_add<<1; height_shift<=height_add<<1;
            bcd_count<=bcd_count-1'b1;
            if(bcd_count==1) begin
                width_bcd<=width_add[34:15]; height_bcd<=height_add[34:15];
                width_digits<=decimal_digits(conversion_size[31:16]);
                height_digits<=decimal_digits(conversion_size[15:0]);
                converted_size<=conversion_size; bcd_busy<=0;
            end
        end
        // First DE is after vertical blank, allowing a new image's metadata
        // to settle and convert before freezing this frame's text.
        if(I_de && line_start && !active_seen) begin
            width_frame_bcd<=width_bcd; height_frame_bcd<=height_bcd;
            width_frame_digits<=width_digits; height_frame_digits<=height_digits;
        end
    end
end

// Values the raster/frame registers take on the next clock.  The font ROM is
// synchronous, so its address and the registered text geometry are computed
// from these; both then line up with pixel_x/pixel_y.
reg [10:0] next_x;
reg [9:0]  next_y;
reg [1:0]  next_brightness, next_contrast;
reg [3:0]  next_volume;
always @(*) begin
    next_x          = pixel_x;
    next_y          = pixel_y;
    next_brightness = brightness_frame;
    next_contrast   = contrast_frame;
    next_volume     = volume_frame;
    if (frame_start) begin
        next_x          = 11'd0;
        next_y          = 10'd0;
        next_brightness = brightness_stable;
        next_contrast   = contrast_stable;
        next_volume     = (volume_stable > 4'd8) ? 4'd8 : volume_stable;
    end else if (I_de) begin
        if (line_start) begin
            next_x = 11'd0;
            if (!active_seen)
                next_y = 10'd0;
            else if (pixel_y < V_ACTIVE - 1)
                next_y = pixel_y + 10'd1;
        end else if (pixel_x < H_ACTIVE - 1) begin
            next_x = pixel_x + 11'd1;
        end
    end else begin
        next_x = 11'd0;
    end
end

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

        pixel_x          <= next_x;
        pixel_y          <= next_y;
        brightness_frame <= next_brightness;
        contrast_frame   <= next_contrast;
        volume_frame     <= next_volume;
        if (frame_start)
            active_seen <= 1'b0;
        else if (I_de && line_start)
            active_seen <= 1'b1;
    end
end

// Three groups occupy one row. Spaces between them are transparent.
// Decode the next pixel for the synchronous font ROM.
reg [1:0] next_text_line;
reg [10:0] next_text_rel_x;
reg [10:0] next_text_origin;
reg       next_text_row_hit;
always @(*) begin
    next_text_line    = 2'd0;
    next_text_rel_x   = 11'd0;
    next_text_origin  = 11'd0;
    next_text_row_hit = 1'b0;
    if (next_y >= TEXT_TOP && next_y < TEXT_TOP + 10'd14) begin
        if (next_x >= BRI_LEFT && next_x < BRI_LEFT + 11'd84) begin
            next_text_line = 2'd0;
            next_text_origin = BRI_LEFT;
            next_text_row_hit = 1'b1;
        end else if (next_x >= CON_LEFT && next_x < CON_LEFT + 11'd84) begin
            next_text_line = 2'd1;
            next_text_origin = CON_LEFT;
            next_text_row_hit = 1'b1;
        end else if (next_x >= VOL_LEFT && next_x < VOL_LEFT + 11'd60) begin
            next_text_line = 2'd2;
            next_text_origin = VOL_LEFT;
            next_text_row_hit = 1'b1;
        end else if(ENABLE_RESOLUTION && next_x>=RES_LEFT && next_x<RES_LEFT+11'd180) begin
            next_text_line=2'd3;
            next_text_origin=RES_LEFT;
            next_text_row_hit=1'b1;
        end
    end
    if (next_text_row_hit)
        next_text_rel_x = next_x - next_text_origin;
end

reg  [3:0] next_char_index;
reg  [3:0] next_char_cell_x;
always @(*) begin
    next_char_index  = 3'd0;
    if (next_text_rel_x < 11'd12) begin
        next_char_index = 3'd0;
    end else if (next_text_rel_x < 11'd24) begin
        next_char_index = 3'd1;
    end else if (next_text_rel_x < 11'd36) begin
        next_char_index = 3'd2;
    end else if (next_text_rel_x < 11'd48) begin
        next_char_index = 3'd3;
    end else if (next_text_rel_x < 11'd60) begin
        next_char_index = 3'd4;
    end else if (next_text_rel_x < 11'd72) begin
        next_char_index = 3'd5;
    end else if(next_text_rel_x < 11'd84) begin
        next_char_index = 3'd6;
    end else if(next_text_rel_x < 11'd96) begin
        next_char_index = 4'd7;
    end else if(next_text_rel_x < 11'd108) begin
        next_char_index = 4'd8;
    end else if(next_text_rel_x < 11'd120) begin
        next_char_index = 4'd9;
    end else if(next_text_rel_x < 11'd132) begin
        next_char_index = 4'd10;
    end else if(next_text_rel_x < 11'd144) begin
        next_char_index = 4'd11;
    end else if(next_text_rel_x < 11'd156) begin
        next_char_index = 4'd12;
    end else if(next_text_rel_x < 11'd168) begin
        next_char_index = 4'd13;
    end else begin
        next_char_index = 4'd14;
    end
    // Only the low four bits are used: x - 12*index == x + 4*index (mod 16).
    next_char_cell_x = next_text_rel_x[3:0] + {next_char_index[1:0], 2'b00};
end

// The first clock after reset is outside the text row.
reg       text_row_hit;
reg [3:0] char_cell_x;
always @(posedge I_clk or posedge I_rst) begin
    if (I_rst) begin
        text_row_hit <= 1'b0;
        char_cell_x  <= 4'd0;
    end else begin
        text_row_hit <= next_text_row_hit;
        char_cell_x  <= next_char_cell_x;
    end
end

wire [3:0] font_col = char_cell_x;
wire [3:0] next_font_row = next_y - TEXT_TOP;
reg [4:0] res_code;
reg [3:0] res_digit_offset;
always @(*) begin
    res_code=5'd31; res_digit_offset=0;
    case(next_char_index)
        0: res_code=5'd12; // R
        1: res_code=5'd19; // E
        2: res_code=5'd20; // S
        3: res_code=5'd10; // :
        default: begin
            if(next_char_index<4+width_frame_digits) begin
                res_digit_offset=width_frame_digits+3-next_char_index;
                res_code={1'b0,width_frame_bcd[res_digit_offset*4 +: 4]};
            end else if(next_char_index==4+width_frame_digits) res_code=5'd21; // x
            else if(next_char_index<5+width_frame_digits+height_frame_digits) begin
                res_digit_offset=height_frame_digits+width_frame_digits+4-next_char_index;
                res_code={1'b0,height_frame_bcd[res_digit_offset*4 +: 4]};
            end
        end
    endcase
end
wire [4:0] next_char_code = next_text_line==3 ? res_code : status_code(next_text_line, next_char_index[2:0],
                                        next_brightness, next_contrast,
                                        next_volume);
// Only font columns 2..7 are ever inked; the ROM stores those twelve bits.
wire [11:0] font_row_ink;
video_status_font_rom u_font_rom (
    .I_clk(I_clk), .I_addr({next_char_code, next_font_row}),
    .O_row(font_row_ink)
);
wire [19:0] current_font_row = {4'd0, font_row_ink, 4'd0};
wire [1:0] text_cov = current_font_row[(9-font_col)*2 +: 2];
wire ink_area = I_enable && I_de && text_row_hit &&
                (char_cell_x < 4'd10);
wire text_hit = ink_area && (text_cov != 2'd0);
// A one-pixel dark shadow keeps the text clear on both light and dark photos.
wire [1:0] left_cov = current_font_row[(10-font_col)*2 +: 2];
wire shadow_hit = ink_area && (char_cell_x != 4'd0) &&
                  (text_cov == 2'd0) && (left_cov != 2'd0);
wire [23:0] text_color = (text_cov == 2'd3) ? 24'hF4F9FC :
                         (text_cov == 2'd2) ? 24'hD4E1E9 : 24'hA8BAC6;
assign O_rgb = text_hit ? text_color :
               shadow_hit ? 24'h13212E : I_rgb;

// Compact font codes: digits map to their value; the rest follow the table
// below.  CODE_BLANK has no ROM rows and therefore draws nothing.
localparam [4:0] CODE_COLON = 5'd10;
localparam [4:0] CODE_B     = 5'd11;
localparam [4:0] CODE_R     = 5'd12;
localparam [4:0] CODE_I     = 5'd13;
localparam [4:0] CODE_C     = 5'd14;
localparam [4:0] CODE_O     = 5'd15;
localparam [4:0] CODE_N     = 5'd16;
localparam [4:0] CODE_V     = 5'd17;
localparam [4:0] CODE_L     = 5'd18;
localparam [4:0] CODE_BLANK = 5'd31;

function [4:0] percent_code;
    input [1:0] level;
    input [1:0] digit;
    begin
        case (level)
            2'd0: percent_code = (digit == 2'd0) ? CODE_BLANK :
                                 (digit == 2'd1) ? 5'd2 : 5'd5;
            2'd1: percent_code = (digit == 2'd0) ? CODE_BLANK :
                                 (digit == 2'd1) ? 5'd5 : 5'd0;
            2'd2: percent_code = (digit == 2'd0) ? CODE_BLANK :
                                 (digit == 2'd1) ? 5'd7 : 5'd5;
            default: percent_code = (digit == 2'd0) ? 5'd1 : 5'd0;
        endcase
    end
endfunction

function [4:0] status_code;
    input [1:0] line;
    input [2:0] index;
    input [1:0] brightness;
    input [1:0] contrast;
    input [3:0] volume;
    reg [1:0] percent_level;
    reg [1:0] percent_digit;
    begin
        status_code = CODE_BLANK;
        percent_level = (line == 2'd0) ? brightness : contrast;
        percent_digit = (index == 3'd4) ? 2'd0 :
                        (index == 3'd5) ? 2'd1 : 2'd2;
        case (index)
            3'd0: status_code = (line == 2'd0) ? CODE_B :
                                (line == 2'd1) ? CODE_C : CODE_V;
            3'd1: status_code = (line == 2'd0) ? CODE_R : CODE_O;
            3'd2: status_code = (line == 2'd0) ? CODE_I :
                                (line == 2'd1) ? CODE_N : CODE_L;
            3'd3: status_code = CODE_COLON;
            default: begin
                if (line[1])
                    status_code = (index == 3'd4) ? {1'b0, volume} : CODE_BLANK;
                else
                    status_code = percent_code(percent_level, percent_digit);
            end
        endcase
    end
endfunction

endmodule

// Noto Sans SC Medium, 10x14, two-bit antialias coverage; columns 2..7 stored.
// Generated from the same font source for all on-screen labels.
module video_status_font_rom (
    input  wire        I_clk,
    input  wire [8:0]  I_addr,   // {font code, row}
    output reg  [11:0] O_row
);
reg [11:0] rom [0:511];
integer i;
initial begin
    for (i = 0; i < 512; i = i + 1) rom[i] = 12'd0;
    rom[9'h003] = 12'h0F0; // 0
    rom[9'h004] = 12'h35C; // 0
    rom[9'h005] = 12'h30C; // 0
    rom[9'h006] = 12'h30D; // 0
    rom[9'h007] = 12'h70D; // 0
    rom[9'h008] = 12'h70D; // 0
    rom[9'h009] = 12'h30C; // 0
    rom[9'h00A] = 12'h30C; // 0
    rom[9'h00B] = 12'h3EC; // 0
    rom[9'h00C] = 12'h0F0; // 0
    rom[9'h013] = 12'h0F0; // 1
    rom[9'h014] = 12'h2F0; // 1
    rom[9'h015] = 12'h070; // 1
    rom[9'h016] = 12'h070; // 1
    rom[9'h017] = 12'h070; // 1
    rom[9'h018] = 12'h070; // 1
    rom[9'h019] = 12'h070; // 1
    rom[9'h01A] = 12'h070; // 1
    rom[9'h01B] = 12'h2F8; // 1
    rom[9'h01C] = 12'h3FC; // 1
    rom[9'h023] = 12'h3F0; // 2
    rom[9'h024] = 12'h32C; // 2
    rom[9'h025] = 12'h00C; // 2
    rom[9'h026] = 12'h01C; // 2
    rom[9'h027] = 12'h02C; // 2
    rom[9'h028] = 12'h030; // 2
    rom[9'h029] = 12'h0F0; // 2
    rom[9'h02A] = 12'h0C0; // 2
    rom[9'h02B] = 12'h3EC; // 2
    rom[9'h02C] = 12'h7FC; // 2
    rom[9'h033] = 12'h3F4; // 3
    rom[9'h034] = 12'h32C; // 3
    rom[9'h035] = 12'h00C; // 3
    rom[9'h036] = 12'h02C; // 3
    rom[9'h037] = 12'h0F0; // 3
    rom[9'h038] = 12'h07C; // 3
    rom[9'h039] = 12'h00C; // 3
    rom[9'h03A] = 12'h00C; // 3
    rom[9'h03B] = 12'h77C; // 3
    rom[9'h03C] = 12'h2F0; // 3
    rom[9'h043] = 12'h038; // 4
    rom[9'h044] = 12'h078; // 4
    rom[9'h045] = 12'h0F8; // 4
    rom[9'h046] = 12'h1D8; // 4
    rom[9'h047] = 12'h328; // 4
    rom[9'h048] = 12'h728; // 4
    rom[9'h049] = 12'hBFE; // 4
    rom[9'h04A] = 12'h02C; // 4
    rom[9'h04B] = 12'h02C; // 4
    rom[9'h04C] = 12'h028; // 4
    rom[9'h053] = 12'h2FC; // 5
    rom[9'h054] = 12'h394; // 5
    rom[9'h055] = 12'h300; // 5
    rom[9'h056] = 12'h390; // 5
    rom[9'h057] = 12'h3FC; // 5
    rom[9'h058] = 12'h00C; // 5
    rom[9'h059] = 12'h00C; // 5
    rom[9'h05A] = 12'h00C; // 5
    rom[9'h05B] = 12'h77C; // 5
    rom[9'h05C] = 12'h2F0; // 5
    rom[9'h063] = 12'h0FC; // 6
    rom[9'h064] = 12'h3C8; // 6
    rom[9'h065] = 12'h300; // 6
    rom[9'h066] = 12'h300; // 6
    rom[9'h067] = 12'h3FC; // 6
    rom[9'h068] = 12'h30C; // 6
    rom[9'h069] = 12'h30D; // 6
    rom[9'h06A] = 12'h30D; // 6
    rom[9'h06B] = 12'h3DC; // 6
    rom[9'h06C] = 12'h0F0; // 6
    rom[9'h073] = 12'h7FD; // 7
    rom[9'h074] = 12'h15C; // 7
    rom[9'h075] = 12'h028; // 7
    rom[9'h076] = 12'h030; // 7
    rom[9'h077] = 12'h070; // 7
    rom[9'h078] = 12'h0B0; // 7
    rom[9'h079] = 12'h0E0; // 7
    rom[9'h07A] = 12'h0D0; // 7
    rom[9'h07B] = 12'h0D0; // 7
    rom[9'h07C] = 12'h0D0; // 7
    rom[9'h083] = 12'h1F4; // 8
    rom[9'h084] = 12'h34C; // 8
    rom[9'h085] = 12'h30C; // 8
    rom[9'h086] = 12'h38C; // 8
    rom[9'h087] = 12'h0F0; // 8
    rom[9'h088] = 12'h37C; // 8
    rom[9'h089] = 12'h30C; // 8
    rom[9'h08A] = 12'h70D; // 8
    rom[9'h08B] = 12'h35C; // 8
    rom[9'h08C] = 12'h1F4; // 8
    rom[9'h093] = 12'h1F0; // 9
    rom[9'h094] = 12'h32C; // 9
    rom[9'h095] = 12'h70C; // 9
    rom[9'h096] = 12'h70C; // 9
    rom[9'h097] = 12'h30C; // 9
    rom[9'h098] = 12'h2FC; // 9
    rom[9'h099] = 12'h00C; // 9
    rom[9'h09A] = 12'h00C; // 9
    rom[9'h09B] = 12'h378; // 9
    rom[9'h09C] = 12'h2F0; // 9
    rom[9'h0A6] = 12'h0F0; // :
    rom[9'h0A7] = 12'h0A0; // :
    rom[9'h0AB] = 12'h0F0; // :
    rom[9'h0AC] = 12'h0A0; // :
    rom[9'h0B3] = 12'h3F8; // B
    rom[9'h0B4] = 12'h71C; // B
    rom[9'h0B5] = 12'h70E; // B
    rom[9'h0B6] = 12'h70C; // B
    rom[9'h0B7] = 12'h3FC; // B
    rom[9'h0B8] = 12'h30E; // B
    rom[9'h0B9] = 12'h707; // B
    rom[9'h0BA] = 12'h70B; // B
    rom[9'h0BB] = 12'h7AD; // B
    rom[9'h0BC] = 12'h3F4; // B
    rom[9'h0C3] = 12'h3F8; // R
    rom[9'h0C4] = 12'h71D; // R
    rom[9'h0C5] = 12'h70A; // R
    rom[9'h0C6] = 12'h70E; // R
    rom[9'h0C7] = 12'h35C; // R
    rom[9'h0C8] = 12'h3F4; // R
    rom[9'h0C9] = 12'h734; // R
    rom[9'h0CA] = 12'h71C; // R
    rom[9'h0CB] = 12'h70D; // R
    rom[9'h0CC] = 12'h30A; // R
    rom[9'h0D3] = 12'h0E0; // I
    rom[9'h0D4] = 12'h0E0; // I
    rom[9'h0D5] = 12'h0E0; // I
    rom[9'h0D6] = 12'h0E0; // I
    rom[9'h0D7] = 12'h0E0; // I
    rom[9'h0D8] = 12'h0E0; // I
    rom[9'h0D9] = 12'h0E0; // I
    rom[9'h0DA] = 12'h0E0; // I
    rom[9'h0DB] = 12'h0E0; // I
    rom[9'h0DC] = 12'h090; // I
    rom[9'h0E3] = 12'h0FC; // C
    rom[9'h0E4] = 12'h3CD; // C
    rom[9'h0E5] = 12'h700; // C
    rom[9'h0E6] = 12'hB00; // C
    rom[9'h0E7] = 12'hE00; // C
    rom[9'h0E8] = 12'hE00; // C
    rom[9'h0E9] = 12'hB00; // C
    rom[9'h0EA] = 12'h300; // C
    rom[9'h0EB] = 12'h3DE; // C
    rom[9'h0EC] = 12'h0F8; // C
    rom[9'h0F3] = 12'h2F8; // O
    rom[9'h0F4] = 12'h71D; // O
    rom[9'h0F5] = 12'hE0B; // O
    rom[9'h0F6] = 12'hC07; // O
    rom[9'h0F7] = 12'hC03; // O
    rom[9'h0F8] = 12'hC03; // O
    rom[9'h0F9] = 12'hC07; // O
    rom[9'h0FA] = 12'hE0F; // O
    rom[9'h0FB] = 12'h3AC; // O
    rom[9'h0FC] = 12'h1F0; // O
    rom[9'h103] = 12'hB0A; // N
    rom[9'h104] = 12'hB0B; // N
    rom[9'h105] = 12'hB8A; // N
    rom[9'h106] = 12'hACA; // N
    rom[9'h107] = 12'hDDB; // N
    rom[9'h108] = 12'hE36; // N
    rom[9'h109] = 12'hA3A; // N
    rom[9'h10A] = 12'hA2E; // N
    rom[9'h10B] = 12'hF0E; // N
    rom[9'h10C] = 12'hA0A; // N
    rom[9'h113] = 12'hE0B; // V
    rom[9'h114] = 12'hB0E; // V
    rom[9'h115] = 12'h70D; // V
    rom[9'h116] = 12'h30C; // V
    rom[9'h117] = 12'h30C; // V
    rom[9'h118] = 12'h35C; // V
    rom[9'h119] = 12'h2A8; // V
    rom[9'h11A] = 12'h0F0; // V
    rom[9'h11B] = 12'h0F0; // V
    rom[9'h11C] = 12'h0A0; // V
    rom[9'h123] = 12'h340; // L
    rom[9'h124] = 12'h340; // L
    rom[9'h125] = 12'h340; // L
    rom[9'h126] = 12'h340; // L
    rom[9'h127] = 12'h340; // L
    rom[9'h128] = 12'h340; // L
    rom[9'h129] = 12'h340; // L
    rom[9'h12A] = 12'h340; // L
    rom[9'h12B] = 12'h3EC; // L
    rom[9'h12C] = 12'h2FD; // L
    rom[9'h133] = 12'h3FC; // E
    rom[9'h134] = 12'h394; // E
    rom[9'h135] = 12'h300; // E
    rom[9'h136] = 12'h300; // E
    rom[9'h137] = 12'h3FC; // E
    rom[9'h138] = 12'h354; // E
    rom[9'h139] = 12'h300; // E
    rom[9'h13A] = 12'h300; // E
    rom[9'h13B] = 12'h3ED; // E
    rom[9'h13C] = 12'h2FD; // E
    rom[9'h143] = 12'h1FC; // S
    rom[9'h144] = 12'h38C; // S
    rom[9'h145] = 12'h300; // S
    rom[9'h146] = 12'h380; // S
    rom[9'h147] = 12'h1F0; // S
    rom[9'h148] = 12'h03C; // S
    rom[9'h149] = 12'h00E; // S
    rom[9'h14A] = 12'h10E; // S
    rom[9'h14B] = 12'h7AC; // S
    rom[9'h14C] = 12'h1F4; // S
    rom[9'h155] = 12'h208; // x
    rom[9'h156] = 12'h35C; // x
    rom[9'h157] = 12'h1F4; // x
    rom[9'h158] = 12'h0F0; // x
    rom[9'h159] = 12'h0F0; // x
    rom[9'h15A] = 12'h1F4; // x
    rom[9'h15B] = 12'h31C; // x
    rom[9'h15C] = 12'h30C; // x
end
always @(posedge I_clk) O_row <= rom[I_addr];
endmodule
