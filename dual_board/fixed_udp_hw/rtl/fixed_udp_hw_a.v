`timescale 1ns/1ps
// Hardware proof for the new fixed-peer endpoint. No TF/SDRAM/HDMI player.
// IMG4 carries 1042 bytes; A returns real IAK2 12-byte UDP acknowledgements.
module fixed_udp_hw_a (
    input wire clk_50,sys_rst_n,phy1_rgmii_rx_clk,phy1_rgmii_rx_ctl,
    input wire [3:0] phy1_rgmii_rx_data,
    output wire phy1_rgmii_tx_clk,phy1_rgmii_tx_ctl,
    output wire [3:0] phy1_rgmii_tx_data,led
);
wire clk,rst,tx_ready,tx_ack,tx_req,tx_valid,rx_valid;
wire [7:0] tx_data,rx_data;
wire [15:0] tx_length,rx_length,rx_port;
dual_board_eth_transport #(.ROLE(0),.FIXED_PEER(1)) u_net (
    .clk_50(clk_50),.sys_rst_n(sys_rst_n),
    .phy1_rgmii_rx_clk(phy1_rgmii_rx_clk),.phy1_rgmii_rx_ctl(phy1_rgmii_rx_ctl),
    .phy1_rgmii_rx_data(phy1_rgmii_rx_data),.phy1_rgmii_tx_clk(phy1_rgmii_tx_clk),
    .phy1_rgmii_tx_ctl(phy1_rgmii_tx_ctl),.phy1_rgmii_tx_data(phy1_rgmii_tx_data),
    .udp_clk(clk),.reset(rst),.tx_ready_app(tx_ready),.tx_ack_app(tx_ack),
    .tx_request_app(tx_req),.tx_valid_app(tx_valid),.tx_data_app(tx_data),.tx_length_app(tx_length),
    .rx_valid_app(rx_valid),.rx_data_app(rx_data),.rx_length_app(rx_length),.rx_port_app(rx_port),
    .media_video_clk(),.media_5x_clk(),.media_clock_ready());
wire pv,fs,fc,fa,packet_done,duplicate;
wire [23:0] rgb;
wire [7:0] tag;
wire [31:0] token,resolution;
wire [15:0] sequence_no,good,bad;
// Register the application descriptor and byte together: the endpoint BRAM
// output must not feed the full image header/CRC decode in the same 8ns cycle.
reg rx_valid_q;
reg [7:0] rx_data_q;
reg [15:0] rx_length_q,rx_port_q;
always @(posedge clk or posedge rst)begin
    if(rst)begin rx_valid_q<=0;rx_data_q<=0;rx_length_q<=0;rx_port_q<=0;end
    else begin rx_valid_q<=rx_valid;rx_data_q<=rx_data;rx_length_q<=rx_length;rx_port_q<=rx_port;end
end
image_packet_rx #(.RELIABLE(1),.UI_TAG(1),.RESOLUTION(1)) rx (
    .clk(clk),.rst(rst),.generation(16'd0),
    .rx_valid(rx_valid_q && rx_port_q==16'h5002),.rx_data(rx_data_q),.rx_length(rx_length_q),
    .pixel_ready(1'b1),.pixel_valid(pv),.pixel_rgb(rgb),.pixel_tag(tag),
    .frame_index(),.frame_top_down(),.frame_resolution(resolution),
    .frame_start(fs),.frame_complete(fc),.frame_abort(fa),.good_packets(good),.bad_packets(bad),
    .packet_done(packet_done),.packet_duplicate(duplicate),.packet_token(token),.packet_sequence(sequence_no));
image_receipt_tx receipt (
    .clk(clk),.rst(rst),.event_valid(packet_done),.event_token(token),.event_sequence(sequence_no),
    .udp_ready(tx_ready),.udp_ack(tx_ack),.udp_request(tx_req),.udp_valid(tx_valid),
    .udp_data(tx_data),.udp_length(tx_length));
reg [25:0] heartbeat_count;
reg heartbeat,frame_ok,error_latched,pixel_bad_q;
reg [9:0] x;
reg [8:0] y;
reg [18:0] count;
always @(posedge clk or posedge rst)begin
    if(rst)begin
        heartbeat_count<=0;heartbeat<=0;frame_ok<=0;error_latched<=0;pixel_bad_q<=0;x<=0;y<=0;count<=0;
    end else begin
        if(heartbeat_count==26'd62499999)begin heartbeat_count<=0;heartbeat<=~heartbeat;end
        else heartbeat_count<=heartbeat_count+1'b1;
        pixel_bad_q<=pv && (rgb!={x[7:0],y[7:0],(x[7:0]^y[7:0])} || tag!=(x[7:0]^8'ha5));
        if(pixel_bad_q)error_latched<=1;
        if(fs)begin
            x<=0;y<=0;count<=0;
            if(resolution!=32'h028001e0)error_latched<=1;
        end else if(pv)begin
            count<=count+1'b1;
            if(x==639)begin x<=0;y<=y+1'b1;end else x<=x+1'b1;
        end
        if(fa || bad!=0)error_latched<=1;
        if(fc)begin
            if(count==307200 && !error_latched && !pixel_bad_q)frame_ok<=1;
            else error_latched<=1;
        end
    end
end
// Logical status, not assumed LED polarity: LED0 heartbeat, LED1 good packet,
// LED2 entire frame RGB+tag checked, LED3 latched error. K1 clears status.
assign led={error_latched,frame_ok,(good!=0),heartbeat};
endmodule
