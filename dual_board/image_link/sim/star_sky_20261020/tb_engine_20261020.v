`timescale 1ns/1ps
// B engine -> CTL4 TX -> byte transport (every 7th packet corrupted) ->
// A CTL4 RX -> toggle CDC into a 25 MHz video domain. Checks: the sky phase
// never moves backwards; every bundle that reaches the video domain is one
// that B actually sent; corrupted packets never update it; logs statistics.
module tb_engine_20261020;
localparam integer TB=6;
reg clk=0; always #4 clk=~clk;          // udp_clk 125 MHz
reg vclk=0; always #20 vclk=~vclk;      // video 25 MHz
reg rst=1;
wire [75:0] eb; wire et;
star_motion_engine #(.TICK_BITS(TB)) eng(.clk(clk),.rst(rst),.bundle(eb),.bundle_toggle(et));
wire req,val; wire [7:0] d; wire [15:0] len; reg ack=0;
media_control_star_tx #(.UPDATE_CYCLES(1500)) tx(.clk(clk),.rst(rst),.star_bundle(eb),
 .udp_ready(1'b1),.udp_ack(ack),.udp_request(req),.udp_valid(val),.udp_data(d),.udp_length(len));
reg [7:0] pd [0:15]; reg [15:0] pv; integer k, sent=0, bytei=0;
reg corrupt=0;
always @(posedge clk) begin
  ack<=req && !ack; pv<={pv[14:0],val};
  pd[0]<=(val && corrupt && bytei==6) ? d^8'h10 : d;
  for(k=1;k<16;k=k+1) pd[k]<=pd[k-1];
  if(val) bytei<=bytei+1; else bytei<=0;
  if(ack) begin sent=sent+1; corrupt<=(sent%7==6); end
end
wire [75:0] rb; wire rt;
media_control_star_rx rx(.clk(clk),.rst(rst),.rx_valid(pv[15]),.rx_data(pd[15]),.rx_length(len),
 .star_bundle(rb),.bundle_toggle(rt));
wire [75:0] vb;
star_bundle_cdc cdc(.dst_clk(vclk),.dst_rst(rst),.src_toggle(rt),.src_data(rb),.dst_data(vb));
// record every bundle B latched into a packet; video-side values must be among them
reg [75:0] hist [0:255]; reg [7:0] hp=0; integer h, found, vchanges=0, rxok=0;
reg [75:0] vb_d;
always @(posedge clk) if(tx.state==1 && ack) begin hist[hp]<=eb; hp<=hp+1; end
always @(posedge clk) if(rt!==rx.bundle_toggle) ; 
reg rt_d=0; always @(posedge clk) begin rt_d<=rt; if(rt!=rt_d) rxok=rxok+1; end
always @(posedge vclk) if(!rst) begin
  vb_d<=vb;
  if(vb!==vb_d && vchanges>0) begin
    found=0; for(h=0;h<256;h=h+1) if(hist[h]===vb) found=1;
    if(!found) $fatal(1,"video bundle %h was never sent by B",vb);
  end
  if(vb!==vb_d) vchanges=vchanges+1;
end
integer fd, ticks=0, back=0;
reg [31:0] prevp; reg havep=0;
always @(posedge clk) if(!rst) begin
  if(eng.tick) begin
    ticks=ticks+1;
    if(havep && eng.phase_q20<prevp && !(prevp>32'h9F00_0000 && eng.phase_q20<32'h0100_0000)) back=back+1;
    prevp=eng.phase_q20; havep=1;
    if(ticks%256==0) $fwrite(fd,"%0d %0d %0d %0d %0d %0d %0d\n",ticks,eng.phase_q20,eng.speed,eb[37],eb[36:21],eb[20:8],eb[7:0]);
    if(ticks==1048576) begin
      $fclose(fd);
      if(back) $fatal(1,"sky moved backwards %0d times",back);
      if(rxok*7 < sent*5) $fatal(1,"too few packets accepted: %0d of %0d",rxok,sent);
      if(rxok > sent - sent/7 + 1) $fatal(1,"corrupted packets accepted: %0d of %0d",rxok,sent);
      $display("PASS engine/CTL4: %0d ticks, %0d sent, %0d accepted (corrupted rejected), %0d video updates, phase monotonic",
               ticks,sent,rxok,vchanges);
      $finish;
    end
  end
end
initial begin fd=$fopen("star_sky_20261020/engine_log.txt","w"); repeat(4)@(posedge clk); rst=0; end
endmodule
