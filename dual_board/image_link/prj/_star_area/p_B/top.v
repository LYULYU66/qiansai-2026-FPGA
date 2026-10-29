module star_area_top(input clk, uclk, rst, vs, de, input [23:0] rgb, output [23:0] o,
  output req, val, output [7:0] d, input rdy, ack);
wire [75:0] eb, vb; wire et; wire [15:0] len;
star_motion_engine eng(.clk(uclk),.rst(rst),.bundle(eb),.bundle_toggle(et));
media_control_star_tx tx(.clk(uclk),.rst(rst),.star_bundle(eb),
  .udp_ready(rdy),.udp_ack(ack),.udp_request(req),.udp_valid(val),.udp_data(d),.udp_length(len));
star_bundle_cdc cdc(.dst_clk(clk),.dst_rst(rst),.src_toggle(et),.src_data(eb),.dst_data(vb));
video_star_sky #(.VIEW_X(640)) sky(.I_clk(clk),.I_rst(rst),.I_enable(1'b1),.I_vs(vs),.I_de(de),.I_rgb(rgb),
  .I_near_q4(vb[75:61]),.I_far_q4(vb[60:46]),.I_twinkle(vb[45:38]),.I_meteor_on(vb[37]),
  .I_meteor_x_q4(vb[36:21]),.I_meteor_y_q4(vb[20:8]),.I_meteor_env(vb[7:0]),.O_rgb(o));
endmodule
