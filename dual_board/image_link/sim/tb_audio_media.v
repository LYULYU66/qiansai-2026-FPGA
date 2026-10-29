`timescale 1ns/1ps
module tb_audio_media;
reg sd_clk=0, clk=0, audio_clk=0;
always #5 sd_clk=~sd_clk;
always #4 clk=~clk;
always #40.690104 audio_clk=~audio_clk; // 12.288 MHz -> 48 kHz stereo
reg rst=1, source_enable=0;
reg [31:0] session_id=1, file_samples=1000;
integer source_count=0, target=2048, burst_left=0;
reg [2:0] source_release=0;
wire source_fifo_reset=rst || !source_enable;
wire source_full, source_empty, source_read, source_ready;
wire [31:0] source_data;
wire [8:0] source_used;
wire source_write=burst_left!=0 && source_count<target;
function [31:0] sample_word;
    input integer n; input integer samples;
    reg [15:0] l,r;
    begin l=16'h5100+(n%samples)*17; r=16'hb100-(n%samples)*13; sample_word={r,l}; end
endfunction
rfifo_32_32_512 #(.SHOW_AHEAD_EN(1'b1)) source_fifo (
    .clkw(sd_clk),.clkr(clk),.rst(source_fifo_reset),.we(source_write),.re(source_read),
    .di(sample_word(source_count,file_samples)),.dout(source_data),.valid(),
    .full_flag(source_full),.empty_flag(source_empty),.afull(),.aempty(),.wrusedw(source_used),.rdusedw()
);
always @(posedge sd_clk) begin
    if(source_fifo_reset) begin source_count<=0; burst_left<=0; source_release<=0; end
    else if(source_write) begin
        if(source_full) $fatal(1,"source sector overflows FIFO");
        source_count<=source_count+1; burst_left<=burst_left-1;
    end else if(source_release<4) source_release<=source_release+1'b1;
    else if(source_used<=256 && source_count<target) burst_left<=128;
end
wire a_req,a_valid,a_ready,a_ack;
wire [7:0] a_data;
wire [15:0] a_length, a_sequence;
wire receipt_valid;
wire [31:0] receipt_session, reported_progress;
wire [15:0] receipt_sequence;
audio_packet_tx #(.RETRY_CYCLES(125000)) tx (
    .clk(clk),.rst(source_fifo_reset),.session_id(session_id),.file_samples(file_samples),
    .source_valid(!source_empty && source_enable),.source_pcm(source_data),.source_ready(source_ready),
    .udp_ready(a_ready),.udp_ack(a_ack),.udp_request(a_req),.udp_valid(a_valid),.udp_data(a_data),.udp_length(a_length),
    .receipt_valid(receipt_valid),.receipt_session(receipt_session),.receipt_sequence(receipt_sequence),.sequence_no(a_sequence)
);
assign source_read=source_ready && !source_empty && source_enable;
wire i_req,i_valid,i_ready,i_ack;
wire [7:0] i_data;
wire [15:0] i_length;
wire image_source_ready;
wire image_receipt_valid;
wire [31:0] image_receipt_token;
wire [15:0] image_receipt_sequence;
integer image_source_count=0;
image_packet_tx #(.FRAME_PACKETS(1),.RELIABLE(1)) image_tx (
    .clk(clk),.rst(rst),.source_valid(image_source_count<2048),.source_ready(image_source_ready),
    .source_rgb(image_source_count[23:0]),.source_frame_start(image_source_count%256==0),
    .source_frame_index(2'd0),.source_top_down(1'b1),.udp_ready(i_ready),.udp_ack(i_ack),
    .udp_request(i_req),.udp_valid(i_valid),.udp_data(i_data),.udp_length(i_length),.frame_sent(),.packets_sent(),
    .receipt_valid(image_receipt_valid),.receipt_token(image_receipt_token),.receipt_sequence(image_receipt_sequence),
    .transfer_token(),.packet_sequence(),.frame_token(32'd0)
);
always @(posedge clk) if(!rst && image_source_ready && image_source_count<2048)
    image_source_count<=image_source_count+1;
wire net_req, net_valid;
wire [7:0] net_data;
wire [15:0] net_length;
reg net_ack=0;
media_udp_arbiter mux (
    .clk(clk),.rst(rst),.net_ready(1'b1),.net_ack(net_ack),.net_request(net_req),.net_valid(net_valid),
    .net_data(net_data),.net_length(net_length),
    .c0_request(i_req),.c0_valid(i_valid),.c0_data(i_data),.c0_length(i_length),.c0_ready(i_ready),.c0_ack(i_ack),
    .c1_request(a_req),.c1_valid(a_valid),.c1_data(a_data),.c1_length(a_length),.c1_ready(a_ready),.c1_ack(a_ack)
);
reg corrupted=0, dropped_ack=0, blackout_done=0;
integer blackout_left=0, frames=0, image_received=0;
wire corrupt_now=net_valid && net_length==530 && session_id==1 && a_sequence==1 && tx.byte_index==40 && !corrupted;
wire blackout=blackout_left!=0;
wire pcm_valid, stream_enable, fifo_reset, receipt_event;
wire [31:0] pcm_data, incoming_samples, event_session;
wire [15:0] event_sequence;
wire fifo_full, fifo_empty, pcm_read, playing, underflow;
wire [31:0] fifo_data;
wire [8:0] fifo_used, fifo_rdused;
wire pcm_ready=!fifo_full && fifo_used<=384;
audio_packet_rx rx (
    .clk(clk),.rst(rst),.rx_valid(net_valid && net_length==530 && !blackout),
    .rx_data(net_data ^ (corrupt_now ? 8'h01 : 8'h00)),.rx_length(net_length),
    .pcm_ready(pcm_ready),.pcm_valid(pcm_valid),.pcm_data(pcm_data),.stream_enable(stream_enable),
    .file_samples(incoming_samples),.fifo_reset(fifo_reset),.receipt_event(receipt_event),
    .stream_session(),
    .receipt_session(event_session),.receipt_sequence(event_sequence)
);
wire image_valid,image_complete;
wire [23:0] image_rgb;
wire [31:0] image_token_rx;
image_packet_rx #(.FRAME_PACKETS(1),.RELIABLE(1)) image_rx (
    .clk(clk),.rst(rst),.rx_valid(net_valid && net_length==782),.rx_data(net_data),.rx_length(net_length),
    .pixel_ready(1'b1),.pixel_valid(image_valid),.pixel_rgb(image_rgb),.frame_start(),.frame_complete(image_complete),
    .frame_abort(),.frame_index(),.frame_top_down(),.good_packets(),.bad_packets(),.packet_done(),.packet_duplicate(),
    .packet_token(image_token_rx),.packet_sequence()
);
rfifo_32_32_512 #(.SHOW_AHEAD_EN(1'b1)) main_fifo (
    .clkw(clk),.clkr(audio_clk),.rst(fifo_reset),.we(pcm_valid && pcm_ready),.re(pcm_read),
    .di(pcm_data),.dout(fifo_data),.valid(),.full_flag(fifo_full),.empty_flag(fifo_empty),.afull(),.aempty(),
    .wrusedw(fifo_used),.rdusedw(fifo_rdused)
);
reg [1:0] enable_sync=0;
always @(posedge audio_clk or posedge rst) begin
    if(rst) enable_sync<=0; else enable_sync<={enable_sync[0],stream_enable};
end
hdmi_audio_pcm_i2s_64fs #(.START_LEVEL(256)) player (
    .I_mclk(audio_clk),.I_rst(rst),.I_enable(enable_sync[1]),.I_pcm_data(fifo_data),.I_pcm_empty(fifo_empty),
    .I_pcm_level(fifo_rdused),.I_volume_level(4'd8),.O_pcm_read(pcm_read),
    .O_i2s_BCLK(),.O_i2s_LRCK(),.O_i2s_DOUT(),.O_playing(playing),.O_underflow(underflow)
);
wire [31:0] played_words;
audio_playback_progress progress (
    .audio_clk(audio_clk),.udp_clk(clk),.rst(fifo_reset),.sample_read(pcm_read && !fifo_empty),.played_words(played_words)
);
wire ack_req,ack_valid,ack_ready,ack_ack;
wire [7:0] ack_data;
wire [15:0] ack_length;
audio_receipt_tx ack_tx (
    .clk(clk),.rst(rst),.event_valid(receipt_event),.event_session(event_session),.event_sequence(event_sequence),
    .played_words(played_words),.udp_ready(ack_ready),.udp_ack(ack_ack),
    .volume_level(4'd8),.analysis_enable(1'b0),
    .udp_request(ack_req),.udp_valid(ack_valid),.udp_data(ack_data),.udp_length(ack_length)
);
wire img_ack_req,img_ack_valid,img_ack_ready,img_ack_ack;
wire [7:0] img_ack_data;
wire [15:0] img_ack_len;
image_receipt_tx img_ack_tx (
    .clk(clk),.rst(rst),.event_valid(image_complete),.event_token(image_token_rx),.event_sequence(16'd0),
    .udp_ready(img_ack_ready),.udp_ack(img_ack_ack),.udp_request(img_ack_req),.udp_valid(img_ack_valid),
    .udp_data(img_ack_data),.udp_length(img_ack_len)
);
wire return_req,return_valid;
wire [7:0] return_data;
wire [15:0] return_length;
reg return_ack=0;
media_udp_arbiter ack_mux (
    .clk(clk),.rst(rst),.net_ready(1'b1),.net_ack(return_ack),.net_request(return_req),.net_valid(return_valid),
    .net_data(return_data),.net_length(return_length),
    .c0_request(img_ack_req),.c0_valid(img_ack_valid),.c0_data(img_ack_data),.c0_length(img_ack_len),
    .c0_ready(img_ack_ready),.c0_ack(img_ack_ack),
    .c1_request(ack_req),.c1_valid(ack_valid),.c1_data(ack_data),.c1_length(ack_length),.c1_ready(ack_ready),.c1_ack(ack_ack)
);
wire drop_ack=ack_tx.session==1 && ack_tx.sequence_no==0 && !dropped_ack;
audio_receipt_rx ack_rx (
    .clk(clk),.rst(rst),.rx_valid(return_valid && return_length==16 && !drop_ack),
    .rx_data(return_data),.rx_length(return_length),.receipt_valid(receipt_valid),
    .receipt_session(receipt_session),.receipt_sequence(receipt_sequence),.played_words(reported_progress),
    .volume_level(),.analysis_enable()
);
image_receipt_rx image_ack_rx (
    .clk(clk),.rst(rst),.rx_valid(return_valid && return_length==12),.rx_data(return_data),.rx_length(return_length),
    .receipt_valid(image_receipt_valid),.receipt_token(image_receipt_token),.receipt_sequence(image_receipt_sequence)
);
integer delivered=0, played=0, underflows=0, packet_bytes=0, frozen_count=0;
reg previous_net_valid=0;
reg [15:0] active_length;
always @(posedge clk) if(!rst) begin
    net_ack<=net_req; return_ack<=return_req;
    previous_net_valid<=net_valid;
    if(net_valid && !previous_net_valid) begin packet_bytes=0; active_length=net_length; end
    if(net_valid) begin
        packet_bytes=packet_bytes+1;
        if(net_length!==active_length) $fatal(1,"arbiter changes owner inside packet");
    end
    if(previous_net_valid && !net_valid && packet_bytes!=active_length)
        $fatal(1,"UDP packet truncated %0d/%0d",packet_bytes,active_length);
    if(corrupt_now) corrupted<=1;
    if(return_valid && return_length==16 && ack_tx.index==15 && drop_ack) dropped_ack<=1;
    if(fifo_reset) delivered=0;
    if(pcm_valid && pcm_ready) begin
        if(pcm_data!==sample_word(delivered,incoming_samples)) $fatal(1,"RX sample %0d got %h",delivered,pcm_data);
        if(fifo_full) $fatal(1,"main FIFO overflows");
        delivered=delivered+1;
    end
    if(image_valid) begin
        if(image_rgb!==image_received[23:0]) $fatal(1,"image damaged by PCM arbitration index=%0d got=%h",image_received,image_rgb);
        image_received=image_received+1;
    end
    if(image_complete) frames=frames+1;
    if(played_words>=300 && !blackout_done && session_id==1) begin
        blackout_left=1800000; blackout_done=1; // 14.4ms > FIFO capacity
    end else if(blackout_left!=0) blackout_left=blackout_left-1;
    if(blackout && fifo_empty && !playing) begin
        frozen_count=frozen_count+1;
        if(frozen_count==1000 && played_words!=played) $fatal(1,"progress advances during underflow");
    end
    if(receipt_valid && receipt_session==session_id && reported_progress>played_words)
        $fatal(1,"ACK progress leads actual playback");
end
always @(posedge audio_clk) begin
    if(fifo_reset) played=0;
    else if(pcm_read && !fifo_empty) begin
        if(fifo_data!==sample_word(played,incoming_samples)) $fatal(1,"played sample %0d got %h",played,fifo_data);
        played=played+1;
    end
    if(underflow) underflows=underflows+1;
end
initial begin
    repeat(8) @(negedge clk); rst=0; source_enable=1;
    wait(played==2048);
    repeat(400) @(negedge clk);
    if(delivered!=2048 || played_words!=2048 || !corrupted || !dropped_ack || underflows==0 || frozen_count<1000 || frames!=8)
        $fatal(1,"coverage missing D=%0d P=%0d U=%0d F=%0d frozen=%0d",delivered,played_words,underflows,frames,frozen_count);
    // New stream after both queues are drained, without resetting the boards.
    source_enable=0;
    repeat(40) @(negedge sd_clk);
    session_id=2; file_samples=997; target=512; source_enable=1;
    wait(rx.session==2);
    wait(played==512);
    repeat(400) @(negedge clk);
    if(delivered!=512 || played_words!=512 || incoming_samples!=997) $fatal(1,"session restart failed");
    $display("PASS audio media: 48kHz, native 100/125/audio FIFO, CRC retry, ACK loss, image arbitration, underflow freeze/recovery, song loop and new session");
    $finish;
end
initial begin #100000000; $fatal(1,"audio test timeout played=%0d delivered=%0d seq=%0d",played,delivered,a_sequence); end
endmodule
