`timescale 1ns/1ps
// TF + reliable image/PCM Ethernet B-board top. Pair with an IMG4/AUD2 main-board
// receiver, never with the old IMGF pattern-test A bit.
module image_media_board_b (
    input wire clk_50, sys_rst_n,
    input wire key_send_n,
    input wire key_song_n,      // Board KEY4/C1: next song (song-list page only)
    input wire sw_music,        // Board SW1/C8: 1=play (turn-on shows music pages), 0=pause
    input wire sw_photo,        // Board SW2/C7: 1=A shows only the photo + top-left readout
    input wire phy1_rgmii_rx_clk, phy1_rgmii_rx_ctl,
    input wire [3:0] phy1_rgmii_rx_data,
    output wire phy1_rgmii_tx_clk, phy1_rgmii_tx_ctl,
    output wire [3:0] phy1_rgmii_tx_data,
    output wire SD_nCS, SD_DCLK, SD_MOSI,
    input wire SD_MISO,
    output wire [3:0] led,
    output wire HDMI_DDC_SCL,
    inout wire HDMI_DDC_SDA,
    output wire HDMI_CLK_P, HDMI_D0_P, HDMI_D1_P, HDMI_D2_P
);
// B owns the local TF pages 5/6/7.  Page 0 is the power-up dashboard,
// page 1 is the star/entertainment companion, and page 2 is the lyric/
// spectrum companion.
localparam [1:0] PREVIEW_INDEX=2'd0;
wire sd_clk, pll_lock, udp_clk, compute_clk, network_reset;
wire mem_clk,mem_shift_clk,hdmi_5x_clk;
sys_pll_b u_sd_clock (
    .refclk(clk_50),.reset(~sys_rst_n),.extlock(pll_lock),
    .clk0_out(sd_clk),.clk1_out(mem_clk),.clk2_out(mem_shift_clk)
);
wire tx_ready, tx_ack, tx_request, tx_valid, rx_valid;
wire [7:0] tx_data, rx_data;
wire [15:0] tx_length, rx_length, rx_port;
// 20261021: udp_clk is 62.5 MHz on B (pll_gen_b.v); every udp_clk interval
// below is given for 62.5 MHz so the real times match A and earlier builds.
dual_board_eth_transport #(.ROLE(1),.UDP_PORT(16'h5002),.FIXED_PEER(1),
                          .APP_CLK_HZ(62_500_000),.SEPARATE_5X(1)) u_net (
    .clk_50(clk_50),.sys_rst_n(sys_rst_n),
    .phy1_rgmii_rx_clk(phy1_rgmii_rx_clk),.phy1_rgmii_rx_ctl(phy1_rgmii_rx_ctl),
    .phy1_rgmii_rx_data(phy1_rgmii_rx_data),.phy1_rgmii_tx_clk(phy1_rgmii_tx_clk),
    .phy1_rgmii_tx_ctl(phy1_rgmii_tx_ctl),.phy1_rgmii_tx_data(phy1_rgmii_tx_data),
    .udp_clk(udp_clk),.reset(network_reset),.tx_ready_app(tx_ready),
    .tx_ack_app(tx_ack),.tx_request_app(tx_request),.tx_valid_app(tx_valid),
    .tx_data_app(tx_data),.tx_length_app(tx_length),.rx_valid_app(rx_valid),
    .rx_data_app(rx_data),.rx_length_app(rx_length),.rx_port_app(rx_port),
    .media_video_clk(compute_clk),.media_5x_clk(hdmi_5x_clk),.media_clock_ready()
);
wire base_request=network_reset || !pll_lock;
wire base_reset;
player_domain_reset u_base_reset (.clk(udp_clk),.request(base_request),.rst(base_reset));
// The switch is sampled in the 50 MHz board domain, then synchronized into
// the 62.5 MHz application clock.  It is a level control, so no pulse or
// high-fanout asynchronous path is created.
(* async_reg="true" *) reg [1:0] music_sw_board, photo_sw_board;
always @(posedge clk_50 or negedge sys_rst_n) begin
    if(!sys_rst_n) begin music_sw_board<=2'b00; photo_sw_board<=2'b00; end
    else begin
        music_sw_board<={music_sw_board[0],sw_music};
        photo_sw_board<={photo_sw_board[0],sw_photo};
    end
end
(* async_reg="true" *) reg [1:0] music_sw_udp, photo_sw_udp;
always @(posedge udp_clk or posedge base_reset) begin
    if(base_reset) begin music_sw_udp<=2'b00; photo_sw_udp<=2'b00; end
    else begin
        music_sw_udp<={music_sw_udp[0],music_sw_board[1]};
        photo_sw_udp<={photo_sw_udp[0],photo_sw_board[1]};
    end
end
wire music_run_udp=music_sw_udp[1];
// SW2 is only forwarded to A (VIZ2 tag bit 30); nothing on B uses it.
wire photo_only_udp=photo_sw_udp[1];
wire link_ready,link_restart,link_tx_ready,link_tx_ack,link_request,link_valid;
wire [15:0] link_generation,link_length;
wire [7:0] link_data;
wire generation_exhausted;
wire [31:0] audio_session;
// Star sky (20261020): A runs the motion engine and sends its bundle to B in
// CTL4 every 250 us; B renders the right half (x 640..1279) of the same sky.
wire [75:0] star_bundle;
wire star_toggle, star_hazard;
media_control_star_rx u_star_rx (
    .clk(udp_clk),.rst(base_reset),
    .rx_valid(rx_valid && rx_port==16'h5002 && rx_length==16),
    .rx_data(rx_data),.rx_length(rx_length),
    .star_bundle(star_bundle),.bundle_toggle(star_toggle),.hazard(star_hazard));
// 20261021: A's safety warning (SW1..SW4) arrives in every CTL4 packet.
// It is dropped if no packet has been accepted for 16.8 ms (2^20 clocks at
// 62.5 MHz; CTL4 arrives every 250 us), i.e. when the link is lost.
reg [20:0] star_age;
reg star_toggle_q, hazard_udp;
always @(posedge udp_clk or posedge base_reset) begin
    if(base_reset) begin star_age<=0; star_toggle_q<=0; hazard_udp<=0; end
    else begin
        star_toggle_q<=star_toggle;
        if(star_toggle_q!=star_toggle) star_age<=0;
        else if(!star_age[20]) star_age<=star_age+1'b1;
        hazard_udp<=star_hazard && !star_age[20];
    end
end
wire media_request=base_request || !link_ready || link_restart;
// Keep local TF5/TF6/TF7 preview alive before Ethernet is ready. Network
// pixels are separately held by image_tf_source until link_ready, so their
// reliable token always uses the current A/B generation.
wire image_media_request=base_request || link_restart;
wire media_reset,media_sd_reset;
player_domain_reset u_media_reset (.clk(udp_clk),.request(media_request),.rst(media_reset));
player_domain_reset u_media_sd_reset (.clk(sd_clk),.request(media_request),.rst(media_sd_reset));
media_link_session #(.ROLE(1),.PIPELINE_RX(1),
                     .HEARTBEAT_CYCLES(6_250_000),.TIMEOUT_CYCLES(31_250_000)) u_link_session (
    .clk(udp_clk),.rst(base_reset),.renew(generation_exhausted || audio_session[15:0]==16'hffff),
    .rx_valid(rx_valid && rx_port==16'h5002 && rx_length==10),
    .rx_data(rx_data),.rx_length(rx_length),
    .udp_ready(link_tx_ready),.udp_ack(link_tx_ack),.udp_request(link_request),
    .udp_valid(link_valid),.udp_data(link_data),.udp_length(link_length),
    .ready(link_ready),.generation(link_generation),.restart(link_restart)
);
// B no longer sends control packets: A owns the picture/sound settings
// (local keys) and the star-sky engine since 20261020.
wire [3:0] state_code, image_number;
wire overflow;
wire image_ready, image_ack, image_request, image_valid;
wire [7:0] image_data;
wire [15:0] image_length;
wire pcm_write, stream_enable, pcm_full, pcm_empty, pcm_read;
wire [31:0] pcm_write_data, pcm_data, file_bytes;
wire [8:0] pcm_wr_used;
reg sector_ready;
// 20261019: link_ready is a udp_clk register (other PLL). It used to drive
// the TF reader's audio-ready input directly; synchronise it first.
(* async_reg="true" *) reg [1:0] link_ready_sd;
always @(posedge sd_clk or posedge media_sd_reset) begin
    if(media_sd_reset) begin sector_ready<=0; link_ready_sd<=0; end
    else begin
        sector_ready<=!pcm_full && pcm_wr_used<=9'd256;
        link_ready_sd<={link_ready_sd[0],link_ready};
    end
end
reg [2:0] requested_song_udp;
reg [1:0] requested_page_udp;
(* async_reg="true" *) reg [5:0] song_request_sd;
always @(posedge sd_clk or posedge media_sd_reset) begin
    if(media_sd_reset) song_request_sd<=0;
    else song_request_sd<={song_request_sd[2:0],requested_song_udp};
end
wire preview_ready,preview_start,preview_top,preview_abort,preview_valid;
wire [2:0] preview_index;
wire [23:0] preview_rgb;
wire [7:0] preview_tag;
wire preview_finish;
// A page numbers are zero-based: A#1=0, A#2=1 (lyrics/spectrum),
// A#3=2 (star entertainment). Map them to B's local TF#5/#6/#7 pages.
function [1:0] b_page_for_a_page;
    input [1:0] a_page;
    begin
        case (a_page)
            2'd1:    b_page_for_a_page=2'd2; // A#2 -> B#7
            2'd2:    b_page_for_a_page=2'd1; // A#3 -> B#6
            default: b_page_for_a_page=2'd0; // power-up/A#1 -> B#5
        endcase
    end
endfunction
// A safety warning always brings the dashboard (TF5) to the B screen.
// SW1 is not forced here: A jumps to its music page once when SW1 turns on,
// and B follows A's reported page to the song list (TF7) as for a key press.
wire [1:0] preview_target = hazard_udp ? 2'd0 : b_page_for_a_page(requested_page_udp);
image_tf_source #(.SESSION_GUARD(1),.DUAL_SONG(1),.LOCAL_PREVIEW(1),.LOCAL_PAIR(1),.LOCAL_FIRST(1),
                    .PREVIEW_INDEX(PREVIEW_INDEX)) u_media (
    .sd_clk(sd_clk),.udp_clk(udp_clk),.rst(image_media_request),
    .generation(link_generation),.network_ready(link_ready),.generation_exhausted(generation_exhausted),
    .key_next(1'b1),.key_auto(1'b1),.SD_nCS(SD_nCS),.SD_DCLK(SD_DCLK),
    .SD_MOSI(SD_MOSI),.SD_MISO(SD_MISO),.udp_ready(image_ready),.udp_ack(image_ack),
    .udp_request(image_request),.udp_valid(image_valid),.udp_data(image_data),.udp_length(image_length),
    .rx_valid(rx_valid && rx_port==16'h5002),.rx_data(rx_data),.rx_length(rx_length),
    .state_code(state_code),.image_number(image_number),.source_resolutions(),.overflow(overflow),
    .audio_fifo_ready(sector_ready && link_ready_sd[1]),.audio_pcm_wr_en(pcm_write),.audio_pcm_data(pcm_write_data),
    .audio_song_request(song_request_sd[5:3]),
    .preview_target(preview_target),
    .audio_stream_enable(stream_enable),.audio_file_bytes(file_bytes),
    .preview_ready(preview_ready),.preview_start(preview_start),.preview_index(preview_index),
    .preview_top_down(preview_top),.preview_abort(preview_abort),
    .preview_valid(preview_valid),.preview_rgb(preview_rgb),.preview_tag(preview_tag),
    .preview_finish(preview_finish)
);
// Song being played: taken from the lyric compute block, which already
// decodes it in compute_clk (= B's HDMI pixel clock).  No new UDP-domain
// logic or clock crossing is added for the song-list highlight.
wire [3:0] playing_song_compute;
wire stream_active;
wire [31:0] file_samples_udp;
b_hdmi_preview #(.PREVIEW_INDEX(PREVIEW_INDEX)) u_local_hdmi (
    .udp_clk(udp_clk),.mem_clk(mem_clk),.mem_shift_clk(mem_shift_clk),
    .video_clk(compute_clk),.serial_clk(hdmi_5x_clk),.reset_request(base_request),
    .star_bundle_udp(star_bundle),.star_toggle_udp(star_toggle),.hazard_udp(hazard_udp),
    .gauge_key_n(key_send_n),
    .playing_song_video(playing_song_compute),
    .source_start(preview_start),.preview_target(preview_target),.source_index(preview_index),
    .source_top_down(preview_top),.source_abort(preview_abort),
    .pixel_valid(preview_valid),.pixel_rgb(preview_rgb),.pixel_tag(preview_tag),.pixel_ready(preview_ready),
    .preview_finish(preview_finish),
    .HDMI_DDC_SCL(HDMI_DDC_SCL),.HDMI_DDC_SDA(HDMI_DDC_SDA),
    .HDMI_CLK_P(HDMI_CLK_P),.HDMI_D0_P(HDMI_D0_P),
    .HDMI_D1_P(HDMI_D1_P),.HDMI_D2_P(HDMI_D2_P)
);
// Reuse the proven SD-sector FIFO. There is no full-song audio storage.
rfifo_32_32_512 #(.SHOW_AHEAD_EN(1'b1)) u_pcm_source_fifo (
    .clkw(sd_clk),.clkr(udp_clk),.rst(media_request || !stream_enable),
    .we(pcm_write),.re(pcm_read),.di(pcm_write_data),.dout(pcm_data),
    .valid(),.full_flag(pcm_full),.empty_flag(pcm_empty),.afull(),.aempty(),
    .wrusedw(pcm_wr_used),.rdusedw()
);
player_audio_session u_audio_session (
    .clk(udp_clk),.rst(media_reset),.stream_async(stream_enable),.generation(link_generation),
    .file_bytes_async(file_bytes),.stream_active(stream_active),
    .session_id(audio_session),.file_samples(file_samples_udp)
);
wire compute_request=media_request || !stream_active;
wire compute_reset;
player_domain_reset u_stream_reset (.clk(udp_clk),.request(compute_request),.rst(compute_reset));
wire audio_ready, audio_ack, audio_request, audio_valid, source_ready;
wire [7:0] audio_data;
wire [15:0] audio_length, receipt_sequence;
wire receipt_valid;
wire [31:0] receipt_session;
wire [31:0] remote_played_words;
wire [3:0] remote_volume;
wire remote_analysis_enable, history_ready;
wire [2:0] remote_song_request;
wire [1:0] remote_page_request;
always @(posedge udp_clk or posedge media_reset) begin
    if(media_reset) requested_page_udp<=0;
    else if(receipt_valid) requested_page_udp<=remote_page_request;
end
// 20261020: songs are selected on B with KEY4, and only while A shows the
// lyrics/spectrum page (A page 1), i.e. while this HDMI shows the song list.
// The choice survives link/media restarts; only a board reset clears it.
// A's receipt song field is no longer used by this board.
wire song_key_press;
key_press_debounce #(.CLK_FREQ_HZ(62_500_000),.DEBOUNCE_MS(20)) u_song_key (
    .clk(udp_clk),.rst(base_reset),.button_in(key_song_n),.press_pulse(song_key_press)
);
always @(posedge udp_clk or posedge base_reset) begin
    if(base_reset) requested_song_udp<=0;
    else if(song_key_press && requested_page_udp==2'd1)
        requested_song_udp<=(requested_song_udp==3'd5) ? 3'd0 : requested_song_udp+3'd1;
end
audio_receipt_rx #(.EXTENDED(1),.SONG_CONTROL(1)) u_audio_receipts (
    .clk(udp_clk),.rst(media_reset),.rx_valid(rx_valid && rx_port==16'h5002 && rx_length==18),
    .rx_data(rx_data),.rx_length(rx_length),.receipt_valid(receipt_valid),
    .receipt_session(receipt_session),.receipt_sequence(receipt_sequence),.played_words(remote_played_words),
    .volume_level(remote_volume),.analysis_enable(remote_analysis_enable),.requested_song(remote_song_request),
    .requested_page(remote_page_request)
);
audio_packet_tx #(.RETRY_CYCLES(62_500)) u_audio_packets (
    .clk(udp_clk),.rst(compute_reset),
    .session_id(audio_session),.file_samples(file_samples_udp),
    .source_valid(!pcm_empty && stream_active && history_ready && music_run_udp),.source_pcm(pcm_data),.source_ready(source_ready),
    .udp_ready(audio_ready),.udp_ack(audio_ack),.udp_request(audio_request),
    .udp_valid(audio_valid),.udp_data(audio_data),.udp_length(audio_length),
    .receipt_valid(receipt_valid),.receipt_session(receipt_session),
    .receipt_sequence(receipt_sequence),.sequence_no()
);
assign pcm_read=source_ready && !pcm_empty && stream_active && history_ready && music_run_udp;
wire [263:0] computed_visual;
wire [31:0] analysed_words;
wire compute_settled;
remote_audio_compute u_remote_compute (
    .udp_clk(udp_clk),.clk(compute_clk),.rst(compute_reset),
    .session_id(audio_session),.file_samples(file_samples_udp),
    .source_valid(pcm_read),.source_pcm(pcm_data),.source_ready(history_ready),
    .feedback_valid(receipt_valid),.feedback_session(receipt_session),.feedback_played(remote_played_words),
    .feedback_volume(remote_volume),.feedback_enable(remote_analysis_enable),
    .visual_state(computed_visual),.analysed_words(analysed_words),.settled(compute_settled),
    .playing_song(playing_song_compute)
);
// Compute runs on the existing 25 MHz Ethernet PLL output (no extra PLL).
// Send only complete, settled states to the 125 MHz packet domain.
wire [295:0] visual_snapshot;
wire snapshot_valid;
reg have_snapshot;
audio_visual_cdc #(.WIDTH(296),.FRAME_BOUNDARY(0),.DATA_RESET(0)) u_compute_snapshot (
    .udp_clk(compute_clk),.video_clk(udp_clk),.rst(compute_request),.frame_vs(1'b0),
    .update_valid(1'b0),.publish_enable(compute_settled),
    .visual_state({analysed_words,computed_visual}),.frame_state(visual_snapshot),.capture_valid(snapshot_valid)
);
always @(posedge udp_clk or posedge compute_reset) begin
    if(compute_reset) have_snapshot<=0;
    else if(snapshot_valid) have_snapshot<=1;
end
wire visual_ready, visual_ack, visual_request, visual_valid;
wire [7:0] visual_data;
wire [15:0] visual_length;
audio_visual_tx #(.UPDATE_CYCLES(1_041_667)) u_visual_packets (
    .clk(udp_clk),.rst(compute_reset),.source_settled(have_snapshot),
    .session_id(audio_session),.analysed_words({music_run_udp,photo_only_udp,visual_snapshot[293:264]}),
    .visual_state(visual_snapshot[263:0]),
    .udp_ready(visual_ready),.udp_ack(visual_ack),.udp_request(visual_request),
    .udp_valid(visual_valid),.udp_data(visual_data),.udp_length(visual_length)
);
// LINK > PCM > visual state > image, at packet boundaries only.
// Base reset owns the scheduler: media-session reset drains a poisoned packet
// rather than abandoning an accepted length inside the encrypted UDP core.
media_udp_scheduler #(.CHANNELS(4),.MAX_LENGTH(1042)) u_packet_scheduler (
    .clk(udp_clk),.rst(base_reset),.net_ready(tx_ready),.net_ack(tx_ack),
    .net_request(tx_request),.net_valid(tx_valid),.net_data(tx_data),.net_length(tx_length),
    .c_request({link_request,audio_request,visual_request,image_request}),
    .c_valid({link_valid,audio_valid,visual_valid,image_valid}),
    .c_data({link_data,audio_data,visual_data,image_data}),
    .c_length({link_length,audio_length,visual_length,image_length}),
    .c_ready({link_tx_ready,audio_ready,visual_ready,image_ready}),
    .c_ack({link_tx_ack,audio_ack,visual_ack,image_ack})
);
reg [25:0] heart_count;
reg [1:0] complete_sync, busy_sync;
always @(posedge udp_clk or posedge media_reset) begin
    if(media_reset) begin heart_count<=0; complete_sync<=0; busy_sync<=0; end
    else begin
        heart_count<=heart_count+1'b1;
        complete_sync<={complete_sync[0],image_number!=0};
        busy_sync<={busy_sync[0],state_code!=0};
    end
end
assign led={overflow,complete_sync[1],busy_sync[1],heart_count[25]};
endmodule
