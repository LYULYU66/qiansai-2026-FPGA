// Actual PCM sample timeline; compact delta ROM plus Q20 pixel interpolation.
// No wall-clock advance during underflow. Intro/interlude maps share the song.
module audio_lyric_timeline #(
    parameter [23:0] SONG_SAMPLES=24'd10043560,
    parameter DUAL_SONG=0
)(
    input I_audio_clk,I_video_clk,I_rst,I_stream_enable,I_song_matches,I_sample_read,
    input [2:0] I_song,
    output reg [7:0] O_line_video,O_next_line_video,
    output reg [4:0] O_sung_chars_video,
    output reg [9:0] O_red_pixels_video
);
reg [23:0] sample_count,last_due,event_due;
reg [8:0] event_index,event_index_d,event_index_d2;
reg [5:0] boundary_index,due_code;
reg due_valid;
// Row ids are {head,id}: head rows live in lyric_line_rom bank 6 at
// id song*5+row+1, so they never share an id with a lyric row of the song.
reg [5:0] current_line,next_line;
reg [4:0] completed;
// I_song is synchronized into this clock domain, but it can change while the
// PCM stream and match flag remain asserted during a track switch.  Remember
// the active bank so a new song always starts from its head-row state
// instead of inheriting the old event index and sample counter.
reg [2:0] song_seen;
reg stream_seen;
wire [29:0] next_event;
wire [5:0] boundary_current,boundary_next;
wire [2:0] song=DUAL_SONG ? I_song : 3'd0;
wire song_valid=!DUAL_SONG || (I_song<6);
wire [4:0] head_first={song,2'b00}+song+5'd1;
wire [2:0] current_bank=current_line[5] ? 3'd6 : song;
wire [2:0] next_bank=next_line[5] ? 3'd6 : song;
wire [23:0] selected_song_samples=(song==3'd5) ? 24'd13232020 :
    (song==3'd4) ? 24'd11526410 :
    (song==3'd3) ? 24'd12391040 :
    (song==3'd2) ? 24'd12484480 :
    // MUSIC2.PCM in the release TF set is 56,489,984 bytes, i.e.
    // 14,122,496 stereo samples.  Using the old 14,295,040 value leaves
    // the lyric clock running past the real EOF and makes the red sweep lag.
    (song==3'd1) ? 24'd14122496 : SONG_SAMPLES;
// The first recording of 一路向北 has a small leading alignment difference
// from the PCM packet clock.  Shift its complete event stream by 120 ms;
// keeping the bias outside event_due avoids accumulating the correction on
// every lyric event and preserves the original inter-line spacing.
localparam [23:0] SONG1_TIMING_BIAS=24'd5760;
wire [24:0] event_due_adjusted={1'b0,event_due}+
    ((song==3'd1)?{1'b0,SONG1_TIMING_BIAS}:25'd0);
lyric_event_rom u_events(I_audio_clk,{song,event_index},next_event);
lyric_boundary_map u_boundaries({song,boundary_index},boundary_current,boundary_next);

// A reusable restoring divider computes one rate per syllable span, taking
// 30 audio clocks (about 2.4us), not a combinational division on the pixel path.
// Progress is pixels Q20. Rounded rate error is <1 pixel even on long spans.
reg [29:0] red_q,rate,limit_q;
reg div_busy;
reg [4:0] div_step;
reg [29:0] div_num,div_quotient;
reg [23:0] div_den;
reg [24:0] div_rem;
wire [24:0] trial={div_rem[23:0],div_num[29]};
wire subtract_ok=(trial>={1'b0,div_den});
wire [29:0] quotient_next={div_quotient[28:0],subtract_ok};
wire [30:0] progress_next={1'b0,red_q}+{1'b0,rate};
// Head and lyric rows share one event format: 1..20 is the completed column,
// so the head sweep is paced by the same PCM sample counter as the lyrics.
wire normal_red_event=(next_event[5:0]>0 && next_event[5:0]<=20 &&
    next_event[4:0]>completed);
wire [4:0] target_span=next_event[4:0];
wire [4:0] column_span=target_span-completed;

// Bundled-data mailbox holds both lines and the exact pixel boundary stable
// until acknowledged. Video takes a coherent snapshot only at VS.
wire [25:0] visual_state={current_bank,current_line[4:0],next_bank,next_line[4:0],red_q[29:20]};
reg [25:0] mailbox;
reg request_toggle,acknowledge_toggle;
reg [1:0] ack_audio_sync,req_video_sync;
always @(posedge I_audio_clk or posedge I_rst) begin
    if(I_rst) begin
        sample_count<=0; last_due<=0; event_due<=0;
        event_index<=0; event_index_d<=511; event_index_d2<=511;
        boundary_index<=0; due_code<=63; due_valid<=0;
        current_line<=0; next_line<=0; completed<=0;
        song_seen<=0; stream_seen<=0;
        red_q<=0; rate<=0; limit_q<=0; div_busy<=0; div_step<=0;
        div_num<=0; div_quotient<=0; div_den<=1; div_rem<=0;
        mailbox<=0; request_toggle<=0; ack_audio_sync<=0;
    end else begin
        ack_audio_sync<={ack_audio_sync[0],acknowledge_toggle};
        stream_seen<=I_stream_enable;
        event_index_d<=event_index; event_index_d2<=event_index_d;
        if(div_busy) begin
            div_num<={div_num[28:0],1'b0};
            div_rem<=subtract_ok ? trial-{1'b0,div_den} : trial;
            div_quotient<=quotient_next;
            if(div_step==29) begin rate<=quotient_next; div_busy<=0; end
            else div_step<=div_step+1'b1;
        end
        if(I_stream_enable && song_valid && (song!=song_seen || !stream_seen)) begin
            // A new file can be selected without a low pulse on the stream
            // enable.  Treat the bank change (or a stream start) as a fresh
            // stream and publish the head immediately; the first event is then
            // scheduled from sample zero for the new PCM file.
            sample_count<=0; last_due<=0; event_due<=0; event_index<=0;
            event_index_d<=511; event_index_d2<=511;
            boundary_index<=0; due_valid<=0; due_code<=63;
            // The song head is part of the same two-row stream as the lyrics:
            // title first (head row 0), followed by the first credit row.
            current_line<={1'b1,head_first}; next_line<={1'b1,head_first+5'd1};
            completed<=0; red_q<=0; rate<=0; limit_q<=0; div_busy<=0;
            song_seen<=song;
        end else if(!I_stream_enable || !I_song_matches || !song_valid ||
           (I_sample_read && sample_count==selected_song_samples-1'b1)) begin
            sample_count<=0; last_due<=0; event_due<=0; event_index<=0;
            event_index_d<=511; event_index_d2<=511;
            boundary_index<=0; due_valid<=0; due_code<=63;
            // Publish the head as soon as a valid stream/song is selected.
            // The matcher may take a few SD/UDP clocks to settle; keeping the
            // head visible during that interval avoids a blank first page.
            current_line<=(I_stream_enable && song_valid)?{1'b1,head_first}:6'd0;
            next_line<=(I_stream_enable && song_valid)?{1'b1,head_first+5'd1}:6'd0;
            completed<=0;
            red_q<=0; rate<=0; limit_q<=0; div_busy<=0;
            song_seen<=song;
        end else begin
            song_seen<=song;
            if(I_sample_read) begin
                sample_count<=sample_count+1'b1;
                if(rate!=0 && due_valid)
                    red_q<=progress_next>{1'b0,limit_q} ? limit_q : progress_next[29:0];
            end
            if(due_valid && {1'b0,sample_count}>=event_due_adjusted) begin
                last_due<=event_due; due_valid<=0; rate<=0; div_busy<=0;
                if(due_code==32) begin
                    current_line<=boundary_current; next_line<=boundary_next;
                    boundary_index<=boundary_index+1'b1;
                    completed<=0; red_q<=0;
                end else if(due_code<=20) begin
                    completed<=due_code[4:0];
                    red_q<={due_code[4:0],25'd0};
                end
                if(event_index!=511) event_index<=event_index+1'b1;
            end else if(!due_valid && event_index==event_index_d &&
                        event_index==event_index_d2 && next_event[5:0]!=63) begin
                event_due<=last_due+next_event[29:6];
                due_code<=next_event[5:0]; due_valid<=1; rate<=0;
                if(normal_red_event && current_line!=0 &&
                   next_event[29:6]!=0) begin
                    limit_q<={target_span,25'd0};
                    div_num<={column_span,25'd0}+{6'd0,next_event[29:7]};
                    div_den<=next_event[29:6]; div_rem<=0;
                    div_quotient<=0; div_step<=0; div_busy<=1;
                end
            end
        end
        if(request_toggle==ack_audio_sync[1] && mailbox!=visual_state) begin
            mailbox<=visual_state; request_toggle<=~request_toggle;
        end
    end
end
always @(posedge I_video_clk or posedge I_rst) begin
    if(I_rst) begin
        req_video_sync<=0; acknowledge_toggle<=0;
        O_line_video<=0; O_next_line_video<=0;
        O_sung_chars_video<=0; O_red_pixels_video<=0;
    end else begin
        req_video_sync<={req_video_sync[0],request_toggle};
        if(req_video_sync[1]!=acknowledge_toggle) begin
            O_line_video<=mailbox[25:18];
            O_next_line_video<=mailbox[17:10];
            O_red_pixels_video<=mailbox[9:0];
            O_sung_chars_video<=mailbox[9:5];
            acknowledge_toggle<=req_video_sync[1];
        end
    end
end
endmodule
