`timescale 1ns/1ps
// B local display: cached TF backgrounds plus the local dashboard palette on
// page 1. The UI tag is carried in the SDRAM spare byte, matching A's render.
// Reuse the known-good SDRAM/HDMI chain and existing 100/25/125 MHz PLL outputs.
// No audio samples, ACR packets, fonts, effects or new PLL are instantiated.
module b_hdmi_preview #(parameter [1:0] PREVIEW_INDEX=2'd1) (
    input wire udp_clk,mem_clk,mem_shift_clk,video_clk,serial_clk,
    input wire reset_request,source_start,source_top_down,source_abort,
    input wire [1:0] preview_target,
    input wire [2:0] source_index,
    input wire pixel_valid,
    input wire [23:0] pixel_rgb,
    input wire [7:0] pixel_tag,
    input wire [15:0] star_phase_udp,
    input wire gauge_key_n,
    // {valid,song} of the PCM file being played, already in video_clk.
    input wire [3:0] playing_song_video,
    output wire pixel_ready,
    output wire preview_finish,
    output wire HDMI_DDC_SCL,
    inout wire HDMI_DDC_SDA,
    output wire HDMI_CLK_P,HDMI_D0_P,HDMI_D1_P,HDMI_D2_P
);
localparam [20:0] FRAME_PIXELS=21'd307200;
// Controller addresses count 32-bit words, not bytes: 1.17 MiB per slot.
localparam [20:0] SLOT0=21'd0,
                   SLOT1=21'd307200,
                   SLOT2=21'd614400,
                   SLOT3=21'd921600;
wire udp_reset,mem_reset,video_reset;
player_domain_reset u_udp_reset(.clk(udp_clk),.request(reset_request),.rst(udp_reset));
player_domain_reset u_mem_reset(.clk(mem_clk),.request(reset_request),.rst(mem_reset));
player_domain_reset u_video_reset(.clk(video_clk),.request(reset_request),.rst(video_reset));
wire write_req,write_ack,write_credit,write_en,write_top,write_finish;
wire [1:0] write_index;
wire [31:0] write_data;
wire committed_valid;
wire [1:0] committed_index;
wire init_done,ref_valid,mem_busy,app_rd_en,app_wr_en,sdr_rd_en;
wire [20:0] app_rd_addr,app_wr_addr;
wire [31:0] app_wr_data,sdr_rd_data;
wire [3:0] app_wr_dm;
reg done_toggle,drain_pending;
wire abort_mem;
player_domain_reset u_abort_mem(.clk(mem_clk),.request(source_abort),.rst(abort_mem));
always @(posedge mem_clk or posedge mem_reset) begin
    if(mem_reset) begin done_toggle<=0;drain_pending<=0;end
    else if(abort_mem) drain_pending<=0;
    else begin
        if(write_finish) drain_pending<=1;
        // Completion must cover the SDRAM controller tail, not just the
        // producer's last pixel or a FIFO word-count comparison.
        if(drain_pending && !mem_busy && !app_wr_en && !ref_valid) begin
            done_toggle<=~done_toggle;drain_pending<=0;
        end
    end
end
(* async_reg="true" *) reg [2:0] valid_sync;
(* async_reg="true" *) reg [5:0] index_sync;
reg frame_valid;
reg [1:0] frame_index;
reg vs_prev;
wire hs_0,vs_0,de_0,read_req,read_ack,read_en;
wire hs,vs,de;
wire [31:0] read_word,delayed_word;
always @(posedge video_clk or posedge video_reset) begin
    if(video_reset) begin
        valid_sync<=0;index_sync<=0;frame_valid<=0;frame_index<=0;vs_prev<=0;
    end else begin
        valid_sync<={valid_sync[1:0],committed_valid};
        index_sync<={index_sync[3:0],committed_index};
        vs_prev<=vs_0;
        if(vs_prev && !vs_0) begin
            // Keep the last complete frame while a newly requested TF page
            // is still being loaded. A transient cache miss must not blank
            // HDMI; the page switches at a frame boundary once committed.
            if(valid_sync[2]) begin
                frame_valid<=1'b1;
                frame_index<=index_sync[5:4];
            end
        end
    end
end
b_image_capture #(.PREVIEW_INDEX(PREVIEW_INDEX)) u_capture (
    .clk(udp_clk),.rst(udp_reset),.source_start(source_start),.preview_target(preview_target),.source_index(source_index),
    .source_abort(source_abort),.source_top_down(source_top_down),
    .pixel_valid(pixel_valid),.pixel_rgb(pixel_rgb),.pixel_tag(pixel_tag),.pixel_ready(pixel_ready),
    .writer_ack(write_ack),.writer_credit(write_credit),.writer_done_toggle(done_toggle),
    .displayed_valid(frame_valid),.displayed_index(frame_index),
    .write_req(write_req),.write_index(write_index),.write_top_down(write_top),
    .write_en(write_en),.write_data(write_data),
    .committed_valid(committed_valid),.committed_index(committed_index),
    .frame_loaded(preview_finish)
);
frame_read_write #(.WRITE_V_FLIP(1),.DYNAMIC_V_FLIP(1),
                   .FRAME_WIDTH(640),.FRAME_HEIGHT(480)) u_frames (
    .rst(udp_reset),.mem_reset(mem_reset),.mem_clk(mem_clk),
    .Sdr_init_done(init_done),.Sdr_init_ref_vld(ref_valid),.Sdr_busy(mem_busy),
    .App_rd_en(app_rd_en),.App_rd_addr(app_rd_addr),.Sdr_rd_en(sdr_rd_en),.Sdr_rd_dout(sdr_rd_data),
    .App_wr_en(app_wr_en),.App_wr_addr(app_wr_addr),.App_wr_din(app_wr_data),.App_wr_dm(app_wr_dm),
    .write_clk(udp_clk),.write_abort(source_abort),.write_req(write_req),.write_req_ack(write_ack),
    .write_finish(write_finish),.write_addr_0(SLOT0),.write_addr_1(SLOT1),
    .write_addr_2(SLOT2),.write_addr_3(SLOT3),.write_addr_index(write_index),
    .write_top_down(write_top),.write_pixel_ready(write_credit),.write_len(FRAME_PIXELS),
    .write_en(write_en),.write_data(write_data),
    .read_clk(video_clk),.read_req(read_req && frame_valid),.read_req_ack(read_ack),.read_finish(),
    .read_b_enable(1'b0),.read_addr_0(SLOT0),.read_addr_1(SLOT1),.read_addr_2(SLOT2),.read_addr_3(SLOT3),
    .read_addr_index(frame_index),.read_addr_index_b(2'd0),.read_len(FRAME_PIXELS),
    .read_en(read_en && frame_valid),.read_data(read_word),.read_data_b(),
    .read_empty_a(),.read_empty_b(),.read_valid_a()
);
sdram u_sdram (
    .Clk(mem_clk),.Clk_sft(mem_shift_clk),.Rst(mem_reset),
    .Sdr_init_done(init_done),.Sdr_init_ref_vld(ref_valid),.Sdr_busy(mem_busy),
    .App_wr_en(app_wr_en),.App_wr_addr(app_wr_addr),.App_wr_dm(app_wr_dm),.App_wr_din(app_wr_data),
    .App_rd_en(app_rd_en),.App_rd_addr(app_rd_addr),.Sdr_rd_en(sdr_rd_en),.Sdr_rd_dout(sdr_rd_data)
);
video_timing_data u_timing (.video_clk(video_clk),.rst(video_reset),
    .read_req(read_req),.read_req_ack(read_ack),.hs(hs_0),.vs(vs_0),.de(de_0));
video_delay #(.DATA_WIDTH(32)) u_pixel_delay (
    .video_clk(video_clk),.rst(video_reset),.read_en(read_en),.read_data(read_word),
    .hs(hs_0),.vs(vs_0),.de(de_0),.hs_r(hs),.vs_r(vs),.de_r(de),.vout_data(delayed_word)
);
wire [15:0] star_phase_video;
audio_visual_cdc #(.WIDTH(16)) u_star_snapshot (
    .udp_clk(udp_clk),.video_clk(video_clk),.rst(reset_request),.frame_vs(vs_0),
    .update_valid(1'b0),.publish_enable(1'b1),.visual_state(star_phase_udp),
    .frame_state(star_phase_video),.capture_valid()
);
wire [23:0] star_rgb;
video_dual_star_overlay #(.VIEW_X(640)) u_stars (
    .I_clk(video_clk),.I_rst(video_reset),.I_enable(frame_valid && frame_index==2'd1),
    .I_vs(vs),.I_de(de),.I_rgb(delayed_word[31:8]),
    .I_phase_q4(star_phase_video),.O_rgb(star_rgb)
);
wire [23:0] dashboard_rgb;
video_dashboard_needles u_dashboard_needles (
    .I_clk(video_clk),.I_rst(video_reset),
    .I_enable(frame_valid && frame_index==2'd0),
    .I_vs(vs),.I_de(de),.I_boost_key_n(gauge_key_n),
    .I_rgb(delayed_word[31:8]),.O_rgb(dashboard_rgb)
);
// Reuse the earlier indexed car introduction below the dashboard.  It is
// placed after the needle overlay so the car never covers the red pointers.
wire [23:0] car_rgb;
wire car_vs,car_de;
video_car_intro_light u_car_intro (
    .I_clk(video_clk),.I_rst(video_reset),
    .I_enable(frame_valid && frame_index==2'd0),
    .I_vs(vs),.I_de(de),.I_rgb(dashboard_rgb),
    .O_rgb(car_rgb),.O_vs(car_vs),.O_de(car_de)
);
// IMAGE3 (slot 2) is the song list; mark the song that is playing.
wire [23:0] playlist_rgb;
video_playlist_highlight u_playlist (
    .I_clk(video_clk),.I_rst(video_reset),
    .I_enable(frame_valid && frame_index==2'd2),
    .I_vs(vs),.I_de(de),.I_playing(playing_song_video[3]),.I_song(playing_song_video[2:0]),
    .I_rgb(delayed_word[31:8]),.O_rgb(playlist_rgb)
);
wire axis_user,axis_valid,axis_last;
wire [23:0] axis_rgb;
video_rgb_to_axis_640x480 u_axis (.I_clk(video_clk),.I_rst(video_reset),
    .I_vs(frame_valid && frame_index==2'd0 ? car_vs : vs),
    .I_de(frame_valid && frame_index==2'd0 ? car_de : de),
    .I_rgb(frame_valid ?
        ((frame_index==2'd1) ? star_rgb :
         ((frame_index==2'd0) ? car_rgb : playlist_rgb)) : 24'd0),
    .O_video_user(axis_user),.O_video_valid(axis_valid),.O_video_last(axis_last),.O_video_data(axis_rgb));
wire edid_trig;
startup_pulse #(.CNT_MAX(20'd100000)) u_edid_trigger (
    .I_clk(video_clk),.I_rst(video_reset),.O_pulse(edid_trig));
wire [9:0] tmds0,tmds1,tmds2,tmdsclk;
hdmi_1_4b_transmitter_core_wrapper #(
    .DEVICE("EG"),.HTOTAL(800),.HSA(96),.HFP(16),.HBP(48),.HACTIVE(640),
    .VTOTAL(525),.VSA(2),.VFP(10),.VBP(33),.VACTIVE(480),
    .VIDEO_VIC(1),.VIDEO_TPG("Disable"),.VIDEO_FORMAT("RGB"),
    .AUDIO_SAMPLE_RATE("48K"),.IIC_SCL_DIV(250)
) u_hdmi (
    .I_pixel_clk(video_clk),.I_rst(video_reset),.I_edid_read_trig(edid_trig),
    .O_edid_read_valid(),.O_edid_read_data(),
    .I_axis_s_user(axis_user),.I_axis_s_valid(axis_valid),.I_axis_s_last(axis_last),
    .I_axis_s_data(axis_rgb),.O_axis_s_ready(),
    .I_audio_valid(1'b0),.I_audio_left_data(24'd0),.I_audio_right_data(24'd0),
    .I_acr_valid(1'b0),.I_acr_cts(20'd0),.I_acr_n(20'd0),.O_video_locked(),
    .O_ddc_scl(HDMI_DDC_SCL),.IO_ddc_sda(HDMI_DDC_SDA),
    .O_ch0_tmds_data(tmds0),.O_ch1_tmds_data(tmds1),
    .O_ch2_tmds_data(tmds2),.O_clk_tmds_data(tmdsclk)
);
hdmi_phy_wrapper #(.DEVICE("EG")) u_phy (
    .I_pixel_clk(video_clk),.I_serial_clk(serial_clk),.I_rst(video_reset),
    .I_tmds_channel_0(tmds0),.I_tmds_channel_1(tmds1),
    .I_tmds_channel_2(tmds2),.I_tmds_channel_clk(tmdsclk),
    .O_tmds_ch0_p(HDMI_D0_P),.O_tmds_ch1_p(HDMI_D1_P),
    .O_tmds_ch2_p(HDMI_D2_P),.O_tmds_clk_p(HDMI_CLK_P)
);
endmodule
