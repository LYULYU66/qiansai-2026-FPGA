module hdmi_audio_pcm_i2s_64fs #(
    parameter integer START_LEVEL = 128
)(
    input  wire        I_mclk,
    input  wire        I_rst,
    input  wire        I_enable,
    input  wire [31:0] I_pcm_data,
    input  wire        I_pcm_empty,
    input  wire [8:0]  I_pcm_level,
    input  wire [3:0]  I_volume_level,
    output reg         O_pcm_read,
    output reg         O_i2s_BCLK,
    output reg         O_i2s_LRCK,
    output reg         O_i2s_DOUT,
    output reg         O_playing,
    output reg         O_underflow
);

// MUSIC.PCM is signed 16-bit little-endian stereo:
// bits 15:0 = left, bits 31:16 = right.  HDMI interprets its 24-bit samples
// at 24-bit full scale, so a 16-bit source must be left-justified by 8 bits.
// Merely sign-extending it would attenuate the programme by about 48 dB.
// The 64-bit slots match the existing receiver.
reg [5:0]  bit_cnt;
reg [63:0] shift_reg;
reg [23:0] right_sample;
reg [3:0]  volume_meta;
reg [3:0]  volume_sync;
reg [3:0]  volume_stable;

wire signed [15:0] pcm_left_raw  = I_pcm_data[15:0];
wire signed [15:0] pcm_right_raw = I_pcm_data[31:16];
wire signed [15:0] pcm_left_scaled =
    scale_sample(pcm_left_raw, volume_stable);
wire signed [15:0] pcm_right_scaled =
    scale_sample(pcm_right_raw, volume_stable);
wire [23:0] pcm_left_24  = {pcm_left_scaled,  8'b0};
wire [23:0] pcm_right_24 = {pcm_right_scaled, 8'b0};

// Gain is represented as 0/8 .. 8/8. Shift/add implementation avoids DSPs.
function signed [15:0] scale_sample;
    input signed [15:0] sample_value;
    input        [3:0]  gain_level;
    reg signed [18:0] sample_ext;
    reg signed [18:0] scaled_ext;
    begin
        sample_ext = {{3{sample_value[15]}}, sample_value};
        case (gain_level)
            4'd0: scaled_ext = 19'sd0;
            4'd1: scaled_ext = sample_ext >>> 3;
            4'd2: scaled_ext = sample_ext >>> 2;
            4'd3: scaled_ext = (sample_ext >>> 2) + (sample_ext >>> 3);
            4'd4: scaled_ext = sample_ext >>> 1;
            4'd5: scaled_ext = (sample_ext >>> 1) + (sample_ext >>> 3);
            4'd6: scaled_ext = (sample_ext >>> 1) + (sample_ext >>> 2);
            4'd7: scaled_ext = sample_ext - (sample_ext >>> 3);
            default: scaled_ext = sample_ext;
        endcase
        scale_sample = scaled_ext[15:0];
    end
endfunction

always @(posedge I_mclk or posedge I_rst) begin
    if (I_rst) begin
        O_pcm_read   <= 1'b0;
        O_i2s_BCLK   <= 1'b0;
        O_i2s_LRCK   <= 1'b0;
        O_i2s_DOUT   <= 1'b0;
        O_playing    <= 1'b0;
        O_underflow  <= 1'b0;
        bit_cnt      <= 6'd0;
        shift_reg    <= 64'd0;
        right_sample <= 24'd0;
        volume_meta  <= 4'd8;
        volume_sync  <= 4'd8;
        volume_stable<= 4'd8;
    end else begin
        // The UART register changes rarely.  Two-stage synchronization plus
        // an equality commit prevents a partially changing multi-bit value
        // from reaching an audio sample.
        volume_meta <= I_volume_level;
        volume_sync <= volume_meta;
        if (volume_sync == volume_meta)
            volume_stable <= volume_sync;

        O_i2s_BCLK  <= ~O_i2s_BCLK;
        O_pcm_read  <= 1'b0;
        O_underflow <= 1'b0;

        // The stream controller and this serializer live in different clock
        // domains.  Never leave the PCM source selected after the stream has
        // stopped; otherwise an empty FIFO would permanently mask the audible
        // fallback with zero samples.
        if (!I_enable)
            O_playing <= 1'b0;

        // Change serial data on BCLK falling edges; the receiver samples on
        // rising edges. LRCK low carries left and LRCK high carries right.
        if (O_i2s_BCLK) begin
            O_i2s_DOUT <= shift_reg[63];
            shift_reg  <= {shift_reg[62:0], 1'b0};

            if (bit_cnt == 6'd63) begin
                bit_cnt <= 6'd0;
                if (!O_i2s_LRCK) begin
                    O_i2s_LRCK <= 1'b1;
                    shift_reg  <= {right_sample, 40'd0};
                end else begin
                    O_i2s_LRCK <= 1'b0;
                    if (!I_enable) begin
                        O_playing    <= 1'b0;
                        shift_reg    <= 64'd0;
                        right_sample<= 24'd0;
                    end else if (!O_playing &&
                                 (I_pcm_level >= START_LEVEL) &&
                                 !I_pcm_empty) begin
                        // Enter PCM mode only on a complete stereo-frame
                        // boundary and load the first word at the same time.
                        O_playing     <= 1'b1;
                        O_pcm_read    <= 1'b1;
                        shift_reg     <= {pcm_left_24, 40'd0};
                        right_sample <= pcm_right_24;
                    end else if (O_playing && !I_pcm_empty) begin
                        O_pcm_read   <= 1'b1;
                        shift_reg    <= {pcm_left_24, 40'd0};
                        right_sample<= pcm_right_24;
                    end else begin
                        shift_reg    <= 64'd0;
                        right_sample<= 24'd0;
                        if (O_playing) begin
                            O_underflow <= 1'b1;
                            O_playing   <= 1'b0;
                        end
                    end
                end
            end else begin
                bit_cnt <= bit_cnt + 6'd1;
            end
        end
    end
end

endmodule
