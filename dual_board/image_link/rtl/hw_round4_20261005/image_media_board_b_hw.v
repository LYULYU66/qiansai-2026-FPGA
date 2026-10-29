`timescale 1ns/1ps
// TF + reliable image/PCM Ethernet B-board top. Pair with an IMG4/AUD2 main-board
// receiver, never with the old IMGF pattern-test A bit.
module image_media_board_b (
    input wire clk_50, sys_rst_n,
    input wire uart_rx,
    output wire uart_tx,
    input wire phy1_rgmii_rx_clk, phy1_rgmii_rx_ctl,
    input wire [3:0] phy1_rgmii_rx_data,
    output wire phy1_rgmii_tx_clk, phy1_rgmii_tx_ctl,
    output wire [3:0] phy1_rgmii_tx_data,
    output wire SD_nCS, SD_DCLK, SD_MOSI,
    input wire SD_MISO,
    output wire [3:0] led
);
wire sd_clk, pll_lock, udp_clk, compute_clk, network_reset;
sys_pll u_sd_clock (
    .refclk(clk_50),.reset(~sys_rst_n),.extlock(pll_lock),
    .clk0_out(sd_clk),.clk1_out(),.clk2_out()
);
wire tx_ready, tx_ack, tx_request, tx_valid, rx_valid;
wire [7:0] tx_data, rx_data;
wire [15:0] tx_length, rx_length, rx_port;
dual_board_eth_transport #(.ROLE(1),.UDP_PORT(16'h5002),.FIXED_PEER(1)) u_net (
    .clk_50(clk_50),.sys_rst_n(sys_rst_n),
    .phy1_rgmii_rx_clk(phy1_rgmii_rx_clk),.phy1_rgmii_rx_ctl(phy1_rgmii_rx_ctl),
    .phy1_rgmii_rx_data(phy1_rgmii_rx_data),.phy1_rgmii_tx_clk(phy1_rgmii_tx_clk),
    .phy1_rgmii_tx_ctl(phy1_rgmii_tx_ctl),.phy1_rgmii_tx_data(phy1_rgmii_tx_data),
    .udp_clk(udp_clk),.reset(network_reset),.tx_ready_app(tx_ready),
    .tx_ack_app(tx_ack),.tx_request_app(tx_request),.tx_valid_app(tx_valid),
    .tx_data_app(tx_data),.tx_length_app(tx_length),.rx_valid_app(rx_valid),
    .rx_data_app(rx_data),.rx_length_app(rx_length),.rx_port_app(rx_port),
    .media_video_clk(compute_clk)
);
wire base_request=network_reset || !pll_lock;
wire base_reset,pc_reset;
player_domain_reset u_base_reset (.clk(udp_clk),.request(base_request),.rst(base_reset));
player_domain_reset u_pc_reset (.clk(clk_50),.request(base_request),.rst(pc_reset));
wire link_ready,link_restart,link_tx_ready,link_tx_ack,link_request,link_valid;
wire [15:0] link_generation,link_length;
wire [7:0] link_data;
wire generation_exhausted;
wire [31:0] audio_session;
wire media_request=base_request || !link_ready || link_restart;
wire media_reset,media_sd_reset;
player_domain_reset u_media_reset (.clk(udp_clk),.request(media_request),.rst(media_reset));
player_domain_reset u_media_sd_reset (.clk(sd_clk),.request(media_request),.rst(media_sd_reset));
media_link_session #(.ROLE(1)) u_link_session (
    .clk(udp_clk),.rst(base_reset),.renew(generation_exhausted || audio_session[15:0]==16'hffff),
    .rx_valid(rx_valid && rx_port==16'h5002 && rx_length==10),
    .rx_data(rx_data),.rx_length(rx_length),
    .udp_ready(link_tx_ready),.udp_ack(link_tx_ack),.udp_request(link_request),
    .udp_valid(link_valid),.udp_data(link_data),.udp_length(link_length),
    .ready(link_ready),.generation(link_generation),.restart(link_restart)
);
wire [3:0] control_volume;
wire [1:0] control_brightness,control_contrast;
wire [7:0] control_settings;
uart_audio_control #(.CLK_FREQ_HZ(50_000_000),.BAUD_RATE(115_200)) u_pc_control (
    .I_clk(clk_50),.I_rst_n(~pc_reset),.I_uart_rx(uart_rx),.O_uart_tx(uart_tx),
    .O_volume_level(control_volume),.O_brightness_level(control_brightness),
    .O_contrast_level(control_contrast),.O_rx_error()
);
audio_visual_cdc #(.WIDTH(8),.FRAME_BOUNDARY(0),.RESET_STATE(8'h38)) u_control_source (
    .udp_clk(clk_50),.video_clk(udp_clk),.rst(base_request),.frame_vs(1'b0),
    .update_valid(1'b0),.publish_enable(1'b1),
    .visual_state({control_contrast,control_brightness,control_volume}),
    .frame_state(control_settings),.capture_valid()
);
wire control_ready,control_ack,control_request,control_valid;
wire [7:0] control_data;
wire [15:0] control_length;
media_control_tx u_control_packets (
    .clk(udp_clk),.rst(base_reset),.settings(control_settings),
    .udp_ready(control_ready),.udp_ack(control_ack),.udp_request(control_request),
    .udp_valid(control_valid),.udp_data(control_data),.udp_length(control_length)
);
wire [3:0] state_code, image_number;
wire overflow;
wire image_ready, image_ack, image_request, image_valid;
wire [7:0] image_data;
wire [15:0] image_length;
wire pcm_write, stream_enable, pcm_full, pcm_empty, pcm_read;
wire [31:0] pcm_write_data, pcm_data, file_bytes;
wire [8:0] pcm_wr_used;
reg sector_ready;
always @(posedge sd_clk or posedge media_sd_reset) begin
    if(media_sd_reset) sector_ready<=0;
    else sector_ready<=!pcm_full && pcm_wr_used<=9'd256;
end
image_tf_source #(.SESSION_GUARD(1)) u_media (
    .sd_clk(sd_clk),.udp_clk(udp_clk),.rst(media_request),
    .generation(link_generation),.generation_exhausted(generation_exhausted),
    .key_next(1'b1),.key_auto(1'b1),.SD_nCS(SD_nCS),.SD_DCLK(SD_DCLK),
    .SD_MOSI(SD_MOSI),.SD_MISO(SD_MISO),.udp_ready(image_ready),.udp_ack(image_ack),
    .udp_request(image_request),.udp_valid(image_valid),.udp_data(image_data),.udp_length(image_length),
    .rx_valid(rx_valid && rx_port==16'h5002),.rx_data(rx_data),.rx_length(rx_length),
    .state_code(state_code),.image_number(image_number),.source_resolutions(),.overflow(overflow),
    .audio_fifo_ready(sector_ready),.audio_pcm_wr_en(pcm_write),.audio_pcm_data(pcm_write_data),
    .audio_stream_enable(stream_enable),.audio_file_bytes(file_bytes)
);
// Reuse the proven SD-sector FIFO. There is no full-song audio storage.
rfifo_32_32_512 #(.SHOW_AHEAD_EN(1'b1)) u_pcm_source_fifo (
    .clkw(sd_clk),.clkr(udp_clk),.rst(media_request || !stream_enable),
    .we(pcm_write),.re(pcm_read),.di(pcm_write_data),.dout(pcm_data),
    .valid(),.full_flag(pcm_full),.empty_flag(pcm_empty),.afull(),.aempty(),
    .wrusedw(pcm_wr_used),.rdusedw()
);
wire stream_active;
wire [31:0] file_samples_udp;
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
audio_receipt_rx #(.EXTENDED(1)) u_audio_receipts (
    .clk(udp_clk),.rst(media_reset),.rx_valid(rx_valid && rx_port==16'h5002 && rx_length==18),
    .rx_data(rx_data),.rx_length(rx_length),.receipt_valid(receipt_valid),
    .receipt_session(receipt_session),.receipt_sequence(receipt_sequence),.played_words(remote_played_words),
    .volume_level(remote_volume),.analysis_enable(remote_analysis_enable)
);
audio_packet_tx u_audio_packets (
    .clk(udp_clk),.rst(compute_reset),
    .session_id(audio_session),.file_samples(file_samples_udp),
    .source_valid(!pcm_empty && stream_active && history_ready),.source_pcm(pcm_data),.source_ready(source_ready),
    .udp_ready(audio_ready),.udp_ack(audio_ack),.udp_request(audio_request),
    .udp_valid(audio_valid),.udp_data(audio_data),.udp_length(audio_length),
    .receipt_valid(receipt_valid),.receipt_session(receipt_session),
    .receipt_sequence(receipt_sequence),.sequence_no()
);
assign pcm_read=source_ready && !pcm_empty && stream_active && history_ready;
wire [263:0] computed_visual;
wire [31:0] analysed_words;
wire compute_settled;
remote_audio_compute u_remote_compute (
    .udp_clk(udp_clk),.clk(compute_clk),.rst(compute_reset),
    .session_id(audio_session),.file_samples(file_samples_udp),
    .source_valid(pcm_read),.source_pcm(pcm_data),.source_ready(history_ready),
    .feedback_valid(receipt_valid),.feedback_session(receipt_session),.feedback_played(remote_played_words),
    .feedback_volume(remote_volume),.feedback_enable(remote_analysis_enable),
    .visual_state(computed_visual),.analysed_words(analysed_words),.settled(compute_settled)
);
// Compute runs on the existing 25 MHz Ethernet PLL output (no extra PLL).
// Send only complete, settled states to the 125 MHz packet domain.
wire [295:0] visual_snapshot;
wire snapshot_valid;
reg have_snapshot;
audio_visual_cdc #(.WIDTH(296),.FRAME_BOUNDARY(0)) u_compute_snapshot (
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
audio_visual_tx u_visual_packets (
    .clk(udp_clk),.rst(compute_reset),.source_settled(have_snapshot),
    .session_id(audio_session),.analysed_words(visual_snapshot[295:264]),.visual_state(visual_snapshot[263:0]),
    .udp_ready(visual_ready),.udp_ack(visual_ack),.udp_request(visual_request),
    .udp_valid(visual_valid),.udp_data(visual_data),.udp_length(visual_length)
);
// LINK > PCM > control > visual state > image, at packet boundaries only.
// Base reset owns the scheduler: media-session reset drains a poisoned packet
// rather than abandoning an accepted length inside the encrypted UDP core.
media_udp_scheduler #(.CHANNELS(5),.MAX_LENGTH(1042)) u_packet_scheduler (
    .clk(udp_clk),.rst(base_reset),.net_ready(tx_ready),.net_ack(tx_ack),
    .net_request(tx_request),.net_valid(tx_valid),.net_data(tx_data),.net_length(tx_length),
    .c_request({link_request,audio_request,control_request,visual_request,image_request}),
    .c_valid({link_valid,audio_valid,control_valid,visual_valid,image_valid}),
    .c_data({link_data,audio_data,control_data,visual_data,image_data}),
    .c_length({link_length,audio_length,control_length,visual_length,image_length}),
    .c_ready({link_tx_ready,audio_ready,control_ready,visual_ready,image_ready}),
    .c_ack({link_tx_ack,audio_ack,control_ack,visual_ack,image_ack})
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
