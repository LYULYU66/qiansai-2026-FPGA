`timescale 1ns/1ps
module tb_audio_visual_guard;
reg clk=0, video_clk=0, rst=1;
always #4 clk=~clk;
always #19 video_clk=~video_clk;
reg settled=1;
reg [263:0] original=264'h123456789abcdef_13579bdf02468ac_876543210abcdef_fedcba987654321_5a;
wire tx_req,tx_valid;
wire [7:0] tx_data;
wire [15:0] tx_length;
reg tx_ack=0;
audio_visual_tx #(.UPDATE_CYCLES(40)) tx (
    .clk(clk),.rst(rst),.source_settled(settled),.session_id(32'd9),.analysed_words(32'd200),
    .visual_state(original),.udp_ready(1'b1),.udp_ack(tx_ack),.udp_request(tx_req),
    .udp_valid(tx_valid),.udp_data(tx_data),.udp_length(tx_length)
);
reg [7:0] packet[0:46];
integer captured=0, updates=0;
always @(posedge clk) if(!rst) begin
    tx_ack<=tx_req;
    if(tx_valid && captured<47) begin
        if(tx_length!=47) $fatal(1,"visual TX length incorrect");
        packet[captured]=tx_data; captured=captured+1;
    end
end
reg rx_valid=0;
reg [7:0] rx_data=0;
reg [15:0] rx_length=47;
reg [31:0] played_words=500, session_id=9;
wire update_valid;
wire [263:0] visual_state, frame_state;
audio_visual_rx rx (
    .clk(clk),.rst(rst),.rx_valid(rx_valid),.rx_data(rx_data),.rx_length(rx_length),
    .session_id(session_id),.played_words(played_words),.update_valid(update_valid),.visual_state(visual_state)
);
reg frame_vs=0;
wire capture_valid;
audio_visual_cdc cdc (
    .udp_clk(clk),.video_clk(video_clk),.rst(rst),.frame_vs(frame_vs),
    .update_valid(update_valid),.publish_enable(1'b1),.visual_state(visual_state),
    .frame_state(frame_state),.capture_valid(capture_valid)
);
always @(posedge clk) if(update_valid) updates=updates+1;
function [15:0] crc_byte;
    input [15:0] old_crc; input [7:0] value;
    reg [15:0] c; integer i;
    begin c=old_crc^{value,8'd0};
        for(i=0;i<8;i=i+1) c=c[15]?(c<<1)^16'h1021:c<<1;
        crc_byte=c;
    end
endfunction
task send;
    input [31:0] sess, head;
    input integer length, bytes;
    input corrupt;
    integer k; reg [15:0] crc; reg [7:0] value;
    begin
        crc=16'hffff; rx_length=length;
        for(k=0;k<bytes;k=k+1) begin
            @(negedge clk); rx_valid=1;
            if(k>=4 && k<8) value=(sess>>((k-4)*8))&255;
            else if(k>=8 && k<12) value=(head>>((k-8)*8))&255;
            else value=packet[k];
            if(k==45) value=crc[15:8];
            if(k==46) value=crc[7:0] ^ (corrupt ? 8'h01 : 0);
            rx_data=value;
            if(k<45) crc=crc_byte(crc,value);
        end
        @(negedge clk); rx_valid=0; repeat(6) @(negedge clk);
    end
endtask
task frame;
    begin
        @(negedge video_clk); frame_vs=1;
        repeat(4) @(negedge video_clk); frame_vs=0;
        repeat(4) @(negedge video_clk);
    end
endtask
integer before_updates;
initial begin
    repeat(8) @(negedge clk); rst=0;
    wait(captured==47); settled=0;
    send(9,200,47,47,0);
    if(updates!=1 || visual_state!==original) $fatal(1,"packed VU/wave/spectrum/lyrics changed");
    repeat(12) @(negedge video_clk);
    if(frame_state!=0) $fatal(1,"metadata visible before VS");
    frame;
    if(frame_state!==original) $fatal(1,"metadata mailbox lost state");
    before_updates=updates;
    send(9,220,47,47,1); send(8,220,47,47,0); send(9,501,47,47,0);
    send(9,199,47,47,0); send(9,220,46,47,0); send(9,220,47,30,0);
    if(updates!=before_updates || visual_state!==original) $fatal(1,"invalid visual packet committed");
    // CRC-valid retransmission at the same head may carry new volume/enable.
    packet[12]=~packet[12]; send(9,200,47,47,0);
    repeat(12) @(negedge video_clk);
    if(frame_state!==original) $fatal(1,"mid-frame change");
    frame;
    if(frame_state[7:0]!==~original[7:0] || updates!=2) $fatal(1,"same-head refresh missed");
    send(9,500,47,47,0);
    if(updates!=3) $fatal(1,"latest valid packet not accepted after loss");
    // Fresh playback context rejects the previous song/session.
    rst=1; repeat(8) @(negedge clk); session_id=10; played_words=0; rst=0;
    send(9,0,47,47,0);
    if(visual_state!=0) $fatal(1,"stale song reappeared");
    send(10,0,47,47,0); repeat(12) @(negedge video_clk); frame;
    if(frame_state!==visual_state || frame_state==0) $fatal(1,"new song metadata missing");
    $display("PASS visual guard: exact packed payload, CRC/length/truncation/session/order/future rejection, replaceable loss, same-head refresh and frame-atomic CDC");
    $finish;
end
initial begin #1000000; $fatal(1,"visual guard timeout"); end
endmodule
