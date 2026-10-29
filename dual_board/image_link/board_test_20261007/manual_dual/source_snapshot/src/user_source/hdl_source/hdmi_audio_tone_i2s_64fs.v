module hdmi_audio_tone_i2s_64fs #(
    parameter [31:0] PHASE_INC = 32'd39370534,
    parameter signed [23:0] AMP = 24'sd2000000,
    parameter integer NOTE_HOLD_FRAMES = 24000
)(
    input  wire I_mclk,
    input  wire I_rst,
    output reg  O_i2s_BCLK,
    output reg  O_i2s_LRCK,
    output reg  O_i2s_DOUT
);

// do/re/mi/fa/so/la/si/do；相位增量按 48 kHz 采样率计算。
function [31:0] note_inc_lut;
    input [2:0] idx;
    begin
        case (idx)
            3'd0: note_inc_lut = 32'd23409862; // C4 261.63 Hz
            3'd1: note_inc_lut = 32'd26276681; // D4 293.66 Hz
            3'd2: note_inc_lut = 32'd29494578; // E4 329.63 Hz
            3'd3: note_inc_lut = 32'd31248410; // F4 349.23 Hz
            3'd4: note_inc_lut = 32'd35075155; // G4 392.00 Hz
            3'd5: note_inc_lut = 32'd39370534; // A4 440.00 Hz
            3'd6: note_inc_lut = 32'd44191930; // B4 493.88 Hz
            default: note_inc_lut = 32'd46819716; // C5 523.25 Hz
        endcase
    end
endfunction

reg [5:0] S_bit_cnt;
reg [63:0] S_shift_reg;
reg [31:0] S_phase_acc;
reg signed [23:0] S_sample_word;
reg signed [23:0] S_sample_next;
reg [2:0] S_note_idx;
reg [15:0] S_note_frame_cnt;

wire [31:0] W_note_inc = note_inc_lut(S_note_idx);

always @(posedge I_mclk or posedge I_rst) begin
    if (I_rst) begin
        O_i2s_BCLK       <= 1'b0;
        O_i2s_LRCK       <= 1'b0;
        O_i2s_DOUT       <= 1'b0;
        S_bit_cnt        <= 6'd0;
        S_shift_reg      <= 64'd0;
        S_phase_acc      <= 32'd0;
        S_sample_word    <= 24'sd0;
        S_sample_next    <= AMP;
        S_note_idx       <= 3'd0;
        S_note_frame_cnt <= 16'd0;
    end else begin
        O_i2s_BCLK <= ~O_i2s_BCLK;

        // 在 BCLK 下降沿更新串行数据，接收端在上升沿采样。
        if (O_i2s_BCLK) begin
            O_i2s_DOUT  <= S_shift_reg[63];
            S_shift_reg <= {S_shift_reg[62:0], 1'b0};

            if (S_bit_cnt == 6'd63) begin
                S_bit_cnt <= 6'd0;
                if (!O_i2s_LRCK) begin
                    O_i2s_LRCK  <= 1'b1;
                    S_shift_reg <= {S_sample_word[23:0], 40'd0};
                end else begin
                    O_i2s_LRCK    <= 1'b0;
                    S_phase_acc   <= S_phase_acc + W_note_inc;
                    S_sample_next <= S_phase_acc[31] ? AMP : -AMP;
                    S_sample_word <= S_sample_next;
                    S_shift_reg   <= {S_sample_next[23:0], 40'd0};

                    if (S_note_frame_cnt == NOTE_HOLD_FRAMES - 1) begin
                        S_note_frame_cnt <= 16'd0;
                        S_note_idx <= (S_note_idx == 3'd7) ? 3'd0 : S_note_idx + 3'd1;
                    end else begin
                        S_note_frame_cnt <= S_note_frame_cnt + 16'd1;
                    end
                end
            end else begin
                S_bit_cnt <= S_bit_cnt + 6'd1;
            end
        end
    end
end

endmodule
