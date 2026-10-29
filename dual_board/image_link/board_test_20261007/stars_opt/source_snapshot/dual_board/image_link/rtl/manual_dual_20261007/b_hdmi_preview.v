`timescale 1ns/1ps
// B manual-only display of TF images #5/#6, before all UI tags.
// Reuse the known-good SDRAM/HDMI chain and existing 100/25/125 MHz PLL outputs.
// Only #6 has stars. Both screens share the B-owned timeline.
// No audio/ACR packets, fonts, frame effects or new PLL are instantiated.
module b_hdmi_preview #(parameter integer KEY_CLK_FREQ=125_000_000, KEY_DEBOUNCE_MS=20) (
    input wire udp_clk,mem_clk,mem_shift_clk,video_clk,serial_clk,
    input wire reset_request,source_start,source_top_down,source_abort,
    input wire [2:0] source_index,
    input wire pixel_valid,
    input wire [23:0] pixel_rgb,
    input wire [15:0] star_phase_udp,
    input wire key_next,
    output wire [7:0] page_token,
    output wire frame_loaded,
    output wire pixel_ready,
    output wire HDMI_DDC_SCL,
    inout wire HDMI_DDC_SDA,
    output wire HDMI_CLK_P,HDMI_D0_P,HDMI_D1_P,HDMI_D2_P
);
localparam [20:0] FRAME_PIXELS=21'd307200;
// Controller addresses count 32-bit words, not bytes: 1.17 MiB per slot.
localparam [20:0] SLOT0=21'd0,SLOT1=21'd307200,
                  SLOT2=21'd614400,SLOT3=21'd921600;
wire udp_reset,mem_reset,video_reset;
player_domain_reset u_udp_reset(.clk(udp_clk),.request(reset_request),.rst(udp_reset));
player_domain_reset u_mem_reset(.clk(mem_clk),.request(reset_request),.rst(mem_reset));
player_domain_reset u_video_reset(.clk(video_clk),.request(reset_request),.rst(video_reset));
wire write_req,write_ack,write_credit,write_en,write_top,write_finish;
wire [1:0] write_index;
wire [31:0] write_data;
wire [1:0] committed_mask,committed_slot0,committed_slot1;
wire requested_page;
b_manual_page_control #(.CLK_FREQ(KEY_CLK_FREQ),.DEBOUNCE_MS(KEY_DEBOUNCE_MS)) u_pages (
    .clk(udp_clk),.rst(udp_reset),.key_next(key_next),
    .cache_valid(committed_mask),.requested_page(requested_page)
);
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
(* async_reg="true" *) reg [1:0] mask_sync0,mask_sync1,mask_sync2;
(* async_reg="true" *) reg [1:0] slot0_sync0,slot0_sync1,slot0_sync2;
(* async_reg="true" *) reg [1:0] slot1_sync0,slot1_sync1,slot1_sync2;
(* async_reg="true" *) reg [2:0] page_sync;
reg frame_valid,frame_page,vs_prev;
reg [1:0] frame_index;
wire hs_0,vs_0,de_0,read_req,read_ack,read_en;
wire hs,vs,de;
wire [31:0] read_word,delayed_word;
always @(posedge video_clk or posedge video_reset) begin
    if(video_reset) begin
        mask_sync0<=0;mask_sync1<=0;mask_sync2<=0;
        slot0_sync0<=0;slot0_sync1<=0;slot0_sync2<=0;
        slot1_sync0<=2;slot1_sync1<=2;slot1_sync2<=2;
        page_sync<=0;frame_valid<=0;frame_index<=0;frame_page<=0;vs_prev<=0;
    end else begin
        mask_sync0<=committed_mask;mask_sync1<=mask_sync0;mask_sync2<=mask_sync1;
        slot0_sync0<=committed_slot0;slot0_sync1<=slot0_sync0;slot0_sync2<=slot0_sync1;
        slot1_sync0<=committed_slot1;slot1_sync1<=slot1_sync0;slot1_sync2<=slot1_sync1;
        page_sync<={page_sync[1:0],requested_page};
        vs_prev<=vs_0;
        if(vs_prev && !vs_0) begin
            if(mask_sync2[page_sync[2]]) begin
                frame_valid<=1;frame_page<=page_sync[2];
                frame_index<=page_sync[2] ? slot1_sync2 : slot0_sync2;
            end else if(!frame_valid && |mask_sync2) begin
                frame_valid<=1;frame_page<=!mask_sync2[0];
                frame_index<=mask_sync2[0] ? slot0_sync2 : slot1_sync2;
            end
        end
    end
end
b_image_capture u_capture (
    .clk(udp_clk),.rst(udp_reset),.source_start(source_start),.source_index(source_index),
    .source_abort(source_abort),.source_top_down(source_top_down),
    .pixel_valid(pixel_valid),.pixel_rgb(pixel_rgb),.pixel_ready(pixel_ready),
    .writer_ack(write_ack),.writer_credit(write_credit),.writer_done_toggle(done_toggle),
    .displayed_valid(frame_valid),.displayed_index(frame_index),
    .write_req(write_req),.write_index(write_index),.write_top_down(write_top),
    .write_en(write_en),.write_data(write_data),
    .committed_mask(committed_mask),.committed_slot0(committed_slot0),
    .committed_slot1(committed_slot1),.frame_loaded(frame_loaded)
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
wire axis_user,axis_valid,axis_last;
wire [23:0] axis_rgb;
wire [15:0] star_phase_video;
audio_visual_cdc #(.WIDTH(16)) u_star_snapshot (
    .udp_clk(udp_clk),.video_clk(video_clk),.rst(reset_request),.frame_vs(vs_0),
    .update_valid(1'b0),.publish_enable(1'b1),.visual_state(star_phase_udp),
    .frame_state(star_phase_video),.capture_valid()
);
wire [23:0] star_rgb;
video_dual_star_overlay #(.VIEW_X(640)) u_stars (
    .I_clk(video_clk),.I_rst(video_reset),.I_enable(frame_valid && frame_page),
    .I_vs(vs),.I_de(de),.I_rgb(delayed_word[31:8]),
    .I_phase_q4(star_phase_video),.O_rgb(star_rgb)
);
video_rgb_to_axis_640x480 u_axis (.I_clk(video_clk),.I_rst(video_reset),
    .I_vs(vs),.I_de(de),.I_rgb(frame_valid ? star_rgb : 24'd0),
    .O_video_user(axis_user),.O_video_valid(axis_valid),.O_video_last(axis_last),.O_video_data(axis_rgb));
// Publish only an actually committed visible page, never a queued key request.
(* async_reg="true" *) reg [1:0] visible_valid_sync,visible_page_sync;
reg last_relax;
reg [6:0] enter_epoch;
reg [7:0] page_snapshot;
wire visible_relax=visible_valid_sync[1] && visible_page_sync[1];
assign page_token=page_snapshot;
always @(posedge udp_clk or posedge udp_reset) begin
    if(udp_reset) begin
        visible_valid_sync<=0;visible_page_sync<=0;last_relax<=0;enter_epoch<=0;page_snapshot<=0;
    end else begin
        visible_valid_sync<={visible_valid_sync[0],frame_valid};
        visible_page_sync<={visible_page_sync[0],frame_page};
        last_relax<=visible_relax;
        page_snapshot<={visible_relax,enter_epoch};
        if(visible_relax && !last_relax) begin
            enter_epoch<=enter_epoch+1'b1;
            page_snapshot<={1'b1,enter_epoch+7'd1};
        end
    end
end
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
