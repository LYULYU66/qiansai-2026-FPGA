`timescale 1ns/1ps
// CTL2 legacy: 12 bytes. STAR_SYNC=1 uses CTL3, 14 bytes:
// PAGE_SYNC=1 (requires STAR_SYNC=1) uses CTL4 with the same 14 bytes;
// reserved byte 11 becomes {B displayed TF6, 7-bit entry epoch}. It is
// snapshotted with settings and phase, CRC-covered, and repeated unchanged.
// magic4, sequence32 LE, settings8, phaseQ4 LE16, reserved0, CRC16 BE.
// settings={contrast2,brightness2,volume4}. Resend the latest state every
// 10 ms: loss does not require a command FIFO or a separate ACK protocol.
module media_control_tx #(
    parameter integer UPDATE_CYCLES=1_250_000,
    parameter STAR_SYNC=0,
    parameter PAGE_SYNC=0
) (
    input wire clk, rst,
    input wire [7:0] settings,
    input wire [15:0] star_phase,
    input wire [7:0] page_token,
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
reg [3:0] index;
reg [31:0] sequence_no;
reg [7:0] snapshot;
reg [15:0] phase_snapshot;
reg [7:0] page_snapshot;
reg [15:0] crc;
localparam PAYLOAD_BYTES=STAR_SYNC ? 12 : 10;
localparam PACKET_BYTES=PAYLOAD_BYTES+2;
assign udp_request=state==1;
assign udp_valid=state==2;
assign udp_length=PACKET_BYTES;
always @* begin
    case(index)
        0:udp_data="C";1:udp_data="T";2:udp_data="L";3:udp_data=PAGE_SYNC ? "4" : (STAR_SYNC ? "3" : "2");
        4:udp_data=sequence_no[7:0];5:udp_data=sequence_no[15:8];
        6:udp_data=sequence_no[23:16];7:udp_data=sequence_no[31:24];
        8:udp_data=snapshot;9:udp_data=STAR_SYNC ? phase_snapshot[7:0] : 0;
        10:udp_data=STAR_SYNC ? phase_snapshot[15:8] : crc[15:8];
        11:udp_data=STAR_SYNC ? (PAGE_SYNC ? page_snapshot : 0) : crc[7:0];
        12:udp_data=crc[15:8];default:udp_data=crc[7:0];
    endcase
end
always @(posedge clk or posedge rst) begin
    if(rst) begin timer<=0;state<=0;index<=0;sequence_no<=0;snapshot<=8'h38;phase_snapshot<=0;page_snapshot<=0;crc<=16'hffff;end
    else begin
        if(timer!=UPDATE_CYCLES-1) timer<=timer+1'b1;
        case(state)
            0:if(timer==UPDATE_CYCLES-1) begin
                snapshot<=settings;phase_snapshot<=STAR_SYNC ? star_phase : 16'd0;
                page_snapshot<=PAGE_SYNC ? page_token : 8'd0;
                timer<=0;state<=3;
            end
            3:if(udp_ready) state<=1;
            1:if(udp_ack) begin state<=2;index<=0;crc<=16'hffff;end
            2:begin
                if(index<PAYLOAD_BYTES) crc<=crc_byte(crc,udp_data);
                if(index==PACKET_BYTES-1) begin state<=0;sequence_no<=sequence_no+1'b1;end
                else index<=index+1'b1;
            end
        endcase
    end
end
endmodule

// Validated controls are held on link loss. Sequence ordering rejects stale
// packets; after 1 s without an accepted packet a restarted B can rebase.
// This only recovers CONTROL; media-session reset recovery is independent.
module media_control_rx #(
    parameter integer REBASE_CYCLES=125_000_000,
    parameter STAR_SYNC=0,
    parameter PAGE_SYNC=0
) (
    input wire clk,rst,rx_valid,
    input wire [7:0] rx_data,
    input wire [15:0] rx_length,
    output reg update_valid,
    output reg [7:0] settings,
    output reg [15:0] star_phase,
    output reg [7:0] page_token
);
function [15:0] crc_byte;
    input [15:0] old_crc; input [7:0] value;
    reg [15:0] c; integer i;
    begin c=old_crc^{value,8'd0};
        for(i=0;i<8;i=i+1) c=c[15] ? (c<<1)^16'h1021 : c<<1;
        crc_byte=c;
    end
endfunction
localparam AGE_BITS=REBASE_CYCLES>1 ? $clog2(REBASE_CYCLES) : 1;
reg [AGE_BITS-1:0] age;
reg previous_valid,header_ok,have_sequence;
reg [3:0] count;
reg [31:0] sequence_no,last_sequence;
reg [7:0] incoming_settings;
reg [15:0] incoming_phase;
reg [7:0] incoming_page;
reg [15:0] crc,received_crc;
localparam PAYLOAD_BYTES=STAR_SYNC ? 12 : 10;
localparam PACKET_BYTES=PAYLOAD_BYTES+2;
wire [31:0] order_delta=sequence_no-last_sequence;
always @(posedge clk or posedge rst) begin
    if(rst) begin
        age<=0;previous_valid<=0;header_ok<=0;have_sequence<=0;count<=0;
        sequence_no<=0;last_sequence<=0;incoming_settings<=8'h38;
        crc<=16'hffff;received_crc<=0;update_valid<=0;settings<=8'h38;
        incoming_phase<=0;star_phase<=0;incoming_page<=0;page_token<=0;
    end else begin
        previous_valid<=rx_valid;update_valid<=0;
        if(age!=REBASE_CYCLES-1) age<=age+1'b1;
        if(rx_valid && !previous_valid) begin
            count<=1;header_ok<=rx_length==PACKET_BYTES && rx_data=="C";
            crc<=crc_byte(16'hffff,rx_data);
        end else if(rx_valid) begin
            if(count!=15) count<=count+1'b1;
            if(count<PAYLOAD_BYTES) crc<=crc_byte(crc,rx_data);
            case(count)
                1:header_ok<=header_ok && rx_data=="T";
                2:header_ok<=header_ok && rx_data=="L";
                3:header_ok<=header_ok && rx_data==(PAGE_SYNC ? "4" : (STAR_SYNC ? "3" : "2"));
                4:sequence_no[7:0]<=rx_data;5:sequence_no[15:8]<=rx_data;
                6:sequence_no[23:16]<=rx_data;7:sequence_no[31:24]<=rx_data;
                8:begin incoming_settings<=rx_data;header_ok<=header_ok && rx_data[3:0]<=8;end
                9:if(STAR_SYNC) incoming_phase[7:0]<=rx_data;
                  else header_ok<=header_ok && rx_data==0;
                10:if(STAR_SYNC)begin
                    incoming_phase[15:8]<=rx_data;
                    // 0..20479 Q4 coordinates, reject out-of-canvas phases.
                    header_ok<=header_ok && rx_data<8'd80;
                   end else received_crc[15:8]<=rx_data;
                11:if(STAR_SYNC)begin
                    if(PAGE_SYNC) incoming_page<=rx_data;
                    else header_ok<=header_ok && rx_data==0;
                   end
                   else received_crc[7:0]<=rx_data;
                12:if(STAR_SYNC)received_crc[15:8]<=rx_data;else header_ok<=0;
                13:if(STAR_SYNC)received_crc[7:0]<=rx_data;else header_ok<=0;
                default:header_ok<=0;
            endcase
        end else if(previous_valid && count==PACKET_BYTES && header_ok && crc==received_crc &&
                    (!have_sequence || !order_delta[31] || age==REBASE_CYCLES-1)) begin
            settings<=incoming_settings;update_valid<=1;last_sequence<=sequence_no;
            star_phase<=STAR_SYNC ? incoming_phase : 16'd0;
            page_token<=PAGE_SYNC ? incoming_page : 8'd0;
            have_sequence<=1;age<=0;
        end
    end
end
endmodule

