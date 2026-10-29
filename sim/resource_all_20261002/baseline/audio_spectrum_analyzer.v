// Resource-conscious stereo VU and 16-band spectrum analyser.
//
// The audio stream is sampled at 48 kHz.  A time-multiplexed 256-sample
// Goertzel filter bank measures 16 approximately logarithmic frequencies.
// Only one signed multiplier is used by all bands.  Outputs use pixel heights
// (0..96) and are smoothed to give fast attack and a controlled decay.
module audio_spectrum_analyzer_resopt_reference (
    input  wire         I_clk,
    input  wire         I_rst,
    input  wire         I_enable,
    input  wire         I_audio_valid,
    input  wire [23:0]  I_audio_left,
    input  wire [23:0]  I_audio_right,
    output reg  [6:0]   O_vu_left_level,
    output reg  [6:0]   O_vu_right_level,
    output reg  [111:0] O_band_levels
);

localparam [2:0] ST_IDLE       = 3'd0;
localparam [2:0] ST_REC_LOAD   = 3'd6;
localparam [2:0] ST_REC_WRITE  = 3'd1;
localparam [2:0] ST_EVAL_LOAD  = 3'd2;
localparam [2:0] ST_EVAL_REAL  = 3'd3;
localparam [2:0] ST_EVAL_IMAG  = 3'd4;
localparam [2:0] ST_EVAL_STORE = 3'd5;

reg [2:0] state;
reg [3:0] band_index;
reg [7:0] sample_count;
reg       last_sample_of_block;

