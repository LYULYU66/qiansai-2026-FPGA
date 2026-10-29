`timescale 1ns/1ps
// IAK2, uint32 token LE, uint16 packet sequence LE, CRC16 BE.
// The final receipt must be released only after SDRAM write_finish.
module image_receipt_tx (
    input wire clk, rst, event_valid,
    input wire [31:0] event_token,
    input wire [15:0] event_sequence,
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
reg [1:0] state;
reg [31:0] token;
reg [15:0] sequence_no, crc;
reg [3:0] index;
assign udp_request=(state==1);
assign udp_valid=(state==2);
assign udp_length=16'd12;
always @* begin
    case(index)
        0: udp_data="I"; 1: udp_data="A";
        2: udp_data="K"; 3: udp_data="2";
        4: udp_data=token[7:0]; 5: udp_data=token[15:8];
        6: udp_data=token[23:16]; 7: udp_data=token[31:24];
        8: udp_data=sequence_no[7:0]; 9: udp_data=sequence_no[15:8];
        10: udp_data=crc[15:8]; default: udp_data=crc[7:0];
    endcase
end
always @(posedge clk or posedge rst) begin
    if(rst) begin state<=0; token<=0; sequence_no<=0; index<=0; crc<=16'hffff; end
    else case(state)
        0: if(event_valid) begin
            token<=event_token; sequence_no<=event_sequence; state<=3;
        end
        3: if(udp_ready) state<=1;
        1: if(udp_ack) begin state<=2; index<=0; crc<=16'hffff; end
        2: begin
            if(index<10) crc<=crc_byte(crc,udp_data);
            if(index==11) state<=0; else index<=index+1'b1;
        end
    endcase
end
endmodule

module image_receipt_rx (
    input wire clk, rst, rx_valid,
    input wire [7:0] rx_data,
    input wire [15:0] rx_length,
    output reg receipt_valid,
    output reg [31:0] receipt_token,
    output reg [15:0] receipt_sequence
);
function [15:0] crc_byte;
    input [15:0] old_crc; input [7:0] value;
    reg [15:0] c; integer i;
    begin c=old_crc^{value,8'd0};
        for(i=0;i<8;i=i+1) c=c[15] ? (c<<1)^16'h1021 : c<<1;
        crc_byte=c;
    end
endfunction
reg previous_valid, header_ok;
// 20261021: the CRC comparison is registered first; it used to feed the
// 48 token/sequence enables directly (B udp_clk -2.5 ns, 285 endpoints).
reg end_q, crc_equal_q;
reg [4:0] count;
reg [15:0] crc, received_crc;
reg [31:0] token;
reg [15:0] sequence_no;
always @(posedge clk or posedge rst) begin
    if(rst) begin
        previous_valid<=0; header_ok<=0; count<=0; crc<=16'hffff;
        received_crc<=0; token<=0; sequence_no<=0;
        receipt_valid<=0; receipt_token<=0; receipt_sequence<=0;
        end_q<=0; crc_equal_q<=0;
    end else begin
        previous_valid<=rx_valid; receipt_valid<=0; end_q<=0;
        // token/sequence are not overwritten before byte 4 of the next
        // packet, so they are still this packet's values one clock later.
        if(end_q && crc_equal_q) begin
            receipt_valid<=1; receipt_token<=token; receipt_sequence<=sequence_no;
        end
        if(rx_valid && !previous_valid) begin
            count<=1; header_ok<=(rx_length==12 && rx_data=="I");
            crc<=crc_byte(16'hffff,rx_data);
        end else if(rx_valid) begin
            if(count<31) count<=count+1'b1;
            if(count<10) crc<=crc_byte(crc,rx_data);
            case(count)
                1: header_ok<=header_ok && rx_data=="A";
                2: header_ok<=header_ok && rx_data=="K";
                3: header_ok<=header_ok && rx_data=="2";
                4: token[7:0]<=rx_data; 5: token[15:8]<=rx_data;
                6: token[23:16]<=rx_data; 7: token[31:24]<=rx_data;
                8: sequence_no[7:0]<=rx_data; 9: sequence_no[15:8]<=rx_data;
                10: received_crc[15:8]<=rx_data; 11: received_crc[7:0]<=rx_data;
                default: header_ok<=0;
            endcase
        end else if(previous_valid && count==12 && header_ok) begin
            end_q<=1; crc_equal_q<=crc==received_crc;
        end
    end
end
endmodule
