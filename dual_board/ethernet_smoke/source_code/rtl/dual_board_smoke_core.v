`timescale 1ns / 1ps

// Isolated link test. No TF card, SDRAM, HDMI, or media logic is instantiated.
// RGMII/MAC/UDP blocks are taken from the 2025 HX4S20 reference design.
module dual_board_smoke_core #(
    parameter integer ROLE = 0
)(
    input  wire       clk_50,
    input  wire       sys_rst_n,
    input  wire       key_send_n,
    input  wire       phy1_rgmii_rx_clk,
    input  wire       phy1_rgmii_rx_ctl,
    input  wire [3:0] phy1_rgmii_rx_data,
    output wire       phy1_rgmii_tx_clk,
    output wire       phy1_rgmii_tx_ctl,
    output wire [3:0] phy1_rgmii_tx_data,
    output wire [3:0] led
);

localparam [1:0] SPEED = 2'b10; // Gigabit mode in the reference MAC.
localparam [31:0] LOCAL_IP = ROLE == 0 ? 32'hc0a80a0b : 32'hc0a80a0c;
localparam [31:0] PEER_IP  = ROLE == 0 ? 32'hc0a80a0c : 32'hc0a80a0b;
localparam [47:0] LOCAL_MAC = ROLE == 0 ? 48'h02000000000b :
                                            48'h02000000000c;
localparam [7:0] BOARD_ID = ROLE == 0 ? 8'ha1 : 8'hb2;
localparam [7:0] PEER_ID  = ROLE == 0 ? 8'hb2 : 8'ha1;
localparam [7:0] ROLE_CHAR = ROLE == 0 ? "A" : "B";
localparam [15:0] UDP_PORT = 16'h5001;

wire pll_reset;
wire gtx_clk, gtx_clk90, udp_clk;
wire clk_12_5, clk_1_25, clk_25;
wire rx_clk_0, rx_clk_90;
reg [2:0] reset_pipe;
wire reset = reset_pipe[2];

clk_gen_rst_gen #(.DEVICE("EG4")) u_clk_gen (
    .reset(~sys_rst_n), .clk_in(clk_50), .rst_out(pll_reset),
    .clk_125_out0(gtx_clk), .clk_125_out1(udp_clk),
    .clk_125_out2(gtx_clk90), .clk_12_5_out(clk_12_5),
    .clk_1_25_out(clk_1_25), .clk_25_out(clk_25)
);

always @(posedge udp_clk or posedge pll_reset) begin
    if (pll_reset) reset_pipe <= 3'b111;
    else reset_pipe <= {reset_pipe[1:0], 1'b0};
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

wire udp_tx_ready, app_tx_ack;
wire app_rx_valid;
wire [7:0] app_rx_data;
wire [15:0] app_rx_length, app_rx_port;
wire app_tx_request, app_tx_valid;
wire [7:0] app_tx_data;
wire [15:0] app_tx_length;
wire [31:0] tx_packets, rx_packets, rx_missing, rx_bad;
reg [1:0] key_sync;
reg [25:0] blink_count;
reg blink;

always @(posedge udp_clk or posedge reset) begin
    if (reset) begin
        key_sync <= 2'b11;
        blink_count <= 26'd0;
        blink <= 1'b0;
    end else begin
        key_sync <= {key_sync[0], key_send_n};
        if (blink_count == 26'd62_499_999) begin
            blink_count <= 26'd0;
            blink <= ~blink;
        end else begin
            blink_count <= blink_count + 26'd1;
        end
    end
end

// LED0: running; LED1: local packet sent; LED2: valid peer packet received;
// LED3: malformed/out-of-sequence peer packet observed. LED1-3 latch until reset.
assign led = {(|rx_bad) || (|rx_missing), |rx_packets, |tx_packets, blink};

udp_smoke_app #(.BOARD_ID(BOARD_ID), .PEER_ID(PEER_ID)) u_smoke_app (
    .clk(udp_clk), .rst(reset),
    .send_enable(!key_sync[1]),
    .rx_valid(app_rx_valid && (app_rx_port == UDP_PORT)),
    .rx_data(app_rx_data), .rx_length(app_rx_length),
    .tx_ready(udp_tx_ready), .tx_ack(app_tx_ack),
    .tx_request(app_tx_request), .tx_valid(app_tx_valid),
    .tx_data(app_tx_data), .tx_length(app_tx_length),
    .tx_packets(tx_packets), .rx_packets(rx_packets),
    .rx_missing(rx_missing), .rx_bad(rx_bad)
);

udp_ip_protocol_stack #(
    .DEVICE("EG4"), .LOCAL_UDP_PORT_NUM(UDP_PORT),
    .LOCAL_IP_ADDRESS(LOCAL_IP), .LOCAL_MAC_ADDRESS(LOCAL_MAC)
) u_udp (
    .udp_rx_clk(udp_clk), .udp_tx_clk(udp_clk), .reset(reset),
    .udp2app_tx_ready(udp_tx_ready), .udp2app_tx_ack(app_tx_ack),
    .app_tx_request(app_tx_request), .app_tx_data_valid(app_tx_valid),
    .app_tx_data(app_tx_data), .app_tx_data_length(app_tx_length),
    .app_tx_dst_port(UDP_PORT), .ip_tx_dst_address(PEER_IP),
    .input_local_udp_port_num(UDP_PORT),
    .input_local_udp_port_num_valid(1'b1),
    .input_local_ip_address(LOCAL_IP),
    .input_local_ip_address_valid(1'b1),
    .app_rx_data_valid(app_rx_valid), .app_rx_data(app_rx_data),
    .app_rx_data_length(app_rx_length), .app_rx_port_num(app_rx_port),
    .temac_rx_ready(temac_rx_ready), .temac_rx_valid(!temac_rx_valid),
    .temac_rx_data(temac_rx_data), .temac_rx_sof(temac_rx_sof),
    .temac_rx_eof(temac_rx_eof), .temac_tx_ready(temac_tx_ready),
    .temac_tx_valid(temac_tx_valid), .temac_tx_data(temac_tx_data),
    .temac_tx_sof(temac_tx_sof), .temac_tx_eof(temac_tx_eof),
    .ip_rx_error(), .arp_request_no_reply_error()
);

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
