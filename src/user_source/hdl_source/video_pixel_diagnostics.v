// Read-only probes and same-bitstream pixel-source isolation. No memory.
// Inputs to the image processor are replaced in mode 1; its one registered
// cycle is mirrored by pattern_d for mode 2 at the final AXIS adapter input.
module video_pixel_diagnostics (
    input wire I_clk, I_rst,
    input wire [1:0] I_requested_mode,
    input wire I_clear_toggle,
    input wire I_vs, I_de,
    input wire [23:0] I_image_rgb, I_processed_rgb,
    input wire I_monitor_enable,
    input wire I_read_en, I_empty_a, I_empty_b, I_read_b_enable,
    input wire I_axis_valid, I_axis_ready, I_hdmi_locked,
    input wire I_crc_vs, I_crc_de, I_crc_stable,
    input wire [23:0] I_crc_rgb,
    input wire [1:0] I_crc_image_idx,
    input wire I_axis_source_vs, I_axis_source_de,
    input wire [23:0] I_axis_source_rgb, I_axis_data,
    input wire I_axis_user, I_axis_last, I_fifo_valid_a,
    input wire [23:0] I_fifo_rgb_a,
    output wire [23:0] O_image_rgb, O_final_rgb,
    output wire [12:0] O_status
);
reg [1:0] mode_meta, mode_sync, mode_stable, mode_frame;
reg clear_meta, clear_sync, clear_seen, vs_d;
reg [9:0] x;
reg [23:0] pattern_d;
reg [2:0] flags;
wire frame_edge = I_vs && !vs_d;
// Eight repeating dark-grey steps. Identical top and bottom halves permit
// spatial comparison; low RGB bits are zero, just like the existing image path.
wire [7:0] grey = {2'b00,x[6:4],3'b000};
wire [23:0] pattern = {grey,grey,grey};
assign O_image_rgb = (mode_frame == 2'd1) ? pattern : I_image_rgb;
assign O_final_rgb = (mode_frame == 2'd2) ? pattern_d : I_processed_rgb;
wire crc_changed, crc_valid;
// The extended alignment probe was an unfinished flicker investigation.
// Keep its UART fields zero in this playback build; no probe loads the video
// path or consumes the extra ~1.7k LUTs seen during trial synthesis.
wire [4:0] alignment_flags = 5'd0;
wire alignment_ready = 1'b0;
assign O_status = {alignment_ready,alignment_flags,crc_valid,crc_changed,mode_frame,flags};
video_frame_crc_monitor u_frame_crc (
    .I_clk(I_clk), .I_rst(I_rst), .I_clear(clear_sync != clear_seen),
    .I_vs(I_crc_vs), .I_de(I_crc_de), .I_rgb(I_crc_rgb),
    .I_stable(I_crc_stable), .I_image_idx(I_crc_image_idx),
    .O_changed(crc_changed), .O_valid(crc_valid)
);
always @(posedge I_clk or posedge I_rst) begin
    if (I_rst) begin
        mode_meta<=0; mode_sync<=0; mode_stable<=0; mode_frame<=0;
        clear_meta<=0; clear_sync<=0; clear_seen<=0; vs_d<=0;
        x<=0; pattern_d<=0; flags<=0;
    end else begin
        mode_meta<=I_requested_mode;
        mode_sync<=mode_meta;
        if (mode_meta == mode_sync) mode_stable<=mode_sync;
        clear_meta<=I_clear_toggle;
        clear_sync<=clear_meta;
        clear_seen<=clear_sync;
        vs_d<=I_vs;
        if (frame_edge)
            mode_frame <= (mode_stable > 2'd2) ? 2'd0 : mode_stable;
        if (!I_de) x<=0;
        else if (x == 10'd639) x<=0;
        else x<=x+1'b1;
        pattern_d <= I_de ? pattern : 24'd0;
        if (clear_sync != clear_seen) flags<=0;
        else if (I_monitor_enable) begin
            if (I_read_en && I_empty_a) flags[0]<=1;
            if (I_read_en && I_read_b_enable && I_empty_b) flags[1]<=1;
            if (I_hdmi_locked && I_axis_valid && !I_axis_ready) flags[2]<=1;
        end
    end
end
endmodule

// Passive pixel-clock probes. Flags [4:0] = E/R/F/L/S. O_ready becomes
// true after one complete observed frame (not a claim that the frame passed).
// No control/handshake signal is driven back into the display pipeline.
module video_alignment_monitor #(
    parameter integer H_ACTIVE=640,
    parameter integer V_ACTIVE=480
)(
    input wire I_clk, I_rst, I_clear, I_enable,
    input wire I_source_vs, I_source_de,
    input wire [23:0] I_source_rgb,
    input wire I_axis_valid, I_axis_user, I_axis_last,
    input wire [23:0] I_axis_rgb,
    input wire I_read_en, I_empty_a, I_fifo_valid,
    input wire [23:0] I_fifo_rgb,
    input wire I_raw_de,
    input wire [23:0] I_raw_rgb,
    output reg [4:0] O_flags,
    output reg O_ready
);
reg ref_vs, ref_de, prev_vs, prev_de, frame_open, sof_pending;
reg [9:0] line_pixels, frame_lines;
reg [2:0] warm;
reg accepted_d, fifo_valid_d;
// Independent, enable-gated reference FFs must survive synthesis. Their
// disabled-state behaviour differs from the actual display registers.
reg [23:0] axis_rgb_ref; /* fehdl keep="true" */
reg [23:0] fifo_rgb_ref; /* fehdl keep="true" */
wire vs_edge = ref_vs != prev_vs;
wire frame_edge = ref_vs && !prev_vs;
wire line_first = ref_de && !prev_de;
wire expected_sof = line_first && (sof_pending || vs_edge);
wire expected_last = ref_de && (prev_de ? (line_pixels == H_ACTIVE-1) : (H_ACTIVE == 1));
always @(posedge I_clk or posedge I_rst) begin
    if(I_rst) begin
        ref_vs<=0; ref_de<=0; prev_vs<=0; prev_de<=0;
        frame_open<=0; sof_pending<=1;
        line_pixels<=0; frame_lines<=0; warm<=0;
        accepted_d<=0; fifo_valid_d<=0; axis_rgb_ref<=0; fifo_rgb_ref<=0;
        O_flags<=0; O_ready<=0;
    end else begin
        ref_vs<=I_source_vs;
        ref_de<=I_enable && I_source_de;
        prev_vs<=ref_vs; prev_de<=ref_de;
        accepted_d<=I_enable && I_read_en && !I_empty_a;
        fifo_valid_d<=I_enable && I_fifo_valid;
        axis_rgb_ref<=I_enable ? I_source_rgb : 24'd0;
        fifo_rgb_ref<=I_enable ? I_fifo_rgb : 24'd0;
        if(I_clear) O_flags<=0;
        if(I_clear || !I_enable) begin
            frame_open<=0; sof_pending<=1;
            line_pixels<=0; frame_lines<=0; warm<=0; O_ready<=0;
        end else begin
            warm<={warm[1:0],1'b1};
            if(vs_edge) sof_pending<=1;
            if(expected_sof) sof_pending<=0;
            if(frame_edge) begin
                if(frame_open) begin
                    O_ready<=1;
                    if(frame_lines != V_ACTIVE || ref_de || prev_de) O_flags[2]<=1;
                end
                frame_open<=1; frame_lines<=0; line_pixels<=0;
            end
            if(frame_open) begin
                // S: SOF wrong beat, missing/extra, or VS inside active video.
                if(I_axis_user != expected_sof || (vs_edge && ref_de)) O_flags[0]<=1;
                // L: source line length OR AXIS EOL beat mismatch.
                if(I_axis_last != expected_last) O_flags[1]<=1;
                if(ref_de) begin
                    if(!prev_de) line_pixels<=10'd1;
                    else if(line_pixels != 10'h3ff) line_pixels<=line_pixels+1'b1;
                end else if(prev_de) begin
                    if(line_pixels != H_ACTIVE) O_flags[1]<=1;
                    if(frame_lines != 10'h3ff) frame_lines<=frame_lines+1'b1;
                    if(frame_lines >= V_ACTIVE) O_flags[2]<=1;
                    line_pixels<=0;
                end
                // E: AXIS valid/data disagree with its registered input.
                if(I_axis_valid != ref_de || (ref_de && I_axis_rgb != axis_rgb_ref)) O_flags[4]<=1;
                // R: accepted read -> FIFO valid -> raw video valid/data.
                // Expected latency follows this project's NOREG/non-showahead FIFO.
                if(&warm) begin
                    if(I_fifo_valid != accepted_d || I_raw_de != fifo_valid_d ||
                       (I_raw_de && I_raw_rgb != fifo_rgb_ref)) O_flags[3]<=1;
                end
            end
        end
    end
end
endmodule

// CRC checks raw visible RGB immediately after video_delay, before transitions,
// brightness and overlays. A mismatch is meaningful only for complete frames
// of the same stationary image. No framebuffer and no feedback into playback.
module video_frame_crc_monitor #(
    parameter integer FRAME_PIXELS = 307200
)(
    input wire I_clk, I_rst, I_clear,
    input wire I_vs, I_de, I_stable,
    input wire [23:0] I_rgb,
    input wire [1:0] I_image_idx,
    output reg O_changed, O_valid
);
reg vs_d, frame_open, frame_clean, baseline_valid;
reg [1:0] frame_idx, baseline_idx;
reg [18:0] pixel_count;
reg [15:0] frame_crc, baseline_crc;
wire frame_edge = I_vs && !vs_d;
function [15:0] crc24;
    input [15:0] previous;
    input [23:0] pixel;
    reg [15:0] c;
    integer b;
    begin
        c=previous;
        for(b=23;b>=0;b=b-1) begin
            if(c[15] ^ pixel[b]) c={c[14:0],1'b0} ^ 16'h1021;
            else c={c[14:0],1'b0};
        end
        crc24=c;
    end
endfunction
always @(posedge I_clk or posedge I_rst) begin
    if(I_rst) begin
        vs_d<=0; frame_open<=0; frame_clean<=0; baseline_valid<=0;
        frame_idx<=0; baseline_idx<=0; pixel_count<=0;
        frame_crc<=16'hffff; baseline_crc<=0;
        O_changed<=0; O_valid<=0;
    end else begin
        vs_d<=I_vs;
        if(I_clear) begin
            frame_open<=0; frame_clean<=0; baseline_valid<=0;
            pixel_count<=0; frame_crc<=16'hffff;
            O_changed<=0; O_valid<=0;
        end else begin
            // Invalidate immediately during transitions, startup or buffer
            // index changes, including changes in the middle of a frame.
            if(!I_stable || (frame_open && I_image_idx != frame_idx)) begin
                frame_clean<=0; baseline_valid<=0; O_valid<=0;
            end
            if(frame_edge) begin
                if(frame_open && frame_clean && I_stable && !I_de &&
                   I_image_idx == frame_idx && pixel_count == FRAME_PIXELS) begin
                    if(baseline_valid && baseline_idx == frame_idx) begin
                        O_valid<=1;
                        if(frame_crc != baseline_crc) O_changed<=1;
                    end else O_valid<=0;
                    baseline_crc<=frame_crc;
                    baseline_idx<=frame_idx;
                    baseline_valid<=1;
                end else begin
                    baseline_valid<=0; O_valid<=0;
                end
                frame_open<=1;
                frame_clean<=I_stable && !I_de;
                frame_idx<=I_image_idx;
                pixel_count<=0;
                frame_crc<=16'hffff;
            end else if(I_de && frame_open) begin
                if(pixel_count < FRAME_PIXELS) begin
                    pixel_count<=pixel_count+1'b1;
                    frame_crc<=crc24(frame_crc,I_rgb);
                end else frame_clean<=0;
            end
        end
    end
end
endmodule
