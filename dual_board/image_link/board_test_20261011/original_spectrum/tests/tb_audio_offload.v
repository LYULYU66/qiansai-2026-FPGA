`timescale 1ns/1ps
module tb_audio_offload #(parameter integer FLAT_SCHEDULER=0, USE_FIXED_UDP=0);
reg sd_clk=0, clk=0, audio_clk=0, compute_clk=0;
always #5 sd_clk=~sd_clk;
always #4 clk=~clk;
always #20 compute_clk=~compute_clk;
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
wire history_ready;
audio_packet_tx #(.RETRY_CYCLES(125000)) tx (
    .clk(clk),.rst(source_fifo_reset),.session_id(session_id),.file_samples(file_samples),
    .source_valid(!source_empty && source_enable && history_ready),.source_pcm(source_data),.source_ready(source_ready),
    .udp_ready(a_ready),.udp_ack(a_ack),.udp_request(a_req),.udp_valid(a_valid),.udp_data(a_data),.udp_length(a_length),
    .receipt_valid(receipt_valid),.receipt_session(receipt_session),.receipt_sequence(receipt_sequence),.sequence_no(a_sequence)
);
assign source_read=source_ready && !source_empty && source_enable && history_ready;
wire [3:0] feedback_volume;
wire feedback_enable;
wire [263:0] computed_visual;
wire [31:0] analysed_words;
wire settled;
remote_audio_compute compute (
    .udp_clk(clk),.clk(compute_clk),.rst(source_fifo_reset),.session_id(session_id),.file_samples(file_samples),
    .source_valid(source_read),.source_pcm(source_data),.source_ready(history_ready),
    .feedback_valid(receipt_valid),.feedback_session(receipt_session),.feedback_played(reported_progress),
    .feedback_volume(feedback_volume),.feedback_enable(feedback_enable),
    .visual_state(computed_visual),.analysed_words(analysed_words),.settled(settled)
);
wire [295:0] snapshot;
wire snapshot_hold;
wire snapshot_valid;
reg have_snapshot=0;
audio_visual_cdc #(.WIDTH(296),.FRAME_BOUNDARY(0),.DESTINATION_HOLD(1)) compute_cdc (
    .udp_clk(compute_clk),.video_clk(clk),.rst(source_fifo_reset),.frame_vs(1'b0),
    .update_valid(1'b0),.publish_enable(settled),.visual_state({analysed_words,computed_visual}),
    .hold_capture(snapshot_hold),.frame_state(snapshot),.capture_valid(snapshot_valid)
);
always @(posedge clk or posedge source_fifo_reset) begin
    if(source_fifo_reset) have_snapshot<=0;
    else if(snapshot_valid) have_snapshot<=1;
end
wire v_req,v_valid,v_ready,v_ack;
wire [7:0] v_data;
wire [15:0] v_length;
audio_visual_tx #(.UPDATE_CYCLES(125000),.SHARED_SNAPSHOT(1)) vis_tx (
    .clk(clk),.rst(source_fifo_reset),.source_settled(have_snapshot),.session_id(session_id),
    .analysed_words(snapshot[295:264]),.visual_state(snapshot[263:0]),.udp_ready(v_ready),.udp_ack(v_ack),
    .snapshot_hold(snapshot_hold),.udp_request(v_req),.udp_valid(v_valid),.udp_data(v_data),.udp_length(v_length)
);
wire i_req,i_valid,i_ready,i_ack;
wire [7:0] i_data;
wire [15:0] i_length;
wire image_source_ready;
wire image_receipt_valid;
wire [31:0] image_receipt_token;
wire [15:0] image_receipt_sequence;
integer image_source_count=0;
image_packet_tx #(.FRAME_PACKETS(1),.RELIABLE(1),.UI_TAG(1),.RESOLUTION(1)) image_tx (
    .clk(clk),.rst(rst),.source_valid(image_source_count<2048),.source_ready(image_source_ready),
    .source_rgb(image_source_count[23:0]),.source_frame_start(image_source_count%256==0),
    .source_tag(image_source_count[7:0]^8'hc3),
    .source_frame_index(2'd0),.source_top_down(1'b1),.udp_ready(i_ready),.udp_ack(i_ack),
    .source_resolution(32'h050003c0),
    .udp_request(i_req),.udp_valid(i_valid),.udp_data(i_data),.udp_length(i_length),.frame_sent(),.packets_sent(),
    .receipt_valid(image_receipt_valid),.receipt_token(image_receipt_token),.receipt_sequence(image_receipt_sequence),
    .transfer_token(),.packet_sequence(),.frame_token(32'd0)
);
always @(posedge clk) if(!rst && image_source_ready && image_source_count<2048)
    image_source_count<=image_source_count+1;
wire net_req, net_valid;
wire [7:0] net_data;
wire [15:0] net_length;
wire net_ready,net_ack;
reg legacy_net_ack=0;
wire net_rx_valid;
wire [7:0] net_rx_data;
wire [15:0] net_rx_length;
wire g_req,g_valid,g_ready,g_ack;
wire [7:0] g_data;
wire [15:0] g_length;
reg [7:0] desired_control=8'h38;
wire ctl_req,ctl_valid,ctl_ready,ctl_ack,info_req,info_valid,info_ready,info_ack;
wire [7:0] ctl_data,info_data,received_control,applied_control;
wire [15:0] ctl_length,info_length;
wire ctl_update;
integer control_updates=0;
media_control_tx #(.UPDATE_CYCLES(125000)) ctl_tx (
    .clk(clk),.rst(rst),.settings(desired_control),.udp_ready(ctl_ready),.udp_ack(ctl_ack),
    .udp_request(ctl_req),.udp_valid(ctl_valid),.udp_data(ctl_data),.udp_length(ctl_length));
generate if(FLAT_SCHEDULER)begin : flat_outgoing
wire [4:0] ready_channels, ack_channels;
assign {a_ready,ctl_ready,v_ready,i_ready}=ready_channels[3:0];
assign {a_ack,ctl_ack,v_ack,i_ack}=ack_channels[3:0];
media_udp_scheduler #(.CHANNELS(5),.MAX_LENGTH(1042)) scheduler (
    .clk(clk),.rst(rst),.net_ready(net_ready),.net_ack(net_ack),.net_request(net_req),.net_valid(net_valid),
    .net_data(net_data),.net_length(net_length),
    .c_request({1'b0,a_req,ctl_req,v_req,i_req}),.c_valid({1'b0,a_valid,ctl_valid,v_valid,i_valid}),
    .c_data({8'd0,a_data,ctl_data,v_data,i_data}),.c_length({16'd10,a_length,ctl_length,v_length,i_length}),
    .c_ready(ready_channels),.c_ack(ack_channels));
end else begin : legacy_outgoing
media_udp_arbiter info_mux (
    .clk(clk),.rst(rst),.net_ready(info_ready),.net_ack(info_ack),.net_request(info_req),.net_valid(info_valid),
    .net_data(info_data),.net_length(info_length),
    .c0_request(v_req),.c0_valid(v_valid),.c0_data(v_data),.c0_length(v_length),.c0_ready(v_ready),.c0_ack(v_ack),
    .c1_request(ctl_req),.c1_valid(ctl_valid),.c1_data(ctl_data),.c1_length(ctl_length),.c1_ready(ctl_ready),.c1_ack(ctl_ack));
media_udp_arbiter graphics_mux (
    .clk(clk),.rst(rst),.net_ready(g_ready),.net_ack(g_ack),.net_request(g_req),.net_valid(g_valid),
    .net_data(g_data),.net_length(g_length),
    .c0_request(i_req),.c0_valid(i_valid),.c0_data(i_data),.c0_length(i_length),.c0_ready(i_ready),.c0_ack(i_ack),
    .c1_request(info_req),.c1_valid(info_valid),.c1_data(info_data),.c1_length(info_length),.c1_ready(info_ready),.c1_ack(info_ack)
);
media_udp_arbiter mux (
    .clk(clk),.rst(rst),.net_ready(net_ready),.net_ack(net_ack),.net_request(net_req),.net_valid(net_valid),
    .net_data(net_data),.net_length(net_length),
    .c0_request(g_req),.c0_valid(g_valid),.c0_data(g_data),.c0_length(g_length),.c0_ready(g_ready),.c0_ack(g_ack),
    .c1_request(a_req),.c1_valid(a_valid),.c1_data(a_data),.c1_length(a_length),.c1_ready(a_ready),.c1_ack(a_ack)
);
end endgenerate
reg corrupted=0, dropped_ack=0, blackout_done=0;
integer blackout_left=0, frames=0, image_received=0;
wire corrupt_now=net_valid && net_length==530 && session_id==1 && a_sequence==1 && tx.byte_index==40 && !corrupted;
// Damage the application CRC-bearing payload before the real UDP endpoint;
// IPv4 checksum validation is independent and must not hide this media error.
wire [7:0] transmitted_data=net_data ^ (corrupt_now ? 8'h01 : 8'h00);
wire blackout=blackout_left!=0;
wire pcm_valid, stream_enable, fifo_reset, receipt_event;
wire [31:0] pcm_data, incoming_samples, event_session, active_session;
wire [15:0] event_sequence;
wire fifo_full, fifo_empty, pcm_read, playing, underflow;
wire [31:0] fifo_data;
wire [8:0] fifo_used, fifo_rdused;
wire pcm_ready=!fifo_full && fifo_used<=384;
audio_packet_rx rx (
    .clk(clk),.rst(rst),.rx_valid(net_rx_valid && net_rx_length==530 && !blackout),
    .rx_data(net_rx_data),.rx_length(net_rx_length),
    .pcm_ready(pcm_ready),.pcm_valid(pcm_valid),.pcm_data(pcm_data),.stream_enable(stream_enable),
    .file_samples(incoming_samples),.fifo_reset(fifo_reset),.receipt_event(receipt_event),
    .stream_session(active_session),
    .receipt_session(event_session),.receipt_sequence(event_sequence)
);
wire image_valid,image_complete;
wire [23:0] image_rgb;
wire [7:0] image_tag;
wire [31:0] image_token_rx;
image_packet_rx #(.FRAME_PACKETS(1),.RELIABLE(1),.UI_TAG(1),.RESOLUTION(1)) image_rx (
    .clk(clk),.rst(rst),.rx_valid(net_rx_valid && net_rx_length==1042),.rx_data(net_rx_data),.rx_length(net_rx_length),
    .pixel_ready(1'b1),.pixel_valid(image_valid),.pixel_rgb(image_rgb),.frame_start(),.frame_complete(image_complete),
    .pixel_tag(image_tag),
    .frame_resolution(),
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
    .I_pcm_level(fifo_rdused),.I_volume_level(applied_control[3:0]),.O_pcm_read(pcm_read),
    .O_i2s_BCLK(),.O_i2s_LRCK(),.O_i2s_DOUT(),.O_playing(playing),.O_underflow(underflow)
);
wire [31:0] played_words;
audio_playback_progress progress (
    .audio_clk(audio_clk),.udp_clk(clk),.rst(fifo_reset),.sample_read(pcm_read && !fifo_empty),.played_words(played_words)
);
wire ack_req,ack_valid,ack_ready,ack_ack;
wire [7:0] ack_data;
wire [15:0] ack_length;
wire [3:0] volume=applied_control[3:0];
audio_receipt_tx #(.EXTENDED(1),.PERIODIC_CYCLES(125000)) ack_tx (
    .clk(clk),.rst(rst || fifo_reset),.event_valid(receipt_event),.event_session(event_session),.event_sequence(event_sequence),
    .played_words(played_words),.volume_level(volume),.analysis_enable(playing),.udp_ready(ack_ready),.udp_ack(ack_ack),
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
wire return_ready,return_ack;
reg legacy_return_ack=0;
wire return_rx_valid;
wire [7:0] return_rx_data;
wire [15:0] return_rx_length;

generate if(USE_FIXED_UDP)begin : fixed_transport
fixed_udp_test_link #(.MAX_PAYLOAD(1042)) media_link (
    .clk(clk),.tx_rst(rst),.rx_rst(rst),.tx_data(transmitted_data),.tx_length(net_length),
    .tx_request(net_req),.tx_valid(net_valid),.tx_ready(net_ready),.tx_ack(net_ack),
    .rx_valid(net_rx_valid),.rx_data(net_rx_data),.rx_length(net_rx_length));
fixed_udp_test_link #(.SOURCE_IP(32'hc0a80a0b),.DEST_IP(32'hc0a80a0c),
    .SOURCE_MAC(48'h02000000000b),.DEST_MAC(48'h02000000000c),.MAX_PAYLOAD(18)) receipt_link (
    .clk(clk),.tx_rst(rst),.rx_rst(rst),.tx_data(return_data),.tx_length(return_length),
    .tx_request(return_req),.tx_valid(return_valid),.tx_ready(return_ready),.tx_ack(return_ack),
    .rx_valid(return_rx_valid),.rx_data(return_rx_data),.rx_length(return_rx_length));
end else begin : direct_transport
assign net_ready=1'b1;
assign net_ack=legacy_net_ack;
assign net_rx_valid=net_valid;
assign net_rx_data=transmitted_data;
assign net_rx_length=net_length;
assign return_ready=1'b1;
assign return_ack=legacy_return_ack;
assign return_rx_valid=return_valid;
assign return_rx_data=return_data;
assign return_rx_length=return_length;
end endgenerate
generate if(FLAT_SCHEDULER)begin : flat_return
wire [2:0] ready_channels, ack_channels;
assign {ack_ready,img_ack_ready}=ready_channels[1:0];
assign {ack_ack,img_ack_ack}=ack_channels[1:0];
media_udp_scheduler #(.CHANNELS(3),.MAX_LENGTH(18)) scheduler (
    .clk(clk),.rst(rst),.net_ready(return_ready),.net_ack(return_ack),.net_request(return_req),.net_valid(return_valid),
    .net_data(return_data),.net_length(return_length),
    .c_request({1'b0,ack_req,img_ack_req}),.c_valid({1'b0,ack_valid,img_ack_valid}),
    .c_data({8'd0,ack_data,img_ack_data}),.c_length({16'd10,ack_length,img_ack_len}),
    .c_ready(ready_channels),.c_ack(ack_channels));
end else begin : legacy_return
media_udp_arbiter ack_mux (
    .clk(clk),.rst(rst),.net_ready(return_ready),.net_ack(return_ack),.net_request(return_req),.net_valid(return_valid),
    .net_data(return_data),.net_length(return_length),
    .c0_request(img_ack_req),.c0_valid(img_ack_valid),.c0_data(img_ack_data),.c0_length(img_ack_len),
    .c0_ready(img_ack_ready),.c0_ack(img_ack_ack),
    .c1_request(ack_req),.c1_valid(ack_valid),.c1_data(ack_data),.c1_length(ack_length),.c1_ready(ack_ready),.c1_ack(ack_ack)
);
end endgenerate
reg fixed_return_previous=0,fixed_drop_active=0;
integer fixed_return_index=0;
reg [31:0] fixed_ack_session=0;
reg [15:0] fixed_ack_sequence=0;
// Lock loss injection to an actual received datagram, not to the TX producer
// (which may already have advanced while UDP still buffers/transmits the ACK).
wire fixed_drop_ack=return_rx_valid && return_rx_length==18 &&
    (fixed_return_previous ? fixed_drop_active : !dropped_ack);
wire drop_ack=USE_FIXED_UDP ? fixed_drop_ack :
    (ack_tx.session==1 && ack_tx.sequence_no==0 && !dropped_ack);
always @(posedge clk) begin
    if(rst)begin
        fixed_return_previous<=0;fixed_drop_active<=0;fixed_return_index=0;
        fixed_ack_session<=0;fixed_ack_sequence<=0;
    end else if(USE_FIXED_UDP)begin
        fixed_return_previous<=return_rx_valid;
        if(return_rx_valid)begin
            if(!fixed_return_previous)begin
                fixed_return_index=0;
                fixed_drop_active<=return_rx_length==18 && !dropped_ack;
            end else fixed_return_index=fixed_return_index+1;
            if(return_rx_length==18)begin
                case(fixed_return_index)
                    4:fixed_ack_session[7:0]<=return_rx_data;
                    5:fixed_ack_session[15:8]<=return_rx_data;
                    6:fixed_ack_session[23:16]<=return_rx_data;
                    7:fixed_ack_session[31:24]<=return_rx_data;
                    8:fixed_ack_sequence[7:0]<=return_rx_data;
                    9:fixed_ack_sequence[15:8]<=return_rx_data;
                    default:begin end
                endcase
                if(fixed_return_index==17 && fixed_drop_ack)begin
                    if(fixed_ack_session!=1 || fixed_ack_sequence!=0)
                        $fatal(1,"wrong received ACK selected for loss injection session=%h seq=%0d",fixed_ack_session,fixed_ack_sequence);
                    dropped_ack<=1;
                end
            end
        end
    end
end
audio_receipt_rx #(.EXTENDED(1)) ack_rx (
    .clk(clk),.rst(rst),.rx_valid(return_rx_valid && return_rx_length==18 && !drop_ack),
    .rx_data(return_rx_data),.rx_length(return_rx_length),.receipt_valid(receipt_valid),
    .receipt_session(receipt_session),.receipt_sequence(receipt_sequence),.played_words(reported_progress),
    .volume_level(feedback_volume),.analysis_enable(feedback_enable)
);
image_receipt_rx image_ack_rx (
    .clk(clk),.rst(rst),.rx_valid(return_rx_valid && return_rx_length==12),.rx_data(return_rx_data),.rx_length(return_rx_length),
    .receipt_valid(image_receipt_valid),.receipt_token(image_receipt_token),.receipt_sequence(image_receipt_sequence)
);
integer delivered=0, played=0, underflows=0, packet_bytes=0, frozen_count=0;
reg previous_net_valid=0;
reg [15:0] active_length;
always @(posedge clk) if(!rst) begin
    legacy_net_ack<=net_req; legacy_return_ack<=return_req;
    previous_net_valid<=net_valid;
    if(net_valid && !previous_net_valid) begin packet_bytes=0; active_length=net_length; end
    if(net_valid) begin
        packet_bytes=packet_bytes+1;
        if(net_length!==active_length) $fatal(1,"arbiter changes owner inside packet");
    end
    if(previous_net_valid && !net_valid && packet_bytes!=active_length)
        $fatal(1,"UDP packet truncated %0d/%0d",packet_bytes,active_length);
    if(corrupt_now) corrupted<=1;
    if(!USE_FIXED_UDP && return_valid && return_length==18 && ack_tx.index==17 && drop_ack) dropped_ack<=1;
    if(fifo_reset) delivered=0;
    if(pcm_valid && pcm_ready) begin
        if(pcm_data!==sample_word(delivered,incoming_samples)) $fatal(1,"RX sample %0d got %h",delivered,pcm_data);
        if(fifo_full) $fatal(1,"main FIFO overflows");
        delivered=delivered+1;
    end
    if(image_valid) begin
        if(image_rgb!==image_received[23:0] || image_tag!==(image_received[7:0]^8'hc3))
            $fatal(1,"image/tag damaged by PCM arbitration index=%0d got=%h/%h",image_received,image_rgb,image_tag);
        image_received=image_received+1;
    end
    if(image_complete) frames=frames+1;
    if(played_words>=150) desired_control<=8'hb6;
    if(ctl_update) control_updates=control_updates+1;
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
wire viz_update;
wire [263:0] received_visual, frame_visual;
integer visual_updates=0, reference_samples=0;
audio_visual_rx vis_rx (
    .clk(clk),.rst(fifo_reset),.rx_valid(net_rx_valid && net_rx_length==47 && !blackout),
    .rx_data(net_rx_data),.rx_length(net_rx_length),.session_id(active_session),.played_words(played_words),
    .update_valid(viz_update),.visual_state(received_visual)
);
reg frame_vs=0;
media_control_rx ctl_rx (
    .clk(clk),.rst(rst),.rx_valid(net_rx_valid && net_rx_length==12 && !blackout),.rx_data(net_rx_data),.rx_length(net_rx_length),
    .update_valid(ctl_update),.settings(received_control));
audio_visual_cdc #(.WIDTH(8),.RESET_STATE(8'h38)) ctl_cdc (
    .udp_clk(clk),.video_clk(compute_clk),.rst(rst),.frame_vs(frame_vs),.update_valid(1'b0),
    .publish_enable(1'b1),.visual_state(received_control),.frame_state(applied_control),.capture_valid());
integer frame_count=0;
always @(posedge compute_clk) begin
    if(frame_count==416665) frame_count<=0; else frame_count<=frame_count+1;
    frame_vs<=frame_count<4;
end
audio_visual_cdc main_visual_cdc (
    .udp_clk(clk),.video_clk(compute_clk),.rst(fifo_reset),.frame_vs(frame_vs),
    .update_valid(viz_update),.publish_enable(1'b1),.visual_state(received_visual),
    .frame_state(frame_visual),.capture_valid()
);
always @(posedge clk) if(viz_update) begin
    visual_updates=visual_updates+1;
    if(vis_rx.progress>played_words) $fatal(1,"visual metadata ahead of actual audio");
end
function signed [15:0] reference_gain;
    input signed [15:0] s; input [3:0] gain;
    reg signed [18:0] x,y;
    begin x=s;
        case(gain)
            0:y=0; 1:y=x>>>3; 2:y=x>>>2; 3:y=(x>>>2)+(x>>>3);
            4:y=x>>>1; 5:y=(x>>>1)+(x>>>3); 6:y=(x>>>1)+(x>>>2);
            7:y=x-(x>>>3); default:y=x;
        endcase
        reference_gain=y[15:0];
    end
endfunction
wire [31:0] ref_raw=sample_word(reference_samples,file_samples);
reg [3:0] ref_volume=8;
wire [23:0] ref_left={reference_gain($signed(ref_raw[15:0]),ref_volume),8'd0};
wire [23:0] ref_right={reference_gain($signed(ref_raw[31:16]),ref_volume),8'd0};
wire [6:0] ref_vul,ref_vur;
wire [111:0] ref_wave,ref_bands;
audio_waveform_analyzer ref_waveform (
    .I_clk(compute_clk),.I_rst(compute.compute_reset),.I_enable(compute.enabled),
    .I_audio_valid(compute.sample_valid),.I_audio_left(ref_left),.I_audio_right(ref_right),
    .O_vu_left_level(ref_vul),.O_vu_right_level(ref_vur),.O_wave_samples(ref_wave)
);
audio_spectrum_analyzer #(.LOW_POWER(1)) ref_spectrum (
    .I_clk(compute_clk),.I_rst(compute.compute_reset),.I_enable(compute.enabled),
    .I_audio_valid(compute.sample_valid),.I_audio_left(ref_left),.I_audio_right(ref_right),
    .O_vu_left_level(),.O_vu_right_level(),.O_band_levels(ref_bands)
);
reg [263:0] previous_frame_visual=0;
integer last_sample_cycle=-1000, compute_cycles=0;
always @(posedge compute_clk) begin
    compute_cycles=compute_cycles+1;
    if(compute.state==1) ref_volume<=compute.volume;
    if(source_fifo_reset) reference_samples<=0;
    else if(compute.sample_valid) begin
        if(reference_samples>=played) $fatal(1,"B computed an unplayed sample");
        if(compute_cycles-last_sample_cycle<256) $fatal(1,"Goertzel overloaded");
        if(compute.enabled && compute.u_spectrum.state!=0) $fatal(1,"Goertzel skips sample");
        last_sample_cycle=compute_cycles;
        if({compute.right_scaled,compute.left_scaled}!=={ref_right[23:8],ref_left[23:8]})
            $fatal(1,"history/gain mismatch n=%0d",reference_samples);
        reference_samples<=reference_samples+1;
    end
end
always @(negedge compute_clk) if(!source_fifo_reset) begin
    if(computed_visual[237:0]!=={ref_wave,ref_bands,ref_vur,ref_vul})
        $fatal(1,"offloaded analysis differs from original reference");
    if(frame_visual!==previous_frame_visual && !frame_vs && !fifo_reset)
        $fatal(1,"visible metadata changed outside VS");
    previous_frame_visual=frame_visual;
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
    wait(analysed_words==2048);
    repeat(140000) @(negedge clk);
    if(delivered!=2048 || played_words!=2048 || !corrupted || !dropped_ack || underflows==0 || frozen_count<1000 || frames!=8)
        $fatal(1,"coverage missing D=%0d P=%0d U=%0d F=%0d frozen=%0d",delivered,played_words,underflows,frames,frozen_count);
    // New stream after both queues are drained, without resetting the boards.
    source_enable=0;
    repeat(40) @(negedge sd_clk);
    session_id=2; file_samples=10043560; target=512; source_enable=1;
    wait(rx.session==2);
    wait(played==512);
    wait(analysed_words==512);
    repeat(140000) @(negedge clk);
    if(delivered!=512 || played_words!=512 || incoming_samples!=10043560 || visual_updates<10 ||
       control_updates<20 || applied_control!=8'hb6 || feedback_volume!=6 ||
       compute.u_lyrics.sample_count!=512 || received_visual[245:238]!=23 || received_visual[253:246]!=24)
        $fatal(1,"session/lyrics restart failed V=%0d",visual_updates);
    if(USE_FIXED_UDP)$display("PASS fixed UDP audio offload: framed IMG4/PCM/VIZ2/CTL2, native FIFO, original analysers, volume/lyrics, CRC retry, actual received ACK loss and 48kHz playback");
    else if(FLAT_SCHEDULER)$display("PASS flat audio offload: real IMG4/PCM/VIZ2/CTL2, original analysers, volume/lyrics, CRC retry, ACK loss and 48kHz playback");
    else $display("PASS audio offload: original analyser equivalence, actual 48k playback feedback, native FIFO, CRC retry/ACK loss, 4-stream IMG4/PCM/visual/control arbitration, remote volume, underflow freeze, session restart and lyric sample count");
    $finish;
end
initial begin #100000000; $fatal(1,"audio test timeout played=%0d delivered=%0d seq=%0d",played,delivered,a_sequence); end
endmodule

module tb_audio_offload_flat;
tb_audio_offload #(.FLAT_SCHEDULER(1)) test();
endmodule

module tb_audio_offload_fixed;
tb_audio_offload #(.FLAT_SCHEDULER(1),.USE_FIXED_UDP(1)) test();
endmodule
