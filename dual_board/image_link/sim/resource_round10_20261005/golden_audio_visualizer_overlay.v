// Compact normal-playback audio visualizer for a 640x480 active video region.
// One transparent row contains: left VU, 16-band spectrum, 16-point waveform,
// and right VU. Analysis values are latched only at a video-frame boundary.
module audio_visualizer_overlay_golden #(
    parameter integer H_ACTIVE = 640,
    parameter integer V_ACTIVE = 480
)(
    input  wire         I_clk,
    input  wire         I_rst,
    input  wire         I_enable,
    input  wire         I_vs,
    input  wire         I_de,
    input  wire [23:0]  I_rgb,
    input  wire [6:0]   I_vu_left_level,
    input  wire [6:0]   I_vu_right_level,
    input  wire [111:0] I_spectrum_levels,
    input  wire [111:0] I_wave_samples,
    input  wire [3:0]   I_volume_level,
    input  wire         I_hazard_front,
    input  wire         I_hazard_left,
    input  wire         I_hazard_right,
    output wire [23:0]  O_rgb
);

localparam [9:0] ROW_TOP       = 10'd316;
localparam [9:0] ROW_BOTTOM    = 10'd388;
localparam [9:0] SPECTRUM_BASE = 10'd382;
localparam [9:0] WAVE_CENTER   = 10'd354;

reg [10:0] pixel_x;
reg [9:0]  pixel_y;
reg        de_d;
reg        vs_d;
reg        active_seen;

reg [6:0]   vu_left_frame;
reg [6:0]   vu_right_frame;
// The per-frame display points live in 16x7 LUT RAMs with combinational
// reads instead of 112-bit registers behind 16:1 selectors.  Lane flags make
// every read return the value the old register arrays held, including the
// zero reset state and the previous-frame view during an update.
reg [6:0]   spectrum_ram     [0:15];
reg [6:0]   wave_pixel_ram   [0:15];
reg [6:0]   wave_update_ram  [0:15];
reg [6:0]   wave_previous_ram[0:15];
reg [15:0]  spectrum_lane_valid;
reg [15:0]  wave_lane_valid;
reg [15:0]  wave_lane_updated;   // lane rewritten since the latest VS
reg [111:0] wave_target_snapshot;
reg signed [6:0] wave_neighbor_left;
reg [111:0] spectrum_target_snapshot;
reg [3:0]   wave_smooth_index;
reg         wave_smooth_busy;
reg [3:0]   wave_write_index;
reg signed [6:0] wave_scaled_target;
reg         wave_scaled_valid;
reg [3:0]   volume_meta;
reg [3:0]   volume_sync;
reg [3:0]   volume_stable;
reg [3:0]   volume_level_frame;
reg [2:0]   hazard_frame;
reg [7:0]   hazard_flash_count;

wire frame_start = I_vs & ~vs_d;
wire line_start  = I_de & ~de_d;

always @(posedge I_clk or posedge I_rst) begin
    if (I_rst) begin
        pixel_x               <= 11'd0;
        pixel_y               <= 10'd0;
        de_d                  <= 1'b0;
        vs_d                  <= 1'b0;
        active_seen           <= 1'b0;
        vu_left_frame         <= 7'd0;
        vu_right_frame        <= 7'd0;
        volume_meta           <= 4'd8;
        volume_sync           <= 4'd8;
        volume_stable         <= 4'd8;
        volume_level_frame    <= 4'd8;
        hazard_frame          <= 3'b000;
        hazard_flash_count    <= 8'd0;
    end else begin
        de_d <= I_de;
        vs_d <= I_vs;

        // UART runs at 50 MHz while drawing runs at 25 MHz.  Commit a
        // multi-bit value only after two consecutive synchronized samples
        // agree, then make it visible at a frame boundary.  This prevents a
        // volume command from splitting one picture into two visual levels.
        volume_meta <= I_volume_level;
        volume_sync <= volume_meta;
        if (volume_sync == volume_meta)
            volume_stable <= volume_sync;

        if (frame_start) begin
            pixel_x               <= 11'd0;
            pixel_y               <= 10'd0;
            active_seen           <= 1'b0;
            vu_left_frame         <= I_vu_left_level;
            vu_right_frame        <= I_vu_right_level;
            volume_level_frame    <= volume_stable;

            // Commit the complete danger set only at VS.  This keeps both
            // VU warning meters coherent for the whole displayed frame.
            if ({I_hazard_front, I_hazard_left, I_hazard_right} !=
                hazard_frame)
                hazard_flash_count <= 8'd0;
            else if (|hazard_frame)
                hazard_flash_count <= hazard_flash_count + 8'd1;
            else
                hazard_flash_count <= 8'd0;
            hazard_frame <= {I_hazard_front,
                             I_hazard_left,
                             I_hazard_right};
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

