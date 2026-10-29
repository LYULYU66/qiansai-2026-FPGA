module probe_top(input uclk, vclk, rst, input [75:0] d, input t, output [75:0] q);
star_bundle_cdc u_control_snapshot(.dst_clk(vclk),.dst_rst(rst),.src_toggle(t),.src_data(d),.dst_data(q));
endmodule
