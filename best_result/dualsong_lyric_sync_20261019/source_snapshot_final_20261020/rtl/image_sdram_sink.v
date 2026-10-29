`timescale 1ns/1ps
// Runs in the UDP/write_clk domain. Connect writer outputs directly to the
// existing frame_read_write ports, and cross mem-clock write_finish as a toggle.
module image_sdram_sink #(
    parameter integer FRAME_PACKETS=1200,
    parameter integer TIMEOUT_CYCLES=250_000_000,
    parameter integer UI_TAG=0,
    parameter integer RESOLUTION=0,
    parameter integer RECOVERY=0,
    parameter integer REUSE_CACHE=0
) (
    input wire clk, rst,
    input wire restart_transfer,
    input wire frame_start, frame_complete, frame_abort,
    input wire [1:0] frame_index,
    input wire frame_top_down,
    input wire [31:0] frame_resolution,
    input wire pixel_valid,
    input wire [23:0] pixel_rgb,
    input wire [7:0] pixel_tag,
    output wire pixel_ready,
    input wire packet_done,
    input wire [31:0] packet_token,
    input wire [15:0] packet_sequence,
    input wire writer_ready, writer_ack,
    input wire writer_finish_toggle,
    input wire [3:0] protected_buffers,
    output reg write_req, write_abort,
    output wire write_en,
    output wire [31:0] write_data,
    output reg [1:0] write_index,
    output reg write_top_down,
    output reg receipt_event,
    output reg [31:0] receipt_token,
    output reg [15:0] receipt_sequence,
    output reg [3:0] cache_valid,
    output reg [127:0] source_resolutions,
    output reg commit_toggle,
    output reg receive_reset,
    output reg fault
);
localparam IDLE=0, CLEAR=1, REQUEST=2, WRITE=3, VERIFY=4;
reg [2:0] state;
reg [3:0] clear_count;
reg [2:0] ack_sync, finish_sync;
reg protocol_done, memory_done;
reg [31:0] final_token;
reg [15:0] final_sequence;
reg [18:0] count;
localparam integer TIMEOUT_BITS=TIMEOUT_CYCLES>1 ? $clog2(TIMEOUT_CYCLES) : 1;
reg [TIMEOUT_BITS-1:0] timeout_count;
// Timing (20261019): the timeout compare and the per-buffer frame-start
// decision are registered, so the 125 MHz state update no longer chains a
// 2-bit buffer index, a 32-bit resolution compare and a 32-bit timeout
// compare. frame_start is acted on one clock later (start_pending), with
// pixel_ready and commit held off for that clock.
reg timeout_hit, start_pending;
reg start_protected, start_reuse_ok;
reg [31:0] pending_resolution;
reg [31:0] frame_crc, expected_crc;
reg [15:0] crc_low_half;
reg crc_pending, final_ack_valid;
// Packed registers, no large RAM and no bulk reset. cache_valid guards every
// use; these fingerprints are installed only after a real SDRAM commit.
reg [127:0] cached_crc;
reg [3:0] cached_top_down;
function [31:0] crc32_half;
    input [31:0] old_crc; input [15:0] value;
    reg [31:0] c; integer i;
    begin
        c=old_crc;
        // First high byte, then low byte; each byte is processed LSB first.
        for(i=0;i<16;i=i+1)
            c=(c>>1)^((c[0]^value[i<8 ? i+8 : i-8]) ? 32'hedb88320 : 32'd0);
        crc32_half=c;
    end
endfunction
wire finish_edge=finish_sync[2]^finish_sync[1];
wire consumed=pixel_valid && pixel_ready;
wire crc_idle=!REUSE_CACHE || !crc_pending;
wire [31:0] next_crc=crc32_half(frame_crc,crc_pending ? crc_low_half : pixel_rgb[23:8]);
wire write_commit=state==WRITE && protocol_done && memory_done &&
                  count==FRAME_PACKETS*256 && crc_idle && !rst &&
                  !(RECOVERY && restart_transfer) && !frame_start && !start_pending &&
                  !frame_abort;
assign pixel_ready=((state==WRITE && writer_ready && !write_abort) ||
                    (REUSE_CACHE && state==VERIFY)) && !rst && crc_idle &&
                   !start_pending && !(RECOVERY && restart_transfer);
assign write_en=consumed && state==WRITE;
assign write_data={pixel_rgb,UI_TAG ? pixel_tag : 8'd0};
always @(posedge clk) if(REUSE_CACHE && write_commit) begin
    cached_crc[write_index*32 +: 32]<=frame_crc;
    cached_top_down[write_index]<=write_top_down;
end
always @(posedge clk or posedge rst) begin
    if(rst) begin
        state<=IDLE; clear_count<=0; ack_sync<=0; finish_sync<=0;
        protocol_done<=0; memory_done<=0; final_token<=0; final_sequence<=0;
        count<=0; timeout_count<=0; write_req<=0; write_abort<=1;
        write_index<=0; write_top_down<=0; receipt_event<=0;
        receipt_token<=0; receipt_sequence<=0; cache_valid<=0;
        commit_toggle<=0; receive_reset<=0; fault<=0;
        pending_resolution<=0;source_resolutions<=0;
        frame_crc<=32'hffffffff; expected_crc<=0; crc_low_half<=0;
        crc_pending<=0; final_ack_valid<=0;
        timeout_hit<=0; start_pending<=0; start_protected<=0; start_reuse_ok<=0;
    end else begin
        ack_sync<={ack_sync[1:0],writer_ack};
        // frame_index/top/resolution are held by the receiver after its
        // frame_start pulse, so the decision registered here stays valid.
        start_pending<=frame_start && !(RECOVERY && restart_transfer);
        start_protected<=protected_buffers[frame_index];
        start_reuse_ok<=REUSE_CACHE && cache_valid[frame_index] &&
            source_resolutions[frame_index*32 +: 32]==
                (RESOLUTION ? frame_resolution : 32'h028001e0) &&
            cached_top_down[frame_index]==frame_top_down;
        timeout_hit<=state!=IDLE && !consumed && !packet_done && !frame_start &&
            !start_pending && !frame_abort && !(RECOVERY && restart_transfer) &&
            timeout_count>=TIMEOUT_CYCLES-1;
        finish_sync<={finish_sync[1:0],writer_finish_toggle};
        receipt_event<=0; receive_reset<=0;
        if(state!=IDLE) begin
            if(consumed || packet_done) timeout_count<=0;
            else timeout_count<=timeout_count+1'b1;
        end else timeout_count<=0;
        // The receiver already exposes one pixel every two clocks. Two
        // 16-bit CRC steps preserve that rate without a 32-bit parallel XOR
        // network. Holding ready low also handles a faster synthetic source.
        if(REUSE_CACHE && consumed) begin
            frame_crc<=next_crc;
            crc_low_half<={pixel_rgb[7:0],UI_TAG ? pixel_tag : 8'd0};
            crc_pending<=1;
        end else if(REUSE_CACHE && crc_pending) begin
            frame_crc<=next_crc; crc_pending<=0;
        end
        if(RECOVERY && restart_transfer) begin
            // A lease change aborts only an unfinished transfer. Committed
            // buffers and their dimensions remain usable by local HDMI.
            state<=IDLE; write_req<=0; write_abort<=1; receive_reset<=1;
            protocol_done<=0; memory_done<=0; count<=0; timeout_count<=0;
            final_token<=0; final_sequence<=0;
            crc_pending<=0; final_ack_valid<=0;
        end else if(start_pending) begin
            frame_crc<=32'hffffffff; crc_pending<=0; final_ack_valid<=0;
            if(start_protected) begin
                // Replaying the current image after B reset is read-only:
                // consume all verified packet pixels, compare the complete
                // fingerprint, and ACK the final packet only on a match.
                write_req<=0; write_abort<=1;
                if(start_reuse_ok) begin
                    state<=VERIFY; write_index<=frame_index;
                    expected_crc<=cached_crc[frame_index*32 +: 32];
                    protocol_done<=0; memory_done<=0; count<=0; timeout_count<=0;
                end else begin
                    state<=IDLE; receive_reset<=1; fault<=1;
                end
            end else begin
                state<=CLEAR; clear_count<=0; write_req<=0; write_abort<=1;
                write_index<=frame_index; write_top_down<=frame_top_down;
                pending_resolution<=RESOLUTION ? frame_resolution : 32'h028001e0;
                cache_valid[frame_index]<=0;
                protocol_done<=0; memory_done<=0; count<=0; timeout_count<=0;
            end
        end else if(frame_abort || timeout_hit) begin
            state<=IDLE; write_req<=0; write_abort<=1; receive_reset<=1; fault<=1;
            protocol_done<=0; memory_done<=0;
            crc_pending<=0; final_ack_valid<=0;
        end else case(state)
            IDLE: begin
                // Lost final ACK: a duplicate packet after commit is safe to
                // acknowledge again, without rewriting the cached frame.
                if(packet_done && packet_token==final_token &&
                   packet_sequence==final_sequence && cache_valid[write_index] &&
                   (!REUSE_CACHE || final_ack_valid)) begin
                    receipt_event<=1; receipt_token<=packet_token;
                    receipt_sequence<=packet_sequence;
                end
            end
            CLEAR: begin
                if(clear_count==15) begin
                    write_abort<=0; write_req<=1; state<=REQUEST;
                end else clear_count<=clear_count+1'b1;
            end
            REQUEST: if(ack_sync[2]) begin
                write_req<=0; state<=WRITE; memory_done<=0;
            end
            WRITE: begin
                if(write_en) count<=count+1'b1;
                if(finish_edge) memory_done<=1;
                if(frame_complete) protocol_done<=1;
                if(packet_done) begin
                    if(packet_sequence==FRAME_PACKETS-1) begin
                        final_token<=packet_token; final_sequence<=packet_sequence;
                    end else begin
                        receipt_event<=1; receipt_token<=packet_token;
                        receipt_sequence<=packet_sequence;
                    end
                end
                if(write_commit) begin
                    cache_valid[write_index]<=1; commit_toggle<=~commit_toggle;
                    source_resolutions[write_index*32 +: 32]<=pending_resolution;
                    receipt_event<=1; receipt_token<=final_token;
                    receipt_sequence<=final_sequence;
                    final_ack_valid<=1;
                    state<=IDLE;
                end
            end
            VERIFY: begin
                if(consumed) count<=count+1'b1;
                if(frame_complete) protocol_done<=1;
                if(packet_done) begin
                    if(packet_sequence==FRAME_PACKETS-1) begin
                        final_token<=packet_token; final_sequence<=packet_sequence;
                    end else begin
                        receipt_event<=1; receipt_token<=packet_token;
                        receipt_sequence<=packet_sequence;
                    end
                end
                if(protocol_done && count==FRAME_PACKETS*256 && crc_idle) begin
                    state<=IDLE;
                    if(frame_crc==expected_crc) begin
                        receipt_event<=1; receipt_token<=final_token;
                        receipt_sequence<=final_sequence; final_ack_valid<=1;
                    end else begin
                        // cached pixels/metadata stay intact. In particular,
                        // a retry of this failed final packet must NOT get ACK.
                        receive_reset<=1; fault<=1; final_ack_valid<=0;
                    end
                end
            end
        endcase
    end
end
endmodule
