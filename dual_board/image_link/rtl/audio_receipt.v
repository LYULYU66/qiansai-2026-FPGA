`timescale 1ns/1ps
// 16 bytes: AAK2, session u32 LE, block u16 LE, actually played words u32 LE,
// CRC16/CCITT-FALSE BE. Not an estimate based on network arrival or wall time.
module audio_receipt_tx #(
    parameter EXTENDED=0,
    parameter integer PERIODIC_CYCLES=0
) (
    input wire clk, rst, event_valid,
    input wire [31:0] event_session, played_words,
    input wire [15:0] event_sequence,
    input wire [3:0] volume_level,
    input wire analysis_enable,
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
reg [31:0] session, progress;
reg [15:0] sequence_no, crc;
reg [4:0] index;
reg [7:0] controls;
reg have_event;
localparam TIMER_BITS=PERIODIC_CYCLES>1 ? $clog2(PERIODIC_CYCLES) : 1;
reg [TIMER_BITS-1:0] timer;
wire periodic_due=PERIODIC_CYCLES!=0 && timer==PERIODIC_CYCLES-1;
assign udp_request=state==1;
assign udp_valid=state==2;
assign udp_length=EXTENDED ? 16'd18 : 16'd16;
always @* begin
    case(index)
        0: udp_data="A"; 1: udp_data="A";
        2: udp_data="K"; 3: udp_data=EXTENDED ? "3" : "2";
        4: udp_data=session[7:0]; 5: udp_data=session[15:8];
        6: udp_data=session[23:16]; 7: udp_data=session[31:24];
        8: udp_data=sequence_no[7:0]; 9: udp_data=sequence_no[15:8];
        10: udp_data=progress[7:0]; 11: udp_data=progress[15:8];
        12: udp_data=progress[23:16]; 13: udp_data=progress[31:24];
        14: udp_data=EXTENDED ? controls : crc[15:8];
        15: udp_data=EXTENDED ? 8'd0 : crc[7:0];
        16: udp_data=crc[15:8]; default: udp_data=crc[7:0];
    endcase
end
always @(posedge clk or posedge rst) begin
    if(rst) begin
        state<=0; session<=0; progress<=0; sequence_no<=0;
        index<=0; crc<=16'hffff; controls<=0; have_event<=0; timer<=0;
    end else begin
      if(PERIODIC_CYCLES!=0 && !periodic_due) timer<=timer+1'b1;
      case(state)
        0: if(event_valid || (periodic_due && have_event)) begin
            if(event_valid) begin
                session<=event_session; sequence_no<=event_sequence; have_event<=1;
            end
            progress<=played_words; controls<={3'd0,analysis_enable,volume_level};
            state<=3; timer<=0;
        end
        3: if(udp_ready) state<=1;
        1: if(udp_ack) begin state<=2; index<=0; crc<=16'hffff; end
        2: begin
            if(index<(EXTENDED ? 16 : 14)) crc<=crc_byte(crc,udp_data);
            if(index==(EXTENDED ? 17 : 15)) state<=0; else index<=index+1'b1;
        end
      endcase
    end
end
endmodule

module audio_receipt_rx #(parameter EXTENDED=0) (
    input wire clk, rst, rx_valid,
    input wire [7:0] rx_data,
    input wire [15:0] rx_length,
    output reg receipt_valid,
    output reg [31:0] receipt_session, played_words,
    output reg [15:0] receipt_sequence,
    output reg [3:0] volume_level,
    output reg analysis_enable
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
reg [4:0] count;
reg [15:0] crc, received_crc, sequence_no;
reg [31:0] session, progress;
reg [7:0] controls;
always @(posedge clk or posedge rst) begin
    if(rst) begin
        previous_valid<=0; header_ok<=0; count<=0; crc<=16'hffff;
        received_crc<=0; session<=0; progress<=0; sequence_no<=0;
        receipt_valid<=0; receipt_session<=0; receipt_sequence<=0; played_words<=0;
        controls<=0; volume_level<=8; analysis_enable<=0;
    end else begin
        previous_valid<=rx_valid; receipt_valid<=0;
        if(rx_valid && !previous_valid) begin
            count<=1; header_ok<=rx_length==(EXTENDED ? 18 : 16) && rx_data=="A";
            crc<=crc_byte(16'hffff,rx_data);
        end else if(rx_valid) begin
            if(count<31) count<=count+1'b1;
            if(count<(EXTENDED ? 16 : 14)) crc<=crc_byte(crc,rx_data);
            case(count)
                1: header_ok<=header_ok && rx_data=="A";
                2: header_ok<=header_ok && rx_data=="K";
                3: header_ok<=header_ok && rx_data==(EXTENDED ? "3" : "2");
                4: session[7:0]<=rx_data; 5: session[15:8]<=rx_data;
                6: session[23:16]<=rx_data; 7: session[31:24]<=rx_data;
                8: sequence_no[7:0]<=rx_data; 9: sequence_no[15:8]<=rx_data;
                10: progress[7:0]<=rx_data; 11: progress[15:8]<=rx_data;
                12: progress[23:16]<=rx_data; 13: progress[31:24]<=rx_data;
                14: if(EXTENDED) begin
                    controls<=rx_data;
                    header_ok<=header_ok && rx_data[7:5]==0 && rx_data[3:0]<=8;
                end else received_crc[15:8]<=rx_data;
                15: if(EXTENDED) header_ok<=header_ok && rx_data==0;
                    else received_crc[7:0]<=rx_data;
                16: if(EXTENDED) received_crc[15:8]<=rx_data; else header_ok<=0;
                17: if(EXTENDED) received_crc[7:0]<=rx_data; else header_ok<=0;
                default: header_ok<=0;
            endcase
        end else if(previous_valid && count==(EXTENDED ? 18 : 16) && header_ok && crc==received_crc) begin
            receipt_valid<=1; receipt_session<=session;
            receipt_sequence<=sequence_no; played_words<=progress;
            if(EXTENDED) begin volume_level<=controls[3:0]; analysis_enable<=controls[4]; end
        end
    end
end
endmodule

// Monotonic counter (including song loops) allows safe Gray synchronization.
// The receiving media source may later map this to its own lyric/FFT timeline.
module audio_playback_progress (
    input wire audio_clk, udp_clk, rst, sample_read,
    output wire [31:0] played_words
);
reg [31:0] count, gray;
(* async_reg="true" *) reg [31:0] gray0, gray1;
wire [31:0] next_count=count+1'b1;
always @(posedge audio_clk or posedge rst) begin
    if(rst) begin count<=0; gray<=0; end
    else if(sample_read) begin count<=next_count; gray<=(next_count>>1)^next_count; end
end
always @(posedge udp_clk or posedge rst) begin
    if(rst) begin gray0<=0; gray1<=0; end
    else begin gray0<=gray; gray1<=gray0; end
end
genvar i;
assign played_words[31]=gray1[31];
generate for(i=30;i>=0;i=i-1) begin:decode
    assign played_words[i]=played_words[i+1]^gray1[i];
end endgenerate
endmodule
