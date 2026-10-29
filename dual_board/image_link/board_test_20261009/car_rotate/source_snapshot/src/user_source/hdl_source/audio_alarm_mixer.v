// Low-resource vehicle hazard alarm mixer.
//
// The input and output streams are signed 24-bit stereo PCM.  All state
// advances only when I_audio_valid is asserted, so the NCO and cadence are
// locked to the 48 kHz audio sample rate even though I_clk is the faster
// video/system clock.  No multiplier, DSP or memory block is required.
module audio_alarm_mixer (
    input  wire        I_clk,
    input  wire        I_rst,
    input  wire        I_audio_valid,
    input  wire [23:0] I_audio_left,
    input  wire [23:0] I_audio_right,
    input  wire        I_hazard_front,
    input  wire        I_hazard_left,
    input  wire        I_hazard_right,
    output reg         O_audio_valid,
    output reg  [23:0] O_audio_left,
    output reg  [23:0] O_audio_right
);

localparam [2:0] MODE_NONE  = 3'd0;
localparam [2:0] MODE_RIGHT = 3'd1;
localparam [2:0] MODE_LEFT  = 3'd2;
localparam [2:0] MODE_BOTH  = 3'd3;
localparam [2:0] MODE_FRONT = 3'd4;

// Priority: front > both rear sides > left > right.
wire [2:0] hazard_mode_request =
    I_hazard_front                    ? MODE_FRONT :
    (I_hazard_left && I_hazard_right) ? MODE_BOTH  :
    I_hazard_left                     ? MODE_LEFT  :
    I_hazard_right                    ? MODE_RIGHT : MODE_NONE;

// Keep the last non-zero mode while the short alarm envelope fades out.
reg [2:0]  tone_mode;
reg [31:0] phase_accumulator;
reg [14:0] cadence_count;
reg [2:0]  envelope_level;  // 0/4, 1/4, 2/4, 3/4, 4/4
reg [4:0]  envelope_step_count;

// 32-bit NCO increments for 48 kHz sampling.
function [31:0] phase_increment;
    input [2:0] mode;
    begin
        case (mode)
            MODE_FRONT: phase_increment = 32'd107374182; // 1200 Hz
            MODE_BOTH:  phase_increment = 32'd80530637;  //  900 Hz
            default:    phase_increment = 32'd62634940;  // ~700 Hz
        endcase
    end
endfunction

// Alarm cadence in samples.  Front is fastest, both sides are intermediate,
// and a single side is deliberately slower.
function [14:0] cadence_on_samples;
    input [2:0] mode;
    begin
        case (mode)
            MODE_FRONT: cadence_on_samples = 15'd3840;  // 80 ms
            MODE_BOTH:  cadence_on_samples = 15'd7200;  // 150 ms
            default:    cadence_on_samples = 15'd12000; // 250 ms
        endcase
    end
endfunction

function [14:0] cadence_period_samples;
    input [2:0] mode;
    begin
        case (mode)
            MODE_FRONT: cadence_period_samples = 15'd7680;  // 160 ms
            MODE_BOTH:  cadence_period_samples = 15'd14400; // 300 ms
            default:    cadence_period_samples = 15'd24000; // 500 ms
        endcase
    end
endfunction

// Fixed alarm level is intentionally independent of the UART music volume.
// The selected values plus the associated ducked full-scale programme remain
// below 24-bit full scale, while a saturator provides a final safety net.
function signed [23:0] alarm_amplitude;
    input [2:0] mode;
    begin
        case (mode)
            MODE_FRONT: alarm_amplitude = 24'sd2000000;
            MODE_BOTH:  alarm_amplitude = 24'sd1600000;
            default:    alarm_amplitude = 24'sd1300000;
        endcase
    end
endfunction

// Eight-step sine approximation: 0, +3/4, +1, +3/4, 0, -3/4, -1, -3/4.
// It sounds less harsh than a square wave and still uses only shifts/adds.
function signed [23:0] stepped_sine;
    input [2:0]  phase_index;
    input signed [23:0] amplitude;
    reg signed [23:0] three_quarters;
    begin
        three_quarters = (amplitude >>> 1) + (amplitude >>> 2);
        case (phase_index)
            3'd0, 3'd4: stepped_sine = 24'sd0;
            3'd1, 3'd3: stepped_sine = three_quarters;
            3'd2:       stepped_sine = amplitude;
            3'd5, 3'd7: stepped_sine = -three_quarters;
            default:    stepped_sine = -amplitude;
        endcase
    end
endfunction

function signed [23:0] apply_envelope;
    input signed [23:0] sample_value;
    input        [2:0]  level;
    begin
        case (level)
            3'd0: apply_envelope = 24'sd0;
            3'd1: apply_envelope = sample_value >>> 2;
            3'd2: apply_envelope = sample_value >>> 1;
            3'd3: apply_envelope =
                      (sample_value >>> 1) + (sample_value >>> 2);
            default: apply_envelope = sample_value;
        endcase
    end
