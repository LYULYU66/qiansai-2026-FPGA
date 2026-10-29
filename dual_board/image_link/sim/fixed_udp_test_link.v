`timescale 1ns/1ps
// Component test bridge: one application datagram traverses two real fixed
// Ethernet/IPv4/UDP endpoints. The native MAC local-link is connected directly;
// this deliberately does not model the PHY, MAC FIFO, preamble, FCS or wire IFG.
// Defaults are source board B (.12 / :0c) -> display board A (.11 / :0b).
// Swap the four address parameters for the A -> B receipt/lease direction.
module fixed_udp_test_link #(
    parameter [31:0] SOURCE_IP=32'hc0a80a0c, DEST_IP=32'hc0a80a0b,
    parameter [47:0] SOURCE_MAC=48'h02000000000c, DEST_MAC=48'h02000000000b,
    parameter integer MAX_PAYLOAD=1042
) (
    input wire clk,tx_rst,rx_rst,
    input wire [7:0] tx_data,
    input wire [15:0] tx_length,
    input wire tx_request,tx_valid,
    output wire tx_ready,tx_ack,
    output wire rx_valid,
    output wire [7:0] rx_data,
    output wire [15:0] rx_length
);
wire [7:0] frame_data;
wire frame_valid_n,frame_ready_n,frame_sof_n,frame_eof_n;

fixed_peer_udp #(
    .LOCAL_IP(SOURCE_IP),.PEER_IP(DEST_IP),
    .LOCAL_MAC(SOURCE_MAC),.PEER_MAC(DEST_MAC),
    .UDP_PORT(16'h5002),.MAX_TX_PAYLOAD(MAX_PAYLOAD),.MAX_RX_PAYLOAD(MAX_PAYLOAD)
) sender (
    .clk(clk),.rst(tx_rst),
    .app_tx_ready(tx_ready),.app_tx_ack(tx_ack),
    .app_tx_request(tx_request),.app_tx_valid(tx_valid),
    .app_tx_data(tx_data),.app_tx_length(tx_length),
    .app_rx_valid(),.app_rx_data(),.app_rx_length(),.app_rx_port(),
    .mac_rx_valid(1'b0),.mac_rx_data(8'd0),
    .mac_rx_sof_n(1'b1),.mac_rx_eof_n(1'b1),.mac_rx_ready_n(),
    .mac_tx_ready_n(frame_ready_n),.mac_tx_valid_n(frame_valid_n),
    .mac_tx_data(frame_data),.mac_tx_sof_n(frame_sof_n),.mac_tx_eof_n(frame_eof_n)
);

fixed_peer_udp #(
    .LOCAL_IP(DEST_IP),.PEER_IP(SOURCE_IP),
    .LOCAL_MAC(DEST_MAC),.PEER_MAC(SOURCE_MAC),
    .UDP_PORT(16'h5002),.MAX_TX_PAYLOAD(MAX_PAYLOAD),.MAX_RX_PAYLOAD(MAX_PAYLOAD)
) receiver (
    .clk(clk),.rst(rx_rst),
    .app_tx_ready(),.app_tx_ack(),
    .app_tx_request(1'b0),.app_tx_valid(1'b0),
    .app_tx_data(8'd0),.app_tx_length(16'd0),
    .app_rx_valid(rx_valid),.app_rx_data(rx_data),
    .app_rx_length(rx_length),.app_rx_port(),
    // Endpoint RX valid is normalized active-high; MAC TX valid_n is active-low.
    .mac_rx_valid(!frame_valid_n),.mac_rx_data(frame_data),
    .mac_rx_sof_n(frame_sof_n),.mac_rx_eof_n(frame_eof_n),.mac_rx_ready_n(frame_ready_n),
    .mac_tx_ready_n(1'b0),.mac_tx_valid_n(),
    .mac_tx_data(),.mac_tx_sof_n(),.mac_tx_eof_n()
);
endmodule
