`timescale 1ns/1ps
// Hold B K2 (B2) to send full IMG4 frames; K1 (A2) is reset, NOT send.
module fixed_udp_hw_b (
    input wire clk_50,sys_rst_n,key_send_n,phy1_rgmii_rx_clk,phy1_rgmii_rx_ctl,
    input wire [3:0] phy1_rgmii_rx_data,
    output wire phy1_rgmii_tx_clk,phy1_rgmii_tx_ctl,
    output wire [3:0] phy1_rgmii_tx_data,led
);
wire clk,rst,tx_ready,tx_ack,tx_req,tx_valid,rx_valid;
wire [7:0] tx_data,rx_data;
wire [15:0] tx_length,rx_length,rx_port;
dual_board_eth_transport #(.ROLE(1),.FIXED_PEER(1)) u_net (
    .clk_50(clk_50),.sys_rst_n(sys_rst_n),
    .phy1_rgmii_rx_clk(phy1_rgmii_rx_clk),.phy1_rgmii_rx_ctl(phy1_rgmii_rx_ctl),
    .phy1_rgmii_rx_data(phy1_rgmii_rx_data),.phy1_rgmii_tx_clk(phy1_rgmii_tx_clk),
    .phy1_rgmii_tx_ctl(phy1_rgmii_tx_ctl),.phy1_rgmii_tx_data(phy1_rgmii_tx_data),
    .udp_clk(clk),.reset(rst),.tx_ready_app(tx_ready),.tx_ack_app(tx_ack),
    .tx_request_app(tx_req),.tx_valid_app(tx_valid),.tx_data_app(tx_data),.tx_length_app(tx_length),
    .rx_valid_app(rx_valid),.rx_data_app(rx_data),.rx_length_app(rx_length),.rx_port_app(rx_port),
    .media_video_clk(),.media_5x_clk(),.media_clock_ready());
wire receipt_valid,frame_sent;
wire [31:0] receipt_token;
wire [15:0] receipt_sequence,packets_sent;
image_receipt_rx receipt (
    .clk(clk),.rst(rst),.rx_valid(rx_valid && rx_port==16'h5002),.rx_data(rx_data),.rx_length(rx_length),
    .receipt_valid(receipt_valid),.receipt_token(receipt_token),.receipt_sequence(receipt_sequence));
reg [1:0] key_sync;
wire active;
wire [18:0] count;
fixed_udp_hw_pattern tx (
    .clk(clk),.rst(rst),.start(!key_sync[1]),.busy(active),.count(count),.udp_ready(tx_ready),.udp_ack(tx_ack),
    .udp_request(tx_req),.udp_valid(tx_valid),.udp_data(tx_data),.udp_length(tx_length),
    .frame_sent(frame_sent),.packets_sent(packets_sent),.receipt_valid(receipt_valid),
    .receipt_token(receipt_token),.receipt_sequence(receipt_sequence));
reg [25:0] heartbeat_count;
reg heartbeat,sent_latched,ack_latched;
always @(posedge clk or posedge rst)begin
    if(rst)begin
        key_sync<=3;
        heartbeat_count<=0;heartbeat<=0;sent_latched<=0;ack_latched<=0;
    end else begin
        key_sync<={key_sync[0],key_send_n};
        if(heartbeat_count==26'd62499999)begin heartbeat_count<=0;heartbeat<=~heartbeat;end
        else heartbeat_count<=heartbeat_count+1'b1;
        if(receipt_valid)ack_latched<=1;
        if(frame_sent)sent_latched<=1;
    end
end
// LED3 valid reverse UDP ACK; LED2 final ACK received (not merely bytes sent).
assign led={ack_latched,sent_latched,(packets_sent!=0),heartbeat};
endmodule
