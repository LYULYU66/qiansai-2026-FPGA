`timescale 1ns/1ps
// Small application-level lease, independent of the encrypted MAC/PHY. A owns
// the generation; B includes it in the existing image/audio token upper half.
// No framebuffer or sample RAM. CRC covers the first eight bytes of LNK1.
module media_link_session #(
    parameter integer ROLE=0,
    parameter integer HEARTBEAT_CYCLES=12_500_000,
    parameter integer TIMEOUT_CYCLES=62_500_000,
    parameter integer RESET_GUARD_CYCLES=64
) (
    input wire clk, rst, renew,
    input wire rx_valid,
    input wire [7:0] rx_data,
    input wire [15:0] rx_length,
    input wire udp_ready, udp_ack,
    output wire udp_request, udp_valid,
    output reg [7:0] udp_data,
    output wire [15:0] udp_length,
    output reg ready,
    output reg [15:0] generation,
    output reg restart
);
function [15:0] crc_byte;
    input [15:0] old_crc; input [7:0] value;
    reg [15:0] c; integer i;
    begin
        c=old_crc^{value,8'd0};
        for(i=0;i<8;i=i+1) c=c[15] ? (c<<1)^16'h1021 : c<<1;
        crc_byte=c;
    end
endfunction
function newer;
    input [15:0] a,b; reg [15:0] delta;
    begin delta=a-b; newer=delta!=0 && !delta[15]; end
endfunction
localparam HB_W=$clog2(HEARTBEAT_CYCLES+1);
localparam AGE_W=$clog2(TIMEOUT_CYCLES+1);
localparam GUARD_W=$clog2(RESET_GUARD_CYCLES+1);
localparam WAIT_PEER=0, OFFERED=1, ACTIVE=2, RESET_GUARD=3;
reg [1:0] state;
reg have_generation, renew_d, solicited;
reg [HB_W-1:0] heartbeat;
reg [AGE_W-1:0] age;
reg [GUARD_W-1:0] guard_count;

reg previous_valid, header_ok;
reg [3:0] rx_count;
reg [1:0] rx_kind;
reg [15:0] rx_generation, rx_crc, rx_received_crc;
wire message=previous_valid && !rx_valid && header_ok &&
             rx_count==10 && rx_crc==rx_received_crc;
always @(posedge clk or posedge rst) begin
    if(rst) begin
        previous_valid<=0; header_ok<=0; rx_count<=0; rx_kind<=0;
        rx_generation<=0; rx_crc<=16'hffff; rx_received_crc<=0;
    end else begin
        previous_valid<=rx_valid;
        if(rx_valid && !previous_valid) begin
            rx_count<=1; header_ok<=rx_length==10 && rx_data=="L";
            rx_crc<=crc_byte(16'hffff,rx_data);
        end else if(rx_valid) begin
            if(rx_count!=15) rx_count<=rx_count+1'b1;
            if(rx_count<8) rx_crc<=crc_byte(rx_crc,rx_data);
            case(rx_count)
                1: header_ok<=header_ok && rx_data=="N";
                2: header_ok<=header_ok && rx_data=="K";
                3: header_ok<=header_ok && rx_data=="1";
                4: begin rx_kind<=rx_data[1:0]; header_ok<=header_ok && rx_data<4; end
                5: header_ok<=header_ok && rx_data==0;
                6: rx_generation[7:0]<=rx_data;
                7: rx_generation[15:8]<=rx_data;
                8: rx_received_crc[15:8]<=rx_data;
                9: rx_received_crc[7:0]<=rx_data;
                default: header_ok<=0;
            endcase
        end
    end
end

// Repeated messages make a one-entry sender sufficient. Never replace fields
// once a packet is requested, including during application-level restarts.
reg send_event;
reg [1:0] send_kind;
reg [15:0] send_generation;
reg [1:0] tx_state, tx_kind;
reg [15:0] tx_generation, tx_crc;
reg [3:0] tx_count;
wire tx_finished=tx_state==3 && tx_count==9;
assign udp_request=tx_state==2;
assign udp_valid=tx_state==3;
assign udp_length=16'd10;
always @* begin
    case(tx_count)
        0: udp_data="L"; 1: udp_data="N"; 2: udp_data="K"; 3: udp_data="1";
        4: udp_data={6'd0,tx_kind}; 5: udp_data=0;
        6: udp_data=tx_generation[7:0]; 7: udp_data=tx_generation[15:8];
        8: udp_data=tx_crc[15:8]; default: udp_data=tx_crc[7:0];
    endcase
end
always @(posedge clk or posedge rst) begin
    if(rst) begin
        tx_state<=0; tx_kind<=0; tx_generation<=0; tx_crc<=16'hffff; tx_count<=0;
    end else case(tx_state)
        0: if(send_event) begin
            tx_kind<=send_kind; tx_generation<=send_generation;
            tx_crc<=16'hffff; tx_count<=0; tx_state<=1;
        end
        1: if(udp_ready) tx_state<=2;
        2: if(udp_ack) tx_state<=3;
        3: begin
            if(tx_count<8) tx_crc<=crc_byte(tx_crc,udp_data);
            if(tx_count==9) tx_state<=0;
            else tx_count<=tx_count+1'b1;
        end
    endcase
end

always @(posedge clk or posedge rst) begin
    if(rst) begin
        state<=WAIT_PEER; ready<=0; generation<=0; have_generation<=0;
        restart<=0; renew_d<=0; solicited<=0; heartbeat<=0; age<=0;
        guard_count<=0; send_event<=0; send_kind<=0; send_generation<=0;
    end else begin
        restart<=0; send_event<=0; renew_d<=renew;
        if(heartbeat<HEARTBEAT_CYCLES-1) heartbeat<=heartbeat+1'b1;
        else heartbeat<=0;
        if(state!=WAIT_PEER && age<TIMEOUT_CYCLES-1) age<=age+1'b1;
        if(ROLE==0) begin
            // Ignore REQUEST during a healthy lease. A delayed old request
            // must not interrupt current playback. A rebooted B retries until
            // its old lease expires, then receives a new generation.
            if(message && (rx_kind==0 || rx_kind==2) && state==WAIT_PEER) begin
                generation<=(!have_generation || newer(rx_generation,generation)) ?
                            rx_generation+16'd1 : generation+16'd1;
                have_generation<=1; state<=OFFERED; age<=0; restart<=1;
            end else if(message && rx_kind==2 && rx_generation==generation &&
                        (state==OFFERED || state==ACTIVE)) begin
                state<=ACTIVE; ready<=1; age<=0;
                if(tx_state==0 && !send_event) begin
                    send_event<=1; send_kind<=3; send_generation<=generation;
                end
            end else if(state!=WAIT_PEER && age==TIMEOUT_CYCLES-1) begin
                state<=WAIT_PEER; ready<=0; restart<=1; age<=0;
            end
            if(state==OFFERED && heartbeat==0 && tx_state==0 && !send_event) begin
                send_event<=1; send_kind<=1; send_generation<=generation;
            end
        end else begin
            if(tx_finished && tx_kind==0 && state==WAIT_PEER) solicited<=1;
            if(message && rx_kind==1 &&
               ((state==WAIT_PEER && solicited &&
                 (!have_generation || newer(rx_generation,generation))) ||
                (state==ACTIVE && newer(rx_generation,generation)))) begin
                generation<=rx_generation; have_generation<=1; ready<=0;
                state<=RESET_GUARD; guard_count<=0; age<=0; restart<=1; solicited<=0;
            end else if(state==RESET_GUARD) begin
                if(guard_count==RESET_GUARD_CYCLES-1) begin
                    state<=ACTIVE; ready<=1; age<=0; heartbeat<=0;
                end else guard_count<=guard_count+1'b1;
            end else if(message && rx_kind==3 && rx_generation==generation && state==ACTIVE) begin
                age<=0;
            end else if((state==ACTIVE && age==TIMEOUT_CYCLES-1) || (renew && !renew_d)) begin
                state<=WAIT_PEER; ready<=0; age<=0; restart<=1; solicited<=0; heartbeat<=0;
            end
            if(heartbeat==0 && tx_state==0 && !send_event && state!=RESET_GUARD) begin
                send_event<=1; send_kind<=state==ACTIVE ? 2 : 0;
                send_generation<=generation;
            end
        end
    end
end
endmodule
