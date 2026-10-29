`timescale 1ns/1ps
// CTL4 (20261020): B -> A star-sky packet, 16 bytes, every 250 us.
//   0..3  "CTL4"
//   4..13 star bundle (76 bits LE); byte 13 = {hazard, 3'b000, bundle[75:72]}
//         (20261021: bit 7 is A's safety-warning state, any of SW1..SW4):
//         {near_q4[15], far_q4[15], twinkle[8], meteor_on, meteor_x_q4[16],
//          meteor_y_q4[13], meteor_env[8]}
//   14..15 CRC16-CCITT BE over bytes 0..13
// The link is a direct fixed-peer UDP pair, so packets cannot be reordered;
// a lost packet is simply replaced 250 us later. A renders from the newest
// accepted bundle at each of its frames (< 0.03 px behind at full speed).
module media_control_star_tx #(
    parameter integer UPDATE_CYCLES=31_250
) (
    input  wire        clk, rst,
    input  wire [75:0] star_bundle,
    input  wire        hazard,          // already in clk
    input  wire        udp_ready, udp_ack,
    output wire        udp_request, udp_valid,
    output reg  [7:0]  udp_data,
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
localparam integer PAYLOAD_BYTES=14, PACKET_BYTES=16;
localparam TIMER_BITS=UPDATE_CYCLES>1 ? $clog2(UPDATE_CYCLES) : 1;
reg [TIMER_BITS-1:0] timer;
reg [1:0] state;
reg [3:0] index;
reg [15:0] crc;
reg [75:0] bundle_snap;   // data only, no reset: always loaded before it is sent
reg hazard_snap;
// star_bundle is a register output of star_motion_engine (20261021).
always @(posedge clk) if(state==1 && udp_ack) begin
    bundle_snap<=star_bundle; hazard_snap<=hazard;
end
assign udp_request=state==1;
assign udp_valid=state==2;
assign udp_length=PACKET_BYTES;
always @* begin
    case(index)
        0:udp_data="C"; 1:udp_data="T"; 2:udp_data="L"; 3:udp_data="4";
        4:udp_data=bundle_snap[7:0];   5:udp_data=bundle_snap[15:8];
        6:udp_data=bundle_snap[23:16]; 7:udp_data=bundle_snap[31:24];
        8:udp_data=bundle_snap[39:32]; 9:udp_data=bundle_snap[47:40];
        10:udp_data=bundle_snap[55:48];11:udp_data=bundle_snap[63:56];
        12:udp_data=bundle_snap[71:64];13:udp_data={hazard_snap,3'd0,bundle_snap[75:72]};
        14:udp_data=crc[15:8];
        default:udp_data=crc[7:0];
    endcase
end
always @(posedge clk or posedge rst) begin
    if(rst) begin
        timer<=0; state<=0; index<=0; crc<=16'hffff;
    end else begin
        if(timer!=UPDATE_CYCLES-1) timer<=timer+1'b1;
        case(state)
            0: if(timer==UPDATE_CYCLES-1) begin timer<=0; state<=3; end
            3: if(udp_ready) state<=1;
            1: if(udp_ack) begin state<=2; index<=0; crc<=16'hffff; end
            2: begin
                if(index<PAYLOAD_BYTES) crc<=crc_byte(crc,udp_data);
                if(index==PACKET_BYTES-1) state<=0;
                else index<=index+1'b1;
            end
        endcase
    end
end
endmodule

// A side. star_bundle is the receive register itself: after an accepted
// packet it is not modified until byte 4 of the next CTL4 packet (250 us
// later), so the toggle-qualified CDC on the video side samples it coherently.
// A packet failing the CRC changes the register but not the toggle, so the
// video side keeps the last good bundle.
module media_control_star_rx (
    input  wire        clk, rst, rx_valid,
    input  wire [7:0]  rx_data,
    input  wire [15:0] rx_length,
    output wire [75:0] star_bundle,
    output reg         bundle_toggle,     // flips with each accepted bundle
    output reg         hazard             // A's warning flag of the last good packet
);
function [15:0] crc_byte;
    input [15:0] old_crc; input [7:0] value;
    reg [15:0] c; integer i;
    begin c=old_crc^{value,8'd0};
        for(i=0;i<8;i=i+1) c=c[15] ? (c<<1)^16'h1021 : c<<1;
        crc_byte=c;
    end
endfunction
localparam integer PAYLOAD_BYTES=14, PACKET_BYTES=16;
reg previous_valid, header_ok;
reg [4:0] count;
reg [79:0] in_bundle;
reg [15:0] crc, received_crc;
assign star_bundle=in_bundle[75:0];
always @(posedge clk or posedge rst) begin
    if(rst) begin
        previous_valid<=0; header_ok<=0; count<=0; in_bundle<=0;
        crc<=16'hffff; received_crc<=0; bundle_toggle<=0; hazard<=0;
    end else begin
        previous_valid<=rx_valid;
        if(rx_valid && !previous_valid) begin
            count<=1; header_ok<=rx_length==PACKET_BYTES && rx_data=="C";
            crc<=crc_byte(16'hffff,rx_data);
        end else if(rx_valid) begin
            if(count!=31) count<=count+1'b1;
            if(count<PAYLOAD_BYTES) crc<=crc_byte(crc,rx_data);
            if(count>=4 && count<=13) in_bundle<={rx_data,in_bundle[79:8]};
            case(count)
                1: header_ok<=header_ok && rx_data=="T";
                2: header_ok<=header_ok && rx_data=="L";
                3: header_ok<=header_ok && rx_data=="4";
                13: header_ok<=header_ok && rx_data[6:4]==3'd0;
                14: received_crc[15:8]<=rx_data;
                15: received_crc[7:0]<=rx_data;
                default: if(count>15) header_ok<=0;
            endcase
        end else if(previous_valid && count==PACKET_BYTES && header_ok && crc==received_crc) begin
            bundle_toggle<=~bundle_toggle;
            hazard<=in_bundle[79];
        end
    end
end
endmodule
