`timescale 1ns/1ps
// Area probe: star sky renderer + engine + CTL4 TX/RX, isolated.
module star_area_top(input clk, uclk, rst, vs, de, input [23:0] rgb, output [23:0] o,
  output req, val, output [7:0] d, input rdy, ack, rxv, input [7:0] rxd);
wire [14:0] nq, fq; wire [7:0] tw, env; wire mon; wire signed [15:0] mx; wire [12:0] my;
star_motion_engine eng(.clk(uclk),.rst(rst),.near_q4(nq),.far_q4(fq),.twinkle(tw),.meteor_on(mon),
  .meteor_x_q4(mx),.meteor_y_q4(my),.meteor_env(env));
wire [15:0] len; wire [75:0] rb; wire upd; wire [7:0] st;
media_control_star_tx tx(.clk(uclk),.rst(rst),.settings(8'h38),.star_bundle({nq,fq,tw,mon,mx,my,env}),
  .udp_ready(rdy),.udp_ack(ack),.udp_request(req),.udp_valid(val),.udp_data(d),.udp_length(len));
media_control_star_rx rx(.clk(uclk),.rst(rst),.rx_valid(rxv),.rx_data(rxd),.rx_length(16'd21),
  .update_valid(upd),.settings(st),.star_bundle(rb));
reg [75:0] vb; always @(posedge clk) vb<=rb;
video_star_sky #(.VIEW_X(640)) sky(.I_clk(clk),.I_rst(rst),.I_enable(1'b1),.I_vs(vs),.I_de(de),.I_rgb(rgb),
  .I_near_q4(vb[75:61]),.I_far_q4(vb[60:46]),.I_twinkle(vb[45:38]),.I_meteor_on(vb[37]),
  .I_meteor_x_q4(vb[36:21]),.I_meteor_y_q4(vb[20:8]),.I_meteor_env(vb[7:0]),.O_rgb(o));
endmodule
