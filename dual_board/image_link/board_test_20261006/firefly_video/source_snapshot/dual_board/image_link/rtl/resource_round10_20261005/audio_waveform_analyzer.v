// Lightweight normal-playback waveform sampler and stereo peak VU meter.
//
// Sixteen signed waveform points are captured after a hysteretic rising zero
// crossing.  A one-pole input filter and a 3/4-old + 1/4-new temporal blend
// prevent unrelated crossings from making the displayed trace jump. Four audio
// samples separate adjacent points, so one trace covers about 1.27 ms at
// 48 kHz. No multiplier, DSP, or RAM is required.
module audio_waveform_analyzer (
    input  wire         I_clk,
    input  wire         I_rst,
    input  wire         I_enable,
    input  wire         I_audio_valid,
    input  wire [23:0]  I_audio_left,
    input  wire [23:0]  I_audio_right,
    output reg  [6:0]   O_vu_left_level,
    output reg  [6:0]   O_vu_right_level,
    output reg  [111:0] O_wave_samples
);

wire signed [15:0] sample_left  = I_audio_left[23:8];
wire signed [15:0] sample_right = I_audio_right[23:8];
wire signed [16:0] sample_mono  =
    ({{1{sample_left[15]}}, sample_left} >>> 1) +
    ({{1{sample_right[15]}}, sample_right} >>> 1);

