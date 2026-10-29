// Actual PCM sample timeline; compact delta ROM plus Q20 pixel interpolation.
// No wall-clock advance during underflow. Intro/interlude maps share the song.
module audio_lyric_timeline #(
    parameter [23:0] SONG_SAMPLES=24'd10043560,
    parameter DUAL_SONG=0
)(
    input I_audio_clk,I_video_clk,I_rst,I_stream_enable,I_song_matches,I_sample_read,
    input I_song,
    output reg [7:0] O_line_video,O_next_line_video,
    output reg [4:0] O_sung_chars_video,
    output reg [9:0] O_red_pixels_video
);
reg [23:0] sample_count,last_due,event_due;
reg [8:0] event_index,event_index_d,event_index_d2;
reg [5:0] boundary_index,due_code;
reg due_valid;
reg [4:0] current_line,next_line,completed;
wire [29:0] next_event;
wire [4:0] boundary_current,boundary_next;
wire song=DUAL_SONG && I_song;
wire [23:0] selected_song_samples=song ? 24'd14122496 : SONG_SAMPLES;
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
wire [4:0] column_span=next_event[4:0]-completed;

// Bundled-data mailbox holds both lines and the exact pixel boundary stable
// until acknowledged. Video takes a coherent snapshot only at VS.
wire [21:0] visual_state={song,current_line,song,next_line,red_q[29:20]};
reg [21:0] mailbox;
reg request_toggle,acknowledge_toggle;
reg [1:0] ack_audio_sync,req_video_sync;
always @(posedge I_audio_clk or posedge I_rst) begin
    if(I_rst) begin
        sample_count<=0; last_due<=0; event_due<=0;
        event_index<=0; event_index_d<=511; event_index_d2<=511;
        boundary_index<=0; due_code<=63; due_valid<=0;
        current_line<=0; next_line<=0; completed<=0;
        red_q<=0; rate<=0; limit_q<=0; div_busy<=0; div_step<=0;
        div_num<=0; div_quotient<=0; div_den<=1; div_rem<=0;
        mailbox<=0; request_toggle<=0; ack_audio_sync<=0;
    end else begin
        ack_audio_sync<={ack_audio_sync[0],acknowledge_toggle};
        event_index_d<=event_index; event_index_d2<=event_index_d;
        if(div_busy) begin
            div_num<={div_num[28:0],1'b0};
            div_rem<=subtract_ok ? trial-{1'b0,div_den} : trial;
            div_quotient<=quotient_next;
            if(div_step==29) begin rate<=quotient_next; div_busy<=0; end
            else div_step<=div_step+1'b1;
        end
        if(!I_stream_enable || !I_song_matches ||
           (I_sample_read && sample_count==selected_song_samples-1'b1)) begin
            sample_count<=0; last_due<=0; event_due<=0; event_index<=0;
            boundary_index<=0; due_valid<=0; due_code<=63;
            // An exact EOF goes straight to next-loop song information.
            // Stop/wrong-file still clears; no transient first-verse preview.
            current_line<=(I_stream_enable && I_song_matches)?5'd23:5'd0;
            next_line<=(I_stream_enable && I_song_matches)?5'd24:5'd0;
            completed<=0;
            red_q<=0; rate<=0; limit_q<=0; div_busy<=0;
        end else begin
            if(I_sample_read) begin
                sample_count<=sample_count+1'b1;
                if(rate!=0 && due_valid)
                    red_q<=progress_next>{1'b0,limit_q} ? limit_q : progress_next[29:0];
            end
            if(due_valid && sample_count>=event_due) begin
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
                if(next_event[5:0]<=20 && next_event[4:0]>completed &&
                   current_line!=0 && current_line!=22 && current_line<26 &&
                   next_event[29:6]!=0) begin
                    limit_q<={next_event[4:0],25'd0};
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
            O_line_video<={2'd0,mailbox[21:16]};
            O_next_line_video<={2'd0,mailbox[15:10]};
            O_red_pixels_video<=mailbox[9:0];
            O_sung_chars_video<=mailbox[9:5];
            acknowledge_toggle<=req_video_sync[1];
        end
    end
end
endmodule
