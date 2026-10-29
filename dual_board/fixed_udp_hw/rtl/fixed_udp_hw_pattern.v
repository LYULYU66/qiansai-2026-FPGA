`timescale 1ns/1ps
// Hardware diagnostic pattern only. Recompute deterministic pixels for retry
// instead of storing 256 pixels in another BRAM. Wire protocol is actual IMG4;
// production TF image_packet_tx remains unchanged and separately regressed.
module fixed_udp_hw_pattern #(
    parameter integer RETRY_CYCLES=12500000
) (
    input wire clk,rst,start,udp_ready,udp_ack,receipt_valid,
    input wire [31:0] receipt_token,
    input wire [15:0] receipt_sequence,
    output wire udp_request,udp_valid,busy,
    output reg [7:0] udp_data,
    output wire [15:0] udp_length,
    output reg frame_sent,
    output reg [15:0] packets_sent,
    output reg [18:0] count
);
localparam IDLE=0,WAIT_READY=1,REQUEST=2,BYTES=3,RECEIPT=4;
reg [2:0] state;
reg [10:0] index;
reg [15:0] sequence_no,crc;
reg [31:0] token;
reg [23:0] retry_count;
reg [9:0] x,start_x;
reg [8:0] y,start_y;
function [15:0] crc_byte;
    input [15:0] old_crc;input [7:0] value;
    reg [15:0] c;integer bit_no;
    begin
        c=old_crc^{value,8'd0};
        for(bit_no=0;bit_no<8;bit_no=bit_no+1)c=c[15]?(c<<1)^16'h1021:c<<1;
        crc_byte=c;
    end
endfunction
assign udp_request=state==REQUEST;
assign udp_valid=state==BYTES;
assign udp_length=1042;
assign busy=state!=IDLE;
always @*begin
    if(index>=16 && index<1040)case(index[1:0])
        0:udp_data=x[7:0];1:udp_data=y[7:0];
        2:udp_data=x[7:0]^y[7:0];3:udp_data=x[7:0]^8'ha5;
    endcase
    else case(index)
        0:udp_data="I";1:udp_data="M";2:udp_data="G";3:udp_data="4";
        4:udp_data=0;5:udp_data=sequence_no[7:0];6:udp_data=sequence_no[15:8];7:udp_data=1;
        8:udp_data=token[7:0];9:udp_data=token[15:8];10:udp_data=token[23:16];11:udp_data=token[31:24];
        12:udp_data=8'h80;13:udp_data=8'h02;14:udp_data=8'he0;15:udp_data=8'h01;
        1040:udp_data=crc[15:8];1041:udp_data=crc[7:0];default:udp_data=0;
    endcase
end
always @(posedge clk or posedge rst)begin
    if(rst)begin
        state<=IDLE;index<=0;sequence_no<=0;crc<=16'hffff;token<=0;
        retry_count<=0;x<=0;y<=0;start_x<=0;start_y<=0;
        frame_sent<=0;packets_sent<=0;count<=0;
    end else begin
        frame_sent<=0;
        case(state)
            IDLE:if(start)begin
                token<=token+1'b1;sequence_no<=0;start_x<=0;start_y<=0;count<=0;state<=WAIT_READY;
            end
            WAIT_READY:if(udp_ready)state<=REQUEST;
            REQUEST:if(udp_ack)begin
                state<=BYTES;index<=0;crc<=16'hffff;x<=start_x;y<=start_y;
            end
            BYTES:begin
                if(index<1040)crc<=crc_byte(crc,udp_data);
                if(index>=16 && index<1040 && index[1:0]==3)begin
                    if(x==639)begin x<=0;y<=y+1'b1;end else x<=x+1'b1;
                end
                if(index==1041)begin
                    state<=RECEIPT;retry_count<=0;packets_sent<=packets_sent+1'b1;
                end else index<=index+1'b1;
            end
            RECEIPT:begin
                if(receipt_valid && receipt_token==token && receipt_sequence==sequence_no)begin
                    count<=count+256;
                    if(sequence_no==1199)begin state<=IDLE;frame_sent<=1;end
                    else begin sequence_no<=sequence_no+1'b1;start_x<=x;start_y<=y;state<=WAIT_READY;end
                end else if(retry_count==RETRY_CYCLES-1)begin state<=WAIT_READY;retry_count<=0;end
                else retry_count<=retry_count+1'b1;
            end
            default:state<=IDLE;
        endcase
    end
end
endmodule
