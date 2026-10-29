module audio_visual_tx_ref #(
    parameter integer UPDATE_CYCLES=2083333
) (
    input wire clk, rst, source_settled,
    input wire [31:0] session_id, analysed_words,
    input wire [263:0] visual_state,
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
reg [5:0] index;
reg [31:0] session, progress;
reg [263:0] payload;
reg [15:0] crc;
// Payload is always overwritten before a packet becomes visible. Avoid a
// 264-bit reset network on temporary serialization data.
always @(posedge clk) begin
    if(state==0 && timer==UPDATE_CYCLES-1 && source_settled) payload<=visual_state;
    else if(state==2 && index>=12 && index<45) payload<=payload>>8;
end
assign udp_request=state==1;
assign udp_valid=state==2;
assign udp_length=47;
always @* begin
    case(index)
        0: udp_data="V"; 1: udp_data="I"; 2: udp_data="Z"; 3: udp_data="2";
        4: udp_data=session[7:0]; 5: udp_data=session[15:8];
        6: udp_data=session[23:16]; 7: udp_data=session[31:24];
        8: udp_data=progress[7:0]; 9: udp_data=progress[15:8];
        10: udp_data=progress[23:16]; 11: udp_data=progress[31:24];
        45: udp_data=crc[15:8]; 46: udp_data=crc[7:0];
        default: udp_data=payload[7:0];
    endcase
end
always @(posedge clk or posedge rst) begin
    if(rst) begin timer<=0; state<=0; index<=0; session<=0; progress<=0; crc<=16'hffff; end
    else begin
        if(timer!=UPDATE_CYCLES-1) timer<=timer+1'b1;
        case(state)
            0: if(timer==UPDATE_CYCLES-1 && source_settled) begin
                session<=session_id; progress<=analysed_words;
                timer<=0; state<=3;
            end
            3: if(udp_ready) state<=1;
            1: if(udp_ack) begin state<=2; index<=0; crc<=16'hffff; end
            2: begin
                if(index<45) crc<=crc_byte(crc,udp_data);
                if(index==46) state<=0; else index<=index+1'b1;
            end
        endcase
    end
end
endmodule
