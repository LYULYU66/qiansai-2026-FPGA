`timescale 1ns/1ps
// Test-only transport shim: actual fixed IPv4/UDP endpoints, crossed MAC
// local-link wires. Does NOT simulate native MAC/PHY, electrical pins or DDR.
module dual_board_eth_transport #(
    parameter integer ROLE=0,FIXED_PEER=0,
    parameter [15:0] UDP_PORT=16'h5002
) (
    input wire clk_50,sys_rst_n,phy1_rgmii_rx_clk,phy1_rgmii_rx_ctl,
    input wire [3:0] phy1_rgmii_rx_data,
    output wire phy1_rgmii_tx_clk,phy1_rgmii_tx_ctl,
    output wire [3:0] phy1_rgmii_tx_data,
    output wire udp_clk,reset,tx_ready_app,tx_ack_app,
    input wire tx_request_app,tx_valid_app,
    input wire [7:0] tx_data_app,
    input wire [15:0] tx_length_app,
    output wire rx_valid_app,
    output wire [7:0] rx_data_app,
    output wire [15:0] rx_length_app,rx_port_app,
    output wire media_video_clk,media_5x_clk,media_clock_ready
);
wire [7:0] sim_rx_data,sim_tx_data;
wire sim_rx_valid,sim_rx_sof_n,sim_rx_eof_n,sim_rx_ready_n;
wire sim_tx_valid_n,sim_tx_sof_n,sim_tx_eof_n,sim_tx_ready_n;
assign udp_clk=clk_50;assign reset=!sys_rst_n;
assign media_video_clk=clk_50;assign media_5x_clk=clk_50;assign media_clock_ready=sys_rst_n;
assign phy1_rgmii_tx_clk=clk_50;assign phy1_rgmii_tx_ctl=0;assign phy1_rgmii_tx_data=0;
initial if(!FIXED_PEER)$fatal(1,"hardware top did not choose fixed-peer network");
fixed_peer_udp #(
    .LOCAL_IP(ROLE==0 ? 32'hc0a80a0b:32'hc0a80a0c),.PEER_IP(ROLE==0 ? 32'hc0a80a0c:32'hc0a80a0b),
    .LOCAL_MAC(ROLE==0 ? 48'h02000000000b:48'h02000000000c),.PEER_MAC(ROLE==0 ? 48'h02000000000c:48'h02000000000b),
    .UDP_PORT(UDP_PORT),.MAX_TX_PAYLOAD(ROLE==0 ? 18:1042),.MAX_RX_PAYLOAD(ROLE==0 ? 1042:18)
) endpoint (
    .clk(clk_50),.rst(reset),.app_tx_request(tx_request_app),.app_tx_valid(tx_valid_app),
    .app_tx_data(tx_data_app),.app_tx_length(tx_length_app),.app_tx_ready(tx_ready_app),.app_tx_ack(tx_ack_app),
    .app_rx_valid(rx_valid_app),.app_rx_data(rx_data_app),.app_rx_length(rx_length_app),.app_rx_port(rx_port_app),
    .mac_rx_valid(sim_rx_valid),.mac_rx_data(sim_rx_data),.mac_rx_sof_n(sim_rx_sof_n),.mac_rx_eof_n(sim_rx_eof_n),
    .mac_rx_ready_n(sim_rx_ready_n),.mac_tx_ready_n(sim_tx_ready_n),.mac_tx_valid_n(sim_tx_valid_n),
    .mac_tx_data(sim_tx_data),.mac_tx_sof_n(sim_tx_sof_n),.mac_tx_eof_n(sim_tx_eof_n));
endmodule

module tb_fixed_udp_hw;
reg clk=0;always #4 clk=~clk;
reg reset_n=0,key_n=1,drop_first_ack=1;
wire [3:0] a_led,b_led;
fixed_udp_hw_a a (.clk_50(clk),.sys_rst_n(reset_n),.phy1_rgmii_rx_clk(1'b0),
    .phy1_rgmii_rx_ctl(1'b0),.phy1_rgmii_rx_data(4'd0),.phy1_rgmii_tx_clk(),
    .phy1_rgmii_tx_ctl(),.phy1_rgmii_tx_data(),.led(a_led));
fixed_udp_hw_b b (.clk_50(clk),.sys_rst_n(reset_n),.key_send_n(key_n),.phy1_rgmii_rx_clk(1'b0),
    .phy1_rgmii_rx_ctl(1'b0),.phy1_rgmii_rx_data(4'd0),.phy1_rgmii_tx_clk(),
    .phy1_rgmii_tx_ctl(),.phy1_rgmii_tx_data(),.led(b_led));
defparam b.tx.RETRY_CYCLES=4000;
assign a.u_net.sim_rx_valid=!b.u_net.sim_tx_valid_n;
assign a.u_net.sim_rx_data=b.u_net.sim_tx_data;
assign a.u_net.sim_rx_sof_n=b.u_net.sim_tx_sof_n;
assign a.u_net.sim_rx_eof_n=b.u_net.sim_tx_eof_n;
assign b.u_net.sim_tx_ready_n=a.u_net.sim_rx_ready_n;
assign b.u_net.sim_rx_valid=!a.u_net.sim_tx_valid_n && !drop_first_ack;
assign b.u_net.sim_rx_data=a.u_net.sim_tx_data;
assign b.u_net.sim_rx_sof_n=a.u_net.sim_tx_sof_n;
assign b.u_net.sim_rx_eof_n=a.u_net.sim_tx_eof_n;
assign a.u_net.sim_tx_ready_n=b.u_net.sim_rx_ready_n;
integer a_packets=0,b_acks=0,completed=0,expected_packets=1201;
always @(negedge clk)if(reset_n && !a.u_net.sim_tx_valid_n && !a.u_net.sim_tx_eof_n)
    drop_first_ack<=0;
always @(posedge clk)if(reset_n)begin
    if(a.packet_done)a_packets=a_packets+1;
    if(b.receipt_valid)b_acks=b_acks+1;
    if(b.frame_sent)completed=completed+1;
    if(a.error_latched)$fatal(1,"hardware top RGB/tag/size/order diagnostic failed");
end
task send_once;
begin
    @(negedge clk);key_n=0;
    wait(b.active);@(negedge clk);key_n=1;
    wait(b.sent_latched);repeat(16)@(negedge clk);
    if(a.count!=307200 || a.good!=1200 || a_packets!=expected_packets || b_acks!=1200 || completed!=1 ||
       a_led[3:1]!=3'b011 || b_led[3:1]!=3'b111)
        $fatal(1,"hardware LED/full-frame/ACK check failed A=%b B=%b packets=%0d ACK=%0d complete=%0d",a_led,b_led,a_packets,b_acks,completed);
end
endtask
initial begin
    repeat(8)@(negedge clk);reset_n=1;
    repeat(100)@(negedge clk);
    if(a_led[3:1]!=0 || b_led[3:1]!=0 || b.active)$fatal(1,"test starts without send key");
    send_once;
    @(negedge clk);reset_n=0;repeat(8)@(negedge clk);
    if(a_led!=0 || b_led!=0)$fatal(1,"K1 reset did not clear diagnostic LEDs");
    a_packets=0;b_acks=0;completed=0;expected_packets=1200;reset_n=1;
    send_once;
    $display("PASS fixed UDP hardware tops: actual A/B checker and key source, two 1200-packet IMG4 RGB/tag frames, lost-ACK retry, 12-byte reverse ACK, LED meaning and reset");
    $finish;
end
initial begin #100000000;$fatal(1,"hardware-top full-frame timeout");end
endmodule
