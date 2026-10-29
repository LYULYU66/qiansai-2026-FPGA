// Frameless, one-line brightness/contrast/volume readout over the image.
// 20261022: same glyphs as the first music card's song title (Noto Sans SC
// Medium 24px, crisp), on a 16-pixel pitch; no color-coded level bars.
// Control values are synchronized and committed at a frame edge.
module video_status_overlay #(
    parameter integer H_ACTIVE = 640,
    parameter integer V_ACTIVE = 480,
    parameter ENABLE_RESOLUTION = 0,
    // 20261020: SELECT_HIGHLIGHT draws the group chosen by I_selected
    // (0 brightness, 1 contrast, 2 volume) in purple for key adjustment.
    parameter SELECT_HIGHLIGHT = 0
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
    input  wire [1:0]  I_selected,
    output wire [23:0] O_rgb
);

// Ink box rows 14..30, above the home logo (y38) and the clock (y38/82).
localparam [9:0]  TEXT_TOP    = 10'd14;
localparam [9:0]  TEXT_ROWS   = 10'd17;
localparam [10:0] BRI_LEFT    = 11'd18;   // "BRI:100" 7 cells
localparam [10:0] CON_LEFT    = 11'd146;  // "CON:100" 7 cells
localparam [10:0] VOL_LEFT    = 11'd274;  // "VOL:8"   5 cells
localparam [10:0] RES_LEFT    = 11'd370;  // "RES:" + up to 5x5 digits, 15 cells to x610

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
    input [19:0] bcd;
    // The converter already produces BCD. Count its leading nonzero nibbles
    // instead of duplicating four 16-bit magnitude comparators per dimension.
    begin decimal_digits=(|bcd[19:16]) ? 5 : (|bcd[15:12]) ? 4 :
        (|bcd[11:8]) ? 3 : (|bcd[7:4]) ? 2 : 1; end
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
                width_digits<=decimal_digits(width_add[34:15]);
                height_digits<=decimal_digits(height_add[34:15]);
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
    if (next_y >= TEXT_TOP && next_y < TEXT_TOP + TEXT_ROWS) begin
        if (next_x >= BRI_LEFT && next_x < BRI_LEFT + 11'd112) begin
            next_text_line = 2'd0;
            next_text_origin = BRI_LEFT;
            next_text_row_hit = 1'b1;
        end else if (next_x >= CON_LEFT && next_x < CON_LEFT + 11'd112) begin
            next_text_line = 2'd1;
            next_text_origin = CON_LEFT;
            next_text_row_hit = 1'b1;
        end else if (next_x >= VOL_LEFT && next_x < VOL_LEFT + 11'd80) begin
            next_text_line = 2'd2;
            next_text_origin = VOL_LEFT;
            next_text_row_hit = 1'b1;
        end else if(ENABLE_RESOLUTION && next_x>=RES_LEFT && next_x<RES_LEFT+11'd240) begin
            next_text_line=2'd3;
            next_text_origin=RES_LEFT;
            next_text_row_hit=1'b1;
        end
    end
    if (next_text_row_hit)
        next_text_rel_x = next_x - next_text_origin;
end

// 16-pixel cells: the character index and cell column are bit slices.
wire [3:0] next_char_index  = next_text_rel_x[7:4];
wire [3:0] next_char_cell_x = next_text_rel_x[3:0];

// The first clock after reset is outside the text row.
reg       text_row_hit;
reg [3:0] char_cell_x;
reg       text_selected;
always @(posedge I_clk or posedge I_rst) begin
    if (I_rst) begin
        text_row_hit <= 1'b0;
        char_cell_x  <= 4'd0;
        text_selected <= 1'b0;
    end else begin
        text_row_hit <= next_text_row_hit;
        char_cell_x  <= next_char_cell_x;
        text_selected <= SELECT_HIGHLIGHT && next_text_line == I_selected;
    end
end

wire [3:0] font_col = char_cell_x;
wire [4:0] next_font_row = next_y - TEXT_TOP;
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
// Cell columns 0..14 hold ink; column 15 is the inter-character gap.
// Font row 16 is stored after the 22 codes (codes never exceed 21).
wire [8:0] font_addr = next_font_row[4] ? 9'd352 + {4'd0, next_char_code} :
                                          {next_char_code, next_font_row[3:0]};
wire [29:0] font_row_ink;
video_status_font_rom u_font_rom (
    .I_clk(I_clk), .I_addr(font_addr), .O_row(font_row_ink)
);
wire [31:0] current_font_row = {font_row_ink, 2'd0};
wire [1:0] text_cov = current_font_row[(15-font_col)*2 +: 2];
wire ink_area = I_enable && I_de && text_row_hit;
wire text_hit = ink_area && (text_cov != 2'd0);
// A one-pixel dark shadow keeps the text clear on both light and dark photos.
wire [1:0] left_cov = current_font_row[(16-font_col)*2 +: 2];
wire shadow_hit = ink_area && (char_cell_x != 4'd0) &&
                  (text_cov == 2'd0) && (left_cov != 2'd0);
wire [23:0] text_color = text_selected ?
                         ((text_cov == 2'd3) ? 24'hC77DFF :
                          (text_cov == 2'd2) ? 24'hA764E0 : 24'h7E4AAE) :
                         ((text_cov == 2'd3) ? 24'hF4F9FC :
                          (text_cov == 2'd2) ? 24'hD4E1E9 : 24'hA8BAC6);
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

// Music-card title font (Noto Sans SC Medium 24px, crisp), 15x17 ink box,
// two-bit coverage. GENERATED by sim/generate_status_font24_20261022.py.
module video_status_font_rom (
    input  wire        I_clk,
    input  wire [8:0]  I_addr,   // {code,row[3:0]}; row 16 at 352+code
    output reg  [29:0] O_row
);
reg [29:0] rom [0:511];
integer i;
initial begin
    for (i = 0; i < 512; i = i + 1) rom[i] = 30'd0;
    rom[9'h000] = 30'h0007FD00; // 0
    rom[9'h001] = 30'h001FFF80; // 0
    rom[9'h002] = 30'h003E0BC0; // 0
    rom[9'h003] = 30'h00BC03E0; // 0
    rom[9'h004] = 30'h00F802F0; // 0
    rom[9'h005] = 30'h00F401F0; // 0
    rom[9'h006] = 30'h00F000F4; // 0
    rom[9'h007] = 30'h00F000F4; // 0
    rom[9'h008] = 30'h01F000F4; // 0
    rom[9'h009] = 30'h00F000F4; // 0
    rom[9'h00A] = 30'h00F000F4; // 0
    rom[9'h00B] = 30'h00F401F0; // 0
    rom[9'h00C] = 30'h00F802F0; // 0
    rom[9'h00D] = 30'h00BC03E0; // 0
    rom[9'h00E] = 30'h003E0BC0; // 0
    rom[9'h00F] = 30'h001FFF80; // 0
    rom[9'h160] = 30'h0007FD00; // 0
    rom[9'h010] = 30'h0000B800; // 1
    rom[9'h011] = 30'h002FFC00; // 1
    rom[9'h012] = 30'h003FFC00; // 1
    rom[9'h013] = 30'h0000FC00; // 1
    rom[9'h014] = 30'h0000FC00; // 1
    rom[9'h015] = 30'h0000FC00; // 1
    rom[9'h016] = 30'h0000FC00; // 1
    rom[9'h017] = 30'h0000FC00; // 1
    rom[9'h018] = 30'h0000FC00; // 1
    rom[9'h019] = 30'h0000FC00; // 1
    rom[9'h01A] = 30'h0000FC00; // 1
    rom[9'h01B] = 30'h0000FC00; // 1
    rom[9'h01C] = 30'h0000FC00; // 1
    rom[9'h01D] = 30'h0000FC00; // 1
    rom[9'h01E] = 30'h0015FD50; // 1
    rom[9'h01F] = 30'h00BFFFF0; // 1
    rom[9'h161] = 30'h007FFFF0; // 1
    rom[9'h020] = 30'h001FFC00; // 2
    rom[9'h021] = 30'h00BFFF40; // 2
    rom[9'h022] = 30'h01F40FC0; // 2
    rom[9'h023] = 30'h005003D0; // 2
    rom[9'h024] = 30'h000003E0; // 2
    rom[9'h025] = 30'h000003E0; // 2
    rom[9'h026] = 30'h000003D0; // 2
    rom[9'h027] = 30'h00000BC0; // 2
    rom[9'h028] = 30'h00000F80; // 2
    rom[9'h029] = 30'h00003F00; // 2
    rom[9'h02A] = 30'h0000BC00; // 2
    rom[9'h02B] = 30'h0002F800; // 2
    rom[9'h02C] = 30'h000BE000; // 2
    rom[9'h02D] = 30'h002F8000; // 2
    rom[9'h02E] = 30'h00BF1560; // 2
    rom[9'h02F] = 30'h01FFFFF4; // 2
    rom[9'h162] = 30'h01FFFFF4; // 2
    rom[9'h030] = 30'h001FFD00; // 3
    rom[9'h031] = 30'h00FFFF80; // 3
    rom[9'h032] = 30'h00F80FD0; // 3
    rom[9'h033] = 30'h001003E0; // 3
    rom[9'h034] = 30'h000003E0; // 3
    rom[9'h035] = 30'h000003D0; // 3
    rom[9'h036] = 30'h00000FC0; // 3
    rom[9'h037] = 30'h0007FE00; // 3
    rom[9'h038] = 30'h0007FD00; // 3
    rom[9'h039] = 30'h00016FC0; // 3
    rom[9'h03A] = 30'h000003F0; // 3
    rom[9'h03B] = 30'h000002F0; // 3
    rom[9'h03C] = 30'h000001F0; // 3
    rom[9'h03D] = 30'h008003F0; // 3
    rom[9'h03E] = 30'h02F40BE0; // 3
    rom[9'h03F] = 30'h00FFFFC0; // 3
    rom[9'h163] = 30'h002FFE00; // 3
    rom[9'h040] = 30'h00001F80; // 4
    rom[9'h041] = 30'h00003FC0; // 4
    rom[9'h042] = 30'h0000FF80; // 4
    rom[9'h043] = 30'h0001FB80; // 4
    rom[9'h044] = 30'h0003CB80; // 4
    rom[9'h045] = 30'h000BCF80; // 4
    rom[9'h046] = 30'h001F0F80; // 4
    rom[9'h047] = 30'h003E0F80; // 4
    rom[9'h048] = 30'h00BC0F80; // 4
    rom[9'h049] = 30'h00F00B80; // 4
    rom[9'h04A] = 30'h03FAAFE8; // 4
    rom[9'h04B] = 30'h03FFFFFC; // 4
    rom[9'h04C] = 30'h01555FD4; // 4
    rom[9'h04D] = 30'h00000B80; // 4
    rom[9'h04E] = 30'h00000F80; // 4
    rom[9'h04F] = 30'h00000FC0; // 4
    rom[9'h164] = 30'h00000B80; // 4
    rom[9'h050] = 30'h003FFFD0; // 5
    rom[9'h051] = 30'h003FFFE0; // 5
    rom[9'h052] = 30'h003E6590; // 5
    rom[9'h053] = 30'h003C0000; // 5
    rom[9'h054] = 30'h003C0000; // 5
    rom[9'h055] = 30'h003C0000; // 5
    rom[9'h056] = 30'h007DF900; // 5
    rom[9'h057] = 30'h007FFF80; // 5
    rom[9'h058] = 30'h003C0FE0; // 5
    rom[9'h059] = 30'h000003F0; // 5
    rom[9'h05A] = 30'h000002F0; // 5
    rom[9'h05B] = 30'h000001F0; // 5
    rom[9'h05C] = 30'h000001F0; // 5
    rom[9'h05D] = 30'h008003F0; // 5
    rom[9'h05E] = 30'h02F40FD0; // 5
    rom[9'h05F] = 30'h01FFFF80; // 5
    rom[9'h165] = 30'h002FFD00; // 5
    rom[9'h060] = 30'h0002FF80; // 6
    rom[9'h061] = 30'h000FFFF0; // 6
    rom[9'h062] = 30'h002F81E0; // 6
    rom[9'h063] = 30'h003E0000; // 6
    rom[9'h064] = 30'h00BC0000; // 6
    rom[9'h065] = 30'h00F80000; // 6
    rom[9'h066] = 30'h00F41400; // 6
    rom[9'h067] = 30'h00F2FF80; // 6
    rom[9'h068] = 30'h00FF9FE0; // 6
    rom[9'h069] = 30'h00FC02F0; // 6
    rom[9'h06A] = 30'h00F000F4; // 6
    rom[9'h06B] = 30'h00F400F8; // 6
    rom[9'h06C] = 30'h00F800F4; // 6
    rom[9'h06D] = 30'h007C00F0; // 6
    rom[9'h06E] = 30'h003F03F0; // 6
    rom[9'h06F] = 30'h000FFFC0; // 6
    rom[9'h166] = 30'h0003FF00; // 6
    rom[9'h070] = 30'h00FFFFF4; // 7
    rom[9'h071] = 30'h01FFFFF4; // 7
    rom[9'h072] = 30'h009567F0; // 7
    rom[9'h073] = 30'h000003C0; // 7
    rom[9'h074] = 30'h00000F80; // 7
    rom[9'h075] = 30'h00001F00; // 7
    rom[9'h076] = 30'h00003E00; // 7
    rom[9'h077] = 30'h00007C00; // 7
    rom[9'h078] = 30'h0000BC00; // 7
    rom[9'h079] = 30'h0000F400; // 7
    rom[9'h07A] = 30'h0000F000; // 7
    rom[9'h07B] = 30'h0001F000; // 7
    rom[9'h07C] = 30'h0002F000; // 7
    rom[9'h07D] = 30'h0003F000; // 7
    rom[9'h07E] = 30'h0003F000; // 7
    rom[9'h07F] = 30'h0003F000; // 7
    rom[9'h167] = 30'h0003E000; // 7
    rom[9'h080] = 30'h000BFE00; // 8
    rom[9'h081] = 30'h002FFFC0; // 8
    rom[9'h082] = 30'h003D03D0; // 8
    rom[9'h083] = 30'h00BC02F0; // 8
    rom[9'h084] = 30'h00BC01F0; // 8
    rom[9'h085] = 30'h007C02E0; // 8
    rom[9'h086] = 30'h003F03C0; // 8
    rom[9'h087] = 30'h000FEF40; // 8
    rom[9'h088] = 30'h000BFF00; // 8
    rom[9'h089] = 30'h003C2FC0; // 8
    rom[9'h08A] = 30'h00F803F0; // 8
    rom[9'h08B] = 30'h00F001F0; // 8
    rom[9'h08C] = 30'h01F000F4; // 8
    rom[9'h08D] = 30'h00F000F4; // 8
    rom[9'h08E] = 30'h00FC03F0; // 8
    rom[9'h08F] = 30'h003FFFD0; // 8
    rom[9'h168] = 30'h000BFE00; // 8
    rom[9'h090] = 30'h000BFC00; // 9
    rom[9'h091] = 30'h003FFF00; // 9
    rom[9'h092] = 30'h00FC0FC0; // 9
    rom[9'h093] = 30'h00F403E0; // 9
    rom[9'h094] = 30'h01F002F0; // 9
    rom[9'h095] = 30'h01F001F0; // 9
    rom[9'h096] = 30'h01F000F0; // 9
    rom[9'h097] = 30'h00F403F0; // 9
    rom[9'h098] = 30'h00FD0FF0; // 9
    rom[9'h099] = 30'h003FFDF0; // 9
    rom[9'h09A] = 30'h0007E0F0; // 9
    rom[9'h09B] = 30'h000002F0; // 9
    rom[9'h09C] = 30'h000003E0; // 9
    rom[9'h09D] = 30'h000007C0; // 9
    rom[9'h09E] = 30'h00741FC0; // 9
    rom[9'h09F] = 30'h00FFFF00; // 9
    rom[9'h169] = 30'h002FF800; // 9
    rom[9'h0A5] = 30'h0001F400; // :
    rom[9'h0A6] = 30'h0003FC00; // :
    rom[9'h0A7] = 30'h0002F400; // :
    rom[9'h0A8] = 30'h00005000; // :
    rom[9'h0AD] = 30'h00009000; // :
    rom[9'h0AE] = 30'h0002F800; // :
    rom[9'h0AF] = 30'h0003FC00; // :
    rom[9'h16A] = 30'h0001F000; // :
    rom[9'h0B0] = 30'h01FFF900; // B
    rom[9'h0B1] = 30'h01FFFFD0; // B
    rom[9'h0B2] = 30'h01F45BF0; // B
    rom[9'h0B3] = 30'h01F000F8; // B
    rom[9'h0B4] = 30'h01F400F8; // B
    rom[9'h0B5] = 30'h01F000F4; // B
    rom[9'h0B6] = 30'h01F003F0; // B
    rom[9'h0B7] = 30'h01FFFF80; // B
    rom[9'h0B8] = 30'h01FFFFE0; // B
    rom[9'h0B9] = 30'h01F001FC; // B
    rom[9'h0BA] = 30'h01F0003D; // B
    rom[9'h0BB] = 30'h01F4003E; // B
    rom[9'h0BC] = 30'h01F4003E; // B
    rom[9'h0BD] = 30'h01F000BD; // B
    rom[9'h0BE] = 30'h01F457FC; // B
    rom[9'h0BF] = 30'h01FFFFF0; // B
    rom[9'h16B] = 30'h01FFFA00; // B
    rom[9'h0C0] = 30'h01FFFA00; // R
    rom[9'h0C1] = 30'h01FFFFE0; // R
    rom[9'h0C2] = 30'h01F95BF4; // R
    rom[9'h0C3] = 30'h01F000FC; // R
    rom[9'h0C4] = 30'h01F400BC; // R
    rom[9'h0C5] = 30'h01F400BC; // R
    rom[9'h0C6] = 30'h01F400FC; // R
    rom[9'h0C7] = 30'h01F002F8; // R
    rom[9'h0C8] = 30'h01FFFFF0; // R
    rom[9'h0C9] = 30'h01FFFF80; // R
    rom[9'h0CA] = 30'h01F43F00; // R
    rom[9'h0CB] = 30'h01F00F80; // R
    rom[9'h0CC] = 30'h01F40FC0; // R
    rom[9'h0CD] = 30'h01F403F0; // R
    rom[9'h0CE] = 30'h01F402F4; // R
    rom[9'h0CF] = 30'h01F400FC; // R
    rom[9'h16C] = 30'h01F4007D; // R
    rom[9'h0D0] = 30'h0002F000; // I
    rom[9'h0D1] = 30'h0002F000; // I
    rom[9'h0D2] = 30'h0002F000; // I
    rom[9'h0D3] = 30'h0002F000; // I
    rom[9'h0D4] = 30'h0002F000; // I
    rom[9'h0D5] = 30'h0002F000; // I
    rom[9'h0D6] = 30'h0002F000; // I
    rom[9'h0D7] = 30'h0002F000; // I
    rom[9'h0D8] = 30'h0002F000; // I
    rom[9'h0D9] = 30'h0002F000; // I
    rom[9'h0DA] = 30'h0002F000; // I
    rom[9'h0DB] = 30'h0002F000; // I
    rom[9'h0DC] = 30'h0002F000; // I
    rom[9'h0DD] = 30'h0002F000; // I
    rom[9'h0DE] = 30'h0002F000; // I
    rom[9'h0DF] = 30'h0002F000; // I
    rom[9'h16D] = 30'h0002F000; // I
    rom[9'h0E0] = 30'h0002FF80; // C
    rom[9'h0E1] = 30'h001FFFF8; // C
    rom[9'h0E2] = 30'h003F81F8; // C
    rom[9'h0E3] = 30'h00FC0010; // C
    rom[9'h0E4] = 30'h02F40000; // C
    rom[9'h0E5] = 30'h03F00000; // C
    rom[9'h0E6] = 30'h03E00000; // C
    rom[9'h0E7] = 30'h03E00000; // C
    rom[9'h0E8] = 30'h03E00000; // C
    rom[9'h0E9] = 30'h03E00000; // C
    rom[9'h0EA] = 30'h03E00000; // C
    rom[9'h0EB] = 30'h03F00000; // C
    rom[9'h0EC] = 30'h02F40000; // C
    rom[9'h0ED] = 30'h00FC0024; // C
    rom[9'h0EE] = 30'h007F81FC; // C
    rom[9'h0EF] = 30'h001FFFF8; // C
    rom[9'h16E] = 30'h0002FFC0; // C
    rom[9'h0F0] = 30'h001FFE00; // O
    rom[9'h0F1] = 30'h00BFFFD0; // O
    rom[9'h0F2] = 30'h02FD0BF4; // O
    rom[9'h0F3] = 30'h03F000FC; // O
    rom[9'h0F4] = 30'h0FC000BD; // O
    rom[9'h0F5] = 30'h0FC0003F; // O
    rom[9'h0F6] = 30'h0F80003F; // O
    rom[9'h0F7] = 30'h1F40002F; // O
    rom[9'h0F8] = 30'h1F40002F; // O
    rom[9'h0F9] = 30'h1F40002F; // O
    rom[9'h0FA] = 30'h0F80003F; // O
    rom[9'h0FB] = 30'h0FC0003F; // O
    rom[9'h0FC] = 30'h0BC000BD; // O
    rom[9'h0FD] = 30'h03F000FC; // O
    rom[9'h0FE] = 30'h02FD0BF0; // O
    rom[9'h0FF] = 30'h00BFFFD0; // O
    rom[9'h16F] = 30'h001FFE00; // O
    rom[9'h100] = 30'h03E0007C; // N
    rom[9'h101] = 30'h03F4007C; // N
    rom[9'h102] = 30'h03FC007C; // N
    rom[9'h103] = 30'h03FD007C; // N
    rom[9'h104] = 30'h03DF007C; // N
    rom[9'h105] = 30'h03CF807C; // N
    rom[9'h106] = 30'h03C3C07C; // N
    rom[9'h107] = 30'h03D3F07C; // N
    rom[9'h108] = 30'h03D0F07C; // N
    rom[9'h109] = 30'h03D0FC7C; // N
    rom[9'h10A] = 30'h03D03C3C; // N
    rom[9'h10B] = 30'h03D02F3C; // N
    rom[9'h10C] = 30'h03D00F7C; // N
    rom[9'h10D] = 30'h03D007FC; // N
    rom[9'h10E] = 30'h03D003FC; // N
    rom[9'h10F] = 30'h03D001FC; // N
    rom[9'h170] = 30'h03D000BC; // N
    rom[9'h110] = 30'h0BC0003E; // V
    rom[9'h111] = 30'h07D0007D; // V
    rom[9'h112] = 30'h03E000BC; // V
    rom[9'h113] = 30'h03F000F8; // V
    rom[9'h114] = 30'h02F000F4; // V
    rom[9'h115] = 30'h00F802F0; // V
    rom[9'h116] = 30'h00FC03E0; // V
    rom[9'h117] = 30'h00BC03D0; // V
    rom[9'h118] = 30'h003D07C0; // V
    rom[9'h119] = 30'h003E0BC0; // V
    rom[9'h11A] = 30'h002F0F40; // V
    rom[9'h11B] = 30'h000F0F00; // V
    rom[9'h11C] = 30'h000F5F00; // V
    rom[9'h11D] = 30'h000BAE00; // V
    rom[9'h11E] = 30'h0007FC00; // V
    rom[9'h11F] = 30'h0003FC00; // V
    rom[9'h171] = 30'h0002F800; // V
    rom[9'h120] = 30'h003D0000; // L
    rom[9'h121] = 30'h003D0000; // L
    rom[9'h122] = 30'h003D0000; // L
    rom[9'h123] = 30'h003D0000; // L
    rom[9'h124] = 30'h003D0000; // L
    rom[9'h125] = 30'h003D0000; // L
    rom[9'h126] = 30'h003D0000; // L
    rom[9'h127] = 30'h003D0000; // L
    rom[9'h128] = 30'h003D0000; // L
    rom[9'h129] = 30'h003D0000; // L
    rom[9'h12A] = 30'h003D0000; // L
    rom[9'h12B] = 30'h003D0000; // L
    rom[9'h12C] = 30'h003D0000; // L
    rom[9'h12D] = 30'h003D0000; // L
    rom[9'h12E] = 30'h003E5564; // L
    rom[9'h12F] = 30'h003FFFF8; // L
    rom[9'h172] = 30'h003FFFF4; // L
    rom[9'h130] = 30'h00BFFFF0; // E
    rom[9'h131] = 30'h00BFFFF4; // E
    rom[9'h132] = 30'h00BD6560; // E
    rom[9'h133] = 30'h00BC0000; // E
    rom[9'h134] = 30'h00BC0000; // E
    rom[9'h135] = 30'h00BC0000; // E
    rom[9'h136] = 30'h00BC0000; // E
    rom[9'h137] = 30'h00BFFFC0; // E
    rom[9'h138] = 30'h00BFFFC0; // E
    rom[9'h139] = 30'h00BC0040; // E
    rom[9'h13A] = 30'h00BC0000; // E
    rom[9'h13B] = 30'h00BC0000; // E
    rom[9'h13C] = 30'h00BC0000; // E
    rom[9'h13D] = 30'h00BC0000; // E
    rom[9'h13E] = 30'h00BD5564; // E
    rom[9'h13F] = 30'h00BFFFF8; // E
    rom[9'h173] = 30'h00BFFFF4; // E
    rom[9'h140] = 30'h0007FF40; // S
    rom[9'h141] = 30'h003FFFF0; // S
    rom[9'h142] = 30'h00BF02F0; // S
    rom[9'h143] = 30'h00FC0040; // S
    rom[9'h144] = 30'h00F80000; // S
    rom[9'h145] = 30'h00FC0000; // S
    rom[9'h146] = 30'h00BF8000; // S
    rom[9'h147] = 30'h002FF800; // S
    rom[9'h148] = 30'h0007FFC0; // S
    rom[9'h149] = 30'h00007FF0; // S
    rom[9'h14A] = 30'h000003F8; // S
    rom[9'h14B] = 30'h000000FC; // S
    rom[9'h14C] = 30'h000000BC; // S
    rom[9'h14D] = 30'h00E000FC; // S
    rom[9'h14E] = 30'h02FD07F4; // S
    rom[9'h14F] = 30'h00FFFFE0; // S
    rom[9'h174] = 30'h000BFF40; // S
    rom[9'h154] = 30'h00E401B0; // x
    rom[9'h155] = 30'h00FC03E0; // x
    rom[9'h156] = 30'h003F0BC0; // x
    rom[9'h157] = 30'h001F0F40; // x
    rom[9'h158] = 30'h000FAF00; // x
    rom[9'h159] = 30'h0003FC00; // x
    rom[9'h15A] = 30'h0003F800; // x
    rom[9'h15B] = 30'h0007FC00; // x
    rom[9'h15C] = 30'h000F3F00; // x
    rom[9'h15D] = 30'h002F1F40; // x
    rom[9'h15E] = 30'h003C0FC0; // x
    rom[9'h15F] = 30'h00FC03F0; // x
    rom[9'h175] = 30'h01F001F0; // x
end
always @(posedge I_clk) O_row <= rom[I_addr];
endmodule
