`timescale 1ns/1ps

// Low-resource vehicle danger overlay.  The existing full-screen directional
// border stays active on every picture. Picture 4 additionally places four
// car-relative warning cards in the free road areas of its TF-card image.
//
// The four switch inputs may be asynchronous to the pixel clock. They are
// synchronized here and committed only at a video-frame boundary, so a switch
// change can never alter only part of a displayed frame.  RGB is otherwise a
// purely combinational pass-through: this module adds no pixel latency and
// therefore needs no matching delay on VS/DE.
module vehicle_hazard_overlay #(
    parameter integer H_ACTIVE        = 640,
    parameter integer V_ACTIVE        = 480,
    parameter integer BORDER_WIDTH    = 12,
    // At about 60 frames/s, bits 3 and 4 give approximately 3.7 Hz and
    // 1.9 Hz full flashing cycles respectively.
    parameter integer FRONT_FLASH_BIT = 3,
    parameter integer SIDE_FLASH_BIT  = 4,
    parameter [23:0] FRONT_BRIGHT     = 24'hFF1838,
    parameter [23:0] FRONT_DIM        = 24'h600008,
    parameter [23:0] LEFT_BRIGHT      = 24'hFF6A00,
    parameter [23:0] LEFT_DIM         = 24'h682000,
    parameter [23:0] RIGHT_BRIGHT     = 24'hFFD000,
    parameter [23:0] RIGHT_DIM        = 24'h685000
)(
    input  wire        I_clk,
    input  wire        I_rst,
    input  wire        I_vs,
    input  wire        I_de,
    input  wire [23:0] I_rgb,
    input  wire        I_warning_page,
    input  wire        I_hazard_front,
    input  wire        I_hazard_left,
    input  wire        I_hazard_right,
    input  wire        I_hazard_rear,
    output wire [23:0] O_rgb
);

// Bit order is front, left, right, rear. Keeping the vector together makes the
// frame-boundary update atomic after the two flip-flop synchronizer.
wire [3:0] hazard_async = {I_hazard_front,
                           I_hazard_left,
                           I_hazard_right, I_hazard_rear};
reg  [3:0] hazard_meta;
reg  [3:0] hazard_sync;
reg  [3:0] hazard_frame;
reg        warning_page_frame;

reg        vs_d;
reg        de_d;
reg        active_seen;
reg [10:0] pixel_x;
reg [9:0]  pixel_y;
reg [7:0]  flash_frame_count;

wire frame_start = I_vs & ~vs_d;
wire line_start  = I_de & ~de_d;
wire any_hazard = |hazard_frame;

// Look ahead by one raster position for the synchronous font ROM. Its row
// and the coordinate registers then describe the same output pixel, without
// introducing a delay in RGB/DE/VS.
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
        hazard_meta      <= 4'b0000;
        hazard_sync      <= 4'b0000;
        hazard_frame     <= 4'b0000;
        warning_page_frame <= 1'b0;
        vs_d             <= 1'b0;
        de_d             <= 1'b0;
        active_seen      <= 1'b0;
        pixel_x          <= 11'd0;
        pixel_y          <= 10'd0;
        flash_frame_count <= 8'd0;
    end else begin
        hazard_meta <= hazard_async;
        hazard_sync <= hazard_meta;
        vs_d        <= I_vs;
        de_d        <= I_de;
        pixel_x     <= next_x;
        pixel_y     <= next_y;
        active_seen <= next_seen;

        if (frame_start) begin
            // Restart in the bright phase whenever the active danger set
            // changes.  A newly asserted warning is therefore visible at
            // once rather than possibly beginning in the dim phase.
            if (hazard_sync != hazard_frame)
                flash_frame_count <= 8'd0;
            else if (any_hazard)
                flash_frame_count <= flash_frame_count + 8'd1;
            else
                flash_frame_count <= 8'd0;

            hazard_frame <= hazard_sync;
            warning_page_frame <= I_warning_page;
        end
    end
end

// A front warning raises the flash rate for every simultaneously visible
// direction.  It does not suppress either side warning.
wire flash_on = (hazard_frame[3] || hazard_frame[0]) ?
                ~flash_frame_count[FRONT_FLASH_BIT] :
                ~flash_frame_count[SIDE_FLASH_BIT];

wire front_hit = I_de && hazard_frame[3] &&
                 (pixel_y < BORDER_WIDTH);
wire left_hit  = I_de && hazard_frame[2] &&
                 (pixel_x < BORDER_WIDTH);
wire right_hit = I_de && hazard_frame[1] &&
                 (pixel_x >= H_ACTIVE - BORDER_WIDTH);
wire rear_hit = I_de && hazard_frame[0] &&
                (pixel_y >= V_ACTIVE - BORDER_WIDTH);

wire [23:0] front_color = flash_on ? FRONT_BRIGHT : FRONT_DIM;
wire [23:0] left_color  = flash_on ? LEFT_BRIGHT  : LEFT_DIM;
wire [23:0] right_color = flash_on ? RIGHT_BRIGHT : RIGHT_DIM;

// Four identical 192x60 cards are deliberately clear of the central car in
// the 640x480 warning background.  A 4-pixel red outline and opaque wine-red
// face keep the text legible over both bright and dark road imagery.  The
// entire card blinks; the existing outer border continues in both phases.
wire front_card = warning_page_frame && I_de && hazard_frame[3] &&
                  pixel_x >= 11'd224 && pixel_x < 11'd416 &&
                  pixel_y >= 10'd68  && pixel_y < 10'd128;
wire left_card  = warning_page_frame && I_de && hazard_frame[2] &&
                  pixel_x >= 11'd16  && pixel_x < 11'd208 &&
                  pixel_y >= 10'd202 && pixel_y < 10'd262;
wire right_card = warning_page_frame && I_de && hazard_frame[1] &&
                  pixel_x >= 11'd432 && pixel_x < 11'd624 &&
                  pixel_y >= 10'd202 && pixel_y < 10'd262;
wire rear_card = warning_page_frame && I_de && hazard_frame[0] &&
                 pixel_x >= 11'd224 && pixel_x < 11'd416 &&
                 pixel_y >= 10'd394 && pixel_y < 10'd454;
wire center_card = front_card || rear_card;
wire card_hit = flash_on && (front_card || left_card || right_card || rear_card);
wire card_edge = card_hit &&
    (pixel_x <  (center_card ? 11'd228 : left_card ? 11'd20 : 11'd436) ||
     pixel_x >= (center_card ? 11'd412 : left_card ? 11'd204 : 11'd620) ||
     pixel_y <  (front_card ? 10'd72 : rear_card ? 10'd398 : 10'd206) ||
     pixel_y >= (front_card ? 10'd124 : rear_card ? 10'd450 : 10'd258));

// Every card shows the same five-character message, 注意安全！.  The four
// Chinese glyphs use the same Noto Sans SC Medium font source as the rest of
// the on-screen UI; a procedural exclamation mark avoids another ROM glyph.
// Draw actual 32x32 antialiased glyphs instead of enlarging a smaller bitmap.
// Four 8-pixel quarters pack each row into 16-bit BRAM words; all four
// non-overlapping cards share the same read port.
reg next_text_valid;
reg [7:0] next_text_dx;
reg [4:0] next_glyph_y;
reg [2:0] next_text_char;
reg [4:0] next_glyph_col;
always @(*) begin
    next_text_valid = 1'b0; next_text_dx = 8'd0; next_glyph_y = 5'd0;
    if (next_x >= 11'd240 && next_x < 11'd400 &&
        next_y >= 10'd82 && next_y < 10'd114) begin
        next_text_valid = 1'b1;
        next_text_dx = next_x - 11'd240; next_glyph_y = next_y - 10'd82;
    end else if (next_x >= 11'd32 && next_x < 11'd192 &&
                 next_y >= 10'd216 && next_y < 10'd248) begin
        next_text_valid = 1'b1;
        next_text_dx = next_x - 11'd32; next_glyph_y = next_y - 10'd216;
    end else if (next_x >= 11'd448 && next_x < 11'd608 &&
                 next_y >= 10'd216 && next_y < 10'd248) begin
        next_text_valid = 1'b1;
        next_text_dx = next_x - 11'd448; next_glyph_y = next_y - 10'd216;
    end else if (next_x >= 11'd240 && next_x < 11'd400 &&
                 next_y >= 10'd408 && next_y < 10'd440) begin
        next_text_valid = 1'b1;
        next_text_dx = next_x - 11'd240; next_glyph_y = next_y - 10'd408;
    end
    next_text_char = next_text_dx[7:5];
    next_glyph_col = next_text_dx[4:0];
end
reg text_valid;
reg [2:0] text_char;
reg [4:0] glyph_col, glyph_row_index;
reg [2:0] quarter_col;
always @(posedge I_clk or posedge I_rst) begin
    if (I_rst) begin
        text_valid <= 1'b0; text_char <= 3'd0;
        glyph_col <= 5'd0; glyph_row_index <= 5'd0; quarter_col <= 3'd0;
    end else begin
        text_valid <= next_text_valid; text_char <= next_text_char;
        glyph_col <= next_glyph_col; glyph_row_index <= next_glyph_y;
        quarter_col <= next_glyph_col[2:0];
    end
end
wire [15:0] glyph_row_bits;
vehicle_warning_glyph_rom u_warning_font (
    .I_clk(I_clk),
    .I_addr({next_text_char[1:0],next_glyph_col[4:3],next_glyph_y}),
    .O_row(glyph_row_bits)
);
wire [1:0] glyph_coverage = glyph_row_bits[(7-quarter_col)*2 +: 2];
wire exclamation = (text_char == 3'd4) &&
                   (glyph_col >= 5'd15 && glyph_col <= 5'd16) &&
                   ((glyph_row_index >= 5'd4 && glyph_row_index <= 5'd23) ||
                    (glyph_row_index >= 5'd27 && glyph_row_index <= 5'd29));
wire text_on = card_hit && text_valid &&
               ((text_char < 3'd4 && glyph_coverage != 2'd0) ||
                exclamation);
wire [23:0] text_color = (glyph_coverage == 2'd1 && !exclamation) ?
                         24'hB9D4D8 :
                         (glyph_coverage == 2'd2 && !exclamation) ?
                         24'hE2F0F2 : 24'hFFFFFF;

// Front has priority only at the two overlapping top corners.  All three
// complete border segments remain visible when every danger input is active.
// Outside active video (or with no warning), the path is strictly transparent.
assign O_rgb = front_hit ? front_color :
               left_hit  ? left_color  :
               right_hit ? right_color :
               rear_hit  ? front_color :
               card_edge ? 24'hFF243C :
               text_on   ? text_color :
               card_hit  ? 24'h531A23 : I_rgb;

endmodule

// Noto Sans SC Medium, 32x32, two-bit antialias coverage.
// 512x16 quarter-row packing shares one BRAM9K across four warning cards.
module vehicle_warning_glyph_rom (
    input wire I_clk,
    input wire [8:0] I_addr, // {glyph[1:0], quarter[1:0], row[4:0]}
    output reg [15:0] O_row
);
reg [15:0] rom [0:511]; /* fehdl force_ram=1, ram_style="bram" */
integer i;
initial begin
    for (i=0; i<512; i=i+1) rom[i]=16'd0;
    rom[9'h004] = 16'h0029; // 注
    rom[9'h005] = 16'h00BF; // 注
    rom[9'h006] = 16'h006F; // 注
    rom[9'h007] = 16'h000B; // 注
    rom[9'h008] = 16'h0001; // 注
    rom[9'h00C] = 16'h0140; // 注
    rom[9'h00D] = 16'h07F4; // 注
    rom[9'h00E] = 16'h07FF; // 注
    rom[9'h00F] = 16'h00BF; // 注
    rom[9'h010] = 16'h001B; // 注
    rom[9'h011] = 16'h0001; // 注
    rom[9'h015] = 16'h0001; // 注
    rom[9'h016] = 16'h0002; // 注
    rom[9'h017] = 16'h0007; // 注
    rom[9'h018] = 16'h000F; // 注
    rom[9'h019] = 16'h002F; // 注
    rom[9'h01A] = 16'h007F; // 注
    rom[9'h01B] = 16'h00BE; // 注
    rom[9'h01C] = 16'h01FC; // 注
    rom[9'h01D] = 16'h02F8; // 注
    rom[9'h01E] = 16'h0060; // 注
    rom[9'h025] = 16'h8000; // 注
    rom[9'h026] = 16'hF400; // 注
    rom[9'h027] = 16'hF800; // 注
    rom[9'h028] = 16'hB400; // 注
    rom[9'h029] = 16'h12AA; // 注
    rom[9'h02A] = 16'h02FF; // 注
    rom[9'h02B] = 16'h02FF; // 注
    rom[9'h02E] = 16'h4000; // 注
    rom[9'h02F] = 16'hD000; // 注
    rom[9'h030] = 16'h8000; // 注
    rom[9'h032] = 16'h00BF; // 注
    rom[9'h033] = 16'h40BF; // 注
    rom[9'h034] = 16'hA06A; // 注
    rom[9'h035] = 16'hF800; // 注
    rom[9'h036] = 16'hF400; // 注
    rom[9'h037] = 16'hE000; // 注
    rom[9'h038] = 16'hD000; // 注
    rom[9'h039] = 16'h8000; // 注
    rom[9'h03A] = 16'h4000; // 注
    rom[9'h03B] = 16'h0555; // 注
    rom[9'h03C] = 16'h0BFF; // 注
    rom[9'h03D] = 16'h0BFF; // 注
    rom[9'h03E] = 16'h06AA; // 注
    rom[9'h043] = 16'h0100; // 注
    rom[9'h044] = 16'h1F80; // 注
    rom[9'h045] = 16'h0FD0; // 注
    rom[9'h046] = 16'h0BE0; // 注
    rom[9'h047] = 16'h03F4; // 注
    rom[9'h048] = 16'h02E4; // 注
    rom[9'h049] = 16'hAAAA; // 注
    rom[9'h04A] = 16'hFFFF; // 注
    rom[9'h04B] = 16'hFFFF; // 注
    rom[9'h04C] = 16'h07E0; // 注
    rom[9'h04D] = 16'h07E0; // 注
    rom[9'h04E] = 16'h07E0; // 注
    rom[9'h04F] = 16'h07E0; // 注
    rom[9'h050] = 16'h07E0; // 注
    rom[9'h051] = 16'h07E0; // 注
    rom[9'h052] = 16'hFFFF; // 注
    rom[9'h053] = 16'hFFFF; // 注
    rom[9'h054] = 16'hABFA; // 注
    rom[9'h055] = 16'h07E0; // 注
    rom[9'h056] = 16'h07E0; // 注
    rom[9'h057] = 16'h07E0; // 注
    rom[9'h058] = 16'h07E0; // 注
    rom[9'h059] = 16'h07E0; // 注
    rom[9'h05A] = 16'h07E0; // 注
    rom[9'h05B] = 16'h57E5; // 注
    rom[9'h05C] = 16'hFFFF; // 注
    rom[9'h05D] = 16'hFFFF; // 注
    rom[9'h05E] = 16'hAAAA; // 注
    rom[9'h069] = 16'hAA80; // 注
    rom[9'h06A] = 16'hFFC0; // 注
    rom[9'h06B] = 16'hFFC0; // 注
    rom[9'h072] = 16'hFF00; // 注
    rom[9'h073] = 16'hFF00; // 注
    rom[9'h074] = 16'hAA00; // 注
    rom[9'h07B] = 16'h5550; // 注
    rom[9'h07C] = 16'hFFE0; // 注
    rom[9'h07D] = 16'hFFF0; // 注
    rom[9'h07E] = 16'hAA90; // 注
    rom[9'h085] = 16'h006A; // 意
    rom[9'h086] = 16'h00BF; // 意
    rom[9'h087] = 16'h006A; // 意
    rom[9'h08A] = 16'h01AA; // 意
    rom[9'h08B] = 16'h03FF; // 意
    rom[9'h08C] = 16'h02AA; // 意
    rom[9'h08E] = 16'h0007; // 意
    rom[9'h08F] = 16'h0007; // 意
    rom[9'h090] = 16'h0007; // 意
    rom[9'h091] = 16'h0007; // 意
    rom[9'h092] = 16'h0007; // 意
    rom[9'h093] = 16'h0007; // 意
    rom[9'h094] = 16'h0007; // 意
    rom[9'h095] = 16'h0007; // 意
    rom[9'h096] = 16'h0007; // 意
    rom[9'h098] = 16'h0009; // 意
    rom[9'h099] = 16'h001F; // 意
    rom[9'h09A] = 16'h003F; // 意
    rom[9'h09B] = 16'h00BE; // 意
    rom[9'h09C] = 16'h02F8; // 意
    rom[9'h09D] = 16'h03F4; // 意
    rom[9'h09E] = 16'h0090; // 意
    rom[9'h0A3] = 16'h0006; // 意
    rom[9'h0A4] = 16'h000B; // 意
    rom[9'h0A5] = 16'hAAAB; // 意
    rom[9'h0A6] = 16'hFFFF; // 意
    rom[9'h0A7] = 16'hAFAA; // 意
    rom[9'h0A8] = 16'h2F00; // 意
    rom[9'h0A9] = 16'h2F40; // 意
    rom[9'h0AA] = 16'hAFAA; // 意
    rom[9'h0AB] = 16'hFFFF; // 意
    rom[9'h0AC] = 16'hAAAA; // 意
    rom[9'h0AE] = 16'hFFFF; // 意
    rom[9'h0AF] = 16'hFFFF; // 意
    rom[9'h0B0] = 16'hD000; // 意
    rom[9'h0B1] = 16'hEAAA; // 意
    rom[9'h0B2] = 16'hFFFF; // 意
    rom[9'h0B3] = 16'hE555; // 意
    rom[9'h0B4] = 16'hD000; // 意
    rom[9'h0B5] = 16'hFBFA; // 意
    rom[9'h0B6] = 16'hFFFF; // 意
    rom[9'h0B7] = 16'h002F; // 意
    rom[9'h0B8] = 16'h0A5F; // 意
    rom[9'h0B9] = 16'h5F82; // 意
    rom[9'h0BA] = 16'h1F80; // 意
    rom[9'h0BB] = 16'h1F80; // 意
    rom[9'h0BC] = 16'h1F80; // 意
    rom[9'h0BD] = 16'h0FFF; // 意
    rom[9'h0BE] = 16'h07FF; // 意
    rom[9'h0BF] = 16'h0055; // 意
    rom[9'h0C3] = 16'h8000; // 意
    rom[9'h0C4] = 16'hD000; // 意
    rom[9'h0C5] = 16'hFAAA; // 意
    rom[9'h0C6] = 16'hFFFF; // 意
    rom[9'h0C7] = 16'hAAFA; // 意
    rom[9'h0C8] = 16'h00FC; // 意
    rom[9'h0C9] = 16'h01F8; // 意
    rom[9'h0CA] = 16'hABFA; // 意
    rom[9'h0CB] = 16'hFFFF; // 意
    rom[9'h0CC] = 16'hAAAA; // 意
    rom[9'h0CE] = 16'hFFFF; // 意
    rom[9'h0CF] = 16'hFFFF; // 意
    rom[9'h0D0] = 16'h0007; // 意
    rom[9'h0D1] = 16'hAAAB; // 意
    rom[9'h0D2] = 16'hFFFF; // 意
    rom[9'h0D3] = 16'h555B; // 意
    rom[9'h0D4] = 16'h0007; // 意
    rom[9'h0D5] = 16'hFFEF; // 意
    rom[9'h0D6] = 16'hFFFF; // 意
    rom[9'h0D7] = 16'h8000; // 意
    rom[9'h0D8] = 16'hE401; // 意
    rom[9'h0D9] = 16'hFD02; // 意
    rom[9'h0DA] = 16'h7860; // 意
    rom[9'h0DB] = 16'h10B8; // 意
    rom[9'h0DC] = 16'h01B8; // 意
    rom[9'h0DD] = 16'hFFF8; // 意
    rom[9'h0DE] = 16'hFFE0; // 意
    rom[9'h0DF] = 16'h5540; // 意
    rom[9'h0E5] = 16'hA900; // 意
    rom[9'h0E6] = 16'hFD00; // 意
    rom[9'h0E7] = 16'hA900; // 意
    rom[9'h0EA] = 16'hAA40; // 意
    rom[9'h0EB] = 16'hFFC0; // 意
    rom[9'h0EC] = 16'hAA80; // 意
    rom[9'h0EE] = 16'hE000; // 意
    rom[9'h0EF] = 16'hE000; // 意
    rom[9'h0F0] = 16'hE000; // 意
    rom[9'h0F1] = 16'hE000; // 意
    rom[9'h0F2] = 16'hE000; // 意
    rom[9'h0F3] = 16'hE000; // 意
    rom[9'h0F4] = 16'hE000; // 意
    rom[9'h0F5] = 16'hE000; // 意
    rom[9'h0F6] = 16'hE000; // 意
    rom[9'h0F8] = 16'hA000; // 意
    rom[9'h0F9] = 16'hF800; // 意
    rom[9'h0FA] = 16'hBD00; // 意
    rom[9'h0FB] = 16'h7F00; // 意
    rom[9'h0FC] = 16'h1F80; // 意
    rom[9'h0FD] = 16'h0B80; // 意
    rom[9'h0FE] = 16'h0400; // 意
    rom[9'h106] = 16'h0055; // 安
    rom[9'h107] = 16'h01FF; // 安
    rom[9'h108] = 16'h01FF; // 安
    rom[9'h109] = 16'h01FA; // 安
    rom[9'h10A] = 16'h01F8; // 安
    rom[9'h10B] = 16'h01F8; // 安
    rom[9'h10C] = 16'h01F8; // 安
    rom[9'h10D] = 16'h0054; // 安
    rom[9'h10F] = 16'h02AA; // 安
    rom[9'h110] = 16'h03FF; // 安
    rom[9'h111] = 16'h03FF; // 安
    rom[9'h115] = 16'h0002; // 安
    rom[9'h116] = 16'h0006; // 安
    rom[9'h11C] = 16'h016B; // 安
    rom[9'h11D] = 16'h01FF; // 安
    rom[9'h11E] = 16'h00BE; // 安
    rom[9'h11F] = 16'h0014; // 安
    rom[9'h123] = 16'h0006; // 安
    rom[9'h124] = 16'h002F; // 安
    rom[9'h125] = 16'h001F; // 安
    rom[9'h126] = 16'h555B; // 安
    rom[9'h127] = 16'hFFFF; // 安
    rom[9'h128] = 16'hFFFF; // 安
    rom[9'h129] = 16'hAAAA; // 安
    rom[9'h12A] = 16'h0014; // 安
    rom[9'h12B] = 16'h003F; // 安
    rom[9'h12C] = 16'h00BF; // 安
    rom[9'h12D] = 16'h00FD; // 安
    rom[9'h12E] = 16'h01FC; // 安
    rom[9'h12F] = 16'hABFE; // 安
    rom[9'h130] = 16'hFFFF; // 安
    rom[9'h131] = 16'hFFFF; // 安
    rom[9'h132] = 16'h2F80; // 安
    rom[9'h133] = 16'h7F40; // 安
    rom[9'h134] = 16'hFD00; // 安
    rom[9'h135] = 16'hFE40; // 安
    rom[9'h136] = 16'hFFF9; // 安
    rom[9'h137] = 16'h6FFF; // 安
    rom[9'h138] = 16'h01BF; // 安
    rom[9'h139] = 16'h002F; // 安
    rom[9'h13A] = 16'h01BF; // 安
    rom[9'h13B] = 16'h6FFE; // 安
    rom[9'h13C] = 16'hFFE4; // 安
    rom[9'h13D] = 16'hFE40; // 安
    rom[9'h13E] = 16'h9000; // 安
    rom[9'h144] = 16'h8000; // 安
    rom[9'h145] = 16'hD000; // 安
    rom[9'h146] = 16'hE555; // 安
    rom[9'h147] = 16'hFFFF; // 安
    rom[9'h148] = 16'hFFFF; // 安
    rom[9'h149] = 16'hAAAA; // 安
    rom[9'h14B] = 16'h4000; // 安
    rom[9'h14F] = 16'hAAAA; // 安
    rom[9'h150] = 16'hFFFF; // 安
    rom[9'h151] = 16'hFFFF; // 安
    rom[9'h152] = 16'h00FD; // 安
    rom[9'h153] = 16'h01F8; // 安
    rom[9'h154] = 16'h03F4; // 安
    rom[9'h155] = 16'h0BE0; // 安
    rom[9'h156] = 16'h2FD0; // 安
    rom[9'h157] = 16'hBF40; // 安
    rom[9'h158] = 16'hFF40; // 安
    rom[9'h159] = 16'hFFE4; // 安
    rom[9'h15A] = 16'hEFFE; // 安
    rom[9'h15B] = 16'h06FF; // 安
    rom[9'h15C] = 16'h006F; // 安
    rom[9'h15D] = 16'h0006; // 安
    rom[9'h166] = 16'h5500; // 安
    rom[9'h167] = 16'hFF40; // 安
    rom[9'h168] = 16'hFF40; // 安
    rom[9'h169] = 16'hAF40; // 安
    rom[9'h16A] = 16'h2F40; // 安
    rom[9'h16B] = 16'h2F40; // 安
    rom[9'h16C] = 16'h2F40; // 安
    rom[9'h16D] = 16'h1500; // 安
    rom[9'h16F] = 16'hAA80; // 安
    rom[9'h170] = 16'hFFC0; // 安
    rom[9'h171] = 16'hFFC0; // 安
    rom[9'h17A] = 16'h4000; // 安
    rom[9'h17B] = 16'hE400; // 安
    rom[9'h17C] = 16'hFE40; // 安
    rom[9'h17D] = 16'hFF40; // 安
    rom[9'h17E] = 16'h7D00; // 安
    rom[9'h17F] = 16'h0400; // 安
    rom[9'h18B] = 16'h0002; // 全
    rom[9'h18C] = 16'h001F; // 全
    rom[9'h18D] = 16'h01BF; // 全
    rom[9'h18E] = 16'h0BFF; // 全
    rom[9'h18F] = 16'h07F7; // 全
    rom[9'h190] = 16'h0283; // 全
    rom[9'h195] = 16'h0001; // 全
    rom[9'h196] = 16'h0002; // 全
    rom[9'h197] = 16'h0002; // 全
    rom[9'h19C] = 16'h02FF; // 全
    rom[9'h19D] = 16'h02FF; // 全
    rom[9'h19E] = 16'h01AA; // 全
    rom[9'h1A3] = 16'h0002; // 全
    rom[9'h1A4] = 16'h0007; // 全
    rom[9'h1A5] = 16'h001F; // 全
    rom[9'h1A6] = 16'h003F; // 全
    rom[9'h1A7] = 16'h00BE; // 全
    rom[9'h1A8] = 16'h07F8; // 全
    rom[9'h1A9] = 16'h1FE0; // 全
    rom[9'h1AA] = 16'h7F80; // 全
    rom[9'h1AB] = 16'hFE00; // 全
    rom[9'h1AC] = 16'hF800; // 全
    rom[9'h1AD] = 16'hD000; // 全
    rom[9'h1AE] = 16'h9AAA; // 全
    rom[9'h1AF] = 16'hFFFF; // 全
    rom[9'h1B0] = 16'hFFFF; // 全
    rom[9'h1B1] = 16'h000B; // 全
    rom[9'h1B2] = 16'h000B; // 全
    rom[9'h1B3] = 16'h000B; // 全
    rom[9'h1B4] = 16'h0007; // 全
    rom[9'h1B5] = 16'hAAAB; // 全
    rom[9'h1B6] = 16'hFFFF; // 全
    rom[9'h1B7] = 16'hFFFF; // 全
    rom[9'h1B8] = 16'h000B; // 全
    rom[9'h1B9] = 16'h000B; // 全
    rom[9'h1BA] = 16'h000B; // 全
    rom[9'h1BB] = 16'h000B; // 全
    rom[9'h1BC] = 16'hFFFF; // 全
    rom[9'h1BD] = 16'hFFFF; // 全
    rom[9'h1BE] = 16'hAAAA; // 全
    rom[9'h1C3] = 16'h4000; // 全
    rom[9'h1C4] = 16'hE000; // 全
    rom[9'h1C5] = 16'hF000; // 全
    rom[9'h1C6] = 16'hF800; // 全
    rom[9'h1C7] = 16'hBE00; // 全
    rom[9'h1C8] = 16'h2F90; // 全
    rom[9'h1C9] = 16'h0BF4; // 全
    rom[9'h1CA] = 16'h02FE; // 全
    rom[9'h1CB] = 16'h00BF; // 全
    rom[9'h1CC] = 16'h002F; // 全
    rom[9'h1CD] = 16'h0006; // 全
    rom[9'h1CE] = 16'hAAA6; // 全
    rom[9'h1CF] = 16'hFFFF; // 全
    rom[9'h1D0] = 16'hFFFF; // 全
    rom[9'h1D1] = 16'hE000; // 全
    rom[9'h1D2] = 16'hE000; // 全
    rom[9'h1D3] = 16'hE000; // 全
    rom[9'h1D4] = 16'hD000; // 全
    rom[9'h1D5] = 16'hEAAA; // 全
    rom[9'h1D6] = 16'hFFFF; // 全
    rom[9'h1D7] = 16'hFFFF; // 全
    rom[9'h1D8] = 16'hE000; // 全
    rom[9'h1D9] = 16'hE000; // 全
    rom[9'h1DA] = 16'hE000; // 全
    rom[9'h1DB] = 16'hE000; // 全
    rom[9'h1DC] = 16'hFFFF; // 全
    rom[9'h1DD] = 16'hFFFF; // 全
    rom[9'h1DE] = 16'hAAAA; // 全
    rom[9'h1EB] = 16'h9000; // 全
    rom[9'h1EC] = 16'hF800; // 全
    rom[9'h1ED] = 16'hFF40; // 全
    rom[9'h1EE] = 16'hFFE0; // 全
    rom[9'h1EF] = 16'hEBE0; // 全
    rom[9'h1F0] = 16'hD280; // 全
    rom[9'h1F5] = 16'h8000; // 全
    rom[9'h1F6] = 16'hC000; // 全
    rom[9'h1F7] = 16'hC000; // 全
    rom[9'h1FC] = 16'hFF80; // 全
    rom[9'h1FD] = 16'hFFC0; // 全
    rom[9'h1FE] = 16'hAA40; // 全
end
always @(posedge I_clk) O_row <= rom[I_addr];
endmodule
