`timescale 1ns/1ps
// VIZ2: magic4 + session u32 LE + consumed-sample tag u32 LE +
// packed VU/spectrum/wave/lyric state33 + CRC16 BE = 47 bytes.
// Latest-only, not stop-and-wait: a lost visualization packet is replaceable.
module audio_visual_tx #(
    parameter integer UPDATE_CYCLES=2083333
) (
    input wire clk, rst, source_settled,
    input wire [31:0] session_id, analysed_words,
    input wire [263:0] visual_state,
    input wire udp_ready, udp_ack,
    output wire udp_request, udp_valid,
    output reg [7:0] udp_data,
    output wire [15:0] udp_length
);
function [15:0] crc_byte;
    input [15:0] old_crc; input [7:0] value;
    reg [15:0] c; integer i;
    begin c=old_crc^{value,8'd0};
        for(i=0;i<8;i=i+1) c=c[15] ? (c<<1)^16'h1021 : c<<1;
        crc_byte=c;
    end
endfunction
localparam TIMER_BITS=UPDATE_CYCLES>1 ? $clog2(UPDATE_CYCLES) : 1;
reg [TIMER_BITS-1:0] timer;
reg [1:0] state;
reg [5:0] index;
reg [31:0] session, progress;
reg [263:0] payload;
reg [15:0] crc;
// Payload is always overwritten before a packet becomes visible. Avoid a
// 264-bit reset network on temporary serialization data.
always @(posedge clk) begin
    if(state==0 && timer==UPDATE_CYCLES-1 && source_settled) payload<=visual_state;
    else if(state==2 && index>=12 && index<45) payload<=payload>>8;
end
assign udp_request=state==1;
assign udp_valid=state==2;
assign udp_length=47;
always @* begin
    case(index)
        0: udp_data="V"; 1: udp_data="I"; 2: udp_data="Z"; 3: udp_data="2";
        4: udp_data=session[7:0]; 5: udp_data=session[15:8];
        6: udp_data=session[23:16]; 7: udp_data=session[31:24];
        8: udp_data=progress[7:0]; 9: udp_data=progress[15:8];
        10: udp_data=progress[23:16]; 11: udp_data=progress[31:24];
        45: udp_data=crc[15:8]; 46: udp_data=crc[7:0];
        default: udp_data=payload[7:0];
    endcase
end
always @(posedge clk or posedge rst) begin
    if(rst) begin timer<=0; state<=0; index<=0; session<=0; progress<=0; crc<=16'hffff; end
    else begin
        if(timer!=UPDATE_CYCLES-1) timer<=timer+1'b1;
        case(state)
            0: if(timer==UPDATE_CYCLES-1 && source_settled) begin
                session<=session_id; progress<=analysed_words;
                timer<=0; state<=3;
            end
            3: if(udp_ready) state<=1;
            1: if(udp_ack) begin state<=2; index<=0; crc<=16'hffff; end
            2: begin
                if(index<45) crc<=crc_byte(crc,udp_data);
                if(index==46) state<=0; else index<=index+1'b1;
            end
        endcase
    end
end
endmodule

module audio_visual_rx (
    input wire clk, rst, rx_valid,
    input wire [7:0] rx_data,
    input wire [15:0] rx_length,
    input wire [31:0] session_id, played_words,
    output reg update_valid,
    output reg [263:0] visual_state
);
function [15:0] crc_byte;
    input [15:0] old_crc; input [7:0] value;
    reg [15:0] c; integer i;
    begin c=old_crc^{value,8'd0};
        for(i=0;i<8;i=i+1) c=c[15] ? (c<<1)^16'h1021 : c<<1;
        crc_byte=c;
    end
endfunction
reg previous_valid, header_ok, have_update;
reg [5:0] count;
reg [15:0] crc, received_crc;
reg [31:0] session, progress, last_progress;
reg [263:0] payload;
wire [31:0] available_delta=played_words-progress;
wire [31:0] ordered_delta=progress-last_progress;
always @(posedge clk) begin
    if(rx_valid && previous_valid && count>=12 && count<45)
        payload<={rx_data,payload[263:8]};
end
always @(posedge clk or posedge rst) begin
    if(rst) begin
        previous_valid<=0; header_ok<=0; have_update<=0; count<=0;
        crc<=16'hffff; received_crc<=0; session<=0; progress<=0; last_progress<=0;
        visual_state<=0; update_valid<=0;
    end else begin
        previous_valid<=rx_valid; update_valid<=0;
        if(rx_valid && !previous_valid) begin
            count<=1; header_ok<=rx_length==47 && rx_data=="V";
            crc<=crc_byte(16'hffff,rx_data);
        end else if(rx_valid) begin
            if(count!=63) count<=count+1'b1;
            if(count<45) crc<=crc_byte(crc,rx_data);
            case(count)
                1: header_ok<=header_ok && rx_data=="I";
                2: header_ok<=header_ok && rx_data=="Z";
                3: header_ok<=header_ok && rx_data=="2";
                4: session[7:0]<=rx_data; 5: session[15:8]<=rx_data;
                6: session[23:16]<=rx_data; 7: session[31:24]<=rx_data;
                8: progress[7:0]<=rx_data; 9: progress[15:8]<=rx_data;
                10: progress[23:16]<=rx_data; 11: progress[31:24]<=rx_data;
                45: received_crc[15:8]<=rx_data; 46: received_crc[7:0]<=rx_data;
                default: if(count<12 || count>=45) header_ok<=0;
            endcase
        end else if(previous_valid && count==47 && header_ok && crc==received_crc &&
                    session==session_id && !available_delta[31] &&
                    (!have_update || !ordered_delta[31])) begin
            visual_state<=payload; update_valid<=1; last_progress<=progress; have_update<=1;
        end
    end
end
endmodule

// Coherent bundled-data CDC; the mailbox remains fixed until video ACK.
// The displayed state only changes at VS, never halfway through a frame.
module audio_visual_cdc #(
    parameter integer WIDTH=264,
    parameter FRAME_BOUNDARY=1,
    parameter [WIDTH-1:0] RESET_STATE=0
) (
    input wire udp_clk, video_clk, rst, frame_vs,
    input wire update_valid, publish_enable,
    input wire [WIDTH-1:0] visual_state,
    output reg [WIDTH-1:0] frame_state,
    output reg capture_valid
);
reg [WIDTH-1:0] mailbox;
reg request_toggle, acknowledge_toggle, previous_vs;
(* async_reg="true" *) reg [1:0] ack_sync, req_sync;
(* async_reg="true" *) reg [1:0] source_release, destination_release;
wire source_reset=rst || source_release[1];
wire destination_reset=rst || destination_release[1];
always @(posedge udp_clk or posedge rst) begin
    if(rst) source_release<=2'b11;
    else source_release<={source_release[0],1'b0};
end
always @(posedge video_clk or posedge rst) begin
    if(rst) destination_release<=2'b11;
    else destination_release<={destination_release[0],1'b0};
end
always @(posedge udp_clk or posedge source_reset) begin
    if(source_reset) begin mailbox<=RESET_STATE; request_toggle<=0; ack_sync<=0; end
    else begin
        ack_sync<={ack_sync[0],acknowledge_toggle};
        if(publish_enable && request_toggle==ack_sync[1] && (update_valid || mailbox!=visual_state)) begin
            mailbox<=visual_state; request_toggle<=~request_toggle;
        end
    end
end
always @(posedge video_clk or posedge destination_reset) begin
    if(destination_reset) begin frame_state<=RESET_STATE; acknowledge_toggle<=0; req_sync<=0; previous_vs<=0; capture_valid<=0; end
    else begin
        capture_valid<=0;
        previous_vs<=frame_vs; req_sync<={req_sync[0],request_toggle};
        if((!FRAME_BOUNDARY || (frame_vs && !previous_vs)) && req_sync[1]!=acknowledge_toggle) begin
            frame_state<=mailbox; acknowledge_toggle<=req_sync[1]; capture_valid<=1;
        end
    end
end
endmodule