endfunction

// Music ducking conveys alarm priority without multipliers.
function signed [23:0] duck_music;
    input signed [23:0] sample_value;
    input        [2:0]  mode;
    begin
        case (mode)
            MODE_FRONT: duck_music = sample_value >>> 3; // 1/8
            MODE_BOTH:  duck_music = sample_value >>> 2; // 1/4
            MODE_LEFT,
            MODE_RIGHT: duck_music = sample_value >>> 1; // 1/2
            default:    duck_music = sample_value;
        endcase
    end
endfunction

localparam signed [24:0] MAX_24 = 25'sd8388607;
localparam signed [24:0] MIN_24 = -25'sd8388608;

function [23:0] saturate_24;
    input signed [24:0] sample_value;
    begin
        if (sample_value > MAX_24)
            saturate_24 = 24'h7fffff;
        else if (sample_value < MIN_24)
            saturate_24 = 24'h800000;
        else
            saturate_24 = sample_value[23:0];
    end
endfunction

wire cadence_gate = (hazard_mode_request != MODE_NONE) &&
                    (cadence_count < cadence_on_samples(tone_mode));

wire signed [23:0] tone_raw =
    stepped_sine(phase_accumulator[31:29], alarm_amplitude(tone_mode));
wire signed [23:0] tone_enveloped =
    apply_envelope(tone_raw, envelope_level);

reg signed [23:0] alarm_left;
reg signed [23:0] alarm_right;
always @* begin
    alarm_left  = 24'sd0;
    alarm_right = 24'sd0;
    case (tone_mode)
        MODE_FRONT,
        MODE_BOTH: begin
            alarm_left  = tone_enveloped;
            alarm_right = tone_enveloped;
        end
        MODE_LEFT: begin
            alarm_left  = tone_enveloped;
            alarm_right = tone_enveloped >>> 2;
        end
        MODE_RIGHT: begin
            alarm_left  = tone_enveloped >>> 2;
            alarm_right = tone_enveloped;
        end
        default: begin
            alarm_left  = 24'sd0;
            alarm_right = 24'sd0;
        end
    endcase
end

wire signed [23:0] music_left =
    duck_music($signed(I_audio_left), hazard_mode_request);
wire signed [23:0] music_right =
    duck_music($signed(I_audio_right), hazard_mode_request);
wire signed [24:0] mixed_left =
    {music_left[23], music_left} + {alarm_left[23], alarm_left};
wire signed [24:0] mixed_right =
    {music_right[23], music_right} + {alarm_right[23], alarm_right};

always @(posedge I_clk or posedge I_rst) begin
    if (I_rst) begin
        O_audio_valid       <= 1'b0;
        O_audio_left        <= 24'd0;
        O_audio_right       <= 24'd0;
        tone_mode           <= MODE_NONE;
        phase_accumulator   <= 32'd0;
        cadence_count       <= 15'd0;
        envelope_level      <= 3'd0;
        envelope_step_count <= 5'd0;
    end else begin
        O_audio_valid <= I_audio_valid;

        if (I_audio_valid) begin
            O_audio_left  <= saturate_24(mixed_left);
            O_audio_right <= saturate_24(mixed_right);

            if ((hazard_mode_request != MODE_NONE) &&
                (hazard_mode_request != tone_mode)) begin
                // Start a newly selected warning at a deterministic phase and
                // cadence boundary.  The envelope prevents a hard tone edge.
                tone_mode         <= hazard_mode_request;
                phase_accumulator <= 32'd0;
                cadence_count     <= 15'd0;
            end else begin
                if ((tone_mode != MODE_NONE) &&
                    ((hazard_mode_request != MODE_NONE) ||
                     (envelope_level != 3'd0)))
                    phase_accumulator <=
                        phase_accumulator + phase_increment(tone_mode);

                if (hazard_mode_request != MODE_NONE) begin
                    if (cadence_count >=
                        (cadence_period_samples(tone_mode) - 15'd1))
                        cadence_count <= 15'd0;
                    else
                        cadence_count <= cadence_count + 15'd1;
                end else begin
                    cadence_count <= 15'd0;
                end
            end

            // Four 24-sample steps give a 2 ms attack/release at 48 kHz.
            if ((cadence_gate && (envelope_level < 3'd4)) ||
                (!cadence_gate && (envelope_level != 3'd0))) begin
                if (envelope_step_count == 5'd23) begin
                    envelope_step_count <= 5'd0;
                    if (cadence_gate)
                        envelope_level <= envelope_level + 3'd1;
                    else
                        envelope_level <= envelope_level - 3'd1;
                end else begin
                    envelope_step_count <= envelope_step_count + 5'd1;
                end
            end else begin
                envelope_step_count <= 5'd0;
            end

            if ((hazard_mode_request == MODE_NONE) &&
                (envelope_level == 3'd0))
                tone_mode <= MODE_NONE;
        end
    end
end

endmodule
