`timescale 1ns/1ps

// Reusable stand-alone UDP/RGMII transport for the image-link throughput test.
// The final HDMI main-board integration must share pll_gen's 25/125 MHz
// outputs with video instead of instantiating another video_pll.
module dual_board_eth_transport #(
    parameter integer ROLE = 0,
    parameter [15:0] UDP_PORT = 16'h5002,
    parameter integer FIXED_PEER = 0
) (
    input  wire       clk_50,
    input  wire       sys_rst_n,
    input  wire       phy1_rgmii_rx_clk,
    input  wire       phy1_rgmii_rx_ctl,
    input  wire [3:0] phy1_rgmii_rx_data,
    output wire       phy1_rgmii_tx_clk,
    output wire       phy1_rgmii_tx_ctl,
    output wire [3:0] phy1_rgmii_tx_data,
    output wire       udp_clk,
    output wire       reset,
    output wire       tx_ready_app,
    output wire       tx_ack_app,
    input  wire       tx_request_app,
    input  wire       tx_valid_app,
    input  wire [7:0] tx_data_app,
    input  wire [15:0] tx_length_app,
    output wire       rx_valid_app,
    output wire [7:0] rx_data_app,
    output wire [15:0] rx_length_app,
    output wire [15:0] rx_port_app,
    output wire       media_video_clk,
    output wire       media_5x_clk,
    output wire       media_clock_ready
);
localparam [1:0] SPEED = 2'b10;
localparam [31:0] LOCAL_IP = ROLE == 0 ? 32'hc0a80a0b : 32'hc0a80a0c;
localparam [31:0] PEER_IP  = ROLE == 0 ? 32'hc0a80a0c : 32'hc0a80a0b;
localparam [47:0] LOCAL_MAC = ROLE == 0 ? 48'h02000000000b :
                                            48'h02000000000c;
localparam [47:0] PEER_MAC = ROLE == 0 ? 48'h02000000000c :
                                           48'h02000000000b;

wire pll_reset;
wire gtx_clk, gtx_clk90;
wire clk_12_5, clk_1_25, clk_25;
wire rx_clk_0, rx_clk_90;
assign media_video_clk=clk_25;
assign media_5x_clk=udp_clk;
assign media_clock_ready=!pll_reset;
reg [2:0] reset_pipe;
assign reset = reset_pipe[2];

clk_gen_rst_gen #(.DEVICE("EG4")) u_clk_gen (
    .reset(~sys_rst_n), .clk_in(clk_50), .rst_out(pll_reset),
    .clk_125_out0(gtx_clk), .clk_125_out1(udp_clk),
    .clk_125_out2(gtx_clk90), .clk_12_5_out(clk_12_5),
    .clk_1_25_out(clk_1_25), .clk_25_out(clk_25)
);
// 20261019 TX watchdog (fixed-peer player only). The application keeps
// tx_request asserted until the UDP endpoint acknowledges; a healthy stack
// acknowledges within microseconds. A request pending for 200 ms means the
// UDP/MAC transmit path is wedged, which previously left the A/B link down
// until power-cycling. Re-run the same synchronous reset the stack gets at
// power-up; the lease protocol then rebuilds the link and media sessions.
// RX watchdog: both boards receive periodic traffic every few ms (control,
// receipts, lease heartbeats). One second without a single received datagram
// means the receive path or the peer is gone; resetting an idle stack is
// harmless, and it recovers a wedged MAC/FIFO without a power cycle.
localparam integer WEDGE_CYCLES=25_000_000;
localparam integer SILENCE_CYCLES=125_000_000;
reg [24:0] wedge_count;
reg [26:0] silence_count;
reg wedge_reset;
always @(posedge udp_clk or posedge pll_reset) begin
    if (pll_reset) begin wedge_count <= 0; silence_count <= 0; wedge_reset <= 1'b0; end
    else begin
        wedge_reset <= 1'b0;
        if (!FIXED_PEER || reset || !tx_request_app || tx_ack_app) wedge_count <= 0;
        else if (wedge_count == WEDGE_CYCLES-1) begin
            wedge_count <= 0; wedge_reset <= 1'b1;
        end else wedge_count <= wedge_count + 1'b1;
        if (!FIXED_PEER || reset || rx_valid_app) silence_count <= 0;
        else if (silence_count == SILENCE_CYCLES-1) begin
            silence_count <= 0; wedge_reset <= 1'b1;
        end else silence_count <= silence_count + 1'b1;
    end
end
always @(posedge udp_clk or posedge pll_reset) begin
    if (pll_reset) reset_pipe <= 3'b111;
    else if (wedge_reset) reset_pipe <= 3'b111;
    else reset_pipe <= {reset_pipe[1:0],1'b0};
end
rx_pll u_rx_pll (
    .refclk(phy1_rgmii_rx_clk), .reset(1'b0),
    .clk0_out(rx_clk_0), .clk1_out(rx_clk_90)
);

wire rx_clk_int, rx_clk_en_int, tx_clk_int, tx_clk_en_int;
wire [7:0] rx_data, tx_data;
wire rx_valid, rx_correct_frame, rx_error_frame;
wire tx_valid, tx_ready, tx_collision, tx_retransmit;
wire temac_rx_ready, temac_rx_valid;
wire [7:0] temac_rx_data;
wire temac_rx_sof, temac_rx_eof;
wire temac_tx_ready, temac_tx_valid;
wire [7:0] temac_tx_data;
wire temac_tx_sof, temac_tx_eof;

// Legacy pattern/smoke projects keep their original stack. Only the formal
// player explicitly opts into the fixed-peer endpoint; MAC, FIFO and clocks
// are shared unchanged and no encrypted source is edited.
generate if(FIXED_PEER)begin : fixed_peer
fixed_peer_udp #(
    .LOCAL_IP(LOCAL_IP),.PEER_IP(PEER_IP),.LOCAL_MAC(LOCAL_MAC),.PEER_MAC(PEER_MAC),
    .UDP_PORT(UDP_PORT),.MAX_TX_PAYLOAD(ROLE==0 ? 18 : 1042),
    .MAX_RX_PAYLOAD(ROLE==0 ? 1042 : 18)
) u_udp (
    .clk(udp_clk),.rst(reset),.app_tx_ready(tx_ready_app),.app_tx_ack(tx_ack_app),
    .app_tx_request(tx_request_app),.app_tx_valid(tx_valid_app),
    .app_tx_data(tx_data_app),.app_tx_length(tx_length_app),
    .app_rx_valid(rx_valid_app),.app_rx_data(rx_data_app),
    .app_rx_length(rx_length_app),.app_rx_port(rx_port_app),
    .mac_rx_valid(!temac_rx_valid),.mac_rx_data(temac_rx_data),
    .mac_rx_sof_n(temac_rx_sof),.mac_rx_eof_n(temac_rx_eof),.mac_rx_ready_n(temac_rx_ready),
    .mac_tx_ready_n(temac_tx_ready),.mac_tx_valid_n(temac_tx_valid),
    .mac_tx_data(temac_tx_data),.mac_tx_sof_n(temac_tx_sof),.mac_tx_eof_n(temac_tx_eof)
);
end else begin : legacy
udp_ip_protocol_stack #(
    .DEVICE("EG4"), .LOCAL_UDP_PORT_NUM(UDP_PORT),
    .LOCAL_IP_ADDRESS(LOCAL_IP), .LOCAL_MAC_ADDRESS(LOCAL_MAC)
) u_udp (
    .udp_rx_clk(udp_clk), .udp_tx_clk(udp_clk), .reset(reset),
    .udp2app_tx_ready(tx_ready_app), .udp2app_tx_ack(tx_ack_app),
    .app_tx_request(tx_request_app), .app_tx_data_valid(tx_valid_app),
    .app_tx_data(tx_data_app), .app_tx_data_length(tx_length_app),
    .app_tx_dst_port(UDP_PORT), .ip_tx_dst_address(PEER_IP),
    .input_local_udp_port_num(UDP_PORT),
    .input_local_udp_port_num_valid(1'b1),
    .input_local_ip_address(LOCAL_IP),
    .input_local_ip_address_valid(1'b1),
    .app_rx_data_valid(rx_valid_app), .app_rx_data(rx_data_app),
    .app_rx_data_length(rx_length_app), .app_rx_port_num(rx_port_app),
    .temac_rx_ready(temac_rx_ready), .temac_rx_valid(!temac_rx_valid),
    .temac_rx_data(temac_rx_data), .temac_rx_sof(temac_rx_sof),
    .temac_rx_eof(temac_rx_eof), .temac_tx_ready(temac_tx_ready),
    .temac_tx_valid(temac_tx_valid), .temac_tx_data(temac_tx_data),
    .temac_tx_sof(temac_tx_sof), .temac_tx_eof(temac_tx_eof),
    .ip_rx_error(), .arp_request_no_reply_error()
);
end endgenerate

wire [47:0] unicast_address = {
    LOCAL_MAC[7:0], LOCAL_MAC[15:8], LOCAL_MAC[23:16],
    LOCAL_MAC[31:24], LOCAL_MAC[39:32], LOCAL_MAC[47:40]
};
wire [19:0] mac_cfg_vector = {
    1'b0, 2'b00, SPEED, 8'b00000010, 7'b0000010
};
temac_block #(.DEVICE("EG4")) u_temac (
    .reset(reset), .gtx_clk(gtx_clk), .gtx_clk_90(gtx_clk90),
    .rx_clk(rx_clk_int), .rx_clk_en(rx_clk_en_int),
    .rx_data(rx_data), .rx_data_valid(rx_valid),
    .rx_correct_frame(rx_correct_frame), .rx_error_frame(rx_error_frame),
    .rx_status_vector(), .rx_status_vld(),
    .tx_clk(tx_clk_int), .tx_clk_en(tx_clk_en_int),
    .tx_data(tx_data), .tx_data_en(tx_valid), .tx_rdy(tx_ready),
    .tx_stop(1'b0), .tx_collision(tx_collision),
    .tx_retransmit(tx_retransmit), .tx_ifg_val(8'h00),
    .tx_status_vector(), .tx_status_vld(),
    .pause_req(1'b0), .pause_val(16'h0000),
    .pause_source_addr(48'h5af1f2f3f4f5),
    .unicast_address(unicast_address), .mac_cfg_vector(mac_cfg_vector),
    .rgmii_txd(phy1_rgmii_tx_data),
    .rgmii_tx_ctl(phy1_rgmii_tx_ctl),
    .rgmii_txc(phy1_rgmii_tx_clk),
    .rgmii_rxd(phy1_rgmii_rx_data),
    .rgmii_rx_ctl(phy1_rgmii_rx_ctl),
    .rgmii_rxc(rx_clk_90),
    .inband_link_status(), .inband_clock_speed(),
    .inband_duplex_status()
);
tx_client_fifo #(.DEVICE("EG4")) u_tx_fifo (
    .rd_clk(tx_clk_int), .rd_sreset(reset),
    .rd_enable(tx_clk_en_int), .tx_data(tx_data),
    .tx_data_valid(tx_valid), .tx_ack(tx_ready),
    .tx_collision(tx_collision), .tx_retransmit(tx_retransmit),
    .overflow(), .wr_clk(udp_clk), .wr_sreset(reset),
    .wr_data(temac_tx_data), .wr_sof_n(temac_tx_sof),
    .wr_eof_n(temac_tx_eof), .wr_src_rdy_n(temac_tx_valid),
    .wr_dst_rdy_n(temac_tx_ready), .wr_fifo_status()
);
rx_client_fifo #(.DEVICE("EG4")) u_rx_fifo (
    .wr_clk(rx_clk_int), .wr_enable(rx_clk_en_int),
    .wr_sreset(reset), .rx_data(rx_data),
    .rx_data_valid(rx_valid), .rx_good_frame(rx_correct_frame),
    .rx_bad_frame(rx_error_frame), .overflow(),
    .rd_clk(udp_clk), .rd_sreset(reset),
    .rd_data_out(temac_rx_data), .rd_sof_n(temac_rx_sof),
    .rd_eof_n(temac_rx_eof), .rd_src_rdy_n(temac_rx_valid),
    .rd_dst_rdy_n(temac_rx_ready), .rx_fifo_status()
);
endmodule
