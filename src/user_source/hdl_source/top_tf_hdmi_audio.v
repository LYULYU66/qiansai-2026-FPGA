
module top(
    input                       clk,
    input                       rst_n,
    input                       key1,           // 手动下一张
    input                       key2,           // 自动播放 开/关

    // Vehicle hazard switches: SW1 rear, SW2 front, SW3 left, SW4 right.
    input                       sw_front,
    input                       sw_left,
    input                       sw_right,
    input                       sw_rear,

    // USB-UART, 115200 baud, 8-N-1
    input                       uart_rx,
    output                      uart_tx,

	output [5:0]                seg_sel,
	output [7:0]                seg_data,

    // HDMI TMDS
    output                      HDMI_CLK_P,
    output                      HDMI_D2_P,
    output                      HDMI_D1_P,
    output                      HDMI_D0_P,

    // HDMI DDC
    output                      HDMI_DDC_SCL,
    inout                       HDMI_DDC_SDA,

    // TF card SPI
    output                      sd_ncs,
    output                      sd_dclk,
    output                      sd_mosi,
    input                       sd_miso
);

parameter MEM_DATA_BITS = 32;
parameter ADDR_BITS     = 21;
parameter BUSRT_BITS    = 10;
parameter [ADDR_BITS-1:0] FRAME_PIXELS = 21'd307200;   // 640*480
parameter [ADDR_BITS-1:0] BUF0_ADDR    = 21'd0;
parameter [ADDR_BITS-1:0] BUF1_ADDR    = 21'd307200;
parameter [ADDR_BITS-1:0] BUF2_ADDR    = 21'd614400;
parameter [ADDR_BITS-1:0] BUF3_ADDR    = 21'd921600;

wire Sdr_init_done;
wire Sdr_init_ref_vld;
wire Sdr_busy;

wire sd_card_clk;
wire ext_mem_clk;
wire ext_mem_clk_sft;
wire video_clk;
wire hdmi_5x_clk;

wire        audio_pll_lock;
wire        audio_mclk;
wire        audio_i2s_bclk;
wire        audio_i2s_lrck;
wire        audio_i2s_dout;
wire        audio_valid;
wire [23:0] audio_left_data;
wire [23:0] audio_right_data;
wire        alarm_audio_valid;
wire [23:0] alarm_audio_left_data;
wire [23:0] alarm_audio_right_data;
wire        audio_pcm_wr_en;
wire [31:0] audio_pcm_wr_data;
wire        audio_stream_enable;
reg         audio_fifo_ready;
wire        audio_fifo_full;
wire        audio_fifo_empty;
wire [8:0]  audio_fifo_wrusedw;
wire [8:0]  audio_fifo_rdusedw;
wire [31:0] audio_fifo_rd_data;
wire        audio_fifo_read;
wire        audio_pcm_playing;
wire        audio_pcm_underflow;
reg  [1:0]  audio_stream_enable_sync;
wire        audio_pcm_selected;
wire [3:0]  uart_volume_level;
wire [1:0]  uart_brightness_level;
wire [1:0]  uart_contrast_level;
wire        uart_rx_error;
wire        acr_valid;
wire [19:0] acr_cts;
wire [19:0] acr_n;

wire hs;
wire vs;
wire de;

wire [23:0] vout_data_raw;
wire [23:0] vout_data_raw_b;
wire [23:0] vout_data_transition;
wire [23:0] vout_data;
wire [23:0] vout_data_osd;
wire [23:0] vout_data_visualizer;
wire [23:0] vout_data_lyrics;
wire [23:0] vout_data_relax;
wire [23:0] vout_data_page;
wire [31:0] audio_file_bytes;
reg audio_song_matches_sd;
reg [1:0] audio_song_matches_audio_sync;
reg [1:0] audio_song_matches_video_sync;
wire [7:0] lyric_line_video;
wire [7:0] lyric_next_line_video;
wire [4:0] lyric_sung_chars_video;
wire [9:0] lyric_red_pixels_video;
wire [23:0] vout_data_adjusted;
wire [23:0] vout_data_status;
wire [23:0] vout_data_clock;
wire [23:0] unified_time_bcd;
wire [15:0] unified_frame_hhmm;
wire [23:0] vout_data_home;
wire [23:0] vout_data_hazard;
wire        adjusted_hs;
wire        adjusted_vs;
wire        adjusted_de;
wire        display_valid;
wire        display_valid_frame;

wire [6:0]   audio_vu_left_level;
wire [6:0]   audio_vu_right_level;
wire [111:0] audio_spectrum_levels;
wire [111:0] audio_wave_samples;
reg  [1:0]   audio_pcm_selected_video_sync;
wire         audio_pcm_selected_video = audio_pcm_selected_video_sync[1];

wire         hazard_front;
wire         hazard_left;
wire         hazard_right;
wire         hazard_rear;
wire         any_hazard = hazard_front | hazard_left | hazard_right | hazard_rear;
wire         warning_image_ready;

