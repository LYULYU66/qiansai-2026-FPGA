`timescale 1ns/1ps
// Actual 115200 baud UART -> 50/125/25 MHz CDC -> packet-locked mux -> A.
module tb_media_control;
reg pc_clk=0,udp_clk=0,video_clk=0;
always #10 pc_clk=~pc_clk;
always #4 udp_clk=~udp_clk;
always #20 video_clk=~video_clk;
reg rst=1,serial_rx=1,blackout=0,vs=0;
wire serial_tx;
wire [3:0] volume;
wire [1:0] brightness,contrast;
wire [7:0] desired={contrast,brightness,volume};
wire [7:0] source_state,received_state,applied;
wire uart_error,rx_update;
integer received_updates=0,cycles=0,video_cycles=0;
uart_audio_control pc (.I_clk(pc_clk),.I_rst_n(~rst),.I_uart_rx(serial_rx),.O_uart_tx(serial_tx),
    .O_volume_level(volume),.O_brightness_level(brightness),.O_contrast_level(contrast),.O_rx_error(uart_error));
audio_visual_cdc #(.WIDTH(8),.FRAME_BOUNDARY(0),.RESET_STATE(8'h38)) source_cdc (
    .udp_clk(pc_clk),.video_clk(udp_clk),.rst(rst),.frame_vs(1'b0),.update_valid(1'b0),
    .publish_enable(1'b1),.visual_state(desired),.frame_state(source_state),.capture_valid());
wire req,valid,ready,ack;
wire [7:0] data;
wire [15:0] length;
media_control_tx #(.UPDATE_CYCLES(2000)) tx (.clk(udp_clk),.rst(rst),.settings(source_state),
    .udp_ready(ready),.udp_ack(ack),.udp_request(req),.udp_valid(valid),.udp_data(data),.udp_length(length));
// A long image-payload producer stresses contention without a packet FIFO.
reg image_request=0,image_valid=0;
reg [10:0] image_bytes=0;
wire image_ready,image_ack,net_req,net_valid;
wire [7:0] net_data;
wire [15:0] net_length;
reg net_ack=0;
wire net_ready=cycles%1600<1400;
media_udp_arbiter mux (.clk(udp_clk),.rst(rst),.net_ready(net_ready),.net_ack(net_ack),
    .net_request(net_req),.net_valid(net_valid),.net_data(net_data),.net_length(net_length),
    .c0_request(image_request),.c0_valid(image_valid),.c0_data(8'h55),.c0_length(16'd1042),
    .c0_ready(image_ready),.c0_ack(image_ack),
    .c1_request(req),.c1_valid(valid),.c1_data(data),.c1_length(length),.c1_ready(ready),.c1_ack(ack));
always @(posedge udp_clk) begin
    if(rst) begin cycles<=0;net_ack<=0;image_request<=0;image_valid<=0;image_bytes<=0;end
    else begin
        cycles<=cycles+1;net_ack<=net_req && net_ready && !net_ack;
        if(image_valid) begin
            if(image_bytes==1041) begin image_valid<=0;image_bytes<=0;end
            else image_bytes<=image_bytes+1'b1;
        end else if(image_request) begin
            if(image_ack) begin image_request<=0;image_valid<=1;end
        end else if(image_ready) image_request<=1;
        if(rx_update) received_updates<=received_updates+1;
    end
end
media_control_rx rx (.clk(udp_clk),.rst(rst),.rx_valid(net_valid && net_length==12 && !blackout),
    .rx_data(net_data),.rx_length(net_length),.update_valid(rx_update),.settings(received_state));
audio_visual_cdc #(.WIDTH(8),.RESET_STATE(8'h38)) destination (
    .udp_clk(udp_clk),.video_clk(video_clk),.rst(rst),.frame_vs(vs),.update_valid(1'b0),
    .publish_enable(1'b1),.visual_state(received_state),.frame_state(applied),.capture_valid());
always @(negedge video_clk) begin
    if(rst) begin video_cycles=0;vs=0;end
    else begin video_cycles=video_cycles+1;vs=video_cycles%500==0;end
end
reg [7:0] previous_applied=8'h38;
always @(posedge video_clk) begin
    #1;
    if(!rst && applied!==previous_applied && !vs) $fatal(1,"control changes outside VS");
    previous_applied=applied;
end
// Decode real UART replies, not internal response registers.
wire reply_valid,reply_error;
wire [7:0] reply_data;
string reply="";
uart_rx reply_rx (.clk(pc_clk),.rst_n(~rst),.rx(serial_tx),.data(reply_data),.valid(reply_valid),.framing_error(reply_error));
always @(posedge pc_clk) if(!rst) begin
    if(reply_error) $fatal(1,"UART reply framing");
    if(reply_valid) reply={reply,reply_data};
end
task send_byte(input [7:0] b);
integer i;
begin
    serial_rx=0;repeat(434) @(negedge pc_clk);
    for(i=0;i<8;i=i+1) begin serial_rx=b[i];repeat(434) @(negedge pc_clk);end
    serial_rx=1;repeat(434) @(negedge pc_clk);
end
endtask
task command(input string s,input string expected_reply,input [7:0] expected_state);
integer i;
begin
    reply="";
    for(i=0;i<s.len();i=i+1) send_byte(s.getc(i));
    send_byte(13);send_byte(10);
    repeat(160000) @(negedge pc_clk);
    if(reply!={expected_reply,8'h0d,8'h0a}) $fatal(1,"wrong UART reply for %s: %s (length %0d)",s,reply,reply.len());
    if(desired!==expected_state) $fatal(1,"parser state for %s got %h expected %h",s,desired,expected_state);
    if(!blackout && applied!==expected_state) $fatal(1,"remote state for %s got %h",s,applied);
end
endtask
integer n;
initial begin
    repeat(10) @(negedge pc_clk);rst=0;
    repeat(1000) @(negedge pc_clk);
    if(desired!==8'h38 || applied!==8'h38) $fatal(1,"wrong startup defaults");
    command("vol 3","OK VOL=3",8'h33);
    blackout=1;
    command("BRI=50","OK BRI=050",8'h13);
    if(applied!==8'h33) $fatal(1,"link loss did not retain valid state");
    blackout=0;repeat(10000) @(negedge pc_clk);
    if(applied!==8'h13) $fatal(1,"latest control not recovered after loss");
    command("CON 100","OK CON=100",8'hd3);
    command("STATUS","VOL=3 BRI=050 CON=100",8'hd3);
    command("PING","PONG",8'hd3);
    command("MUTE","OK VOL=0",8'hd0);
    command("FULL","OK VOL=8",8'hd8);
    command("VOL+","OK VOL=8",8'hd8);
    command("VOL-","OK VOL=7",8'hd7);
    command("BRI 75","OK BRI=075",8'he7);
    command("BRI 25","OK BRI=025",8'hc7);
    command("BRI 100","OK BRI=100",8'hf7);
    command("CON 25","OK CON=025",8'h37);
    command("CON 50","OK CON=050",8'h77);
    command("CON 75","OK CON=075",8'hb7);
    command("VOL 9","ERR",8'hb7);
    if(received_updates<10) $fatal(1,"missing periodic recovery coverage");
    $display("PASS media control: actual UART commands/replies, 50/125/25 MHz CDC, image contention, loss recovery, VS atomic update");$finish;
end
initial begin #100000000;$fatal(1,"control integration timeout");end
endmodule