wire [15:0] sample_left_abs = sample_left[15] ?
                              (~I_audio_left[23:8] + 16'd1) :
                              I_audio_left[23:8];
wire [15:0] sample_right_abs = sample_right[15] ?
                               (~I_audio_right[23:8] + 16'd1) :
                               I_audio_right[23:8];
wire [16:0] sample_mono_abs = sample_mono[16] ?
                              (~sample_mono + 17'd1) : sample_mono;

// Only the upper byte contributes to VU height. Max and truncation commute,
// so retaining this byte gives exactly the same output with smaller peaks.
reg [7:0] peak_left_work;
reg [7:0] peak_right_work;
wire [7:0] peak_left_next = (sample_left_abs[15:8] > peak_left_work) ?
                              sample_left_abs[15:8] : peak_left_work;
wire [7:0] peak_right_next = (sample_right_abs[15:8] > peak_right_work) ?
                               sample_right_abs[15:8] : peak_right_work;

reg [7:0] sample_count;
reg signed [16:0] filtered_mono;
reg       trigger_armed;
reg       capture_active;
reg [1:0] capture_divider;
reg [3:0] capture_index;
reg [9:0] trigger_timeout;
reg [7:0] capture_holdoff;
// Fifteen previous points plus the just-captured point make the published
// trace. A single shift enable replaces sixteen independent lane decoders.
// No intermediate partial trace is exposed on O_wave_samples.
reg [104:0] wave_work;

wire signed [17:0] sample_mono_extended =
    {{1{sample_mono[16]}}, sample_mono};
wire signed [17:0] filtered_mono_extended =
    {{1{filtered_mono[16]}}, filtered_mono};
wire signed [17:0] filter_delta =
    sample_mono_extended - filtered_mono_extended;
wire signed [17:0] filtered_next_wide =
    filtered_mono_extended + (filter_delta >>> 2);
wire signed [16:0] filtered_next = filtered_next_wide[16:0];

wire signed [6:0] waveform_offset = sample_to_offset(filtered_next);
wire [6:0] target_vu_left  = peak_to_level(peak_left_next);
wire [6:0] target_vu_right = peak_to_level(peak_right_next);
wire stable_rising_crossing = trigger_armed &&
                              (filtered_next >= 17'sd0);
// Ping-pong LUT-RAM copy of the published trace replaces a 16:1 selector on
// O_wave_samples. A capture writes every lane of the work bank and the banks
// swap in the cycle O_wave_samples is published; published_valid reproduces
// the zeroed output after reset/disable. capture_index is 0 while idle, so
// the trigger's lane-0 read uses the same port.
reg [6:0] wave_bank_ram [0:31];
reg       published_bank;
reg       published_valid;
wire signed [6:0] old_capture_point = published_valid ?
    wave_bank_ram[{published_bank, capture_index}] : 7'sd0;
wire signed [6:0] smoothed_capture_point =
    smooth_offset(old_capture_point, waveform_offset);

wire capture_trigger = !capture_active && (capture_holdoff == 8'd0) &&
    (stable_rising_crossing || (trigger_timeout == 10'd1023));
wire capture_step = capture_active && (capture_divider == 2'd3);
// Temporary shift data is never observed before all fifteen previous points
// have been replaced. Reset/disable clears capture_active/published_valid;
// retaining temporary data removes a 105-bit clear/enable network safely.
always @(posedge I_clk)
    if (!I_rst && I_enable && I_audio_valid && (capture_trigger || capture_step))
        wave_work <= {smoothed_capture_point, wave_work[104:7]};
always @(posedge I_clk)
    if (!I_rst && I_enable && I_audio_valid && (capture_trigger || capture_step))
        wave_bank_ram[{~published_bank, capture_index}] <= smoothed_capture_point;

function signed [6:0] sample_to_offset;
    input signed [16:0] sample;
    reg signed [16:0] scaled;
    begin
        // 1 pixel per 512 PCM counts, clamped to +/-44 pixels.
        scaled = sample >>> 9;
        if (scaled > 17'sd44)
            sample_to_offset = 7'sd44;
        else if (scaled < -17'sd44)
            sample_to_offset = -7'sd44;
        else
            sample_to_offset = scaled[6:0];
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

function signed [6:0] smooth_offset;
    input signed [6:0] old_value;
    input signed [6:0] new_value;
    reg signed [8:0] old_extended;
    reg signed [8:0] new_extended;
    reg signed [8:0] delta;
    reg signed [8:0] blended;
    begin
        old_extended = {{2{old_value[6]}}, old_value};
        new_extended = {{2{new_value[6]}}, new_value};
        delta = new_extended - old_extended;
        blended = old_extended + (delta >>> 2);
        if (blended > 9'sd44)
            smooth_offset = 7'sd44;
        else if (blended < -9'sd44)
            smooth_offset = -7'sd44;
        else
            smooth_offset = blended[6:0];
    end
endfunction

function [6:0] peak_to_level;
    input [7:0] peak;
    reg [7:0] linear_level;
    begin
        linear_level = peak;
        if (linear_level >= 8'd96)
            peak_to_level = 7'd96;
        else
            peak_to_level = linear_level[6:0];
    end
endfunction

always @(posedge I_clk or posedge I_rst) begin
    if (I_rst) begin
        O_vu_left_level  <= 7'd0;
        O_vu_right_level <= 7'd0;
        O_wave_samples   <= 112'd0;
        peak_left_work   <= 8'd0;
        peak_right_work  <= 8'd0;
        sample_count     <= 8'd0;
        filtered_mono    <= 17'sd0;
        trigger_armed    <= 1'b0;
        capture_active   <= 1'b0;
        capture_divider  <= 2'd0;
        capture_index    <= 4'd0;
        trigger_timeout  <= 10'd0;
        capture_holdoff  <= 8'd0;
        published_bank   <= 1'b0;
        published_valid  <= 1'b0;
    end else if (!I_enable) begin
        O_vu_left_level  <= 7'd0;
        O_vu_right_level <= 7'd0;
        O_wave_samples   <= 112'd0;
        peak_left_work   <= 8'd0;
        peak_right_work  <= 8'd0;
        sample_count     <= 8'd0;
        filtered_mono    <= 17'sd0;
        trigger_armed    <= 1'b0;
        capture_active   <= 1'b0;
        capture_divider  <= 2'd0;
        capture_index    <= 4'd0;
        trigger_timeout  <= 10'd0;
        capture_holdoff  <= 8'd0;
        published_valid  <= 1'b0;
    end else if (I_audio_valid) begin
        filtered_mono <= filtered_next;
        if (filtered_next < -17'sd512)
            trigger_armed <= 1'b1;

        // Independent stereo peak VU, refreshed every 256 samples.
        if (sample_count == 8'd255) begin
            if (target_vu_left >= O_vu_left_level)
                O_vu_left_level <= target_vu_left;
            else if (O_vu_left_level > 7'd4)
                O_vu_left_level <= O_vu_left_level - 7'd4;
            else
                O_vu_left_level <= 7'd0;

            if (target_vu_right >= O_vu_right_level)
                O_vu_right_level <= target_vu_right;
            else if (O_vu_right_level > 7'd4)
                O_vu_right_level <= O_vu_right_level - 7'd4;
            else
                O_vu_right_level <= 7'd0;

            peak_left_work  <= 8'd0;
            peak_right_work <= 8'd0;
            sample_count    <= 8'd0;

        end else begin
            peak_left_work  <= peak_left_next;
            peak_right_work <= peak_right_next;
            sample_count    <= sample_count + 8'd1;
        end

        if (!capture_active) begin
            if (capture_holdoff != 8'd0) begin
                capture_holdoff <= capture_holdoff - 8'd1;
                trigger_timeout <= 10'd0;
            end else if (stable_rising_crossing ||
                         (trigger_timeout == 10'd1023)) begin
                capture_index   <= 4'd1;
                capture_divider <= 2'd0;
                capture_active  <= 1'b1;
                trigger_timeout <= 10'd0;
                trigger_armed   <= 1'b0;
            end else begin
                trigger_timeout <= trigger_timeout + 10'd1;
            end
        end else if (capture_divider == 2'd3) begin
            capture_divider <= 2'd0;

            if (capture_index == 4'd15) begin
                // Include the final point in the same atomic publication.
                O_wave_samples <= {smoothed_capture_point, wave_work[104:0]};
                published_bank  <= ~published_bank;
                published_valid <= 1'b1;
                capture_active <= 1'b0;
                capture_index  <= 4'd0;
                capture_holdoff <= 8'd255;
                trigger_armed  <= 1'b0;
            end else begin
                capture_index <= capture_index + 4'd1;
            end
        end else begin
            capture_divider <= capture_divider + 2'd1;
        end
    end
end

endmodule