// The analyser can publish several traces per video frame.  Take one atomic
// snapshot at VS, then reuse a single FIR/slew datapath for the sixteen points
// during vertical blanking.  Sixteen pixel clocks are only about 0.64 us at
// 25 MHz, so the update is complete long before active video while avoiding
// sixteen parallel filter networks.
wire [6:0] update_wave_old = wave_lane_valid[wave_write_index] ?
    wave_update_ram[wave_write_index] : 7'd0;
wire [6:0] next_display_wave = (volume_level_frame == 4'd0) ? 7'd0 :
    smooth_display_sample(update_wave_old, wave_scaled_target);
wire [6:0] next_display_band = scale_unsigned_by_volume(
    spectrum_target_snapshot[6:0],
    volume_level_frame);
wire signed [6:0] spatial_left = (wave_smooth_index == 4'd0) ?
    $signed(wave_target_snapshot[6:0]) : wave_neighbor_left;
wire signed [6:0] spatial_right = (wave_smooth_index == 4'd15) ?
    $signed(wave_target_snapshot[6:0]) : $signed(wave_target_snapshot[13:7]);
// Same lane schedule as the former register-array writes.
wire wave_lane_write = !frame_start && wave_scaled_valid;
wire spectrum_lane_write = !frame_start && wave_smooth_busy;
always @(posedge I_clk) begin
    if (!I_rst && wave_lane_write) begin
        wave_pixel_ram[wave_write_index]    <= next_display_wave;
        wave_update_ram[wave_write_index]   <= next_display_wave;
        // Old value at this lane is exactly its value at the latest VS.
        wave_previous_ram[wave_write_index] <= update_wave_old;
    end
    if (!I_rst && spectrum_lane_write)
        spectrum_ram[wave_smooth_index] <= next_display_band;
end
always @(posedge I_clk or posedge I_rst) begin
    if (I_rst) begin
        spectrum_lane_valid         <= 16'd0;
        wave_lane_valid             <= 16'd0;
        wave_lane_updated           <= 16'd0;
        wave_target_snapshot        <= 112'd0;
        wave_neighbor_left          <= 7'sd0;
        spectrum_target_snapshot    <= 112'd0;
        wave_smooth_index            <= 4'd0;
        wave_smooth_busy             <= 1'b0;
        wave_write_index             <= 4'd0;
        wave_scaled_target           <= 7'sd0;
        wave_scaled_valid            <= 1'b0;
    end else if (frame_start) begin
        wave_lane_updated           <= 16'd0;
        wave_target_snapshot        <= I_wave_samples;
        wave_neighbor_left          <= 7'sd0;
        spectrum_target_snapshot    <= I_spectrum_levels;
        wave_smooth_index            <= 4'd0;
        wave_smooth_busy             <= 1'b1;
        wave_scaled_valid            <= 1'b0;
    end else if (wave_smooth_busy) begin
        // Consume points in order: fixed slices replace four 16:1 selectors.
        wave_neighbor_left <= wave_target_snapshot[6:0];
        wave_target_snapshot <= {7'd0, wave_target_snapshot[111:7]};
        spectrum_target_snapshot <= {7'd0, spectrum_target_snapshot[111:7]};
        // First pipeline stage computes the spatial/volume target.  From the
        // second cycle onward, the previous target is eased and written.
        // Splitting these operations prevents a long combinational chain.
        if (wave_scaled_valid) begin
            wave_lane_valid[wave_write_index]   <= 1'b1;
            wave_lane_updated[wave_write_index] <= 1'b1;
        end
        wave_scaled_target <=
            scale_wave_vertical(
                spatial_wave_triplet(spatial_left, wave_target_snapshot[6:0],
                                     spatial_right),
                volume_level_frame);
        wave_write_index  <= wave_smooth_index;
        wave_scaled_valid <= 1'b1;
        // Reuse this same sixteen-cycle blanking-time sequencer for the
        // spectrum.  Keeping visual gain out of the per-pixel draw path saves
        // LUTs and preserves video timing margin.
        spectrum_lane_valid[wave_smooth_index] <= 1'b1;
        if (wave_smooth_index == 4'd15) begin
            wave_smooth_busy <= 1'b0;
        end else begin
            wave_smooth_index <= wave_smooth_index + 4'd1;
        end
    end else if (wave_scaled_valid) begin
        // Flush point 15 one clock after the sixteen target calculations.
        wave_lane_valid[wave_write_index]   <= 1'b1;
        wave_lane_updated[wave_write_index] <= 1'b1;
        wave_scaled_valid <= 1'b0;
    end
end

// Narrow outside VU meters. Analyzer levels are 0..96; 3/4 scaling maps
// them into this row's 72-pixel height without a multiplier.  A directional
// danger adds a pulsing minimum height while retaining any larger measured
// audio level, so the warning is unmistakable without replacing the VU data.
wire [6:0] left_vu_audio_height =
    (vu_left_frame >> 1) + (vu_left_frame >> 2);
wire [6:0] right_vu_audio_height =
    (vu_right_frame >> 1) + (vu_right_frame >> 2);

wire left_channel_warning  = hazard_frame[2] || hazard_frame[1];
wire right_channel_warning = hazard_frame[2] || hazard_frame[0];
wire hazard_flash_on = hazard_frame[2] ?
                       ~hazard_flash_count[3] :
                       ~hazard_flash_count[4];
wire [6:0] hazard_minimum_height = hazard_flash_on ? 7'd68 : 7'd40;

wire [6:0] left_vu_height =
    left_channel_warning &&
    (left_vu_audio_height < hazard_minimum_height) ?
        hazard_minimum_height : left_vu_audio_height;
wire [6:0] right_vu_height =
    right_channel_warning &&
    (right_vu_audio_height < hazard_minimum_height) ?
        hazard_minimum_height : right_vu_audio_height;
wire [9:0] left_vu_top  = ROW_BOTTOM - {3'd0, left_vu_height};
wire [9:0] right_vu_top = ROW_BOTTOM - {3'd0, right_vu_height};

wire left_vu_track = (I_enable || left_channel_warning) && I_de &&
                     (pixel_x >= 11'd36) && (pixel_x < 11'd50) &&
                     (pixel_y >= ROW_TOP) && (pixel_y < ROW_BOTTOM);
wire right_vu_track = (I_enable || right_channel_warning) && I_de &&
                      (pixel_x >= 11'd590) && (pixel_x < 11'd604) &&
                      (pixel_y >= ROW_TOP) && (pixel_y < ROW_BOTTOM);
wire left_vu_fill  = left_vu_track  && (pixel_y >= left_vu_top);
wire right_vu_fill = right_vu_track && (pixel_y >= right_vu_top);

// A thin frame around only the affected channel gives a second directional
// cue without restoring the old full-width grey visualizer panel.
wire left_warning_outline = I_de && left_channel_warning &&
    ((((pixel_x >= 11'd32) && (pixel_x < 11'd54)) &&
      (((pixel_y >= 10'd312) && (pixel_y < 10'd316)) ||
       ((pixel_y >= 10'd388) && (pixel_y < 10'd392)))) ||
     ((((pixel_x >= 11'd32) && (pixel_x < 11'd36)) ||
       ((pixel_x >= 11'd50) && (pixel_x < 11'd54))) &&
      (pixel_y >= 10'd312) && (pixel_y < 10'd392)));
wire right_warning_outline = I_de && right_channel_warning &&
    ((((pixel_x >= 11'd586) && (pixel_x < 11'd608)) &&
      (((pixel_y >= 10'd312) && (pixel_y < 10'd316)) ||
       ((pixel_y >= 10'd388) && (pixel_y < 10'd392)))) ||
     ((((pixel_x >= 11'd586) && (pixel_x < 11'd590)) ||
       ((pixel_x >= 11'd604) && (pixel_x < 11'd608))) &&
      (pixel_y >= 10'd312) && (pixel_y < 10'd392)));

// Compact 16-band spectrum: 10-pixel bars on a 14-pixel pitch.
// Decode x/14 with four bounded conditional subtractions. The old unrolled
// range checks inferred 32 wide comparators and a priority encoder.
wire [10:0] spectrum_x_offset = pixel_x - 11'd72;
wire spectrum_span = (pixel_x >= 11'd72) && (pixel_x < 11'd296);
wire spectrum_bit3 = spectrum_x_offset[7:0] >= 8'd112;
wire [6:0] spectrum_rem3 = spectrum_bit3 ?
    spectrum_x_offset[6:0] - 7'd112 : spectrum_x_offset[6:0];
wire spectrum_bit2 = spectrum_rem3 >= 7'd56;
wire [5:0] spectrum_rem2 = spectrum_bit2 ?
    spectrum_rem3[5:0] - 6'd56 : spectrum_rem3[5:0];
wire spectrum_bit1 = spectrum_rem2 >= 6'd28;
wire [4:0] spectrum_rem1 = spectrum_bit1 ?
    spectrum_rem2[4:0] - 5'd28 : spectrum_rem2[4:0];
wire spectrum_bit0 = spectrum_rem1 >= 5'd14;
wire [3:0] spectrum_remainder = spectrum_bit0 ?
    spectrum_rem1[3:0] - 4'd14 : spectrum_rem1[3:0];
wire spectrum_x_hit = spectrum_span && (spectrum_remainder < 4'd10);
wire [3:0] spectrum_index =
    {spectrum_bit3, spectrum_bit2, spectrum_bit1, spectrum_bit0};

wire [6:0] selected_spectrum_level = spectrum_lane_valid[spectrum_index] ?
    spectrum_ram[spectrum_index] : 7'd0;
wire [6:0] spectrum_height = selected_spectrum_level >> 1;
wire [9:0] spectrum_top = SPECTRUM_BASE - {3'd0, spectrum_height};
wire spectrum_fill = I_enable && I_de && spectrum_x_hit &&
                     (spectrum_height != 7'd0) &&
                     (pixel_y >= spectrum_top) &&
                     (pixel_y < SPECTRUM_BASE);
wire spectrum_tip = spectrum_fill && (pixel_y < spectrum_top + 10'd2);

// Reference-style time-domain waveform: sixteen separated fluorescent
// dashes. Frame-rate temporal easing and a three-point spatial FIR make the
// dash heights form one coherent contour without turning it into a solid
// saw-tooth line.  Give the two highest UART volume settings extra visual
// headroom: VOL8 uses 7/8, VOL7 uses 3/4, and lower settings keep 5/8.
// The helper saturates at +/-32 pixels so the glow cannot run far outside
// this row.  This scaling is calculated by the sixteen-cycle blanking-time
// sequencer above; the per-pixel path only consumes the registered result.
// The waveform pitch is exactly 16 pixels. Decode one 8-bit offset instead
// of unrolling 32 eleven-bit range comparators and priority assignments.
// Core columns are offset 1..10; glow columns are 0..11 for each point.
wire [10:0] wave_x_offset = pixel_x - 11'd333;
wire wave_x_span = (pixel_x >= 11'd333) && (pixel_x < 11'd589);
wire wave_x_glow_hit = wave_x_span && (wave_x_offset[3:0] < 4'd12);
wire wave_x_hit = wave_x_span &&
                  (wave_x_offset[3:0] >= 4'd1) &&
                  (wave_x_offset[3:0] <= 4'd10);
wire [3:0] wave_index = wave_x_offset[7:4];

wire signed [6:0] selected_wave_sample = wave_lane_valid[wave_index] ?
    wave_pixel_ram[wave_index] : 7'sd0;
wire signed [7:0] selected_wave_scaled =
    {{1{selected_wave_sample[6]}}, selected_wave_sample};
wire signed [10:0] selected_wave_y_signed =
    11'sd354 - {{3{selected_wave_scaled[7]}}, selected_wave_scaled};
wire [9:0] selected_wave_y = selected_wave_y_signed[9:0];

// Until a lane is rewritten after VS its current value is still the frame-
// start value, which is exactly what the previous-frame snapshot held.
wire signed [6:0] previous_wave_sample = wave_lane_updated[wave_index] ?
    wave_previous_ram[wave_index] : selected_wave_sample;
wire signed [7:0] previous_wave_scaled =
    {{1{previous_wave_sample[6]}}, previous_wave_sample};
wire signed [10:0] previous_wave_y_signed =
    11'sd354 - {{3{previous_wave_scaled[7]}}, previous_wave_scaled};
wire [9:0] previous_wave_y = previous_wave_y_signed[9:0];

// Compare a shared signed vertical distance against tiny constant ranges.
// The 640x480 raster and signed seven-bit points keep both y targets between
// 290 and 418, so there is no modular wrap in the original glow comparisons.
wire [10:0] wave_distance={1'b0,pixel_y}-{1'b0,selected_wave_y};
wire [10:0] previous_distance={1'b0,pixel_y}-{1'b0,previous_wave_y};

wire wave_core = I_enable && I_de && wave_x_hit &&
                 (wave_distance[10:1]==10'd0);
wire wave_glow_near = I_enable && I_de && wave_x_glow_hit &&
                      (wave_distance==11'h7FF ||
                       (wave_distance[10:2]==9'd0 && wave_distance[1:0]!=2'd3));
wire wave_glow_far = I_enable && I_de && wave_x_glow_hit &&
                     (wave_distance[10:2]==9'd0 || wave_distance[10:1]==10'h3FF);
wire wave_previous_trail = I_enable && I_de && wave_x_hit &&
                           (previous_wave_sample != selected_wave_sample) &&
                           (previous_distance[10:1]==10'd0);

wire reference_line = I_enable && I_de &&
                      (pixel_x >= 11'd330) && (pixel_x < 11'd586) &&
                      (pixel_y == WAVE_CENTER);
wire center_separator = I_enable && I_de &&
                        (pixel_x >= 11'd320) && (pixel_x < 11'd322) &&
                        (pixel_y >= 10'd322) && (pixel_y < ROW_BOTTOM);

// Small white L/R labels above the meters.
wire label_l = (I_enable || left_channel_warning) && I_de &&
               ((((pixel_x >= 11'd39) && (pixel_x < 11'd41)) &&
                  (pixel_y >= 10'd299) && (pixel_y < 10'd313)) ||
                (((pixel_x >= 11'd39) && (pixel_x < 11'd49)) &&
                  (pixel_y >= 10'd311) && (pixel_y < 10'd313)));

wire label_r = (I_enable || right_channel_warning) && I_de &&
               ((((pixel_x >= 11'd592) && (pixel_x < 11'd594)) &&
                  (pixel_y >= 10'd299) && (pixel_y < 10'd313)) ||
                (((pixel_x >= 11'd592) && (pixel_x < 11'd600)) &&
                  (((pixel_y >= 10'd299) && (pixel_y < 10'd301)) ||
                   ((pixel_y >= 10'd305) && (pixel_y < 10'd307)))) ||
                (((pixel_x >= 11'd598) && (pixel_x < 11'd600)) &&
                  (pixel_y >= 10'd301) && (pixel_y < 10'd305)) ||
                (((pixel_x >= 11'd594) && (pixel_x < 11'd596)) &&
                  (pixel_y >= 10'd307) && (pixel_y < 10'd309)) ||
                (((pixel_x >= 11'd596) && (pixel_x < 11'd598)) &&
                  (pixel_y >= 10'd309) && (pixel_y < 10'd311)) ||
                (((pixel_x >= 11'd598) && (pixel_x < 11'd600)) &&
                  (pixel_y >= 10'd311) && (pixel_y < 10'd313)));

wire [23:0] vu_color = (pixel_y < 10'd334) ? 24'hFF3B30 :
                       (pixel_y < 10'd352) ? 24'hFFD60A :
                                             24'h25D366;
wire [23:0] spectrum_color = (pixel_y < 10'd346) ? 24'h5EF4FF :
                             (pixel_y < 10'd364) ? 24'h18C8FF :
                                                   24'h287BFF;

wire [23:0] left_warning_color = hazard_frame[2] ?
    (hazard_flash_on ? 24'hFF1838 : 24'h600008) :
    (hazard_flash_on ? 24'hFF6A00 : 24'h682000);
wire [23:0] right_warning_color = hazard_frame[2] ?
    (hazard_flash_on ? 24'hFF1838 : 24'h600008) :
    (hazard_flash_on ? 24'hFFD000 : 24'h685000);
wire [23:0] left_track_color = left_channel_warning ?
                               24'h321008 : 24'h14232B;
wire [23:0] right_track_color = right_channel_warning ?
                                24'h302800 : 24'h14232B;

assign O_rgb = label_l              ? (left_channel_warning ?
                                        left_warning_color : 24'hFFFFFF) :
               label_r              ? (right_channel_warning ?
                                        right_warning_color : 24'hFFFFFF) :
               left_warning_outline ? left_warning_color :
               right_warning_outline? right_warning_color :
               left_vu_fill         ? (left_channel_warning ?
                                        left_warning_color : vu_color) :
               right_vu_fill        ? (right_channel_warning ?
                                        right_warning_color : vu_color) :
               spectrum_tip        ? 24'hD8FFFF :
               spectrum_fill       ? spectrum_color :
               wave_core           ? 24'h39FF5A :
               reference_line      ? 24'hFFFFFF :
               wave_glow_near      ? 24'h12C93D :
               wave_previous_trail ? 24'h08752A :
               wave_glow_far       ? 24'h064A1C :
               center_separator    ? 24'hB8D7E5 :
               left_vu_track       ? left_track_color :
               right_vu_track      ? right_track_color :
                                     I_rgb;

// Read-only views with the former register-array names for testbenches.
// They read every RAM entry, so they are hidden from synthesis to keep the
// arrays inferable as LUT RAM.
// synthesis translate_off
wire [111:0] spectrum_levels_frame;
wire [111:0] wave_samples_frame;
wire [111:0] wave_samples_previous_frame;
genvar view_lane;
generate
    for (view_lane = 0; view_lane < 16; view_lane = view_lane + 1) begin : g_frame_view
        assign spectrum_levels_frame[view_lane*7 +: 7] =
            spectrum_lane_valid[view_lane] ? spectrum_ram[view_lane] : 7'd0;
        assign wave_samples_frame[view_lane*7 +: 7] =
            wave_lane_valid[view_lane] ? wave_pixel_ram[view_lane] : 7'd0;
        assign wave_samples_previous_frame[view_lane*7 +: 7] =
            wave_lane_updated[view_lane] ? wave_previous_ram[view_lane] :
            wave_samples_frame[view_lane*7 +: 7];
    end
endgenerate
// synthesis translate_on

function [6:0] get_spectrum_level;
    input [111:0] levels;
    input [3:0] index;
    begin
        case (index)
            4'd0:  get_spectrum_level = levels[6:0];
            4'd1:  get_spectrum_level = levels[13:7];
            4'd2:  get_spectrum_level = levels[20:14];
            4'd3:  get_spectrum_level = levels[27:21];
            4'd4:  get_spectrum_level = levels[34:28];
            4'd5:  get_spectrum_level = levels[41:35];
            4'd6:  get_spectrum_level = levels[48:42];
            4'd7:  get_spectrum_level = levels[55:49];
            4'd8:  get_spectrum_level = levels[62:56];
            4'd9:  get_spectrum_level = levels[69:63];
            4'd10: get_spectrum_level = levels[76:70];
            4'd11: get_spectrum_level = levels[83:77];
            4'd12: get_spectrum_level = levels[90:84];
            4'd13: get_spectrum_level = levels[97:91];
            4'd14: get_spectrum_level = levels[104:98];
            default: get_spectrum_level = levels[111:105];
        endcase
    end
endfunction

// Deliberately apply the UART level once more in the display path.  The
// analyser sees the already-scaled PCM, but its quasi-log mapping compresses
// audible level changes.  This second, linear 0/8..8/8 visual gain restores a
// clear height difference without a multiplier or DSP.
function [6:0] scale_unsigned_by_volume;
    input [6:0] value;
    input [3:0] volume;
    reg [7:0] scaled;
    begin
        case (volume)
            4'd0: scaled = 8'd0;
            4'd1: scaled = value >> 3;
            4'd2: scaled = value >> 2;
            4'd3: scaled = (value >> 2) + (value >> 3);
            4'd4: scaled = value >> 1;
            4'd5: scaled = (value >> 1) + (value >> 3);
            4'd6: scaled = (value >> 1) + (value >> 2);
            4'd7: scaled = value - (value >> 3);
            default: scaled = value;
        endcase
        scale_unsigned_by_volume = scaled[6:0];
    end
endfunction

function signed [6:0] scale_signed_by_volume;
    input signed [6:0] value;
    input        [3:0] volume;
    reg signed [8:0] value_ext;
    reg signed [8:0] scaled;
    begin
        value_ext = {{2{value[6]}}, value};
        case (volume)
            4'd0: scaled = 9'sd0;
            4'd1: scaled = value_ext >>> 3;
            4'd2: scaled = value_ext >>> 2;
            4'd3: scaled = (value_ext >>> 2) + (value_ext >>> 3);
            4'd4: scaled = value_ext >>> 1;
            4'd5: scaled = (value_ext >>> 1) + (value_ext >>> 3);
            4'd6: scaled = (value_ext >>> 1) + (value_ext >>> 2);
            4'd7: scaled = value_ext - (value_ext >>> 3);
            default: scaled = value_ext;
        endcase
        scale_signed_by_volume = scaled[6:0];
    end
endfunction

// Display-only volume/vertical mapping.  The analyser already follows PCM
// volume; this second mapping deliberately makes UART levels visually
// distinct.  Audio samples and spectrum analysis are not changed here.
function signed [6:0] scale_wave_vertical;
    input signed [6:0] value;
    input        [3:0] volume;
    reg signed [8:0] value_ext;
    reg signed [8:0] scaled;
    begin
        value_ext = {{2{value[6]}}, value};
        case (volume)
            4'd0: scaled = 9'sd0;
            4'd1: scaled = value_ext >>> 4;                 // 1/16
            4'd2: scaled = value_ext >>> 3;                 // 1/8
            4'd3: scaled = value_ext >>> 2;                 // 1/4
            4'd4: scaled = (value_ext >>> 2) +
                           (value_ext >>> 3);                // 3/8
            4'd5: scaled = value_ext >>> 1;                 // 1/2
            4'd6: scaled = (value_ext >>> 1) +
                           (value_ext >>> 3);                // 5/8
            4'd7: scaled = (value_ext >>> 1) +
                           (value_ext >>> 2);                // 3/4
            default: scaled = value_ext - (value_ext >>> 3);// 7/8
        endcase

        if (scaled > 9'sd32)
            scale_wave_vertical = 7'sd32;
        else if (scaled < -9'sd32)
            scale_wave_vertical = -7'sd32;
        else
            scale_wave_vertical = scaled[6:0];
    end
endfunction

function signed [6:0] get_wave_sample;
    input [111:0] levels;
    input [3:0] index;
    begin
        case (index)
            4'd0:  get_wave_sample = levels[6:0];
            4'd1:  get_wave_sample = levels[13:7];
            4'd2:  get_wave_sample = levels[20:14];
            4'd3:  get_wave_sample = levels[27:21];
            4'd4:  get_wave_sample = levels[34:28];
            4'd5:  get_wave_sample = levels[41:35];
            4'd6:  get_wave_sample = levels[48:42];
            4'd7:  get_wave_sample = levels[55:49];
            4'd8:  get_wave_sample = levels[62:56];
            4'd9:  get_wave_sample = levels[69:63];
            4'd10: get_wave_sample = levels[76:70];
            4'd11: get_wave_sample = levels[83:77];
            4'd12: get_wave_sample = levels[90:84];
            4'd13: get_wave_sample = levels[97:91];
            4'd14: get_wave_sample = levels[104:98];
            default: get_wave_sample = levels[111:105];
        endcase
    end
endfunction

// Three-point [1 2 1]/4 FIR. End points mirror their nearest neighbour so
// the contour does not droop toward zero at its left and right edges.
function signed [6:0] spatial_wave_triplet;
    input signed [6:0] left_sample;
    input signed [6:0] center_sample;
    input signed [6:0] right_sample;
    reg signed [9:0] spatial_sum;
    reg signed [9:0] spatial_value;
    begin
        spatial_sum = {{3{left_sample[6]}}, left_sample} +
                      ({{3{center_sample[6]}}, center_sample} <<< 1) +
                      {{3{right_sample[6]}}, right_sample};
        spatial_value = spatial_sum >>> 2;
        if (spatial_value > 10'sd44)
            spatial_wave_triplet = 7'sd44;
        else if (spatial_value < -10'sd44)
            spatial_wave_triplet = -7'sd44;
        else
            spatial_wave_triplet = spatial_value[6:0];
    end
endfunction

function signed [6:0] spatial_wave_sample;
    input [111:0] levels;
    input [3:0] index;
    reg signed [6:0] left_sample;
    reg signed [6:0] center_sample;
    reg signed [6:0] right_sample;
    reg signed [9:0] spatial_sum;
    reg signed [9:0] spatial_value;
    begin
        center_sample = get_wave_sample(levels, index);
        if (index == 4'd0)
            left_sample = center_sample;
        else
            left_sample = get_wave_sample(levels, index - 4'd1);

        if (index == 4'd15)
            right_sample = center_sample;
        else
            right_sample = get_wave_sample(levels, index + 4'd1);

        spatial_sum = {{3{left_sample[6]}}, left_sample} +
                      ({{3{center_sample[6]}}, center_sample} <<< 1) +
                      {{3{right_sample[6]}}, right_sample};
        spatial_value = spatial_sum >>> 2;
        if (spatial_value > 10'sd44)
            spatial_wave_sample = 7'sd44;
        else if (spatial_value < -10'sd44)
            spatial_wave_sample = -7'sd44;
        else
            spatial_wave_sample = spatial_value[6:0];
    end
endfunction

// Frame-domain 1/8-style easing with a minimum one-pixel movement and a
// maximum three-pixel slew. Slow changes remain alive while large changes
// cannot make the complete trace jump between adjacent video frames.
function signed [6:0] smooth_display_sample;
    input signed [6:0] old_value;
    input signed [6:0] target_value;
    reg signed [7:0] delta;
    reg signed [7:0] next_value;
    reg signed [3:0] step_value;
    begin
        delta = {target_value[6],target_value} - {old_value[6],old_value};
        if (delta >= 9'sd24)
            step_value = 4'sd3;
        else if (delta >= 9'sd16)
            step_value = 4'sd2;
        else if (delta > 9'sd0)
            step_value = 4'sd1;
        else if (delta <= -9'sd24)
            step_value = -4'sd3;
        else if (delta <= -9'sd16)
            step_value = -4'sd2;
        else if (delta < 9'sd0)
            step_value = -4'sd1;
        else
            step_value = 4'sd0;

        next_value = {old_value[6],old_value} +
                     {{4{step_value[3]}}, step_value};

        if (next_value > 9'sd44)
            smooth_display_sample = 7'sd44;
        else if (next_value < -9'sd44)
            smooth_display_sample = -7'sd44;
        else
            smooth_display_sample = next_value[6:0];
    end
endfunction

endmodule
