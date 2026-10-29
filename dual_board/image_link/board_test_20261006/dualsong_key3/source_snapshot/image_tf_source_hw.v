`timescale 1ns/1ps
// B media-source component. SD stays at the original 100 MHz; the Ethernet
// application interface stays at 125 MHz. A final ACK replaces the old local
// SDRAM write_finish. The isolated wrapper only exposes live BMP dimensions;
// the single-board SD/FAT/PCM/resample implementation is unchanged.
module image_tf_source #(parameter integer SESSION_GUARD=0, parameter DUAL_SONG=0) (
    input wire sd_clk, udp_clk, rst,
    input wire [15:0] generation,
    output wire generation_exhausted,
    input wire key_next, key_auto,
    output wire SD_nCS, SD_DCLK, SD_MOSI,
    input wire SD_MISO,
    input wire udp_ready, udp_ack,
    output wire udp_request, udp_valid,
    output wire [7:0] udp_data,
    output wire [15:0] udp_length,
    input wire rx_valid,
    input wire [7:0] rx_data,
    input wire [15:0] rx_length,
    output wire [3:0] state_code, image_number,
    output wire [127:0] source_resolutions,
    output wire overflow,
    input wire audio_fifo_ready,
    input wire audio_song_request,
    output wire audio_pcm_wr_en, audio_stream_enable,
    output wire [31:0] audio_pcm_data, audio_file_bytes
);
wire write_req, write_en, top_down, load_abort, fifo_ready;
wire [31:0] write_data;
wire [1:0] write_index;
reg write_ack, source_active, start_toggle;
reg [1:0] index_latched;
reg top_latched;
reg [31:0] resolution_latched;
wire [31:0] live_source_resolution;
reg finish_toggle;
wire frame_sent;
wire bridge_reset=rst || load_abort;
wire source_sd_reset,source_udp_reset,bridge_sd_reset,bridge_udp_reset;
player_domain_reset u_source_sd_reset (.clk(sd_clk),.request(rst),.rst(source_sd_reset));
player_domain_reset u_source_udp_reset (.clk(udp_clk),.request(rst),.rst(source_udp_reset));
player_domain_reset u_bridge_sd_reset (.clk(sd_clk),.request(bridge_reset),.rst(bridge_sd_reset));
player_domain_reset u_bridge_udp_reset (.clk(udp_clk),.request(bridge_reset),.rst(bridge_udp_reset));
sd_card_bmp_remote #(.CLK_FREQ_HZ(100_000_000),.ENABLE_RESAMPLE(1),
             .PIPELINED_CLUSTER_ADDR(1),.FAST_AUDIO_START(0),.DUAL_SONG(DUAL_SONG)) u_tf (
    .clk(sd_clk),.rst(source_sd_reset),.key_next(key_next),.key_auto(key_auto),
    .I_warning_hold(1'b0),.bmp_width(16'd640),.bmp_height(16'd480),
    .display_valid(),.warning_image_ready(),.state_code(state_code),
    .image_number(image_number),.write_finish_toggle(finish_toggle),
    .write_buf_idx(write_index),.disp_buf_idx(),.load_abort(load_abort),
    .write_req(write_req),.write_req_ack(write_ack),
    .write_en(write_en),.write_data(write_data),.write_top_down(top_down),
    .source_resolutions(source_resolutions),.write_pixel_ready(fifo_ready),
    .live_source_resolution(live_source_resolution),
    .audio_fifo_ready(audio_fifo_ready),.audio_pcm_wr_en(audio_pcm_wr_en),.audio_pcm_data(audio_pcm_data),
    .audio_song_request(audio_song_request),.audio_selected_song(),
    .audio_stream_enable(audio_stream_enable),.audio_file_bytes(audio_file_bytes),
    .SD_nCS(SD_nCS),.SD_DCLK(SD_DCLK),.SD_MOSI(SD_MOSI),.SD_MISO(SD_MISO)
);
wire pixel_valid, pixel_ready;
wire [23:0] pixel_rgb;
image_pixel_cdc u_pixels (
    .rst(bridge_reset),.wr_clk(sd_clk),.wr_valid(write_en),
    .wr_rgb(write_data[31:8]),.wr_ready(fifo_ready),.overflow(overflow),
    .rd_clk(udp_clk),.rd_ready(pixel_ready),.rd_valid(pixel_valid),.rd_rgb(pixel_rgb)
);
reg [2:0] finish_sync;
always @(posedge sd_clk or posedge bridge_sd_reset) begin
    if(bridge_sd_reset) begin
        write_ack<=0; source_active<=0; start_toggle<=0;
        index_latched<=0; top_latched<=0; finish_sync<=0;
        resolution_latched<=0;
    end else begin
        finish_sync<={finish_sync[1:0],finish_toggle};
        if(!write_req) write_ack<=0;
        if(write_req && !source_active && !write_ack) begin
            index_latched<=write_index; top_latched<=top_down;
            resolution_latched<=live_source_resolution;
            start_toggle<=~start_toggle; source_active<=1; write_ack<=1;
        end
        if(finish_sync[2]^finish_sync[1]) source_active<=0;
    end
end
reg [2:0] start_sync;
reg udp_active;
reg [18:0] source_count;
reg [1:0] udp_index;
reg udp_top;
reg [31:0] udp_resolution;
wire tx_source_ready;
wire ui_ready;
wire [7:0] ui_index;
// One non-fallthrough pixel stage. Home coordinates advance when RGB/tag
// are captured together, NOT through the packet transmitter's ready cone.
// The pending pixel stays stable across packet fill/wait/retry boundaries.
reg staged_valid,staged_first;
reg [23:0] staged_rgb;
reg [7:0] staged_tag;
wire stage_load=pixel_valid && pixel_ready;
always @(posedge udp_clk or posedge bridge_udp_reset) begin
    if(bridge_udp_reset)begin staged_valid<=0;staged_first<=0;end
    else begin
        if(staged_valid && tx_source_ready) staged_valid<=0;
        if(stage_load)begin staged_valid<=1;staged_first<=source_count==0;end
    end
end
// Data need no reset: staged_valid is synchronously released and prevents
// either the packet RAM or CRC from using an uninitialised held pixel.
always @(posedge udp_clk) if(stage_load)begin
    staged_rgb<=pixel_rgb;staged_tag<=ui_index;
end
home_index_stream u_home_indices (
    .clk(udp_clk),.rst(bridge_udp_reset),.start(start_sync[2]^start_sync[1]),
    .consume(pixel_valid && pixel_ready),.frame_index(index_latched),
    .top_down(top_latched),.ready(ui_ready),.index(ui_index)
);
reg [31:0] epoch_counter;
assign generation_exhausted=SESSION_GUARD && epoch_counter[15:0]==16'hffff;
// A failed load resets packet/FIFO state, but must not reuse its token.
always @(posedge udp_clk or posedge source_udp_reset) begin
    if(source_udp_reset) epoch_counter<=0;
    else if(!bridge_udp_reset && (start_sync[2]^start_sync[1]))
        epoch_counter<=epoch_counter+1'b1;
end
assign pixel_ready=udp_active && !staged_valid && ui_ready;
always @(posedge udp_clk or posedge bridge_udp_reset) begin
    if(bridge_udp_reset) begin
        start_sync<=0; udp_active<=0; source_count<=0;
        udp_index<=0; udp_top<=0; finish_toggle<=0;
        udp_resolution<=0;
    end else begin
        start_sync<={start_sync[1:0],start_toggle};
        if(start_sync[2]^start_sync[1]) begin
            udp_active<=1; source_count<=0;
            // Bundled metadata is stable before the synchronized toggle and
            // remains stable until the remote frame is committed.
            udp_index<=index_latched; udp_top<=top_latched;
            udp_resolution<=resolution_latched;
        end
        if(pixel_valid && pixel_ready) source_count<=source_count+1'b1;
        if(frame_sent) begin udp_active<=0; finish_toggle<=~finish_toggle; end
    end
end
wire receipt_valid;
wire [31:0] receipt_token;
wire [15:0] receipt_sequence;
image_receipt_rx u_receipt (
    .clk(udp_clk),.rst(bridge_udp_reset),.rx_valid(rx_valid),.rx_data(rx_data),
    .rx_length(rx_length),.receipt_valid(receipt_valid),
    .receipt_token(receipt_token),.receipt_sequence(receipt_sequence)
);
image_packet_tx #(.RELIABLE(1),.EXTERNAL_TOKEN(1),.UI_TAG(1),.RESOLUTION(1)) u_packets (
    .clk(udp_clk),.rst(bridge_udp_reset),.source_valid(staged_valid && udp_active),
    .source_ready(tx_source_ready),.source_rgb(staged_rgb),.source_tag(staged_tag),
    .source_frame_start(staged_first),.source_frame_index(udp_index),
    .source_top_down(udp_top),.udp_ready(udp_ready),.udp_ack(udp_ack),
    .source_resolution(udp_resolution),
    .udp_request(udp_request),.udp_valid(udp_valid),.udp_data(udp_data),
    .udp_length(udp_length),.frame_sent(frame_sent),.packets_sent(),
    .receipt_valid(receipt_valid),.receipt_token(receipt_token),
    .receipt_sequence(receipt_sequence),.transfer_token(),.packet_sequence(),
    .frame_token(SESSION_GUARD ? {generation,epoch_counter[15:0]} : epoch_counter)
);
endmodule