wire        transition_hs;
wire        transition_vs;
wire        transition_de;
wire [1:0]  transition_read_idx_a;
wire [1:0]  transition_read_idx_b;
wire [1:0]  transition_display_idx;
wire        transition_read_b_enable;
wire        transition_active;
wire [1:0]  transition_kind;
wire [5:0]  transition_step;
// The dashboard is exclusive to picture 1.  During an image transition the
// old overlays remain until the new picture is fully committed.
wire first_image_home;
wire second_image_music;
wire third_image_selected;
wire third_image_relax;
wire playback_osd_enable;
wire playback_visualizer_enable;
wire visual_analysis_enable=audio_pcm_selected_video &&
                            (playback_visualizer_enable || third_image_relax);
// Keep picture 4 free of the normal playback OSD throughout its outgoing
// transition.  Draw warnings only once its own image is fully on screen.
wire fourth_image_selected;
wire fourth_image_warning;

wire [3:0]  state_code;
wire [3:0]  image_number;
reg  [3:0]  image_number_sync0;
reg  [3:0]  image_number_sync1;
wire [6:0]  seg_data_0;

wire        video_read_req;
wire        video_read_req_ack;
wire        video_read_en;
wire [31:0] video_read_data;
wire [31:0] video_read_data_b;

wire        sd_card_write_en;
wire [31:0] sd_card_write_data;
wire        sd_card_write_req;
wire        sd_card_write_req_ack;
wire        frame_write_finish;
reg         frame_write_toggle_mem;
wire        frame_write_abort;

wire [1:0]  write_buf_idx;
wire sd_write_top_down;
wire sd_write_pixel_ready;
wire [127:0] source_resolutions;
wire [31:0] display_resolution=source_resolutions[transition_display_idx*32 +: 32];
wire [1:0]  disp_buf_idx;

wire App_rd_en;
wire [ADDR_BITS-1:0] App_rd_addr;
wire Sdr_rd_en;
wire [MEM_DATA_BITS-1:0] Sdr_rd_dout;
wire App_wr_en;
wire [ADDR_BITS-1:0] App_wr_addr;
wire [MEM_DATA_BITS-1:0] App_wr_din;
wire [3:0] App_wr_dm;

wire hs_0;
wire vs_0;
wire de_0;

// HDMI 1.4b 相关
wire        axis_s_user;
wire        axis_s_valid;
wire        axis_s_last;
wire [23:0] axis_s_data;
wire        axis_s_ready;

wire        edid_trig;
wire        edid_valid;
wire [7:0]  edid_data;

wire [9:0]  tmds_ch0_data;
wire [9:0]  tmds_ch1_data;
wire [9:0]  tmds_ch2_data;
wire [9:0]  tmds_clk_data;

// 统一复位：TF 图像链路 + HDMI 链路
wire sys_pll_lock;
wire video_pll_lock;
wire rst_all;

reg [19:0] rst_cnt = 20'd0;
reg rst_all_reg = 1'b1;

always @(posedge clk) begin
    if (!rst_n) begin
        rst_cnt <= 20'd0;
        rst_all_reg <= 1'b1;
    end else if (!rst_all_reg) begin
        // 一旦复位释放，忽略后续微小的 PLL 抖动，防止系统在使用时随机复位
        rst_all_reg <= 1'b0;
    end else if (sys_pll_lock && video_pll_lock && audio_pll_lock) begin
        // 等待系统、视频和音频 PLL 连续稳定 20ms @ 50MHz
        if (rst_cnt < 20'd1_000_000) begin
            rst_cnt <= rst_cnt + 1'b1;
            rst_all_reg <= 1'b1;
        end else begin
            rst_all_reg <= 1'b0;
        end
    end else begin
        rst_cnt <= 20'd0;
        rst_all_reg <= 1'b1;
    end
end

assign rst_all = rst_all_reg;

// Text command interface derived from lesson07..lesson10.  Volume defaults to
// full scale (8/8), so an unconnected UART does not change existing playback.
uart_audio_control #(
    .CLK_FREQ_HZ(50_000_000),
    .BAUD_RATE  (115_200)
) u_uart_audio_control (
    .I_clk         (clk),
    .I_rst_n       (~rst_all),
    .I_uart_rx     (uart_rx),
    .O_uart_tx     (uart_tx),
    .O_volume_level(uart_volume_level),
    .O_brightness_level(uart_brightness_level),
    .O_contrast_level  (uart_contrast_level),
    .O_rx_error    (uart_rx_error)
);

