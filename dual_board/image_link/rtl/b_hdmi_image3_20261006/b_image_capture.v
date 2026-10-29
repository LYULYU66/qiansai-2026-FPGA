`timescale 1ns/1ps
// A single raw-BMP tap, not a second TF/decoder instance. Two SDRAM slots make
// failed/restarted loads harmless to the picture currently on the B display.
module b_image_capture #(
    parameter integer FRAME_PIXELS=307200,
    parameter [1:0] PREVIEW_INDEX=2'd1
) (
    input wire clk,rst,
    input wire source_start,source_abort,source_top_down,
    input wire [1:0] preview_target,
    input wire [2:0] source_index,
    input wire pixel_valid,
    input wire [23:0] pixel_rgb,
    input wire [7:0] pixel_tag,
    output wire pixel_ready,
    input wire writer_ack,writer_credit,writer_done_toggle,
    input wire displayed_valid,
    input wire [1:0] displayed_index,
    output reg write_req,
    output reg [1:0] write_index,
    output reg write_top_down,
    output wire write_en,
    output wire [31:0] write_data,
    output wire committed_valid,
    output wire [1:0] committed_index,
    output reg frame_loaded
);
localparam IDLE=0,SAFE=1,ACK=2,STREAM=3,DRAIN=4;
reg [2:0] state;
reg [18:0] accepted;
reg [1:0] active_index;
reg [2:0] cache_valid;
(* async_reg="true" *) reg [1:0] ack_sync;
(* async_reg="true" *) reg [2:0] done_sync;
wire complete_event=done_sync[2]^done_sync[1];
assign pixel_ready=state==STREAM && writer_credit && !source_abort;
assign write_en=pixel_valid && pixel_ready;
assign write_data={pixel_rgb,pixel_tag};
assign committed_valid=cache_valid[preview_target];
assign committed_index=preview_target;
always @(posedge clk or posedge rst) begin
    if(rst) begin
        ack_sync<=0;done_sync<=0;
    end else begin
        ack_sync<={ack_sync[0],writer_ack};
        done_sync<={done_sync[1:0],writer_done_toggle};
    end
end
always @(posedge clk or posedge rst) begin
    if(rst) begin
        state<=IDLE;accepted<=0;write_req<=0;write_index<=0;write_top_down<=0;
        active_index<=0;cache_valid<=0;frame_loaded<=0;
    end else if(source_abort) begin
        // Link/media abort cancels the writer, but is NOT a display reset.
        state<=IDLE;accepted<=0;write_req<=0;frame_loaded<=0;
    end else if(source_start && source_index>=3'd4 && source_index<=3'd6) begin
        state<=SAFE;accepted<=0;write_req<=0;
        active_index<=source_index-3'd4;
        write_index<=source_index-3'd4;
        write_top_down<=source_top_down;
        frame_loaded<=0;
    end else begin
        frame_loaded<=0;
        case(state)
        SAFE: begin
            // Each TF image owns a fixed SDRAM slot. The three slots are
            // filled once during preload, so switching pages never reloads
            // or overwrites the currently displayed frame.
            write_req<=1;state<=ACK;
        end
        ACK: if(ack_sync[1]) begin write_req<=0;state<=STREAM;end
        STREAM: if(write_en) begin
            accepted<=accepted+1'b1;
            if(accepted==FRAME_PIXELS-1) state<=DRAIN;
        end
        DRAIN: if(complete_event) begin
            cache_valid[active_index]<=1'b1;
            frame_loaded<=1'b1;
            state<=IDLE;
        end
        default: begin state<=IDLE;write_req<=0;end
        endcase
    end
end
endmodule
