module star_area_top(input clk, uclk, rst, vs, de, input [23:0] rgb, output [23:0] o,
  input rxv, input [7:0] rxd);
wire [75:0] rb, vb; wire rt, upd; wire [7:0] st;
media_control_star_rx rx(.clk(uclk),.rst(rst),.rx_valid(rxv),.rx_data(rxd),.rx_length(16'd21),
  .star_bundle(rb),.bundle_toggle(rt));
star_bundle_cdc cdc(.dst_clk(clk),.dst_rst(rst),.src_toggle(rt),.src_data(rb),.dst_data(vb));
video_star_sky #(.VIEW_X(0)) sky(.I_clk(clk),.I_rst(rst),.I_enable(1'b1),.I_vs(vs),.I_de(de),.I_rgb(rgb),
  .I_near_q4(vb[75:61]),.I_far_q4(vb[60:46]),.I_twinkle(vb[45:38]),.I_meteor_on(vb[37]),
  .I_meteor_x_q4(vb[36:21]),.I_meteor_y_q4(vb[20:8]),.I_meteor_env(vb[7:0]),.O_rgb(o));
endmodule
