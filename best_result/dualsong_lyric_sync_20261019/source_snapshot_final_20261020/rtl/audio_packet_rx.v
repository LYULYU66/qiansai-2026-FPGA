`timescale 1ns/1ps
// Validate a complete sector before exposing any audio. Retries of the last
// consumed block are ACKed, not replayed. During a slow drain, incoming
// retries cannot overwrite packet RAM. A fresh session starts only at block 0.
module audio_packet_rx #(parameter integer SESSION_GUARD=0) (
    input wire clk, rst, rx_valid,
    input wire [15:0] generation,
    input wire [7:0] rx_data,
    input wire [15:0] rx_length,
    input wire pcm_ready,
    output wire pcm_valid,
    output wire [31:0] pcm_data,
    output reg stream_enable,
    output reg [31:0] file_samples,
    output wire [31:0] stream_session,
    output wire fifo_reset,
    output reg receipt_event,
    output reg [31:0] receipt_session,
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
localparam IDLE=0, CLEAR_FIFO=1, FETCH=2, APPEND=3, DRAIN=4;
reg [2:0] state;
reg previous_valid, capture, header_ok, have_session, have_last;
reg [9:0] count;
reg [15:0] crc, received_crc, incoming_sequence, expected_sequence, last_sequence;
reg [31:0] incoming_session, incoming_samples, session;
reg [7:0] packet_mem[0:511]; /* fehdl force_ram=1, ram_style="bram" */
reg [7:0] packet_out;
reg [31:0] pcm_pack;
reg [1:0] read_phase;
reg [6:0] read_index;
reg [3:0] clear_count;
wire [8:0] payload_offset=count-10'd16;
wire mem_write=rx_valid && previous_valid && capture && count>=16 && count<528;
wire [31:0] session_delta=incoming_session-session;
wire newer_session=session_delta!=0 && !session_delta[31];
// 20261019 timing: header comparisons are registered once the 16-byte header
// is complete; session/sequence state is stable while a packet is received
// (reception only starts in IDLE and the state only leaves IDLE on accept).
reg h_basic_ok, h_new_stream, h_next_block, h_replay;
always @(posedge clk) begin
    if(rx_valid && count==16) begin
        h_basic_ok  <= incoming_samples!=0 && incoming_samples[31:30]==0 &&
                       (!SESSION_GUARD || incoming_session[31:16]==generation);
        h_new_stream<= (!have_session || incoming_session!=session) &&
                       incoming_sequence==0 && (!have_session || newer_session);
        h_next_block<= have_session && incoming_session==session &&
                       incoming_samples==file_samples && incoming_sequence==expected_sequence;
        h_replay    <= have_session && incoming_session==session &&
                       incoming_samples==file_samples && have_last &&
                       incoming_sequence==last_sequence &&
                       incoming_sequence!=expected_sequence;
    end
end
assign pcm_valid=state==DRAIN;
assign pcm_data=pcm_pack;
assign stream_session=session;
assign fifo_reset=rst || state==CLEAR_FIFO || !stream_enable;
always @(posedge clk) begin
    if(mem_write) begin
        packet_mem[payload_offset]<=rx_data;
    end
    if(state==FETCH) packet_out<=packet_mem[{read_index,read_phase}];
end
always @(posedge clk or posedge rst) begin
    if(rst) begin
        state<=IDLE; previous_valid<=0; capture<=0; header_ok<=0; have_session<=0; have_last<=0;
        count<=0; crc<=16'hffff; received_crc<=0; incoming_sequence<=0; expected_sequence<=0; last_sequence<=0;
        incoming_session<=0; incoming_samples<=0; session<=0; pcm_pack<=0; read_index<=0; read_phase<=0; clear_count<=0;
        stream_enable<=0; file_samples<=0; receipt_event<=0; receipt_session<=0; receipt_sequence<=0;
    end else begin
        previous_valid<=rx_valid; receipt_event<=0;
        if(rx_valid && !previous_valid) begin
            count<=1; capture<=state==IDLE;
            header_ok<=state==IDLE && rx_length==530 && rx_data=="A";
            crc<=crc_byte(16'hffff,rx_data);
        end else if(rx_valid) begin
            if(count<1023) count<=count+1'b1;
            if(count<528) crc<=crc_byte(crc,rx_data);
            case(count)
                1: header_ok<=header_ok && rx_data=="U";
                2: header_ok<=header_ok && rx_data=="D";
                3: header_ok<=header_ok && rx_data=="2";
                4: incoming_session[7:0]<=rx_data; 5: incoming_session[15:8]<=rx_data;
                6: incoming_session[23:16]<=rx_data; 7: incoming_session[31:24]<=rx_data;
                8: incoming_sequence[7:0]<=rx_data; 9: incoming_sequence[15:8]<=rx_data;
                10,11: header_ok<=header_ok && rx_data==0;
                12: incoming_samples[7:0]<=rx_data; 13: incoming_samples[15:8]<=rx_data;
                14: incoming_samples[23:16]<=rx_data; 15: incoming_samples[31:24]<=rx_data;
                528: received_crc[15:8]<=rx_data; 529: received_crc[7:0]<=rx_data;
                default: if(count<16 || count>=528) header_ok<=0;
            endcase
        end else if(previous_valid && header_ok && count==530 && crc==received_crc &&
                    h_basic_ok) begin
            if(h_new_stream) begin
                session<=incoming_session; file_samples<=incoming_samples;
                have_session<=1; have_last<=0; expected_sequence<=0;
                stream_enable<=0; state<=CLEAR_FIFO; clear_count<=0; read_index<=0; read_phase<=0;
            end else if(h_next_block) begin
                read_index<=0; read_phase<=0; state<=FETCH;
            end else if(h_replay) begin
                receipt_event<=1; receipt_session<=session; receipt_sequence<=last_sequence;
            end
        end
        case(state)
            CLEAR_FIFO: if(clear_count==15) begin
                            stream_enable<=1; state<=FETCH; clear_count<=3;
                        end
                        else clear_count<=clear_count+1'b1;
            // The reused asynchronous FIFO synchronously releases its reset
            // in two write clocks. Do not lose the first word on that boundary.
            FETCH: if(clear_count!=0) clear_count<=clear_count-1'b1;
                   else state<=APPEND;
            APPEND: begin
                case(read_phase)
                    0: pcm_pack[7:0]<=packet_out;
                    1: pcm_pack[15:8]<=packet_out;
                    2: pcm_pack[23:16]<=packet_out;
                    3: pcm_pack[31:24]<=packet_out;
                endcase
                read_phase<=read_phase+1'b1;
                state<=read_phase==3 ? DRAIN : FETCH;
            end
            DRAIN: if(pcm_ready) begin
                if(read_index==127) begin
                    state<=IDLE; have_last<=1; last_sequence<=expected_sequence;
                    receipt_event<=1; receipt_session<=session; receipt_sequence<=expected_sequence;
                    expected_sequence<=expected_sequence+1'b1;
                end else begin read_index<=read_index+1'b1; state<=FETCH; end
            end
            default: ;
        endcase
    end
end
endmodule
