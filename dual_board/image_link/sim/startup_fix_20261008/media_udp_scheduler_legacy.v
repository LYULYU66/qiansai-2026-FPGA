`timescale 1ns/1ps
// A remains the original scheduler in the actual unchanged A bit.
module media_udp_scheduler_legacy #(
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
reg [2:0] prime_wait;
reg [15:0] crc;
reg [CHANNELS-1:0] choice;
reg [15:0] choice_length;
reg [7:0] source_data;
reg higher_request;
integer i, k;
function [15:0] crc_byte;
    input [15:0] old_crc; input [7:0] value;
    reg [15:0] c; integer j;
    begin c=old_crc^{value,8'd0};
        for(j=0;j<8;j=j+1) c=c[15] ? (c<<1)^16'h1021 : c<<1;
        crc_byte=c;
    end
endfunction
always @* begin
    choice=0; choice_length=0;
    // A malformed local producer cannot truncate the declared UDP length.
    for(i=0;i<CHANNELS;i=i+1)
        if(c_request[i] && c_length[i*16+:16]>=2 &&
           c_length[i*16+:16]<=MAX_LENGTH) begin
            choice=0; choice[i]=1'b1; choice_length=c_length[i*16+:16];
        end
    higher_request=0; c_ready=0;
    for(i=CHANNELS-1;i>=0;i=i-1) begin
        c_ready[i]=net_ready && !busy && !higher_request;
        higher_request=higher_request || (c_request[i] &&
                       c_length[i*16+:16]>=2 && c_length[i*16+:16]<=MAX_LENGTH);
    end
end
wire [CHANNELS-1:0] selected=busy ? owner : choice;
wire source_valid=|(c_valid & owner);
always @* begin
    source_data=0;
    for(k=0;k<CHANNELS;k=k+1)
        source_data=source_data | ({8{selected[k]}} & c_data[k*8+:8]);
end
assign net_request=busy ? !acknowledged : |choice;
assign c_ack=selected & {CHANNELS{net_ack && (busy || |choice)}};
assign net_length=busy ? {{(16-COUNT_BITS){1'b0}},length} : choice_length;
assign net_valid=busy && acknowledged && remaining!=0 &&
                 (source_valid || remaining!=length || prime_wait==7);
wire padding=aborting || !source_valid;
assign net_data=padding ? (remaining==1 ? (crc[7:0]^8'h01) :
                          remaining==2 ? crc[15:8] : 8'd0) : source_data;
always @(posedge clk or posedge rst) begin
    if(rst) begin
        busy<=0; acknowledged<=0; aborting<=0; owner<=0;
        length<=0; remaining<=0; prime_wait<=0; crc<=16'hffff;
    end else if(!busy) begin
        if(net_request) begin
            busy<=1; owner<=choice; acknowledged<=net_ack;
            length<=choice_length[COUNT_BITS-1:0];
            remaining<=choice_length[COUNT_BITS-1:0];
            prime_wait<=0; aborting<=0; crc<=16'hffff;
        end
    end else begin
        if(net_ack) acknowledged<=1;
        if(acknowledged && !source_valid && prime_wait!=7)
            prime_wait<=prime_wait+1'b1;
        if(net_valid) begin
            remaining<=remaining-1'b1;
            if(!source_valid) aborting<=1;
            if(remaining>2) crc<=crc_byte(crc,net_data);
        end
        if(acknowledged && remaining==0) begin
            busy<=0; acknowledged<=0;
        end
    end
end
endmodule

