`timescale 1ns/1ps
// Component-level dual-board restart: real lease, IMG4/AUD2/ACK producers,
// packet arbiters, native PCM FIFO and 48 kHz serializer. Decoded media is
// generated here; this is NOT a TF/FAT, encrypted MAC, SDRAM or HDMI test.
module tb_media_restart #(parameter integer FLAT_SCHEDULER=0, USE_FIXED_UDP=0);
reg clk=0;always #4 clk=~clk;
reg audio_clk=0;always #40.69 audio_clk=~audio_clk;
reg ar=1,br=1,aa=0,ba=0;
wire a_ready,b_ready,a_restart,b_restart;
wire [15:0] ag,bg;
wire a_req,a_valid,b_req,b_valid;
wire [7:0] a_data,b_data;
wire [15:0] a_length,b_length;
wire a_net_ready,a_net_ack,b_net_ready,b_net_ack;
wire a_rx_valid,b_rx_valid;
wire [7:0] a_rx_data,b_rx_data;
wire [15:0] a_rx_length,b_rx_length;
// Endpoint buffers reset only with their owning board. A retains its partial
// receive/send state through a B reset, as in the formal transport topology.
generate if(USE_FIXED_UDP)begin : fixed_transport
fixed_udp_test_link #(.MAX_PAYLOAD(1042)) b_to_a (
    .clk(clk),.tx_rst(br),.rx_rst(ar),.tx_data(b_data),.tx_length(b_length),
    .tx_request(b_req),.tx_valid(b_valid),.tx_ready(b_net_ready),.tx_ack(b_net_ack),
    .rx_valid(a_rx_valid),.rx_data(a_rx_data),.rx_length(a_rx_length));
fixed_udp_test_link #(.SOURCE_IP(32'hc0a80a0b),.DEST_IP(32'hc0a80a0c),
    .SOURCE_MAC(48'h02000000000b),.DEST_MAC(48'h02000000000c),.MAX_PAYLOAD(18)) a_to_b (
    .clk(clk),.tx_rst(ar),.rx_rst(br),.tx_data(a_data),.tx_length(a_length),
    .tx_request(a_req),.tx_valid(a_valid),.tx_ready(a_net_ready),.tx_ack(a_net_ack),
    .rx_valid(b_rx_valid),.rx_data(b_rx_data),.rx_length(b_rx_length));
end else begin : direct_transport
assign a_net_ready=1'b1;assign a_net_ack=aa;
assign b_net_ready=1'b1;assign b_net_ack=ba;
assign a_rx_valid=b_valid;assign a_rx_data=b_data;assign a_rx_length=b_length;
assign b_rx_valid=a_valid;assign b_rx_data=a_data;assign b_rx_length=a_length;
end endgenerate
wire al_ready,al_ack,al_req,al_valid,bl_ready,bl_ack,bl_req,bl_valid;
wire [7:0] al_data,bl_data;
wire [15:0] al_length,bl_length;
media_link_session #(.ROLE(0),.HEARTBEAT_CYCLES(2500),.TIMEOUT_CYCLES(20000)) lease_a (
    .clk(clk),.rst(ar),.renew(1'b0),.rx_valid(a_rx_valid && a_rx_length==10),.rx_data(a_rx_data),.rx_length(a_rx_length),
    .udp_ready(al_ready),.udp_ack(al_ack),.udp_request(al_req),.udp_valid(al_valid),.udp_data(al_data),.udp_length(al_length),
    .ready(a_ready),.generation(ag),.restart(a_restart));
media_link_session #(.ROLE(1),.HEARTBEAT_CYCLES(2500),.TIMEOUT_CYCLES(20000)) lease_b (
    .clk(clk),.rst(br),.renew(1'b0),.rx_valid(b_rx_valid && b_rx_length==10),.rx_data(b_rx_data),.rx_length(b_rx_length),
    .udp_ready(bl_ready),.udp_ack(bl_ack),.udp_request(bl_req),.udp_valid(bl_valid),.udp_data(bl_data),.udp_length(bl_length),
    .ready(b_ready),.generation(bg),.restart(b_restart));
wire b_media_reset=br || !b_ready || b_restart;
reg [1:0] page;
reg preload_done;
reg [3:0] gap;
integer pixel_count=0,audio_source_count=0;
wire image_reset=b_media_reset || gap!=0 || preload_done;
wire image_source_ready,image_sent,audio_source_ready;
wire bi_ready,bi_ack,bi_req,bi_valid;
wire [7:0] bi_data;
wire [15:0] bi_length;
wire ir_valid;
wire [31:0] ir_token;
wire [15:0] ir_seq;
wire [23:0] source_rgb={6'd0,page,pixel_count[15:0]};
wire [7:0] source_tag=pixel_count[7:0]^{6'd0,page};
image_packet_tx #(.FRAME_PACKETS(1),.RELIABLE(1),.EXTERNAL_TOKEN(1),.UI_TAG(1),.RESOLUTION(1),.RETRY_CYCLES(6000)) image_tx (
    .clk(clk),.rst(image_reset),.source_valid(pixel_count<256 && !preload_done),.source_ready(image_source_ready),
    .source_rgb(source_rgb),.source_tag(source_tag),.source_frame_start(pixel_count==0),.source_frame_index(page),
    .source_top_down(1'b1),.source_resolution(32'h050003c0),.frame_token({bg,14'd0,page}+32'd1),
    .udp_ready(bi_ready),.udp_ack(bi_ack),.udp_request(bi_req),.udp_valid(bi_valid),.udp_data(bi_data),.udp_length(bi_length),
    .frame_sent(image_sent),.packets_sent(),.receipt_valid(ir_valid),.receipt_token(ir_token),.receipt_sequence(ir_seq),
    .transfer_token(),.packet_sequence());
image_receipt_rx image_receipts (
    .clk(clk),.rst(b_media_reset),.rx_valid(b_rx_valid && b_rx_length==12),.rx_data(b_rx_data),.rx_length(b_rx_length),
    .receipt_valid(ir_valid),.receipt_token(ir_token),.receipt_sequence(ir_seq));
always @(posedge clk or posedge b_media_reset) begin
    if(b_media_reset)begin page<=0;preload_done<=0;gap<=8;pixel_count<=0;audio_source_count<=0;end
    else begin
        if(gap!=0)gap<=gap-1'b1;
        if(image_source_ready && !image_reset && pixel_count<256)pixel_count<=pixel_count+1;
        if(image_sent)begin
            pixel_count<=0;gap<=8;
            if(page==3)preload_done<=1;else page<=page+1'b1;
        end
        if(audio_source_ready && preload_done && audio_source_count<512)audio_source_count<=audio_source_count+1;
    end
end
wire bp_ready,bp_ack,bp_req,bp_valid;
wire [7:0] bp_data;
wire [15:0] bp_length;
wire pr_valid;
wire [31:0] pr_session;
wire [15:0] pr_seq;
wire [31:0] song_session={bg,16'd1};
wire [31:0] sample_data=32'h12340000+audio_source_count;
audio_packet_tx #(.RETRY_CYCLES(6000)) audio_tx (
    .clk(clk),.rst(b_media_reset || !preload_done),.session_id(song_session),.file_samples(32'd512),
    .source_valid(preload_done && audio_source_count<512),.source_pcm(sample_data),.source_ready(audio_source_ready),
    .udp_ready(bp_ready),.udp_ack(bp_ack),.udp_request(bp_req),.udp_valid(bp_valid),.udp_data(bp_data),.udp_length(bp_length),
    .receipt_valid(pr_valid),.receipt_session(pr_session),.receipt_sequence(pr_seq),.sequence_no());
audio_receipt_rx #(.EXTENDED(1)) audio_receipts (
    .clk(clk),.rst(b_media_reset),.rx_valid(b_rx_valid && b_rx_length==18),.rx_data(b_rx_data),.rx_length(b_rx_length),
    .receipt_valid(pr_valid),.receipt_session(pr_session),.receipt_sequence(pr_seq),.played_words(),.volume_level(),.analysis_enable());
wire bm_ready,bm_ack,bm_req,bm_valid;
wire [7:0] bm_data;
wire [15:0] bm_length;
generate if(FLAT_SCHEDULER)begin : flat_b
wire [4:0] ready_channels,ack_channels;
assign {bl_ready,bp_ready}=ready_channels[4:3];
assign bi_ready=ready_channels[0];
assign {bl_ack,bp_ack}=ack_channels[4:3];
assign bi_ack=ack_channels[0];
media_udp_scheduler #(.CHANNELS(5),.MAX_LENGTH(1042)) scheduler (
    .clk(clk),.rst(br),.net_ready(b_net_ready),.net_ack(b_net_ack),.net_request(b_req),.net_valid(b_valid),.net_data(b_data),.net_length(b_length),
    .c_request({bl_req,bp_req,2'b00,bi_req}),.c_valid({bl_valid,bp_valid,2'b00,bi_valid}),
    .c_data({bl_data,bp_data,16'd0,bi_data}),.c_length({bl_length,bp_length,16'd12,16'd47,bi_length}),
    .c_ready(ready_channels),.c_ack(ack_channels));
end else begin : legacy_b
media_udp_arbiter b_media_mux (
    .clk(clk),.rst(br),.net_ready(bm_ready),.net_ack(bm_ack),.net_request(bm_req),.net_valid(bm_valid),.net_data(bm_data),.net_length(bm_length),
    .c0_request(bi_req),.c0_valid(bi_valid),.c0_data(bi_data),.c0_length(bi_length),.c0_ready(bi_ready),.c0_ack(bi_ack),
    .c1_request(bp_req),.c1_valid(bp_valid),.c1_data(bp_data),.c1_length(bp_length),.c1_ready(bp_ready),.c1_ack(bp_ack));
media_udp_arbiter b_link_mux (
    .clk(clk),.rst(br),.net_ready(b_net_ready),.net_ack(b_net_ack),.net_request(b_req),.net_valid(b_valid),.net_data(b_data),.net_length(b_length),
    .c0_request(bm_req),.c0_valid(bm_valid),.c0_data(bm_data),.c0_length(bm_length),.c0_ready(bm_ready),.c0_ack(bm_ack),
    .c1_request(bl_req),.c1_valid(bl_valid),.c1_data(bl_data),.c1_length(bl_length),.c1_ready(bl_ready),.c1_ack(bl_ack));
end endgenerate

wire ai_ready,ai_ack,ai_req,ai_valid,write_req,write_abort,write_en;
wire [7:0] ai_data;
wire [15:0] ai_length;
wire [31:0] write_data;
wire [1:0] write_index;
wire [3:0] cache;
reg writer_ack=0,finish_toggle=0,writer_active=0,finish_issued=0;
integer received_frame=0,finish_delay=0;
integer writes[0:3];
reg [3:0] protect_mask=1;
image_main_ingress #(.FRAME_PACKETS(1),.TIMEOUT_CYCLES(30000),.UI_TAG(1),.RESOLUTION(1),.SESSION_GUARD(1),.REUSE_CACHE(1)) ingress (
    .clk(clk),.rst(ar),.generation(ag),.restart_receive(!a_ready || a_restart),
    .rx_valid(a_rx_valid && a_rx_length==1042),.rx_data(a_rx_data),.rx_length(a_rx_length),
    .writer_ready(1'b1),.writer_ack(writer_ack),.writer_finish_toggle(finish_toggle),
    .protected_buffers(cache & protect_mask),.write_req(write_req),.write_abort(write_abort),.write_en(write_en),
    .write_data(write_data),.write_index(write_index),.write_top_down(),.cache_valid(cache),.source_resolutions(),
    .commit_toggle(),.fault(),.udp_ready(ai_ready),.udp_ack(ai_ack),.udp_request(ai_req),.udp_valid(ai_valid),.udp_data(ai_data),.udp_length(ai_length));
always @(posedge clk)begin
    aa<=a_req;ba<=b_req;writer_ack<=write_req && !write_abort;
    if(write_abort)begin writer_active<=0;received_frame<=0;finish_delay<=0;finish_issued<=0;end
    else begin
        if(write_req && !writer_active)begin writer_active<=1;received_frame<=0;finish_delay<=0;finish_issued<=0;end
        if(write_en)begin
            if(cache[write_index] && protect_mask[write_index])$fatal(1,"visible page overwritten after B reset");
            if(write_data!=={6'd0,write_index,received_frame[15:0],(received_frame[7:0]^{6'd0,write_index})})
                $fatal(1,"restart image word damaged idx=%0d p=%0d",write_index,received_frame);
            received_frame<=received_frame+1;writes[write_index]=writes[write_index]+1;
        end
        if(received_frame==256 && !finish_issued)begin
            finish_delay<=finish_delay+1;
            if(finish_delay==10)begin finish_toggle<=~finish_toggle;finish_issued<=1;end
        end
    end
end
wire ap_ready,ap_ack,ap_req,ap_valid,pcm_valid,stream_enable,fifo_reset,event_valid;
wire [7:0] ap_data;
wire [15:0] ap_length,event_seq;
wire [31:0] pcm_data,event_session,playing_session;
wire full,empty,read_sample,playing;
wire [8:0] wr_used,rd_used;
wire [31:0] fifo_data,played_words;
wire pcm_ready=!full && wr_used<=384;
audio_packet_rx #(.SESSION_GUARD(1)) audio_rx (
    .clk(clk),.rst(ar || !a_ready || a_restart),.generation(ag),.rx_valid(a_rx_valid && a_rx_length==530),.rx_data(a_rx_data),.rx_length(a_rx_length),
    .pcm_ready(pcm_ready),.pcm_valid(pcm_valid),.pcm_data(pcm_data),.stream_enable(stream_enable),.file_samples(),.stream_session(playing_session),
    .fifo_reset(fifo_reset),.receipt_event(event_valid),.receipt_session(event_session),.receipt_sequence(event_seq));
rfifo_32_32_512 #(.SHOW_AHEAD_EN(1'b1)) fifo (
    .clkw(clk),.clkr(audio_clk),.rst(fifo_reset),.we(pcm_valid && pcm_ready),.re(read_sample),.di(pcm_data),.dout(fifo_data),
    .valid(),.full_flag(full),.empty_flag(empty),.afull(),.aempty(),.wrusedw(wr_used),.rdusedw(rd_used));
wire [1:0] enable_sync;
media_audio_enable_cdc enable_cdc (.clk(audio_clk),.fifo_reset(fifo_reset),.stream_enable(stream_enable),.enable_sync(enable_sync));
hdmi_audio_pcm_i2s_64fs #(.START_LEVEL(256)) player (
    .I_mclk(audio_clk),.I_rst(ar),.I_enable(enable_sync[1]),.I_pcm_data(fifo_data),.I_pcm_empty(empty),.I_pcm_level(rd_used),.I_volume_level(4'd8),
    .O_pcm_read(read_sample),.O_i2s_BCLK(),.O_i2s_LRCK(),.O_i2s_DOUT(),.O_playing(playing),.O_underflow());
audio_playback_progress progress (
    .audio_clk(audio_clk),.udp_clk(clk),.rst(fifo_reset),.sample_read(read_sample && !empty),.played_words(played_words));
audio_receipt_tx #(.EXTENDED(1)) pcm_receipts (
    .clk(clk),.rst(ar || fifo_reset),.event_valid(event_valid),.event_session(event_session),.event_sequence(event_seq),.played_words(played_words),
    .volume_level(4'd8),.analysis_enable(1'b0),.udp_ready(ap_ready),.udp_ack(ap_ack),.udp_request(ap_req),
    .udp_valid(ap_valid),.udp_data(ap_data),.udp_length(ap_length));
wire am_ready,am_ack,am_req,am_valid;
wire [7:0] am_data;
wire [15:0] am_length;
generate if(FLAT_SCHEDULER)begin : flat_a
media_udp_scheduler #(.CHANNELS(3),.MAX_LENGTH(18)) scheduler (
    .clk(clk),.rst(ar),.net_ready(a_net_ready),.net_ack(a_net_ack),.net_request(a_req),.net_valid(a_valid),.net_data(a_data),.net_length(a_length),
    .c_request({al_req,ap_req,ai_req}),.c_valid({al_valid,ap_valid,ai_valid}),
    .c_data({al_data,ap_data,ai_data}),.c_length({al_length,ap_length,ai_length}),
    .c_ready({al_ready,ap_ready,ai_ready}),.c_ack({al_ack,ap_ack,ai_ack}));
end else begin : legacy_a
media_udp_arbiter a_media_mux (
    .clk(clk),.rst(ar),.net_ready(am_ready),.net_ack(am_ack),.net_request(am_req),.net_valid(am_valid),.net_data(am_data),.net_length(am_length),
    .c0_request(ai_req),.c0_valid(ai_valid),.c0_data(ai_data),.c0_length(ai_length),.c0_ready(ai_ready),.c0_ack(ai_ack),
    .c1_request(ap_req),.c1_valid(ap_valid),.c1_data(ap_data),.c1_length(ap_length),.c1_ready(ap_ready),.c1_ack(ap_ack));
media_udp_arbiter a_link_mux (
    .clk(clk),.rst(ar),.net_ready(a_net_ready),.net_ack(a_net_ack),.net_request(a_req),.net_valid(a_valid),.net_data(a_data),.net_length(a_length),
    .c0_request(am_req),.c0_valid(am_valid),.c0_data(am_data),.c0_length(am_length),.c0_ready(am_ready),.c0_ack(am_ack),
    .c1_request(al_req),.c1_valid(al_valid),.c1_data(al_data),.c1_length(al_length),.c1_ready(al_ready),.c1_ack(al_ack));
end endgenerate
integer played=0,i,round;
integer expected_writes[0:3];
reg [3:0] has_committed=0;
always @(posedge audio_clk or posedge fifo_reset)begin
    if(fifo_reset)played=0;
    else if(read_sample && !empty)begin
        if(fifo_data!==32'h12340000+played)$fatal(1,"restart plays duplicated/old PCM word %0d",played);
        played=played+1;
    end
end
always @(posedge clk)if(!ar)begin
    has_committed<=has_committed | cache;
    if((has_committed & protect_mask & ~cache)!=0)$fatal(1,"B restart removed visible image");
    if(ingress.fault)$fatal(1,"unexpected restart ingress fault");
end
reg [15:0] first_generation;
initial begin
    for(i=0;i<4;i=i+1)writes[i]=0;
    repeat(8)@(negedge clk);ar=0;br=0;
    wait(played==32);
    if(cache!=15 || !preload_done || ag!=bg)$fatal(1,"initial media preload incomplete");
    for(i=0;i<4;i=i+1)begin
        if(writes[i]!=256)$fatal(1,"initial page not fully written");expected_writes[i]=256;
    end
    for(round=0;round<5;round=round+1)begin
        @(negedge clk);protect_mask=round==4 ? 4'b0101 : (4'b0001<<round);
        first_generation=ag;br=1;repeat(8)@(negedge clk);br=0;
        wait(ag!=first_generation && a_ready && b_ready);
        wait(playing_session=={ag,16'd1});wait(played==(round==4?512:32));
        repeat(100)@(negedge clk);
        if(cache!=15 || !preload_done || played_words!=(round==4?512:32))$fatal(1,"restart/preload/audio recovery incomplete");
        for(i=0;i<4;i=i+1)begin
            if(!protect_mask[i])expected_writes[i]=expected_writes[i]+256;
            if(writes[i]!=expected_writes[i])$fatal(1,"wrong replay write count round=%0d idx=%0d got=%0d expected=%0d",round,i,writes[i],expected_writes[i]);
        end
    end
    if(USE_FIXED_UDP)$display("PASS fixed UDP media restart: framed LNK1/IMG4/AUD2/receipts, five B resets, protected caches, native FIFO and exact playback head");
    else if(FLAT_SCHEDULER)$display("PASS flat media restart: five B resets, protected caches, native FIFO and exact playback head");
    else $display("PASS media restart: actual LNK1 and packet arbiters, five B resets, each protected page and dual-frame mask, four-cache preload, native FIFO, 48kHz PCM restart and exact playback head");$finish;
end
initial begin #40000000;$fatal(1,"media restart timeout page=%0d cache=%b A=%0d B=%0d played=%0d",page,cache,ag,bg,played);end
endmodule

module tb_media_restart_flat;
tb_media_restart #(.FLAT_SCHEDULER(1)) test();
endmodule

module tb_media_restart_fixed;
tb_media_restart #(.FLAT_SCHEDULER(1),.USE_FIXED_UDP(1)) test();
endmodule
