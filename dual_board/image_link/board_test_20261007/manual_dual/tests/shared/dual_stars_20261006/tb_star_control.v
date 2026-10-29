`timescale 1ns/1ps
module tb_star_control;
reg clk=0,vclk=0;always #4 clk=~clk;always #20 vclk=~vclk;
reg rst=1,vs=0,drop=0,ready=1;
wire [15:0] master;
dual_star_motion_clock #(.TICK_CYCLES(2)) time_master(.clk(clk),.rst(rst),.phase_q4(master));
wire req,valid;wire [7:0] data;wire [15:0] length;
reg ack=0;reg [7:0] settings=8'h38;
media_control_tx #(.STAR_SYNC(1),.UPDATE_CYCLES(80)) tx(.clk(clk),.rst(rst),.settings(settings),
 .star_phase(master),.udp_ready(ready),.udp_ack(ack),.udp_request(req),.udp_valid(valid),.udp_data(data),.udp_length(length));
always @(posedge clk)ack<=!rst && req && !ack;
reg corrupt=0;wire [7:0] received_byte=data^((corrupt && tx.index==13) ? 8'd1 : 8'd0);
wire update;wire [7:0] received;wire [15:0] remote;
media_control_rx #(.STAR_SYNC(1),.REBASE_CYCLES(1000000)) rx(.clk(clk),.rst(rst),
 .rx_valid(valid && !drop),.rx_data(received_byte),.rx_length(length),.update_valid(update),.settings(received),.star_phase(remote));
wire [15:0] applied_a,applied_b;
audio_visual_cdc #(.WIDTH(16)) a(.udp_clk(clk),.video_clk(vclk),.rst(rst),.frame_vs(vs),
 .update_valid(1'b0),.publish_enable(1'b1),.visual_state(remote),.frame_state(applied_a),.capture_valid());
audio_visual_cdc #(.WIDTH(16)) b(.udp_clk(clk),.video_clk(vclk),.rst(rst),.frame_vs(vs),
 .update_valid(1'b0),.publish_enable(1'b1),.visual_state(master),.frame_state(applied_b),.capture_valid());
integer packets=0,cycles=0,frames=0,wraps=0;
reg [15:0] old_a=0,old_b=0,old_master=0,last_snapshot=0;
always @(posedge clk)begin
 if(!rst)begin
  cycles=cycles+1;
  if(valid && tx.index==0)last_snapshot=tx.phase_snapshot;
  if(valid && length!=14)$fatal(1,"CTL3 packet length");
  if(update)begin
   packets=packets+1;
   if(remote!=last_snapshot)$fatal(1,"phase and settings not packet-atomic");
   if(received[3:0]>8)$fatal(1,"invalid controls");
  end
  if(old_master==20479 && master==0)wraps=wraps+1;
  old_master=master;
 end
end
always @(negedge vclk)if(!rst)begin frames=frames+1;vs=frames%30==0;end
always @(posedge vclk)begin
 #1;if(!rst && (old_a!=applied_a || old_b!=applied_b) && !vs)$fatal(1,"phase changed outside VS");
 old_a=applied_a;old_b=applied_b;
end
integer n,saved_packets;reg [15:0] saved_phase;
initial begin
 repeat(8)@(negedge clk);rst=0;
 repeat(1000)@(negedge clk);
 if(packets<5 || applied_a==0)$fatal(1,"phase not delivered without PCM");
 // Stop the transport. The time source must continue, independently of it.
 drop=1;saved_phase=remote;saved_packets=packets;
 repeat(500)@(negedge clk);
 if(remote!=saved_phase || packets!=saved_packets || master==saved_phase)$fatal(1,"loss hold/independent time");
 drop=0;repeat(400)@(negedge clk);
 if(packets<=saved_packets || remote==saved_phase)$fatal(1,"phase not recovered after loss");
 // Wait for a packet boundary, then invalidate only the CRC (phase must hold).
 wait(!valid);@(negedge clk);corrupt=1;saved_packets=packets;saved_phase=remote;
 repeat(500)@(negedge clk);
 if(packets!=saved_packets || remote!=saved_phase)$fatal(1,"corrupted phase applied");
 corrupt=0;settings=8'hd0;repeat(500)@(negedge clk);
 if(received!=8'hd0 || remote==saved_phase)$fatal(1,"mute stopped phase or changed controls");
 repeat(43000)@(negedge clk);
 if(wraps!=1)$fatal(1,"motion modulus incorrect, wraps=%0d",wraps);
 $display("PASS star control: CTL3 atomic phase/controls, CRC corruption, packet loss/recovery, mute and PCM independence, 50/125/25-style CDC frame boundaries, 1280-pixel wrap");
 $finish;
end
initial begin #2000000;$fatal(1,"star control timeout");end
endmodule
