`timescale 1ns/1ps
// Fixed unicast Ethernet/IPv4/UDP endpoint, not a general-purpose IP stack.
// No ARP, ICMP, VLAN, IPv6, IP options, fragmentation or routing. The two
// configured peers use UDP checksum=0 (permitted for IPv4), with the existing
// application CRC and reliable receipts unchanged. Nonzero UDP checksums are
// rejected rather than accepted without verification. Native MAC strips/adds
// FCS and rejects bad frames; local-link SOF/EOF/ready/valid *_n are active LOW.
// Whole-payload TX buffering bridges the no-backpressure application interface
// to MAC backpressure. RX validates the complete frame BEFORE publishing a
// contiguous application datagram, so short/bad frames cannot leak a prefix.
module fixed_peer_udp #(
    parameter [31:0] LOCAL_IP=32'hc0a80a0b, PEER_IP=32'hc0a80a0c,
    parameter [47:0] LOCAL_MAC=48'h02000000000b, PEER_MAC=48'h02000000000c,
    parameter [15:0] UDP_PORT=16'h5002,
    parameter integer MAX_TX_PAYLOAD=1042, MAX_RX_PAYLOAD=1042,
    parameter integer FILL_TIMEOUT_CYCLES=4096
) (
    input wire clk,rst,
    output wire app_tx_ready,
    output reg app_tx_ack,
    input wire app_tx_request,app_tx_valid,
    input wire [7:0] app_tx_data,
    input wire [15:0] app_tx_length,
    output wire app_rx_valid,
    output wire [7:0] app_rx_data,
    output wire [15:0] app_rx_length,app_rx_port,
    input wire mac_rx_valid,
    input wire [7:0] mac_rx_data,
    input wire mac_rx_sof_n,mac_rx_eof_n,
    output wire mac_rx_ready_n,
    input wire mac_tx_ready_n,
    output wire mac_tx_valid_n,
    output reg [7:0] mac_tx_data,
    output wire mac_tx_sof_n,mac_tx_eof_n
);
localparam integer TX_BITS=$clog2(MAX_TX_PAYLOAD+1);
localparam integer RX_BITS=$clog2(MAX_RX_PAYLOAD+1);
localparam integer TX_ADDR_BITS=MAX_TX_PAYLOAD<2 ? 1 : $clog2(MAX_TX_PAYLOAD);
localparam integer RX_ADDR_BITS=MAX_RX_PAYLOAD<2 ? 1 : $clog2(MAX_RX_PAYLOAD);
localparam integer TX_FRAME_BITS=$clog2(MAX_TX_PAYLOAD+43)<6 ? 6 : $clog2(MAX_TX_PAYLOAD+43);
localparam integer RX_FRAME_BITS=$clog2(MAX_RX_PAYLOAD+43)<6 ? 6 : $clog2(MAX_RX_PAYLOAD+43);
localparam integer WAIT_BITS=$clog2(FILL_TIMEOUT_CYCLES+1);
localparam [19:0] TX_IP_BASE_SUM=20'h04500+20'h04000+20'h04011+
                              LOCAL_IP[31:16]+LOCAL_IP[15:0]+PEER_IP[31:16]+PEER_IP[15:0];
function [15:0] fold_sum;
    input [19:0] sum;
    reg [16:0] folded;
    begin
        folded={1'b0,sum[15:0]}+{13'd0,sum[19:16]};
        fold_sum=folded[15:0]+folded[16];
    end
endfunction

localparam TX_IDLE=0,TX_FILL=1,TX_SEND=2;
reg [1:0] tx_state;
reg [TX_BITS-1:0] tx_length,tx_fill_index;
reg [TX_FRAME_BITS-1:0] tx_frame_index,tx_payload_end,tx_frame_end;
reg [WAIT_BITS-1:0] fill_wait;
reg [7:0] tx_mem[0:(1<<TX_ADDR_BITS)-1]; /* fehdl force_ram=1, ram_style="bram" */
reg [7:0] tx_ram_out;
wire [15:0] tx_ip_length=tx_length+16'd28;
wire [15:0] tx_udp_length=tx_length+16'd8;
wire [15:0] tx_ip_checksum=~fold_sum(TX_IP_BASE_SUM+{4'd0,tx_ip_length});
wire tx_accept=tx_state==TX_SEND && !mac_tx_ready_n;
wire [TX_FRAME_BITS-1:0] tx_next_address=tx_frame_index-41;
assign app_tx_ready=!rst && tx_state==TX_IDLE;
assign mac_tx_valid_n=rst || tx_state!=TX_SEND;
assign mac_tx_sof_n=tx_state!=TX_SEND || tx_frame_index!=0;
assign mac_tx_eof_n=tx_state!=TX_SEND || tx_frame_index!=tx_frame_end;
always @(posedge clk)begin
    if(tx_state==TX_FILL && app_tx_valid && !rst)
        tx_mem[tx_fill_index[TX_ADDR_BITS-1:0]]<=app_tx_data;
    // The last header transfer prefetches payload byte 0. Each accepted payload
    // transfer prefetches the next byte; during a MAC stall RAM output holds.
    if(tx_accept && tx_frame_index>=41 && tx_frame_index<tx_payload_end)
        tx_ram_out<=tx_mem[tx_next_address[TX_ADDR_BITS-1:0]];
end
always @* begin
    mac_tx_data=0;
    if(tx_frame_index>=42)begin
        if(tx_frame_index<=tx_payload_end)mac_tx_data=tx_ram_out;
    end else case(tx_frame_index[5:0])
        0:mac_tx_data=PEER_MAC[47:40];1:mac_tx_data=PEER_MAC[39:32];
        2:mac_tx_data=PEER_MAC[31:24];3:mac_tx_data=PEER_MAC[23:16];
        4:mac_tx_data=PEER_MAC[15:8];5:mac_tx_data=PEER_MAC[7:0];
        6:mac_tx_data=LOCAL_MAC[47:40];7:mac_tx_data=LOCAL_MAC[39:32];
        8:mac_tx_data=LOCAL_MAC[31:24];9:mac_tx_data=LOCAL_MAC[23:16];
        10:mac_tx_data=LOCAL_MAC[15:8];11:mac_tx_data=LOCAL_MAC[7:0];
        12:mac_tx_data=8'h08;14:mac_tx_data=8'h45;
        16:mac_tx_data=tx_ip_length[15:8];17:mac_tx_data=tx_ip_length[7:0];
        20:mac_tx_data=8'h40;22:mac_tx_data=8'h40;23:mac_tx_data=8'h11;
        24:mac_tx_data=tx_ip_checksum[15:8];25:mac_tx_data=tx_ip_checksum[7:0];
        26:mac_tx_data=LOCAL_IP[31:24];27:mac_tx_data=LOCAL_IP[23:16];
        28:mac_tx_data=LOCAL_IP[15:8];29:mac_tx_data=LOCAL_IP[7:0];
        30:mac_tx_data=PEER_IP[31:24];31:mac_tx_data=PEER_IP[23:16];
        32:mac_tx_data=PEER_IP[15:8];33:mac_tx_data=PEER_IP[7:0];
        34,36:mac_tx_data=UDP_PORT[15:8];35,37:mac_tx_data=UDP_PORT[7:0];
        38:mac_tx_data=tx_udp_length[15:8];39:mac_tx_data=tx_udp_length[7:0];
        default:mac_tx_data=0;
    endcase
end
always @(posedge clk or posedge rst)begin
    if(rst)begin
        tx_state<=TX_IDLE;app_tx_ack<=0;tx_length<=0;tx_fill_index<=0;
        tx_frame_index<=0;tx_payload_end<=0;tx_frame_end<=0;fill_wait<=0;
    end else begin
        app_tx_ack<=0;
        case(tx_state)
            TX_IDLE:if(app_tx_request && app_tx_length!=0 && app_tx_length<=MAX_TX_PAYLOAD)begin
                tx_length<=app_tx_length[TX_BITS-1:0];tx_fill_index<=0;
                fill_wait<=0;app_tx_ack<=1;tx_state<=TX_FILL;
            end
            TX_FILL:begin
                if(app_tx_valid)begin
                    fill_wait<=0;
                    if(tx_fill_index==tx_length-1'b1)begin
                        tx_payload_end<=tx_length+41;
                        tx_frame_end<=tx_length<18 ? 59 : tx_length+41;
                        tx_frame_index<=0;tx_state<=TX_SEND;
                    end else tx_fill_index<=tx_fill_index+1'b1;
                end else if(fill_wait==FILL_TIMEOUT_CYCLES-1)begin
                    // Nothing has entered the native MAC FIFO yet.
                    tx_state<=TX_IDLE;fill_wait<=0;
                end else fill_wait<=fill_wait+1'b1;
            end
            TX_SEND:if(tx_accept)begin
                if(tx_frame_index==tx_frame_end)tx_state<=TX_IDLE;
                else tx_frame_index<=tx_frame_index+1'b1;
            end
            default:tx_state<=TX_IDLE;
        endcase
    end
end

localparam RX_SEEK=0,RX_FRAME=1,RX_PRIME=2,RX_DELIVER=3;
reg [1:0] rx_state;
reg [RX_FRAME_BITS-1:0] rx_index,rx_payload_end,rx_frame_end;
reg [RX_BITS-1:0] rx_write_count,rx_read_index,rx_length,rx_remaining;
reg [15:0] rx_ip_length,rx_udp_length;
reg [19:0] rx_ip_sum;
reg [7:0] rx_high_byte;
reg header_ok,payload_ok;
reg [7:0] rx_mem[0:(1<<RX_ADDR_BITS)-1]; /* fehdl force_ram=1, ram_style="bram" */
reg [7:0] rx_ram_out;
wire rx_accept=mac_rx_valid && !mac_rx_ready_n;
wire rx_write=rx_accept && mac_rx_sof_n && rx_state==RX_FRAME &&
              payload_ok && rx_index>=42 && rx_index<=rx_payload_end;
// For a 20-bit one's-complement sum, fold(sum)==FFFF exactly when the
// low 16 bits equal FFFF minus the high nibble. That is FFF:~high, so the
// acceptance predicate needs equality only, not two cascaded carry chains.
// TX still folds normally to generate an arbitrary checksum value.
wire rx_ip_checksum_ok=rx_ip_sum[15:4]==12'hfff && rx_ip_sum[3:0]==~rx_ip_sum[19:16];
wire candidate_ok=header_ok && mac_rx_data==0 && rx_ip_checksum_ok &&
                  rx_udp_length>=9 && rx_udp_length<=MAX_RX_PAYLOAD+8 &&
                  {1'b0,rx_ip_length}=={1'b0,rx_udp_length}+17'd20;
wire [15:0] candidate_length=rx_udp_length-16'd8;
wire [16:0] candidate_frame_length={1'b0,rx_udp_length}+17'd34;
wire [RX_BITS-1:0] rx_next_address=rx_state==RX_PRIME ? 0 : rx_read_index+1'b1;
assign mac_rx_ready_n=rst || rx_state==RX_PRIME || rx_state==RX_DELIVER;
assign app_rx_valid=!rst && rx_state==RX_DELIVER;
assign app_rx_data=rx_ram_out;
assign app_rx_length={{(16-RX_BITS){1'b0}},rx_length};
assign app_rx_port=UDP_PORT;
always @(posedge clk)begin
    if(rx_write)rx_mem[rx_write_count[RX_ADDR_BITS-1:0]]<=mac_rx_data;
    if(rx_state==RX_PRIME || (rx_state==RX_DELIVER && rx_remaining>1))
        rx_ram_out<=rx_mem[rx_next_address[RX_ADDR_BITS-1:0]];
end
always @(posedge clk or posedge rst)begin
    if(rst)begin
        rx_state<=RX_SEEK;rx_index<=0;rx_payload_end<=0;rx_frame_end<=0;
        rx_write_count<=0;rx_read_index<=0;rx_length<=0;rx_remaining<=0;
        rx_ip_length<=0;rx_udp_length<=0;rx_ip_sum<=0;rx_high_byte<=0;
        header_ok<=0;payload_ok<=0;
    end else if(rx_state==RX_PRIME)begin
        rx_read_index<=0;rx_remaining<=rx_length;rx_state<=RX_DELIVER;
    end else if(rx_state==RX_DELIVER)begin
        if(rx_remaining==1)begin rx_state<=RX_SEEK;rx_remaining<=0;end
        else begin rx_remaining<=rx_remaining-1'b1;rx_read_index<=rx_read_index+1'b1;end
    end else if(rx_accept)begin
        if(!mac_rx_sof_n)begin
            rx_state<=mac_rx_eof_n ? RX_FRAME : RX_SEEK;rx_index<=1;
            rx_write_count<=0;rx_ip_length<=0;rx_udp_length<=0;rx_ip_sum<=0;
            rx_high_byte<=0;payload_ok<=0;
            header_ok<=mac_rx_data==LOCAL_MAC[47:40];
        end else if(rx_state==RX_FRAME)begin
            // Saturate instead of wrapping: a giant foreign frame must never
            // revisit the header or appear to have a valid short EOF length.
            if(!(&rx_index))rx_index<=rx_index+1'b1;
            if(rx_write)rx_write_count<=rx_write_count+1'b1;
            if(rx_index>=14 && rx_index<34)begin
                if(!rx_index[0])rx_high_byte<=mac_rx_data;
                else rx_ip_sum<=rx_ip_sum+{rx_high_byte,mac_rx_data};
            end
            case(rx_index)
                1:header_ok<=header_ok && mac_rx_data==LOCAL_MAC[39:32];
                2:header_ok<=header_ok && mac_rx_data==LOCAL_MAC[31:24];
                3:header_ok<=header_ok && mac_rx_data==LOCAL_MAC[23:16];
                4:header_ok<=header_ok && mac_rx_data==LOCAL_MAC[15:8];
                5:header_ok<=header_ok && mac_rx_data==LOCAL_MAC[7:0];
                6:header_ok<=header_ok && mac_rx_data==PEER_MAC[47:40];
                7:header_ok<=header_ok && mac_rx_data==PEER_MAC[39:32];
                8:header_ok<=header_ok && mac_rx_data==PEER_MAC[31:24];
                9:header_ok<=header_ok && mac_rx_data==PEER_MAC[23:16];
                10:header_ok<=header_ok && mac_rx_data==PEER_MAC[15:8];
                11:header_ok<=header_ok && mac_rx_data==PEER_MAC[7:0];
                12:header_ok<=header_ok && mac_rx_data==8'h08;
                13:header_ok<=header_ok && mac_rx_data==0;
                14:header_ok<=header_ok && mac_rx_data==8'h45;
                16:rx_ip_length[15:8]<=mac_rx_data;
                17:rx_ip_length[7:0]<=mac_rx_data;
                20:header_ok<=header_ok && (mac_rx_data & 8'hbf)==0;
                21:header_ok<=header_ok && mac_rx_data==0;
                22:header_ok<=header_ok && mac_rx_data!=0;
                23:header_ok<=header_ok && mac_rx_data==8'h11;
                26:header_ok<=header_ok && mac_rx_data==PEER_IP[31:24];
                27:header_ok<=header_ok && mac_rx_data==PEER_IP[23:16];
                28:header_ok<=header_ok && mac_rx_data==PEER_IP[15:8];
                29:header_ok<=header_ok && mac_rx_data==PEER_IP[7:0];
                30:header_ok<=header_ok && mac_rx_data==LOCAL_IP[31:24];
                31:header_ok<=header_ok && mac_rx_data==LOCAL_IP[23:16];
                32:header_ok<=header_ok && mac_rx_data==LOCAL_IP[15:8];
                33:header_ok<=header_ok && mac_rx_data==LOCAL_IP[7:0];
                34,36:header_ok<=header_ok && mac_rx_data==UDP_PORT[15:8];
                35,37:header_ok<=header_ok && mac_rx_data==UDP_PORT[7:0];
                38:rx_udp_length[15:8]<=mac_rx_data;
                39:rx_udp_length[7:0]<=mac_rx_data;
                40:header_ok<=header_ok && mac_rx_data==0;
                41:begin
                    payload_ok<=candidate_ok;
                    if(candidate_ok)begin
                        rx_length<=candidate_length[RX_BITS-1:0];
                        rx_payload_end<=candidate_frame_length-1'b1;
                        rx_frame_end<=candidate_frame_length<60 ? 59 : candidate_frame_length-1'b1;
                    end
                end
                default:begin end
            endcase
            if(!mac_rx_eof_n)begin
                // A MAC client may keep the Ethernet pad or strip it. Accept
                // only either complete shape, never an intermediate/truncated
                // payload or an unexplained longer tail (FCS is MAC-owned).
                if(payload_ok && (rx_index==rx_payload_end || rx_index==rx_frame_end) &&
                   rx_write_count+rx_write==rx_length)rx_state<=RX_PRIME;
                else rx_state<=RX_SEEK;
                payload_ok<=0;
            end
        end
    end
end
endmodule
