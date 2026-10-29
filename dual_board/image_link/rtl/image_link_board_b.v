`timescale 1ns/1ps

// B-board deterministic image source for the second Ethernet hardware test.
// Hold K2 to keep transmitting full 640x480 pattern frames; K1 resets.
// TF/BMP is deliberately not integrated until this full-frame link is proven.
module image_link_board_b (
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
wire udp_clk, reset, tx_ready_app, tx_ack_app;
wire tx_request_app, tx_valid_app;
wire [7:0] tx_data_app;
wire [15:0] tx_length_app;
dual_board_eth_transport #(.ROLE(1), .UDP_PORT(16'h5002)) u_net (
    .clk_50(clk_50), .sys_rst_n(sys_rst_n),
    .phy1_rgmii_rx_clk(phy1_rgmii_rx_clk),
    .phy1_rgmii_rx_ctl(phy1_rgmii_rx_ctl),
    .phy1_rgmii_rx_data(phy1_rgmii_rx_data),
    .phy1_rgmii_tx_clk(phy1_rgmii_tx_clk),
    .phy1_rgmii_tx_ctl(phy1_rgmii_tx_ctl),
    .phy1_rgmii_tx_data(phy1_rgmii_tx_data),
    .udp_clk(udp_clk), .reset(reset),
    .tx_ready_app(tx_ready_app), .tx_ack_app(tx_ack_app),
    .tx_request_app(tx_request_app), .tx_valid_app(tx_valid_app),
    .tx_data_app(tx_data_app), .tx_length_app(tx_length_app),
    .rx_valid_app(), .rx_data_app(), .rx_length_app(), .rx_port_app()
);

reg [1:0] key_sync;
reg active;
reg [18:0] pixels_source;
reg [9:0] x;
reg [8:0] y;
wire source_ready;
wire source_valid = active && (pixels_source < 19'd307200);
wire [23:0] source_rgb = {x[7:0],y[7:0],(x[7:0] ^ y[7:0])};
wire frame_sent;
wire [15:0] packets_sent;
image_packet_tx u_image_tx (
    .clk(udp_clk), .rst(reset),
    .source_valid(source_valid), .source_ready(source_ready),
    .source_rgb(source_rgb),
    .source_frame_start(pixels_source == 19'd0),
    .source_frame_index(2'd0), .source_top_down(1'b1),
    .udp_ready(tx_ready_app), .udp_ack(tx_ack_app),
    .udp_request(tx_request_app), .udp_valid(tx_valid_app),
    .udp_data(tx_data_app), .udp_length(tx_length_app),
    .frame_sent(frame_sent), .packets_sent(packets_sent)
);

reg [25:0] blink_count;
reg blink;
reg sent_frame_latched;
always @(posedge udp_clk or posedge reset) begin
    if (reset) begin
        key_sync <= 2'b11;
        active <= 1'b0;
        pixels_source <= 19'd0;
        x <= 10'd0;
        y <= 9'd0;
        blink_count <= 26'd0;
        blink <= 1'b0;
        sent_frame_latched <= 1'b0;
    end else begin
        key_sync <= {key_sync[0],key_send_n};
        if (blink_count == 26'd62_499_999) begin
            blink_count <= 26'd0;
            blink <= ~blink;
        end else blink_count <= blink_count + 26'd1;
        if (frame_sent) begin
            sent_frame_latched <= 1'b1;
            active <= 1'b0;
        end else if (!active && !key_sync[1]) begin
            active <= 1'b1;
            pixels_source <= 19'd0;
            x <= 10'd0;
            y <= 9'd0;
        end
        if (source_valid && source_ready) begin
            pixels_source <= pixels_source + 19'd1;
            if (x == 10'd639) begin
                x <= 10'd0;
                y <= y + 9'd1;
            end else x <= x + 10'd1;
        end
    end
end
assign led = {1'b0,sent_frame_latched,
              (packets_sent != 16'd0),blink};
endmodule
