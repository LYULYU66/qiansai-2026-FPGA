`timescale 1ns/1ps
// B engine -> CTL4 TX -> byte stream -> CTL4 RX -> A follower engine.
// The follower must match the master once synced, and stay locked.
module tb_ctl4_20261020;
reg clk=0; always #4 clk=~clk;
reg rst=1;
wire [31:0] tm, pm; wire [5:0] dm;
star_motion_engine #(.TICK_BITS(6)) master(.clk(clk),.rst(rst),.load(1'b0),.load_time(32'd0),.load_phase(32'd0),.load_div(16'd0),
 .time_ticks(tm),.phase_q20(pm),.divider(dm),.near_q4(),.far_q4(),.twinkle(),.meteor_on(),.meteor_x_q4(),.meteor_y_q4(),.meteor_env());
wire req, val; wire [7:0] d; wire [15:0] len; reg ready=1, ack=0;
media_control_star_tx #(.UPDATE_CYCLES(3000)) tx(.clk(clk),.rst(rst),.settings(8'h38),.star_time(tm),.star_phase(pm),
 .star_div({10'd0,dm}),.udp_ready(ready),.udp_ack(ack),.udp_request(req),.udp_valid(val),.udp_data(d),.udp_length(len));
// minimal transport: ack the request, forward bytes after a short delay
reg [7:0] pipe_d [0:15]; reg [15:0] pipe_v; integer k;
always @(posedge clk) begin ack<=req && !ack; pipe_v<={pipe_v[14:0],val};
  pipe_d[0]<=d; for(k=1;k<16;k=k+1) pipe_d[k]<=pipe_d[k-1]; end
wire ld, upd; wire [31:0] lt, lp; wire [15:0] lv; wire [7:0] st;
media_control_star_rx #(.REBASE_CYCLES(100000)) rx(.clk(clk),.rst(rst),.rx_valid(pipe_v[15]),.rx_data(pipe_d[15]),.rx_length(len),
 .update_valid(upd),.settings(st),.load(ld),.load_time(lt),.load_phase(lp),.load_div(lv));
wire [31:0] tf, pf; wire [5:0] df;
star_motion_engine #(.TICK_BITS(6)) follower(.clk(clk),.rst(rst),.load(ld),.load_time(lt),.load_phase(lp),.load_div(lv),
 .time_ticks(tf),.phase_q20(pf),.divider(df),.near_q4(),.far_q4(),.twinkle(),.meteor_on(),.meteor_x_q4(),.meteor_y_q4(),.meteor_env());
integer loads=0, ticks=0, lagmax=0, lag;
always @(posedge clk) if(!rst) begin
  if(ld) loads=loads+1;
  if(master.tick) ticks=ticks+1;
  if(loads>0) begin
    lag=(tm-tf)*64+(dm-df);
    if(lag<0) lag=-lag;
    if(lag>lagmax) lagmax=lag;
  end
  if(ticks==20000) begin
    if(loads<20) $fatal(1,"too few CTL4 loads: %0d",loads);
    if(lagmax>60) $fatal(1,"follower lag %0d clocks",lagmax);
    $display("PASS CTL4 sync: %0d packets accepted, follower time lag <= %0d clocks (packet transit)",loads,lagmax);
    $finish;
  end
end
initial begin repeat(4)@(posedge clk); rst=0; end
endmodule
