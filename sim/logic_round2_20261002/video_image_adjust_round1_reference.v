// Four-level image brightness and contrast processor.
// Levels 0/1/2/3 are displayed as 25/50/75/100.  Brightness is a true
// 25/50/75/100-percent output gain.  Contrast uses level 25 as the natural
// image and progressively expands pixel distance from mid-grey at the upper
// levels, so lowering the setting never overlays a grey veil on the picture.
// RGB and timing are registered together to keep the arithmetic out of the
// downstream OSD pixel critical path.
module video_image_adjust_round1_reference (
    input  wire        I_clk,
    input  wire        I_rst,
    input  wire        I_hs,
    input  wire        I_vs,
    input  wire        I_de,
    input  wire [23:0] I_rgb,
    input  wire [1:0]  I_brightness_level,
    input  wire [1:0]  I_contrast_level,
    output reg         O_hs,
    output reg         O_vs,
    output reg         O_de,
    output reg  [23:0] O_rgb
);

reg [1:0] brightness_meta;
reg [1:0] brightness_sync;
reg [1:0] brightness_stable;
reg [1:0] brightness_frame;
reg [1:0] contrast_meta;
reg [1:0] contrast_sync;
reg [1:0] contrast_stable;
reg [1:0] contrast_frame;
reg       vs_d;

wire frame_start = I_vs & ~vs_d;

always @(posedge I_clk or posedge I_rst) begin
    if (I_rst) begin
        brightness_meta   <= 2'd3;
        brightness_sync   <= 2'd3;
        brightness_stable <= 2'd3;
        brightness_frame  <= 2'd3;
        contrast_meta     <= 2'd0;
        contrast_sync     <= 2'd0;
        contrast_stable   <= 2'd0;
        contrast_frame    <= 2'd0;
        vs_d              <= 1'b0;
        O_hs              <= 1'b0;
        O_vs              <= 1'b0;
        O_de              <= 1'b0;
        O_rgb             <= 24'd0;
    end else begin
        brightness_meta <= I_brightness_level;
        brightness_sync <= brightness_meta;
        if (brightness_sync == brightness_meta)
            brightness_stable <= brightness_sync;

        contrast_meta <= I_contrast_level;
        contrast_sync <= contrast_meta;
        if (contrast_sync == contrast_meta)
            contrast_stable <= contrast_sync;

        vs_d <= I_vs;
        if (frame_start) begin
            brightness_frame <= brightness_stable;
            contrast_frame   <= contrast_stable;
        end

        O_hs  <= I_hs;
        O_vs  <= I_vs;
        O_de  <= I_de;
        O_rgb <= I_de ? {
            adjust_channel(I_rgb[23:16], brightness_frame, contrast_frame),
            adjust_channel(I_rgb[15:8],  brightness_frame, contrast_frame),
            adjust_channel(I_rgb[7:0],   brightness_frame, contrast_frame)
        } : 24'd0;
    end
end

// Contrast is centered on 128.  Level 25 is neutral; levels 50/75/100 add
// 1/4, 1/2 or all of the distance from 128 and saturate at the legal range.
// Brightness then applies 1/4, 1/2, 3/4 or unity gain with rounding.  The
// final two LSBs are held at zero (RGB666 source precision) to prevent dark
// low-order colour codes from alternating on 6-bit/FRC display panels.
// Only shifts and small add/subtract/compare logic are used: no DSP or BRAM.
function [7:0] adjust_channel;
    input [7:0] value;
    input [1:0] brightness;
    input [1:0] contrast;
    reg   [7:0] distance;
    reg   [7:0] contrast_extra;
    reg   [8:0] contrast_sum;
    reg   [7:0] contrasted;
    reg   [9:0] brightness_sum;
    reg   [7:0] brightened;
    begin
        if (value < 8'd128)
            distance = 8'd128 - value;
        else
            distance = value - 8'd128;

        case (contrast)
            2'd0: contrast_extra = 8'd0;
            2'd1: contrast_extra = distance >> 2;
            2'd2: contrast_extra = distance >> 1;
            default: contrast_extra = distance;
        endcase

        if (value < 8'd128) begin
            if (contrast_extra >= value)
                contrasted = 8'd0;
            else
                contrasted = value - contrast_extra;
        end else begin
            contrast_sum = {1'b0, value} + {1'b0, contrast_extra};
            if (contrast_sum[8])
                contrasted = 8'hFF;
            else
                contrasted = contrast_sum[7:0];
        end

        case (brightness)
            2'd0: begin
                brightness_sum = {2'b00, contrasted} + 10'd2;
                brightened = brightness_sum >> 2;
            end
            2'd1: begin
                brightness_sum = {2'b00, contrasted} + 10'd1;
                brightened = brightness_sum >> 1;
            end
            2'd2: begin
                brightness_sum = ({2'b00, contrasted} << 1) +
                                 {2'b00, contrasted} + 10'd2;
                brightened = brightness_sum >> 2;
            end
            default: brightened = contrasted;
        endcase

        adjust_channel = {brightened[7:2], 2'b00};
    end
endfunction

endmodule
