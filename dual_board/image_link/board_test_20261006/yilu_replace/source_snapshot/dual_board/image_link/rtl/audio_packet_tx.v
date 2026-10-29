`timescale 1ns/1ps
// AUD2: magic4, session u32 LE, block u16 LE, reserved u16=0,
// file stereo-word count u32 LE, 128 signed16 stereo words LE, CRC16 BE.
// Exactly one 512-byte sector is retained for stop/wait retransmission.
module audio_packet_tx #(
    parameter integer RETRY_CYCLES=125_000
) (
    input wire clk, rst,
    input wire [31:0] session_id, file_samples,
    input wire source_valid,
    input wire [31:0] source_pcm,
    output wire source_ready,
    input wire udp_ready, udp_ack,
    output wire udp_request, udp_valid,
    output reg [7:0] udp_data,
    output wire [15:0] udp_length,
    input wire receipt_valid,
    input wire [31:0] receipt_session,
    input wire [15:0] receipt_sequence,
    output reg [15:0] sequence_no
);
function [15:0] crc_byte;
    input [15:0] old_crc; input [7:0] value;
    reg [15:0] c; integer i;
    begin c=old_crc^{value,8'd0};
        for(i=0;i<8;i=i+1) c=c[15] ? (c<<1)^16'h1021 : c<<1;
        crc_byte=c;
    end
endfunction
localparam FILL=0, WAIT_NET=1, REQUEST=2, PRIME=3, BYTES=4, RECEIPT=5, FILL_BYTES=6;
localparam integer RETRY_BITS=$clog2(RETRY_CYCLES+1);
reg [2:0] state;
// Serialize both RAM ports to byte width: TD maps this 512x8 buffer to one
// BRAM9K, rather than two blocks for a 32-bit dual-port packet store.
reg [7:0] packet_mem[0:511]; /* fehdl force_ram=1, ram_style="bram" */
reg [7:0] packet_out;
reg [23:0] fill_remaining;
reg [1:0] fill_phase;
reg [15:0] crc;
reg [8:0] fill_index;
reg [9:0] byte_index;
reg [RETRY_BITS-1:0] retry_count;
reg [31:0] session, samples;
wire [8:0] payload_offset=byte_index-10'd16;
wire mem_read=state==PRIME ||
    (state==BYTES && byte_index>=16 && byte_index<527);
wire [8:0] read_index=state==PRIME ? 9'd0 : payload_offset+9'd1;
assign source_ready=state==FILL;
assign udp_request=state==REQUEST;
assign udp_valid=state==BYTES;
assign udp_length=16'd530;
always @(posedge clk) begin
    if((source_valid && source_ready) || state==FILL_BYTES)
        packet_mem[fill_index]<=state==FILL ? source_pcm[7:0] : fill_remaining[7:0];
    if(mem_read) packet_out<=packet_mem[read_index];
end
always @* begin
    case(byte_index)
        0: udp_data="A"; 1: udp_data="U"; 2: udp_data="D"; 3: udp_data="2";
        4: udp_data=session[7:0]; 5: udp_data=session[15:8];
        6: udp_data=session[23:16]; 7: udp_data=session[31:24];
        8: udp_data=sequence_no[7:0]; 9: udp_data=sequence_no[15:8];
        10,11: udp_data=0;
        12: udp_data=samples[7:0]; 13: udp_data=samples[15:8];
        14: udp_data=samples[23:16]; 15: udp_data=samples[31:24];
        528: udp_data=crc[15:8]; 529: udp_data=crc[7:0];
        default: udp_data=packet_out;
    endcase
end
always @(posedge clk or posedge rst) begin
    if(rst) begin
        state<=FILL; fill_index<=0; byte_index<=0; retry_count<=0;
        sequence_no<=0; session<=0; samples<=0; crc<=16'hffff; fill_phase<=0; fill_remaining<=0;
    end else case(state)
        FILL: if(source_valid) begin
            if(fill_index==0) begin session<=session_id; samples<=file_samples; end
            fill_remaining<=source_pcm[31:8]; fill_phase<=1;
            fill_index<=fill_index+1'b1; state<=FILL_BYTES;
        end
        FILL_BYTES: begin
            fill_remaining<={8'd0,fill_remaining[23:8]};
            fill_index<=fill_index+1'b1;
            if(fill_phase==3) state<=fill_index==511 ? WAIT_NET : FILL;
            else fill_phase<=fill_phase+1'b1;
        end
        WAIT_NET: if(udp_ready) state<=REQUEST;
        REQUEST: if(udp_ack) state<=PRIME;
        PRIME: begin byte_index<=0; crc<=16'hffff; state<=BYTES; end
        BYTES: begin
            if(byte_index<528) crc<=crc_byte(crc,udp_data);
            if(byte_index==529) begin retry_count<=0; state<=RECEIPT; end
            else byte_index<=byte_index+1'b1;
        end
        RECEIPT: begin
            if(receipt_valid && receipt_session==session && receipt_sequence==sequence_no) begin
                sequence_no<=sequence_no+1'b1; state<=FILL;
            end else if(retry_count==RETRY_CYCLES-1) begin retry_count<=0; state<=WAIT_NET; end
            else retry_count<=retry_count+1'b1;
        end
        default: state<=FILL;
    endcase
end
endmodule
