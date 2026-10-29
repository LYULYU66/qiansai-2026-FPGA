`timescale 1ns/1ps

// A-board large-payload link test only: checks 307200 RGB pixels but does not
// drive HDMI/SDRAM yet. LED0 heartbeat, LED1 any good packet, LED2 complete
// image, LED3 bad packet or pixel. All status LEDs latch until K1 reset.
module image_link_board_a (
    input  wire       clk_50,
    input  wire       sys_rst_n,
    input  wire       phy1_rgmii_rx_clk,
    input  wire       phy1_rgmii_rx_ctl,
    input  wire [3:0] phy1_rgmii_rx_data,
    output wire       phy1_rgmii_tx_clk,
    output wire       phy1_rgmii_tx_ctl,
    output wire [3:0] phy1_rgmii_tx_data,
    output wire [3:0] led
);
wire udp_clk, reset, tx_ready_app, tx_ack_app;
wire rx_valid_app;
wire [7:0] rx_data_app;
wire [15:0] rx_length_app, rx_port_app;
dual_board_eth_transport #(.ROLE(0), .UDP_PORT(16'h5002)) u_net (
    .clk_50(clk_50), .sys_rst_n(sys_rst_n),
    .phy1_rgmii_rx_clk(phy1_rgmii_rx_clk),
    .phy1_rgmii_rx_ctl(phy1_rgmii_rx_ctl),
    .phy1_rgmii_rx_data(phy1_rgmii_rx_data),
    .phy1_rgmii_tx_clk(phy1_rgmii_tx_clk),
    .phy1_rgmii_tx_ctl(phy1_rgmii_tx_ctl),
    .phy1_rgmii_tx_data(phy1_rgmii_tx_data),
    .udp_clk(udp_clk), .reset(reset),
    .tx_ready_app(tx_ready_app), .tx_ack_app(tx_ack_app),
    .tx_request_app(1'b0), .tx_valid_app(1'b0),
    .tx_data_app(8'd0), .tx_length_app(16'd0),
    .rx_valid_app(rx_valid_app), .rx_data_app(rx_data_app),
    .rx_length_app(rx_length_app), .rx_port_app(rx_port_app)
);

wire pixel_valid, frame_top_down, frame_start, frame_complete, frame_abort;
wire [23:0] pixel_rgb;
wire [1:0] frame_index;
wire [15:0] good_packets, bad_packets;
image_packet_rx u_image_rx (
    .clk(udp_clk), .rst(reset),
    .rx_valid(rx_valid_app && (rx_port_app == 16'h5002)),
    .rx_data(rx_data_app), .rx_length(rx_length_app),
    .pixel_ready(1'b1), .pixel_valid(pixel_valid),
    .pixel_rgb(pixel_rgb), .frame_index(frame_index),
    .frame_top_down(frame_top_down), .frame_start(frame_start),
    .frame_complete(frame_complete), .frame_abort(frame_abort),
    .good_packets(good_packets), .bad_packets(bad_packets)
);

reg [25:0] blink_count;
reg blink;
reg [9:0] x;
reg [8:0] y;
reg [18:0] pixels_received;
reg pixel_bad;
reg frame_ok;
always @(posedge udp_clk or posedge reset) begin
    if (reset) begin
        blink_count <= 26'd0;
        blink <= 1'b0;
        x <= 10'd0;
        y <= 9'd0;
        pixels_received <= 19'd0;
        pixel_bad <= 1'b0;
        frame_ok <= 1'b0;
    end else begin
        if (blink_count == 26'd62_499_999) begin
            blink_count <= 26'd0;
            blink <= ~blink;
        end else blink_count <= blink_count + 26'd1;
        if (frame_start) begin
            x <= 10'd0;
            y <= 9'd0;
            pixels_received <= 19'd0;
            pixel_bad <= 1'b0;
        end else if (pixel_valid) begin
            if (pixel_rgb != {x[7:0],y[7:0],(x[7:0] ^ y[7:0])})
                pixel_bad <= 1'b1;
            pixels_received <= pixels_received + 19'd1;
            if (x == 10'd639) begin
                x <= 10'd0;
                y <= y + 9'd1;
            end else x <= x + 10'd1;
        end
        if (frame_complete && !pixel_bad &&
            (pixels_received == 19'd307200))
            frame_ok <= 1'b1;
    end
end
assign led = {(bad_packets != 16'd0) || pixel_bad,
              frame_ok, (good_packets != 16'd0), blink};
endmodule
