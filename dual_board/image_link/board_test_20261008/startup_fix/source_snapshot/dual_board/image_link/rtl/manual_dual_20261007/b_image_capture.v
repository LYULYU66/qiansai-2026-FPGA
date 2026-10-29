`timescale 1ns/1ps
// Two local pages, each with two off-chip SDRAM slots. A reconnect writes the
// other bank; a partial or aborted frame can never replace the visible page.
module b_image_capture #(
    parameter integer FRAME_PIXELS=307200
) (
    input wire clk,rst,source_start,source_abort,source_top_down,
    input wire [2:0] source_index,
    input wire pixel_valid,
    input wire [23:0] pixel_rgb,
    output wire pixel_ready,
    input wire writer_ack,writer_credit,writer_done_toggle,
    input wire displayed_valid,
    input wire [1:0] displayed_index,
    output reg write_req,
    output reg [1:0] write_index,
    output reg write_top_down,
    output wire write_en,
    output wire [31:0] write_data,
    output reg [1:0] committed_mask,
    output reg [1:0] committed_slot0,committed_slot1,
    output reg frame_loaded
);
localparam IDLE=0,SAFE=1,ACK=2,STREAM=3,DRAIN=4;
reg [2:0] state;
reg [18:0] accepted;
reg load_page;
(* async_reg="true" *) reg [1:0] ack_sync,display_valid_sync;
(* async_reg="true" *) reg [1:0] display_index_sync0,display_index_sync1;
(* async_reg="true" *) reg [2:0] done_sync;
wire complete_event=done_sync[2]^done_sync[1];
assign pixel_ready=state==STREAM && writer_credit && !source_abort;
assign write_en=pixel_valid && pixel_ready;
assign write_data={pixel_rgb,8'd0};
always @(posedge clk or posedge rst) begin
    if(rst) begin
        ack_sync<=0;done_sync<=0;display_valid_sync<=0;
        display_index_sync0<=0;display_index_sync1<=0;
    end else begin
        ack_sync<={ack_sync[0],writer_ack};
        done_sync<={done_sync[1:0],writer_done_toggle};
        display_valid_sync<={display_valid_sync[0],displayed_valid};
        display_index_sync0<=displayed_index;
        display_index_sync1<=display_index_sync0;
    end
end
always @(posedge clk or posedge rst) begin
    if(rst) begin
        state<=IDLE;accepted<=0;write_req<=0;write_index<=0;write_top_down<=0;
        committed_mask<=0;committed_slot0<=0;committed_slot1<=2;
        frame_loaded<=0;load_page<=0;
    end else begin
        frame_loaded<=0;
        if(source_abort) begin
            state<=IDLE;accepted<=0;write_req<=0;
        end else if(source_start && (source_index==3'd4 || source_index==3'd5)) begin
            state<=SAFE;accepted<=0;write_req<=0;load_page<=source_index[0];
            if(source_index==3'd4)
                write_index<=committed_mask[0] ? {1'b0,!committed_slot0[0]} : 2'd0;
            else write_index<=committed_mask[1] ? {1'b1,!committed_slot1[0]} : 2'd2;
            write_top_down<=source_top_down;
        end else case(state)
            SAFE: if(!display_valid_sync[1] || display_index_sync1!=write_index) begin
                write_req<=1;state<=ACK;
            end
            ACK: if(ack_sync[1]) begin write_req<=0;state<=STREAM;end
            STREAM: if(write_en) begin
                accepted<=accepted+1'b1;
                if(accepted==FRAME_PIXELS-1) state<=DRAIN;
            end
            DRAIN: if(complete_event) begin
                committed_mask[load_page]<=1;
                if(load_page) committed_slot1<=write_index;
                else committed_slot0<=write_index;
                frame_loaded<=1;state<=IDLE;
            end
            default: begin state<=IDLE;write_req<=0;end
        endcase
    end
end
endmodule

// Same manual key position as A: physical KEY2. No other button is allocated.
// No free-running carousel timer. Presses against an unloaded page are ignored.
module b_manual_page_control #(
    parameter integer CLK_FREQ=125_000_000,
    parameter integer DEBOUNCE_MS=20
) (
    input wire clk,rst,key_next,
    input wire [1:0] cache_valid,
    output reg requested_page
);
wire next_press;
key_press_debounce #(.CLK_FREQ_HZ(CLK_FREQ),.DEBOUNCE_MS(DEBOUNCE_MS)) u_next(
    .clk(clk),.rst(rst),.button_in(key_next),.press_pulse(next_press));
always @(posedge clk or posedge rst) begin
    if(rst) requested_page<=0;
    else if(next_press && cache_valid[!requested_page])
        requested_page<=!requested_page;
end
endmodule