// 保持你原来的 TF / SDRAM / video 时钟
sys_pll sys_pll_m0(
    .refclk     (clk),
    .reset      (1'b0),
    .extlock    (sys_pll_lock),
    .clk0_out   (sd_card_clk),
    .clk1_out   (ext_mem_clk),
    .clk2_out   (ext_mem_clk_sft)
);

video_pll video_pll_m0(
    .refclk     (clk),
    .reset      (1'b0),
    .extlock    (video_pll_lock),
    .clk0_out   (video_clk),
    .clk1_out   (hdmi_5x_clk)
);

// SW1-SW4 are asynchronous mechanical inputs.  Qualify each position
// for 10 ms in the video clock domain before it can affect picture or sound.
alarm_switch_control #(
    .STABLE_CYCLES (250000)
) u_alarm_switch_control (
    .I_clk          (video_clk),
    .I_rst          (rst_all),
    .I_sw_front     (sw_front),
    .I_sw_left      (sw_left),
    .I_sw_right     (sw_right),
    .I_sw_rear      (sw_rear),
    .O_hazard_front (hazard_front),
    .O_hazard_left  (hazard_left),
    .O_hazard_right (hazard_right),
    .O_hazard_rear  (hazard_rear)
);

// 参考 lab_ex5_i2s：产生约 12.288 MHz 音频主时钟，供 48 kHz/64fs I2S 链路使用。
PLL_HDMI_AUDIO u_audio_pll(
    .refclk     (clk),
    .reset      (1'b0),
    .extlock    (audio_pll_lock),
    .clk0_out   (),
    .clk1_out   (),
    .clk2_out   (audio_mclk)
);

// mem_clk 域把 write_finish 单拍转成 toggle，供 sd_card_clk 域可靠同步
always @(posedge ext_mem_clk or posedge rst_all) begin
    if (rst_all)
        frame_write_toggle_mem <= 1'b0;
    else if (frame_write_finish)
        frame_write_toggle_mem <= ~frame_write_toggle_mem;
end

// ===================== TF 多图扫描与缓存（双缓冲） =====================
sd_card_bmp #(
    .CLK_FREQ_HZ       (100_000_000),
    .SCAN_TARGET_COUNT (3'd4),
    .AUTO_PLAY_DEFAULT (1'b0),
    .ENABLE_RESAMPLE   (1),
    .FAST_AUDIO_START  (1),
    .PIPELINED_CLUSTER_ADDR (1)
) sd_card_bmp_m0(
    .clk               (sd_card_clk),
    .rst               (rst_all),
    .key_next          (key1),
    .key_auto          (key2),
    .I_warning_hold    (any_hazard),
    .state_code        (state_code),
    .image_number      (image_number),
    .bmp_width         (16'd640),
    .bmp_height        (16'd480),
    .display_valid     (display_valid),
    .warning_image_ready(warning_image_ready),

    .write_finish_toggle(frame_write_toggle_mem),
    .write_buf_idx     (write_buf_idx),
    .disp_buf_idx      (disp_buf_idx),
    .load_abort        (frame_write_abort),

    .write_req         (sd_card_write_req),
    .write_req_ack     (sd_card_write_req_ack),
    .write_en          (sd_card_write_en),
    .write_data        (sd_card_write_data),
    .write_top_down    (sd_write_top_down),
    .source_resolutions(source_resolutions),
    .write_pixel_ready (sd_write_pixel_ready),
    .audio_fifo_ready  (audio_fifo_ready),
    .audio_pcm_wr_en   (audio_pcm_wr_en),
    .audio_pcm_data    (audio_pcm_wr_data),
    .audio_stream_enable(audio_stream_enable),
    .audio_file_bytes   (audio_file_bytes),
    .SD_nCS            (sd_ncs),
    .SD_DCLK           (sd_dclk),
    .SD_MOSI           (sd_mosi),
    .SD_MISO           (sd_miso)
);

// 图片编号跨入板载 50 MHz 域后再驱动数码管；数码管不依赖 SD PLL 的复位状态。
always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
        image_number_sync0 <= 4'd0;
        image_number_sync1 <= 4'd0;
    end else begin
        image_number_sync0 <= display_valid_frame ?
                              ({2'b00, transition_display_idx} + 4'd1) : 4'd0;
        image_number_sync1 <= image_number_sync0;
    end
end

seg_decoder seg_decoder_m0(
    .bin_data          (image_number_sync1),
    .seg_data          (seg_data_0)
);

// 本板原始例程的可见个位对应 seg_data_5；上电预载期间显示 0，完成后显示 1~4。
seg_scan #(
    .CLK_FREQ          (50_000_000)
) seg_scan_m0(
    .clk               (clk),
    .rst_n             (rst_n),
    .seg_sel           (seg_sel),
    .seg_data          (seg_data),
    .seg_data_0        ({1'b1,7'b1111_111}),
    .seg_data_1        ({1'b1,7'b1111_111}),
    .seg_data_2        ({1'b1,7'b1111_111}),
    .seg_data_3        ({1'b1,7'b1111_111}),
    .seg_data_4        ({1'b1,7'b1111_111}),
    .seg_data_5        ({1'b1,seg_data_0})
);

// ===================== 原图像时序与帧缓存 =====================
video_timing_data video_timing_data_m0(
    .video_clk         (video_clk),
    .rst               (rst_all),
    .read_req          (video_read_req),
    .read_req_ack      (video_read_req_ack),
    .hs                (hs_0),
    .vs                (vs_0),
    .de                (de_0)
);

// display_valid is generated in the 100 MHz TF-card domain.  Do not expose it
// directly to the pixel stream: an image may complete halfway through a video
// frame, while the read FIFO still contains startup data.  Synchronize it and
// commit the change only at the next VS frame boundary.
video_frame_valid_gate u_video_frame_valid_gate (
    .I_clk         (video_clk),
    .I_async_rst   (rst_all),
    .I_frame_vs    (vs_0),
    .I_async_valid (display_valid),
    .O_frame_valid (display_valid_frame)
);

video_delay video_delay_m0(
    .video_clk         (video_clk),
    .rst               (rst_all),
    .read_en           (video_read_en),
    .read_data         (video_read_data[31:8]),
    .hs                (hs_0),
    .vs                (vs_0),
    .de                (de_0),
    .hs_r              (hs),
    .vs_r              (vs),
    .de_r              (de),
    .vout_data         (vout_data_raw)
);

video_delay video_delay_b_m0(
    .video_clk         (video_clk),
    .rst               (rst_all),
    .read_en           (),
    .read_data         (video_read_data_b[31:8]),
    .hs                (hs_0),
    .vs                (vs_0),
    .de                (de_0),
    .hs_r              (),
    .vs_r              (),
    .de_r              (),
    .vout_data         (vout_data_raw_b)
);

video_transition_effects #(
    .H_ACTIVE          (640),
    .V_ACTIVE          (480),
    .TRANSITION_STEPS  (32)
) u_video_transition_effects (
    .I_clk              (video_clk),
    .I_rst              (rst_all),
    .I_frame_vs         (vs_0),
    .I_hs               (hs),
    .I_vs               (vs),
    .I_de               (de),
    .I_rgb_a            (vout_data_raw),
    .I_rgb_b            (vout_data_raw_b),
    .I_display_valid    (display_valid_frame),
    .I_requested_idx    (disp_buf_idx),
    .I_frame_read_req   (video_read_req),
    .I_force_warning    (any_hazard),
    .I_warning_ready    (warning_image_ready),
    .O_read_idx_a       (transition_read_idx_a),
    .O_read_idx_b       (transition_read_idx_b),
    .O_read_b_enable    (transition_read_b_enable),
    .O_display_idx      (transition_display_idx),
    .O_transition_active(transition_active),
    .O_transition_kind  (transition_kind),
    .O_transition_step  (transition_step),
    .O_hs               (transition_hs),
    .O_vs               (transition_vs),
    .O_de               (transition_de),
    .O_rgb              (vout_data_transition)
);

// 首图提交前黑屏；提交后一直显示当前显示缓冲区内容
assign vout_data = display_valid_frame ? vout_data_transition : 24'd0;

// Image-only brightness/contrast control.  The one-cycle RGB pipeline also
// delays timing, so all following overlays remain pixel-aligned.  Defaults
// are BRI100/CON25; CON25 is the natural picture reference setting.
video_image_adjust #(.USE_LUT_ROM(1)) u_video_image_adjust (
    .I_clk               (video_clk),
    .I_rst               (rst_all),
    .I_hs                (transition_hs),
    .I_vs                (transition_vs),
    .I_de                (transition_de),
    .I_rgb               (vout_data),
    .I_brightness_level  (uart_brightness_level),
    .I_contrast_level    (uart_contrast_level),
    .O_hs                (adjusted_hs),
    .O_vs                (adjusted_vs),
    .O_de                (adjusted_de),
    .O_rgb               (vout_data_adjusted)
);

// 底部动态 OSD：半透明白底、黑字“FPGA创新设计竞赛”。
osd_alpha_overlay u_osd_alpha_overlay(
    .I_clk       (video_clk),
    .I_rst       (rst_all),
    .I_enable    (playback_osd_enable),
    .I_vs        (adjusted_vs),
    .I_de        (adjusted_de),
    .I_rgb       (vout_data_adjusted),
    .O_rgb       (vout_data_osd)
);

// Normal playback audio visualisation. Spectrum, waveform and drawing all run
// in the video clock domain because I2S_receiver already commits complete
// stereo samples into this domain. Display values are captured only at a
// video-frame boundary inside the overlay, preventing mid-frame tearing.
always @(posedge video_clk or posedge rst_all) begin
    if (rst_all)
        audio_pcm_selected_video_sync <= 2'b00;
    else
        audio_pcm_selected_video_sync <= {audio_pcm_selected_video_sync[0],
                                          audio_pcm_selected};
end

audio_waveform_analyzer u_audio_waveform_analyzer (
    .I_clk              (video_clk),
    .I_rst              (rst_all),
    // The only consumers are playback visualization and relax-page lights.
    // PCM serialization, alarm mixing and lyric sample time stay running.
    .I_enable           (visual_analysis_enable),
    .I_audio_valid      (alarm_audio_valid),
    .I_audio_left       (alarm_audio_left_data),
    .I_audio_right      (alarm_audio_right_data),
    .O_vu_left_level    (audio_vu_left_level),
    .O_vu_right_level   (audio_vu_right_level),
    .O_wave_samples     (audio_wave_samples)
);

audio_spectrum_analyzer #(.LOW_POWER(1)) u_audio_spectrum_analyzer (
    .I_clk              (video_clk),
    .I_rst              (rst_all),
    .I_enable           (visual_analysis_enable),
    .I_audio_valid      (alarm_audio_valid),
    .I_audio_left       (alarm_audio_left_data),
    .I_audio_right      (alarm_audio_right_data),
    .O_vu_left_level    (),
    .O_vu_right_level   (),
    .O_band_levels      (audio_spectrum_levels)
);

audio_visualizer_overlay u_audio_visualizer_overlay (
    .I_clk              (video_clk),
    .I_rst              (rst_all),
    .I_enable           (playback_visualizer_enable),
    .I_vs               (adjusted_vs),
    .I_de               (adjusted_de),
    .I_rgb              (vout_data_osd),
    .I_vu_left_level    (audio_vu_left_level),
    .I_vu_right_level   (audio_vu_right_level),
    .I_spectrum_levels  (audio_spectrum_levels),
    .I_wave_samples     (audio_wave_samples),
    .I_volume_level     (uart_volume_level),
    // The VU meters remain audio-only; directional cues now belong to the
    // dedicated vehicle warning overlay, not the left/right audio channels.
    .I_hazard_front     (1'b0),
    .I_hazard_left      (1'b0),
    .I_hazard_right     (1'b0),
    .O_rgb              (vout_data_visualizer)
);

// Two frameless lyric lines only on picture 2, above the visualizer:
// Native 24px current row y232, upcoming y268; continuous per-pixel red sweep.
// Intro credits share the font; instrumental gaps preview upcoming two rows.
// They are added after image adjustment so its controls do not recolor text.
// The existing scrolling competition strip remains unchanged on picture 2.
// One shared dashboard renderer: picture 1 is unchanged, picture 2 selects
// only its wider music card. The existing album/QQ ROMs are not duplicated.
video_home_overlay #(.EXTERNAL_CLOCK(1)) u_video_home_overlay (
    .I_clk(video_clk), .I_rst(rst_all),
    .I_enable(first_image_home || second_image_music),
    .I_music_page(second_image_music),
    .I_vs(adjusted_vs), .I_de(adjusted_de),
    .I_rgb(vout_data_visualizer), .O_rgb(vout_data_home)
);

video_lyric_overlay #(.LOW_POWER(1)) u_video_lyric_overlay (
    .I_clk(video_clk), .I_rst(rst_all),
    .I_enable(second_image_music && audio_song_matches_video_sync[1]),
    .I_card_enable(second_image_music),
    .I_vs(adjusted_vs), .I_de(adjusted_de),
    .I_rgb(vout_data_home), .I_line(lyric_line_video),
    .I_next_line(lyric_next_line_video), .I_red_pixels(lyric_red_pixels_video),
    .O_rgb(vout_data_lyrics)
);

// Relax mode reads the adjusted TF photograph directly, rather than feeding
// through any subtitle/spectrum/waveform/card layer. Other pages are unchanged.
video_relax_overlay #(.LOW_POWER(1)) u_video_relax_overlay (
    .I_clk(video_clk), .I_rst(rst_all), .I_enable(third_image_relax),
    .I_vs(adjusted_vs), .I_de(adjusted_de), .I_rgb(vout_data_adjusted),
    .I_audio_active(audio_pcm_selected_video),
    .I_vu_left(audio_vu_left_level), .I_vu_right(audio_vu_right_level),
    .I_spectrum_levels(audio_spectrum_levels), .O_rgb(vout_data_relax)
);
video_playback_overlay_select u_video_playback_overlay_select (
    .I_valid(display_valid_frame), .I_transition_active(transition_active),
    .I_pcm_available(audio_pcm_selected_video), .I_picture_idx(transition_display_idx),
    .I_regular_rgb(vout_data_lyrics), .I_relax_rgb(vout_data_relax),
    .O_home(first_image_home), .O_music(second_image_music),
    .O_warning_selected(fourth_image_selected), .O_warning_draw(fourth_image_warning),
    .O_relax_selected(third_image_selected), .O_relax_draw(third_image_relax),
    .O_osd(playback_osd_enable), .O_visualizer(playback_visualizer_enable),
    .O_rgb(vout_data_page)
);

video_status_overlay #(.ENABLE_RESOLUTION(1)) u_video_status_overlay (
    .I_clk               (video_clk),
    .I_rst               (rst_all),
    .I_enable            (display_valid_frame),
    .I_vs                (adjusted_vs),
    .I_de                (adjusted_de),
    .I_rgb               (vout_data_page),
    .I_brightness_level  (uart_brightness_level),
    .I_contrast_level    (uart_contrast_level),
    .I_volume_level      (uart_volume_level),
    .I_source_width      (display_resolution[31:16]),
    .I_source_height     (display_resolution[15:0]),
    .O_rgb               (vout_data_status)
);

// Final safety layer. The existing directional screen-edge border remains on
// all pictures; picture 4 also has four car-relative warning panels.
video_unified_clock u_video_unified_clock (
    .I_clk(video_clk),.I_rst(rst_all),.I_vs(adjusted_vs),
    .O_time_bcd(unified_time_bcd),.O_frame_hhmm(unified_frame_hhmm)
);
video_clock_overlay #(.LOW_POWER(1)) u_video_clock_overlay (
    .I_clk(video_clk),.I_rst(rst_all),.I_vs(adjusted_vs),.I_de(adjusted_de),
    .I_enable(display_valid_frame),.I_picture_idx(transition_display_idx),
    .I_frame_hhmm(unified_frame_hhmm),.I_rgb(vout_data_status),.O_rgb(vout_data_clock)
);

vehicle_hazard_overlay u_vehicle_hazard_overlay (
    .I_clk          (video_clk),
    .I_rst          (rst_all),
    .I_vs           (adjusted_vs),
    .I_de           (adjusted_de),
    .I_rgb          (vout_data_clock),
    .I_warning_page (fourth_image_warning),
    .I_hazard_front (hazard_front),
    .I_hazard_left  (hazard_left),
    .I_hazard_right (hazard_right),
    .I_hazard_rear  (hazard_rear),
    .O_rgb          (vout_data_hazard)
);

frame_read_write #(
    .WRITE_V_FLIP     (1),
    .DYNAMIC_V_FLIP   (1),
    .FRAME_WIDTH      (640),
    .FRAME_HEIGHT     (480)
) frame_read_write_m0(
    .mem_clk           (ext_mem_clk),
    .rst               (rst_all),
    .Sdr_init_done     (Sdr_init_done),
    .Sdr_init_ref_vld  (Sdr_init_ref_vld),
    .Sdr_busy          (Sdr_busy),

    .App_rd_en         (App_rd_en),
    .App_rd_addr       (App_rd_addr),
    .Sdr_rd_en         (Sdr_rd_en),
    .Sdr_rd_dout       (Sdr_rd_dout),

    .read_clk          (video_clk),
    .read_req          (video_read_req),
    .read_req_ack      (video_read_req_ack),
    .read_finish       (),
    .read_b_enable     (transition_read_b_enable),
    .read_addr_0       (BUF0_ADDR),
    .read_addr_1       (BUF1_ADDR),
    .read_addr_2       (BUF2_ADDR),
    .read_addr_3       (BUF3_ADDR),
    .read_addr_index   (transition_read_idx_a),
    .read_addr_index_b (transition_read_idx_b),
    .read_len          (FRAME_PIXELS),
    .read_en           (video_read_en),
    .read_data         (video_read_data),
    .read_data_b       (video_read_data_b),
    .read_empty_a      (),
    .read_empty_b      (),
    .read_valid_a      (),

    .App_wr_en         (App_wr_en),
    .App_wr_addr       (App_wr_addr),
    .App_wr_din        (App_wr_din),
    .App_wr_dm         (App_wr_dm),

    .write_clk         (sd_card_clk),
    .write_abort       (frame_write_abort),
    .write_req         (sd_card_write_req),
    .write_req_ack     (sd_card_write_req_ack),
    .write_finish      (frame_write_finish),
    .write_addr_0      (BUF0_ADDR),
    .write_addr_1      (BUF1_ADDR),
    .write_addr_2      (BUF2_ADDR),
    .write_addr_3      (BUF3_ADDR),
    .write_addr_index  (write_buf_idx),
    .write_top_down    (sd_write_top_down),
    .write_pixel_ready (sd_write_pixel_ready),
    .write_len         (FRAME_PIXELS),
    .write_en          (sd_card_write_en),
    .write_data        (sd_card_write_data)
);

sdram U3(
    .Clk               (ext_mem_clk),
    .Clk_sft           (ext_mem_clk_sft),
    .Rst               (rst_all),
    .Sdr_init_done     (Sdr_init_done),
    .Sdr_init_ref_vld  (Sdr_init_ref_vld),
    .Sdr_busy          (Sdr_busy),
    .App_wr_en         (App_wr_en),
    .App_wr_addr       (App_wr_addr),
    .App_wr_dm         (App_wr_dm),
    .App_wr_din        (App_wr_din),
    .App_rd_en         (App_rd_en),
    .App_rd_addr       (App_rd_addr),
    .Sdr_rd_en         (Sdr_rd_en),
    .Sdr_rd_dout       (Sdr_rd_dout)
);

// ===================== TF MUSIC.PCM -> HDMI 48 kHz =====================
// Guard the fixed song timeline against the previous 60-second PCM file.
// File size is stable after directory scan; register the comparison before
// crossing clocks rather than distributing a changing 32-bit metadata bus.
always @(posedge sd_card_clk or posedge rst_all) begin
    if (rst_all) audio_song_matches_sd <= 1'b0;
    else audio_song_matches_sd <= (audio_file_bytes == 32'd40174240);
end
always @(posedge audio_mclk or posedge rst_all) begin
    if (rst_all) audio_song_matches_audio_sync <= 2'b00;
    else audio_song_matches_audio_sync <=
        {audio_song_matches_audio_sync[0],audio_song_matches_sd};
end
always @(posedge video_clk or posedge rst_all) begin
    if (rst_all) audio_song_matches_video_sync <= 2'b00;
    else audio_song_matches_video_sync <=
        {audio_song_matches_video_sync[0],audio_song_matches_sd};
end
audio_lyric_timeline u_audio_lyric_timeline (
    .I_audio_clk(audio_mclk), .I_video_clk(video_clk), .I_rst(rst_all),
    .I_stream_enable(audio_stream_enable_sync[1]),
    .I_song_matches(audio_song_matches_audio_sync[1]),
    .I_sample_read(audio_fifo_read && !audio_fifo_empty),
    .O_line_video(lyric_line_video), .O_next_line_video(lyric_next_line_video),
    .O_sung_chars_video(lyric_sung_chars_video), .O_red_pixels_video(lyric_red_pixels_video)
);

// SD works in bursts while HDMI consumes exactly one stereo word per sample.
// A dual-clock FIFO absorbs the latency variation and starts playback only
// after 128 words have been prefetched.  Register the write-side flow-control
// decision in the SD clock domain: this removes the FIFO used-count/decode
// chain from the SD reader's state enables.  The 256-word stop threshold
// leaves room for one complete 512-byte sector plus ample guard space, so the
// one-cycle response cannot overflow the 512-word FIFO.
always @(posedge sd_card_clk or posedge rst_all) begin
    if (rst_all)
        audio_fifo_ready <= 1'b0;
    else
        audio_fifo_ready <= !audio_fifo_full &&
                            (audio_fifo_wrusedw <= 9'd256);
end

assign audio_pcm_selected = audio_stream_enable_sync[1] && audio_pcm_playing;

// Synchronize the long-lived stream enable into the audio clock domain.  PCM
// selection itself changes only at a stereo-frame boundary inside the
// serializer, so the downstream I2S receiver never sees a half-frame source.
always @(posedge audio_mclk or posedge rst_all) begin
    if (rst_all)
        audio_stream_enable_sync <= 2'b00;
    else
        audio_stream_enable_sync <= {audio_stream_enable_sync[0],
                                     audio_stream_enable};
end

rfifo_32_32_512 #(
    .SHOW_AHEAD_EN     (1'b1)
) u_audio_pcm_fifo (
    .clkw              (sd_card_clk),
    .clkr              (audio_mclk),
    .rst               (rst_all | ~audio_stream_enable),
    .we                (audio_pcm_wr_en),
    .re                (audio_fifo_read),
    .di                (audio_pcm_wr_data),
    .dout              (audio_fifo_rd_data),
    .valid             (),
    .full_flag         (audio_fifo_full),
    .empty_flag        (audio_fifo_empty),
    .afull             (),
    .aempty            (),
    .wrusedw           (audio_fifo_wrusedw),
    .rdusedw           (audio_fifo_rdusedw)
);

hdmi_audio_pcm_i2s_64fs #(
    .START_LEVEL       (128)
) u_hdmi_audio_pcm_i2s_64fs (
    .I_mclk            (audio_mclk),
    .I_rst             (rst_all),
    .I_enable          (audio_stream_enable_sync[1]),
    .I_pcm_data        (audio_fifo_rd_data),
    .I_pcm_empty       (audio_fifo_empty),
    .I_pcm_level       (audio_fifo_rdusedw),
    .I_volume_level    (uart_volume_level),
    .O_pcm_read        (audio_fifo_read),
    .O_i2s_BCLK        (audio_i2s_bclk),
    .O_i2s_LRCK        (audio_i2s_lrck),
    .O_i2s_DOUT        (audio_i2s_dout),
    .O_playing         (audio_pcm_playing),
    .O_underflow       (audio_pcm_underflow)
);

// The PCM serializer keeps its clocks running even while disabled/empty.
// Send silence until real TF samples are buffered; never play a startup scale.

I2S_receiver u_i2s_receiver(
    .I_clk              (video_clk),
    .I_rst              (rst_all),
    .I_i2s_BCLK         (audio_i2s_bclk),
    .I_i2s_LRCK         (audio_i2s_lrck),
    .I_i2s_DOUT         (audio_i2s_dout),
    .O_audio_valid      (audio_valid),
    .O_audio_left_data  (audio_left_data),
    .O_audio_right_data (audio_right_data)
);

// Safety audio is mixed after the I2S receiver.  This keeps the existing
// SD/FIFO/I2S clocks untouched and guarantees that the alarm remains audible
// even if UART volume is zero.  Front danger has highest sound priority,
// followed by both sides, then a single directional side warning. Rear uses
// the existing bilateral fast alarm and music ducking, without another mixer.
audio_alarm_mixer u_audio_alarm_mixer (
    .I_clk              (video_clk),
    .I_rst              (rst_all),
    .I_audio_valid      (audio_valid),
    .I_audio_left       (audio_left_data),
    .I_audio_right      (audio_right_data),
    .I_hazard_front     (hazard_front | hazard_rear),
    .I_hazard_left      (hazard_left),
    .I_hazard_right     (hazard_right),
    .O_audio_valid      (alarm_audio_valid),
    .O_audio_left       (alarm_audio_left_data),
    .O_audio_right      (alarm_audio_right_data)
);

// HDMI ACR：N=6144 对应 48 kHz，CTS 根据实际音频样本间隔动态测量。
audio_arc_calculate #(
    .ACR_N             (6144)
) u_audio_arc_calculate (
    .I_clk             (video_clk),
    .I_rst             (rst_all),
    .I_audio_valid     (alarm_audio_valid),
    .O_acr_valid       (acr_valid),
    .O_acr_cts         (acr_cts),
    .O_acr_n           (acr_n)
);

// ===================== RGB/DE 转 AXIS 视频 =====================
video_rgb_to_axis_640x480 u_video_rgb_to_axis_640x480(
    .I_clk         (video_clk),
    .I_rst         (rst_all),
    .I_vs          (adjusted_vs),
    .I_de          (adjusted_de),
    .I_rgb         (vout_data_hazard),
    .O_video_user  (axis_s_user),
    .O_video_valid (axis_s_valid),
    .O_video_last  (axis_s_last),
    .O_video_data  (axis_s_data)
);

// 上电后自动打一拍，触发一次 EDID 读取
startup_pulse #(
    .CNT_MAX(20'd100000)
) u_startup_pulse (
    .I_clk   (video_clk),
    .I_rst   (rst_all),
    .O_pulse (edid_trig)
);

// ===================== HDMI 1.4b 发射 =====================
hdmi_1_4b_transmitter_core_wrapper #(
    .DEVICE                 ( "EG"       ),
    .HTOTAL                 ( 800        ),
    .HSA                    ( 96         ),
    .HFP                    ( 16         ),
    .HBP                    ( 48         ),
    .HACTIVE                ( 640        ),
    .VTOTAL                 ( 525        ),
    .VSA                    ( 2          ),
    .VFP                    ( 10         ),
    .VBP                    ( 33         ),
    .VACTIVE                ( 480        ),
    .VIDEO_VIC              ( 1          ),
    .VIDEO_TPG              ( "Disable"  ),
    .VIDEO_FORMAT           ( "RGB"      ),
    .AUDIO_SAMPLE_RATE      ( "48K"      ),
    .IIC_SCL_DIV            ( 250        )
) u_hdmi_1_4b_transmitter_core_wrapper(
    .I_pixel_clk        (video_clk),
    .I_rst              (rst_all),
    .I_edid_read_trig   (edid_trig),
    .O_edid_read_valid  (edid_valid),
    .O_edid_read_data   (edid_data),

    .I_axis_s_user      (axis_s_user),
    .I_axis_s_valid     (axis_s_valid),
    .I_axis_s_last      (axis_s_last),
    .I_axis_s_data      (axis_s_data),
    .O_axis_s_ready     (axis_s_ready),

    .I_audio_valid      (alarm_audio_valid),
    .I_audio_left_data  (alarm_audio_left_data),
    .I_audio_right_data (alarm_audio_right_data),
    .I_acr_valid        (acr_valid),
    .I_acr_cts          (acr_cts),
    .I_acr_n            (acr_n),

    .O_video_locked     (),
    .O_ddc_scl          (HDMI_DDC_SCL),
    .IO_ddc_sda         (HDMI_DDC_SDA),

    .O_ch0_tmds_data    (tmds_ch0_data),
    .O_ch1_tmds_data    (tmds_ch1_data),
    .O_ch2_tmds_data    (tmds_ch2_data),
    .O_clk_tmds_data    (tmds_clk_data)
);

hdmi_phy_wrapper #(
    .DEVICE ( "EG" )
) u_hdmi2phy_wrapper(
    .I_pixel_clk        (video_clk),
    .I_serial_clk       (hdmi_5x_clk),
    .I_rst              (rst_all),
    .I_tmds_channel_0   (tmds_ch0_data),
    .I_tmds_channel_1   (tmds_ch1_data),
    .I_tmds_channel_2   (tmds_ch2_data),
    .I_tmds_channel_clk (tmds_clk_data),
    .O_tmds_ch0_p       (HDMI_D0_P),
    .O_tmds_ch1_p       (HDMI_D1_P),
    .O_tmds_ch2_p       (HDMI_D2_P),
    .O_tmds_clk_p       (HDMI_CLK_P)
);

endmodule
