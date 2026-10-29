`timescale 1ns/1ps
// A -> B CTL4 through the production path: star engine -> CTL4 TX ->
// 4-channel scheduler (with a busy higher-priority 18-byte receipt stream and
// a 10-byte lease stream competing) -> A fixed_peer_udp -> B fixed_peer_udp ->
// B's CTL4 filter (length 16) -> media_control_star_rx. Checks every
// accepted bundle equals a sent one, the hazard bit follows A, and nearly all
// CTL4 packets get through.
module tb_a2b_ctl4;
reg clk=0; always #8 clk=~clk;          // 62.5 MHz
reg rst=1;
wire [75:0] eb; wire et;
star_motion_engine #(.TICK_BITS(5)) eng(.clk(clk),.rst(rst),.bundle(eb),.bundle_toggle(et));
reg hazard=0;
wire s_req,s_val,s_rdy,s_ack; wire [7:0] s_d; wire [15:0] s_len;
media_control_star_tx #(.UPDATE_CYCLES(400)) stx(.clk(clk),.rst(rst),.star_bundle(eb),.hazard(hazard),
    .udp_ready(s_rdy),.udp_ack(s_ack),.udp_request(s_req),.udp_valid(s_val),.udp_data(s_d),.udp_length(s_len));
// Competing producers: 18-byte "receipt" every 150 clocks, 10-byte "lease" every 900.
reg [9:0] rt, lt; reg r_pend, l_pend; reg [4:0] r_i, l_i; reg r_on, l_on;
wire r_rdy, r_ack, l_rdy, l_ack;
always @(posedge clk) if(rst) begin rt<=0; lt<=0; r_pend<=0; l_pend<=0; r_on<=0; l_on<=0; r_i<=0; l_i<=0; end
else begin
    rt<=rt==149 ? 0 : rt+1; lt<=lt==899 ? 0 : lt+1;
    if(rt==0 && !r_pend && !r_on) r_pend<=1;
    if(lt==0 && !l_pend && !l_on) l_pend<=1;
    if(r_pend && r_ack) begin r_pend<=0; r_on<=1; r_i<=0; end
    if(r_on) begin r_i<=r_i+1; if(r_i==17) r_on<=0; end
    if(l_pend && l_ack) begin l_pend<=0; l_on<=1; l_i<=0; end
    if(l_on) begin l_i<=l_i+1; if(l_i==9) l_on<=0; end
end
wire unused_ack;
wire n_req,n_val; wire [7:0] n_d; wire [15:0] n_len; wire n_rdy,n_ack;
media_udp_scheduler #(.CHANNELS(4),.MAX_LENGTH(18)) sch(.clk(clk),.rst(rst),.net_ready(n_rdy),.net_ack(n_ack),
    .net_request(n_req),.net_valid(n_val),.net_data(n_d),.net_length(n_len),
    .c_request({l_pend,r_pend,1'b0,s_req}),.c_valid({l_on,r_on,1'b0,s_val}),
    .c_data({8'h4C,8'h41,8'h00,s_d}),.c_length({16'd10,16'd18,16'd0,s_len}),
    .c_ready(),.c_ack({l_ack,r_ack,unused_ack,s_ack}));
assign s_rdy=sch.c_ready[0]; assign r_rdy=sch.c_ready[2]; assign l_rdy=sch.c_ready[3];
wire b_valid; wire [7:0] b_data; wire [15:0] b_len;
fixed_udp_test_link #(.SOURCE_IP(32'hc0a80a0b),.DEST_IP(32'hc0a80a0c),
    .SOURCE_MAC(48'h02000000000b),.DEST_MAC(48'h02000000000c),.MAX_PAYLOAD(1042)) link (
    .clk(clk),.tx_rst(rst),.rx_rst(rst),.tx_data(n_d),.tx_length(n_len),.tx_request(n_req),.tx_valid(n_val),
    .tx_ready(n_rdy),.tx_ack(n_ack),.rx_valid(b_valid),.rx_data(b_data),.rx_length(b_len));
wire [75:0] rb; wire rt_tog, rhz;
media_control_star_rx srx(.clk(clk),.rst(rst),.rx_valid(b_valid && b_len==16),.rx_data(b_data),.rx_length(b_len),
    .star_bundle(rb),.bundle_toggle(rt_tog),.hazard(rhz));
// bookkeeping
reg [75:0] sent [0:4095]; integer ns=0, na=0, errs=0, k, hz_ok=0, other=0; reg last_t=0; reg found;
reg hz_snap [0:4095];
always @(posedge clk) if(!rst && stx.state==1 && s_ack) begin sent[ns%4096]=eb; ns=ns+1; end
always @(posedge clk) if(!rst && b_valid && !srx.previous_valid && b_len!=16) other=other+1;
always @(posedge clk) if(!rst) begin
    if(rt_tog!==last_t) begin
        last_t=rt_tog; na=na+1; found=0;
        for(k=0;k<16;k=k+1) if(ns-1-k>=0 && sent[(ns-1-k)%4096]===rb) found=1;
        if(!found) begin errs=errs+1; if(errs<5) $display("ERR bundle %h not among last sent", rb); end
    end
end
initial begin
    #200 rst=0;
    #400000 hazard=1;
    #100000 if(rhz!==1) begin errs=errs+1; $display("ERR hazard did not reach B"); end
    #300000 hazard=0;
    #100000 if(rhz!==0) begin errs=errs+1; $display("ERR hazard did not clear on B"); end
    #200000;
    $display("CTL4 sent=%0d accepted=%0d other_packets=%0d errors=%0d", ns, na, other, errs);
    if(errs==0 && na*10>=ns*9 && other>100) $display("PASS A->B CTL4 with competing traffic and hazard flag"); else $display("FAIL");
    $finish;
end
endmodule
