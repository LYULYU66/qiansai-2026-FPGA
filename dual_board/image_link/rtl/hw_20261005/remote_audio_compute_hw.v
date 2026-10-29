`timescale 1ns/1ps
// B-side compute follows A's consumed sample counter, NEVER TF arrival time.
// A short 1024-word history retains the audio already given to the packet TX.
// Backpressure reserves 128 words; no overwritten or future sample is analysed.
module remote_audio_compute #(
    parameter integer SAMPLE_GAP=256
) (
    input wire udp_clk, clk, rst,
    input wire [31:0] session_id, file_samples,
    input wire source_valid,
    input wire [31:0] source_pcm,
    output wire source_ready,
    input wire feedback_valid,
    input wire [31:0] feedback_session, feedback_played,
    input wire [3:0] feedback_volume,
    input wire feedback_enable,
    output wire [263:0] visual_state,
    output wire [31:0] analysed_words,
    output wire settled
);
function signed [15:0] scale_sample;
    input signed [15:0] sample_value;
    input [3:0] gain_level;
    reg signed [18:0] sample_ext, scaled_ext;
    begin
        sample_ext={{3{sample_value[15]}},sample_value};
        case(gain_level)
            0: scaled_ext=0;
            1: scaled_ext=sample_ext>>>3;
            2: scaled_ext=sample_ext>>>2;
            3: scaled_ext=(sample_ext>>>2)+(sample_ext>>>3);
            4: scaled_ext=sample_ext>>>1;
            5: scaled_ext=(sample_ext>>>1)+(sample_ext>>>3);
            6: scaled_ext=(sample_ext>>>1)+(sample_ext>>>2);
            7: scaled_ext=sample_ext-(sample_ext>>>3);
            default: scaled_ext=sample_ext;
        endcase
        scale_sample=scaled_ext[15:0];
    end
endfunction
reg [31:0] history[0:1023]; /* fehdl force_ram=1, ram_style="bram" */
reg [31:0] history_out;
reg [31:0] written, analysed;
reg [31:0] written_gray, analysed_gray;
(* async_reg="true" *) reg [31:0] written_g0, written_g1, analysed_g0, analysed_g1;
reg [31:0] written_local, analysed_local;
wire [31:0] written_decoded, analysed_decoded;
reg [31:0] backlog_q;
reg history_space_q;
reg [36:0] controls_udp;
wire [36:0] controls_local;
wire [31:0] target=controls_local[36:5];
wire [3:0] volume=controls_local[4:1];
wire enabled=controls_local[0];
reg [1:0] state;
localparam GAP_BITS=SAMPLE_GAP>1 ? $clog2(SAMPLE_GAP) : 1;
reg [GAP_BITS-1:0] pace;
reg [15:0] left_scaled, right_scaled;
(* async_reg="true" *) reg [1:0] compute_release;
wire compute_reset=rst || compute_release[1];
always @(posedge clk or posedge rst) begin
    if(rst) compute_release<=2'b11;
    else compute_release<={compute_release[0],1'b0};
end
wire [31:0] backlog=written-analysed_local;
wire [31:0] progress_delta=feedback_played-controls_udp[36:5];
wire [31:0] available_delta=written-feedback_played;
wire read_start=state==0 && pace==0 && analysed!=target && analysed!=written_local;
wire sample_valid=state==2;
// Decode -> subtract -> compare are three separate UDP pipeline stages.
// At full input rate the subtraction/ready lag permits at most TWO extra
// words. Threshold 894 preserves the original maximum of 896 stored words
// and the 128-word reserve. Delayed consumed pointers only reduce free space.
assign source_ready=history_space_q;
assign analysed_words=analysed;
assign settled=state==0 && pace==0 && analysed==target;
always @(posedge udp_clk) begin
    if(source_valid && source_ready) history[written[9:0]]<=source_pcm;
end
always @(posedge clk) begin
    if(read_start) history_out<=history[analysed[9:0]];
end
always @(posedge udp_clk or posedge rst) begin
    if(rst) begin
        written<=0; written_gray<=0; analysed_g0<=0; analysed_g1<=0;
        analysed_local<=0; backlog_q<=0; history_space_q<=1;
        controls_udp<={32'd0,4'd8,1'b0};
    end else begin
        analysed_g0<=analysed_gray; analysed_g1<=analysed_g0;
        analysed_local<=analysed_decoded;
        backlog_q<=backlog;
        history_space_q<=backlog_q<32'd894;
        if(source_valid && source_ready) begin
            written<=written+1'b1;
            written_gray<=((written+1'b1)>>1)^(written+1'b1);
        end
        // Serial arithmetic also works across the 32-bit (~24.9-hour) wrap.
        if(feedback_valid && feedback_session==session_id &&
           !progress_delta[31] && !available_delta[31]) begin
            controls_udp<={feedback_played,feedback_volume,feedback_enable};
        end
    end
end
audio_visual_cdc #(.WIDTH(37),.FRAME_BOUNDARY(0)) u_controls_cdc (
    .udp_clk(udp_clk),.video_clk(clk),.rst(rst),.frame_vs(1'b0),
    .update_valid(1'b0),.publish_enable(1'b1),.visual_state(controls_udp),
    .frame_state(controls_local),.capture_valid()
);
genvar g;
assign written_decoded[31]=written_g1[31];
assign analysed_decoded[31]=analysed_g1[31];
generate for(g=30;g>=0;g=g-1) begin:gray_decode
    assign written_decoded[g]=written_decoded[g+1]^written_g1[g];
    assign analysed_decoded[g]=analysed_decoded[g+1]^analysed_g1[g];
end endgenerate
always @(posedge clk or posedge compute_reset) begin
    if(compute_reset) begin
        analysed<=0; analysed_gray<=0; written_g0<=0; written_g1<=0; written_local<=0;
        state<=0; pace<=0; left_scaled<=0; right_scaled<=0;
    end else begin
        written_g0<=written_gray; written_g1<=written_g0;
        written_local<=written_decoded;
        if(pace!=0) pace<=pace-1'b1;
        case(state)
            0: if(read_start) state<=1;
            1: begin
                left_scaled<=scale_sample($signed(history_out[15:0]),volume);
                right_scaled<=scale_sample($signed(history_out[31:16]),volume);
                state<=2;
            end
            2: begin
                analysed<=analysed+1'b1;
                analysed_gray<=((analysed+1'b1)>>1)^(analysed+1'b1);
                pace<=SAMPLE_GAP-1; state<=0;
            end
        endcase
    end
end
wire [6:0] vu_left, vu_right;
wire [111:0] bands, wave;
wire [7:0] lyric_line, lyric_next;
wire [9:0] lyric_red;
reg [1:0] song_match_sync;
always @(posedge clk or posedge compute_reset) begin
    if(compute_reset) song_match_sync<=0;
    else song_match_sync<={song_match_sync[0],file_samples==32'd10043560};
end
audio_waveform_analyzer u_wave (
    .I_clk(clk),.I_rst(compute_reset),.I_enable(enabled),.I_audio_valid(sample_valid),
    .I_audio_left({left_scaled,8'd0}),.I_audio_right({right_scaled,8'd0}),
    .O_vu_left_level(vu_left),.O_vu_right_level(vu_right),.O_wave_samples(wave)
);
audio_spectrum_analyzer #(.LOW_POWER(1)) u_spectrum (
    .I_clk(clk),.I_rst(compute_reset),.I_enable(enabled),.I_audio_valid(sample_valid),
    .I_audio_left({left_scaled,8'd0}),.I_audio_right({right_scaled,8'd0}),
    .O_vu_left_level(),.O_vu_right_level(),.O_band_levels(bands)
);
audio_lyric_timeline u_lyrics (
    .I_audio_clk(clk),.I_video_clk(clk),.I_rst(compute_reset),.I_stream_enable(1'b1),
    .I_song_matches(song_match_sync[1]),.I_sample_read(sample_valid),
    .O_line_video(lyric_line),.O_next_line_video(lyric_next),
    .O_sung_chars_video(),.O_red_pixels_video(lyric_red)
);
assign visual_state={lyric_red,lyric_next,lyric_line,wave,bands,vu_right,vu_left};
endmodule
