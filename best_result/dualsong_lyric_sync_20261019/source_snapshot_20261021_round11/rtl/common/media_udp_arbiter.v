`timescale 1ns/1ps
// One existing UDP core, two application producers. Channel 1 (audio) has
// packet-boundary priority; an image packet is never interrupted midway.
module media_udp_arbiter (
    input wire clk, rst,
    input wire net_ready, net_ack,
    output wire net_request, net_valid,
    output wire [7:0] net_data,
    output wire [15:0] net_length,
    input wire c0_request, c0_valid,
    input wire [7:0] c0_data,
    input wire [15:0] c0_length,
    output wire c0_ready, c0_ack,
    input wire c1_request, c1_valid,
    input wire [7:0] c1_data,
    input wire [15:0] c1_length,
    output wire c1_ready, c1_ack
);
reg busy, owner, acknowledged;
reg [15:0] length, sent_bytes;
reg [2:0] prime_wait;
reg aborting;
reg [15:0] crc;
function [15:0] crc_byte;
    input [15:0] old_crc; input [7:0] value;
    reg [15:0] c; integer i;
    begin c=old_crc^{value,8'd0};
        for(i=0;i<8;i=i+1) c=c[15] ? (c<<1)^16'h1021 : c<<1;
        crc_byte=c;
    end
endfunction
wire selected=busy ? owner : c1_request;
wire source_valid=owner ? c1_valid : c0_valid;
assign c0_ready=net_ready && !busy && !c1_request;
assign c1_ready=net_ready && !busy;
assign net_request=busy ? !acknowledged : (selected ? c1_request : c0_request);
// If a producer is locally aborted after its UDP request was accepted, finish
// the declared length with padding and a deliberately WRONG CRC. All four
// media packet types have a trailing CCITT CRC. No partial producer reset can
// accidentally pass CRC or leave the MAC waiting for a missing packet tail.
assign net_valid=busy && acknowledged && sent_bytes<length &&
                 (source_valid || sent_bytes!=0 || prime_wait==7);
wire padding=busy && (aborting || !source_valid);
assign net_data=padding ?
                (sent_bytes==length-1'b1 ? (crc[7:0]^8'h01) :
                 sent_bytes==length-16'd2 ? crc[15:8] : 8'd0) :
                (selected ? c1_data : c0_data);
assign net_length=busy ? length : (selected ? c1_length : c0_length);
assign c0_ack=net_ack && !selected;
assign c1_ack=net_ack && selected;
always @(posedge clk or posedge rst) begin
    if(rst) begin
        busy<=0; owner<=0; acknowledged<=0; length<=0; sent_bytes<=0;
        prime_wait<=0; aborting<=0; crc<=16'hffff;
    end
    else if(!busy) begin
        if(net_request) begin
            busy<=1; owner<=selected; acknowledged<=net_ack;
            length<=selected ? c1_length : c0_length;
            sent_bytes<=0; prime_wait<=0; aborting<=0; crc<=16'hffff;
        end
    end else begin
        if(net_ack) acknowledged<=1;
        if(acknowledged && !source_valid && prime_wait!=7) prime_wait<=prime_wait+1'b1;
        if(net_valid) begin
            sent_bytes<=sent_bytes+1'b1;
            if(!source_valid) aborting<=1;
            if(sent_bytes<length-16'd2) crc<=crc_byte(crc,net_data);
        end
        if(acknowledged && sent_bytes==length) begin busy<=0; acknowledged<=0; end
    end
end
endmodule

// Flat packet scheduler for the formal dual-board player. Highest numbered
// channel wins only while idle; one owner, length/count and poison-CRC engine
// serve every producer. Producers must emit a contiguous payload after ACK
// (up to six prime clocks); there is no byte-level backpressure interface.
module media_udp_scheduler #(
    parameter integer CHANNELS=5,
    parameter integer MAX_LENGTH=1042
) (
    input wire clk, rst,
    input wire net_ready, net_ack,
    output wire net_request, net_valid,
    output wire [7:0] net_data,
    output wire [15:0] net_length,
    input wire [CHANNELS-1:0] c_request, c_valid,
    input wire [CHANNELS*8-1:0] c_data,
    input wire [CHANNELS*16-1:0] c_length,
    output reg [CHANNELS-1:0] c_ready,
    output wire [CHANNELS-1:0] c_ack
);
localparam integer COUNT_BITS=$clog2(MAX_LENGTH+1);
reg busy, acknowledged, aborting;
reg [CHANNELS-1:0] owner;
reg [COUNT_BITS-1:0] length, remaining;
reg [3:0] prime_wait;
reg [15:0] crc;
reg [CHANNELS-1:0] choice;
reg [15:0] choice_length;
reg [7:0] source_data;
reg higher_request;
// 20261019 timing: the abort-padding CRC is accumulated from a registered copy
// of each transmitted byte, so producer data no longer runs through the CRC.
// A padded packet waits one clock before its two CRC bytes while the last
// byte is folded in; complete packets are never delayed.
reg crc_pending;
reg [7:0] crc_data;
// 20261021 timing: every producer input is registered before the shared
// choice/ownership/padding logic, so no producer's state or byte-index decode
// runs through the scheduler into the UDP endpoint. Requests and lengths are
// seen one clock later (a producer holds them until ACK, and a packet keeps
// the scheduler busy far longer than one clock); the byte stream is delayed
// by one clock as a whole, so the prime limit moves from 7 to 8 clocks and a
// producer is still treated as aborted if it starts 7 or more after ACK.
reg [CHANNELS-1:0] req_q, valid_q;
reg [CHANNELS*8-1:0] data_q;
reg [CHANNELS*16-1:0] length_q;
integer i, k;
function [15:0] crc_byte;
    input [15:0] old_crc; input [7:0] value;
    reg [15:0] c; integer j;
    begin c=old_crc^{value,8'd0};
        for(j=0;j<8;j=j+1) c=c[15] ? (c<<1)^16'h1021 : c<<1;
        crc_byte=c;
    end
endfunction
always @(posedge clk or posedge rst) begin
    if(rst) begin req_q<=0; valid_q<=0; end
    else begin
        valid_q<=c_valid;
        // A malformed local producer cannot truncate the declared UDP length.
        for(i=0;i<CHANNELS;i=i+1)
            req_q[i]<=c_request[i] && c_length[i*16+:16]>=2 &&
                      c_length[i*16+:16]<=MAX_LENGTH;
    end
end
always @(posedge clk) begin
    data_q<=c_data;
    length_q<=c_length;
end
always @* begin
    choice=0; choice_length=0;
    for(i=0;i<CHANNELS;i=i+1)
        if(req_q[i]) begin
            choice=0; choice[i]=1'b1; choice_length=length_q[i*16+:16];
        end
    higher_request=0; c_ready=0;
    for(i=CHANNELS-1;i>=0;i=i-1) begin
        c_ready[i]=net_ready && !busy && !higher_request;
        higher_request=higher_request || req_q[i];
    end
end
wire [CHANNELS-1:0] selected=busy ? owner : choice;
wire source_valid=|(valid_q & owner);
always @* begin
    source_data=0;
    for(k=0;k<CHANNELS;k=k+1)
        source_data=source_data | ({8{owner[k]}} & data_q[k*8+:8]);
end
assign net_request=busy ? !acknowledged : |choice;
assign c_ack=selected & {CHANNELS{net_ack && (busy || |choice)}};
assign net_length=busy ? {{(16-COUNT_BITS){1'b0}},length} : choice_length;
wire padding=aborting || !source_valid;
assign net_valid=busy && acknowledged && remaining!=0 &&
                 (source_valid || remaining!=length || prime_wait==8) &&
                 !(padding && remaining<=2 && crc_pending);
assign net_data=padding ? (remaining==1 ? (crc[7:0]^8'h01) :
                          remaining==2 ? crc[15:8] : 8'd0) : source_data;
always @(posedge clk or posedge rst) begin
    if(rst) begin
        busy<=0; acknowledged<=0; aborting<=0; owner<=0;
        length<=0; remaining<=0; prime_wait<=0; crc<=16'hffff;
        crc_pending<=0; crc_data<=0;
    end else if(!busy) begin
        crc_pending<=0;
        if(net_request) begin
            busy<=1; owner<=choice; acknowledged<=net_ack;
            length<=choice_length[COUNT_BITS-1:0];
            remaining<=choice_length[COUNT_BITS-1:0];
            prime_wait<=0; aborting<=0; crc<=16'hffff;
        end
    end else begin
        if(net_ack) acknowledged<=1;
        if(acknowledged && !source_valid && prime_wait!=8)
            prime_wait<=prime_wait+1'b1;
        crc_pending<=net_valid && remaining>2;
        crc_data<=net_data;
        if(crc_pending) crc<=crc_byte(crc,crc_data);
        if(net_valid) begin
            remaining<=remaining-1'b1;
            if(!source_valid) aborting<=1;
        end
        if(acknowledged && remaining==0) begin
            busy<=0; acknowledged<=0;
        end
    end
end
endmodule
