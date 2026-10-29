`timescale 1ns/1ps
// CTL4 (20261020): B -> A control/star-sky packet, 21 bytes, every 250 us.
//   0..3 "CTL4"   4..7 sequence u32 LE   8 settings
//   9..18 star bundle (76 bits LE, top 4 bits zero):
//         {near_q4[15], far_q4[15], twinkle[8], meteor_on, meteor_x_q4[16],
//          meteor_y_q4[13], meteor_env[8]}
//   19..20 CRC16-CCITT BE over bytes 0..18
// The bundle is latched when the UDP scheduler accepts the packet. A renders
// from the newest accepted bundle at each of its frames; at 4 kHz the bundle
// is at most 0.25 ms old (< 0.03 px at the fastest sky speed).
module media_control_star_tx #(
    parameter integer UPDATE_CYCLES=31_250
) (
    input  wire        clk, rst,
    input  wire [7:0]  settings,
    input  wire [75:0] star_bundle,
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
localparam integer PAYLOAD_BYTES=19, PACKET_BYTES=21;
localparam TIMER_BITS=UPDATE_CYCLES>1 ? $clog2(UPDATE_CYCLES) : 1;
reg [TIMER_BITS-1:0] timer;
reg [1:0] state;
reg [4:0] index;
reg [31:0] sequence_no;
reg [75:0] bundle_snap;
reg [7:0] settings_snap;
reg [15:0] crc;
assign udp_request=state==1;
assign udp_valid=state==2;
assign udp_length=PACKET_BYTES;
always @* begin
    case(index)
        0:udp_data="C"; 1:udp_data="T"; 2:udp_data="L"; 3:udp_data="4";
        4:udp_data=sequence_no[7:0];  5:udp_data=sequence_no[15:8];
        6:udp_data=sequence_no[23:16];7:udp_data=sequence_no[31:24];
        8:udp_data=settings_snap;
        9:udp_data=bundle_snap[7:0];   10:udp_data=bundle_snap[15:8];
        11:udp_data=bundle_snap[23:16];12:udp_data=bundle_snap[31:24];
        13:udp_data=bundle_snap[39:32];14:udp_data=bundle_snap[47:40];
        15:udp_data=bundle_snap[55:48];16:udp_data=bundle_snap[63:56];
        17:udp_data=bundle_snap[71:64];18:udp_data={4'd0,bundle_snap[75:72]};
        19:udp_data=crc[15:8];
        default:udp_data=crc[7:0];
    endcase
end
always @(posedge clk) if(state==1 && udp_ack) bundle_snap<=star_bundle;
always @(posedge clk or posedge rst) begin
    if(rst) begin
        timer<=0; state<=0; index<=0; sequence_no<=0; crc<=16'hffff;
        settings_snap<=8'h38;
    end else begin
        if(timer!=UPDATE_CYCLES-1) timer<=timer+1'b1;
        case(state)
            0: if(timer==UPDATE_CYCLES-1) begin timer<=0; state<=3; end
            3: if(udp_ready) state<=1;
            1: if(udp_ack) begin
                state<=2; index<=0; crc<=16'hffff;
                settings_snap<=settings;
            end
            2: begin
                if(index<PAYLOAD_BYTES) crc<=crc_byte(crc,udp_data);
                if(index==PACKET_BYTES-1) begin state<=0; sequence_no<=sequence_no+1'b1; end
                else index<=index+1'b1;
            end
        endcase
    end
end
endmodule

// A side. Sequence ordering rejects stale packets; after 1 s without an
// accepted packet a restarted B is accepted again. The bundle is held until
// the next accepted packet.
module media_control_star_rx #(
    parameter integer REBASE_CYCLES=125_000_000
) (
    input  wire        clk, rst, rx_valid,
    input  wire [7:0]  rx_data,
    input  wire [15:0] rx_length,
    output reg         update_valid,
    output reg  [7:0]  settings,
    output reg  [75:0] star_bundle,
    output reg         bundle_toggle      // flips with each accepted bundle
);
function [15:0] crc_byte;
    input [15:0] old_crc; input [7:0] value;
    reg [15:0] c; integer i;
    begin c=old_crc^{value,8'd0};
        for(i=0;i<8;i=i+1) c=c[15] ? (c<<1)^16'h1021 : c<<1;
        crc_byte=c;
    end
endfunction
localparam integer PAYLOAD_BYTES=19, PACKET_BYTES=21;
localparam AGE_BITS=REBASE_CYCLES>1 ? $clog2(REBASE_CYCLES) : 1;
reg [AGE_BITS-1:0] age;
reg previous_valid, header_ok, have_sequence;
reg [4:0] count;
reg [31:0] sequence_no, last_sequence;
reg [79:0] in_bundle;
reg [15:0] crc, received_crc;
reg [7:0] in_settings;
wire [31:0] order_delta=sequence_no-last_sequence;
always @(posedge clk or posedge rst) begin
    if(rst) begin
        age<=0; previous_valid<=0; header_ok<=0; have_sequence<=0; count<=0;
        sequence_no<=0; last_sequence<=0; in_bundle<=0;
        in_settings<=8'h38; crc<=16'hffff; received_crc<=0;
        update_valid<=0; settings<=8'h38; star_bundle<=0; bundle_toggle<=0;
    end else begin
        previous_valid<=rx_valid; update_valid<=0;
        if(age!=REBASE_CYCLES-1) age<=age+1'b1;
        if(rx_valid && !previous_valid) begin
            count<=1; header_ok<=rx_length==PACKET_BYTES && rx_data=="C";
            crc<=crc_byte(16'hffff,rx_data);
        end else if(rx_valid) begin
            if(count!=31) count<=count+1'b1;
            if(count<PAYLOAD_BYTES) crc<=crc_byte(crc,rx_data);
            if(count>=9 && count<=18) in_bundle<={rx_data,in_bundle[79:8]};
            case(count)
                1: header_ok<=header_ok && rx_data=="T";
                2: header_ok<=header_ok && rx_data=="L";
                3: header_ok<=header_ok && rx_data=="4";
                4: sequence_no[7:0]<=rx_data;   5: sequence_no[15:8]<=rx_data;
                6: sequence_no[23:16]<=rx_data; 7: sequence_no[31:24]<=rx_data;
                8: begin in_settings<=rx_data; header_ok<=header_ok && rx_data[3:0]<=8; end
                18: header_ok<=header_ok && rx_data[7:4]==4'd0;
                19: received_crc[15:8]<=rx_data;
                20: received_crc[7:0]<=rx_data;
                default: if(count>20) header_ok<=0;
            endcase
        end else if(previous_valid && count==PACKET_BYTES && header_ok && crc==received_crc &&
                    (!have_sequence || !order_delta[31] || age==REBASE_CYCLES-1)) begin
            settings<=in_settings; update_valid<=1; last_sequence<=sequence_no;
            star_bundle<=in_bundle[75:0]; bundle_toggle<=~bundle_toggle;
            have_sequence<=1; age<=0;
        end
    end
end
endmodule