// Store both recurrence histories in synchronous block RAM instead of 864
// resettable flip-flops plus wide read/write selectors. Valid bits make an
// uninitialised or disabled band read as zero, including the first sample
// immediately after enable. No RAM clearing delay or sample is discarded.
// Recurrence takes 32 clocks; block-end evaluation adds 64. The worst-case
// 96-clock processing time fits the ~520-clock 25 MHz / 48 kHz sample period.
reg [53:0] band_history [0:15]; /* fehdl force_ram=1, ram_style="bram" */
reg [53:0] history_read_data;
reg [15:0] history_valid;
reg signed [26:0] recurrence_q2;
wire [3:0] history_read_addr =
    ((state == ST_REC_WRITE) || (state == ST_EVAL_STORE)) ?
        (band_index + 4'd1) : band_index;
wire signed [26:0] history_q1 = history_valid[band_index] ?
    history_read_data[53:27] : 27'sd0;
wire signed [26:0] history_q2 = history_valid[band_index] ?
    history_read_data[26:0] : 27'sd0;

reg signed [16:0] sample_mono_latched;
reg signed [26:0] mult_x;
reg signed [15:0] mult_c;
wire signed [42:0] mult_product = mult_x * mult_c;
wire signed [28:0] mult_scaled  = mult_product >>> 14;

reg signed [26:0] eval_q1;
reg signed [26:0] eval_q2;
reg signed [28:0] eval_real;
reg signed [28:0] eval_imag;

wire signed [15:0] sample_left  = I_audio_left[23:8];
wire signed [15:0] sample_right = I_audio_right[23:8];
wire signed [16:0] sample_mono  =
    {{1{sample_left[15]}}, sample_left} / 2 +
    {{1{sample_right[15]}}, sample_right} / 2;

wire [15:0] sample_left_abs = sample_left[15] ?
                              (~I_audio_left[23:8] + 16'd1) :
                              I_audio_left[23:8];
wire [15:0] sample_right_abs = sample_right[15] ?
                               (~I_audio_right[23:8] + 16'd1) :
                               I_audio_right[23:8];

reg [15:0] peak_left_work;
reg [15:0] peak_right_work;

wire signed [28:0] rec_value_wide =
    {{12{sample_mono_latched[16]}}, sample_mono_latched} +
    mult_scaled - {{2{recurrence_q2[26]}}, recurrence_q2};

always @(posedge I_clk) begin
    history_read_data <= band_history[history_read_addr];
    if (!I_rst && I_enable && state == ST_REC_WRITE)
        band_history[band_index] <= {rec_value_wide[26:0], mult_x};
end

wire [28:0] eval_real_abs = eval_real[28] ?
                            (~eval_real + 29'd1) : eval_real;
wire [28:0] eval_imag_abs = eval_imag[28] ?
                            (~eval_imag + 29'd1) : eval_imag;
wire [29:0] eval_magnitude =
    (eval_real_abs >= eval_imag_abs) ?
    ({1'b0, eval_real_abs} + ({1'b0, eval_imag_abs} >> 1)) :
    ({1'b0, eval_imag_abs} + ({1'b0, eval_real_abs} >> 1));

wire [6:0] evaluated_level = magnitude_to_level(eval_magnitude);
wire [6:0] current_band_level =
    O_band_levels[(band_index * 7) +: 7];
wire [6:0] target_vu_left  = peak_to_level(peak_left_work);
wire [6:0] target_vu_right = peak_to_level(peak_right_work);

// Q2.14 coefficient for q0=x+2*cos(w)*q1-q2.
function signed [15:0] recurrence_coefficient;
    input [3:0] index;
    begin
        case (index)
            4'd0:  recurrence_coefficient =  16'sd32758; // 187.5 Hz
            4'd1:  recurrence_coefficient =  16'sd32729; // 375 Hz
            4'd2:  recurrence_coefficient =  16'sd32679; // 562.5 Hz
            4'd3:  recurrence_coefficient =  16'sd32610; // 750 Hz
            4'd4:  recurrence_coefficient =  16'sd32522; // 937.5 Hz
            4'd5:  recurrence_coefficient =  16'sd32286; // 1.3125 kHz
            4'd6:  recurrence_coefficient =  16'sd31972; // 1.6875 kHz
            4'd7:  recurrence_coefficient =  16'sd31357; // 2.25 kHz
            4'd8:  recurrence_coefficient =  16'sd30274; // 3.0 kHz
            4'd9:  recurrence_coefficient =  16'sd28511; // 3.9375 kHz
            4'd10: recurrence_coefficient =  16'sd25330; // 5.25 kHz
            4'd11: recurrence_coefficient =  16'sd20160; // 6.9375 kHz
            4'd12: recurrence_coefficient =  16'sd11793; // 9.1875 kHz
            4'd13: recurrence_coefficient = -16'sd804;   // 12.1875 kHz
            4'd14: recurrence_coefficient = -16'sd16846; // 16.125 kHz
            default: recurrence_coefficient = -16'sd30572; // 21.1875 kHz
        endcase
    end
endfunction

// Q1.14 cosine coefficient used for the complex magnitude reconstruction.
function signed [15:0] cosine_coefficient;
    input [3:0] index;
    begin
        case (index)
            4'd0:  cosine_coefficient =  16'sd16379;
            4'd1:  cosine_coefficient =  16'sd16364;
            4'd2:  cosine_coefficient =  16'sd16340;
            4'd3:  cosine_coefficient =  16'sd16305;
            4'd4:  cosine_coefficient =  16'sd16261;
            4'd5:  cosine_coefficient =  16'sd16143;
            4'd6:  cosine_coefficient =  16'sd15986;
            4'd7:  cosine_coefficient =  16'sd15679;
            4'd8:  cosine_coefficient =  16'sd15137;
            4'd9:  cosine_coefficient =  16'sd14256;
            4'd10: cosine_coefficient =  16'sd12665;
            4'd11: cosine_coefficient =  16'sd10080;
            4'd12: cosine_coefficient =  16'sd5897;
            4'd13: cosine_coefficient = -16'sd402;
            4'd14: cosine_coefficient = -16'sd8423;
            default: cosine_coefficient = -16'sd15286;
        endcase
    end
endfunction

// Q1.14 sine coefficient used for the complex magnitude reconstruction.
function signed [15:0] sine_coefficient;
    input [3:0] index;
    begin
        case (index)
            4'd0:  sine_coefficient = 16'sd402;
            4'd1:  sine_coefficient = 16'sd804;
            4'd2:  sine_coefficient = 16'sd1205;
            4'd3:  sine_coefficient = 16'sd1606;
            4'd4:  sine_coefficient = 16'sd2006;
            4'd5:  sine_coefficient = 16'sd2801;
            4'd6:  sine_coefficient = 16'sd3590;
            4'd7:  sine_coefficient = 16'sd4756;
            4'd8:  sine_coefficient = 16'sd6270;
            4'd9:  sine_coefficient = 16'sd8076;
            4'd10: sine_coefficient = 16'sd10394;
            4'd11: sine_coefficient = 16'sd12916;
            4'd12: sine_coefficient = 16'sd15286;
            4'd13: sine_coefficient = 16'sd16379;
            4'd14: sine_coefficient = 16'sd14053;
            default: sine_coefficient = 16'sd5897;
        endcase
    end
endfunction

// Quasi-logarithmic mapping.  Musical energy spans a large range; a log-like
// display remains active without a divider, square-root unit, or AGC RAM.
function [6:0] magnitude_to_level;
    input [29:0] value;
    begin
        if      (|value[29:20]) magnitude_to_level = 7'd96;
        else if (value[19])     magnitude_to_level = 7'd88 + {value[18:17], 1'b0};
        else if (value[18])     magnitude_to_level = 7'd78 + {value[17:16], 1'b0};
        else if (value[17])     magnitude_to_level = 7'd68 + {value[16:15], 1'b0};
        else if (value[16])     magnitude_to_level = 7'd58 + {value[15:14], 1'b0};
        else if (value[15])     magnitude_to_level = 7'd48 + {value[14:13], 1'b0};
        else if (value[14])     magnitude_to_level = 7'd38 + {value[13:12], 1'b0};
        else if (value[13])     magnitude_to_level = 7'd28 + {value[12:11], 1'b0};
        else if (value[12])     magnitude_to_level = 7'd18 + {value[11:10], 1'b0};
        else if (value[11])     magnitude_to_level = 7'd12;
        else if (value[10])     magnitude_to_level = 7'd8;
        else if (value[9])      magnitude_to_level = 7'd4;
        else                    magnitude_to_level = 7'd0;
    end
endfunction

function [6:0] peak_to_level;
    input [15:0] peak;
    reg [7:0] linear_level;
    begin
        linear_level = peak[15:8];
        if (linear_level >= 8'd96)
            peak_to_level = 7'd96;
        else
            peak_to_level = linear_level[6:0];
    end
endfunction

integer write_lane;
always @(posedge I_clk or posedge I_rst) begin
    if (I_rst) begin
        state                <= ST_IDLE;
        band_index           <= 4'd0;
        sample_count         <= 8'd0;
        last_sample_of_block <= 1'b0;
        sample_mono_latched  <= 17'sd0;
        mult_x               <= 27'sd0;
        mult_c               <= 16'sd0;
        eval_q1              <= 27'sd0;
        eval_q2              <= 27'sd0;
        eval_real            <= 29'sd0;
        eval_imag            <= 29'sd0;
        peak_left_work       <= 16'd0;
        peak_right_work      <= 16'd0;
        O_vu_left_level      <= 7'd0;
        O_vu_right_level     <= 7'd0;
        O_band_levels        <= 112'd0;
        history_valid        <= 16'd0;
        recurrence_q2        <= 27'sd0;
    end else if (!I_enable) begin
        state                <= ST_IDLE;
        band_index           <= 4'd0;
        sample_count         <= 8'd0;
        last_sample_of_block <= 1'b0;
        peak_left_work       <= 16'd0;
        peak_right_work      <= 16'd0;
        O_vu_left_level      <= 7'd0;
        O_vu_right_level     <= 7'd0;
        O_band_levels        <= 112'd0;
        history_valid        <= 16'd0;
    end else begin
        case (state)
            ST_IDLE: begin
                if (I_audio_valid) begin
                    sample_mono_latched  <= sample_mono;
                    last_sample_of_block <= (sample_count == 8'd255);
                    band_index           <= 4'd0;
                    state                <= ST_REC_LOAD;

                    if (sample_left_abs > peak_left_work)
                        peak_left_work <= sample_left_abs;
                    if (sample_right_abs > peak_right_work)
                        peak_right_work <= sample_right_abs;
                end
            end

            ST_REC_LOAD: begin
                mult_x        <= history_q1;
                recurrence_q2 <= history_q2;
                mult_c        <= recurrence_coefficient(band_index);
                state         <= ST_REC_WRITE;
            end

            ST_REC_WRITE: begin
                history_valid[band_index] <= 1'b1;

                if (band_index == 4'd15) begin
                    band_index <= 4'd0;
                    if (last_sample_of_block) begin
                        state <= ST_EVAL_LOAD;
                    end else begin
                        sample_count <= sample_count + 8'd1;
                        state <= ST_IDLE;
                    end
                end else begin
                    band_index <= band_index + 4'd1;
                    state <= ST_REC_LOAD;
                end
            end

            ST_EVAL_LOAD: begin
                eval_q1 <= history_q1;
                eval_q2 <= history_q2;
                mult_x  <= history_q2;
                mult_c  <= cosine_coefficient(band_index);
                state   <= ST_EVAL_REAL;
            end

            ST_EVAL_REAL: begin
                eval_real <= {{2{eval_q1[26]}}, eval_q1} - mult_scaled;
                mult_x    <= eval_q2;
                mult_c    <= sine_coefficient(band_index);
                state     <= ST_EVAL_IMAG;
            end

            ST_EVAL_IMAG: begin
                eval_imag <= mult_scaled;
                state     <= ST_EVAL_STORE;
            end

            ST_EVAL_STORE: begin
                for (write_lane = 0; write_lane < 16; write_lane = write_lane + 1) begin
                    if (band_index == write_lane) begin
                        if (evaluated_level >= current_band_level)
                            O_band_levels[write_lane*7 +: 7] <= evaluated_level;
                        else if (current_band_level > 7'd2)
                            O_band_levels[write_lane*7 +: 7] <= current_band_level - 7'd2;
                        else
                            O_band_levels[write_lane*7 +: 7] <= 7'd0;
                    end
                end

                history_valid[band_index] <= 1'b0;

                if (band_index == 4'd15) begin
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

                    peak_left_work  <= 16'd0;
                    peak_right_work <= 16'd0;
                    sample_count    <= 8'd0;
                    band_index      <= 4'd0;
                    state           <= ST_IDLE;
                end else begin
                    band_index <= band_index + 4'd1;
                    state      <= ST_EVAL_LOAD;
                end
            end

            default: state <= ST_IDLE;
        endcase
    end
end

endmodule
