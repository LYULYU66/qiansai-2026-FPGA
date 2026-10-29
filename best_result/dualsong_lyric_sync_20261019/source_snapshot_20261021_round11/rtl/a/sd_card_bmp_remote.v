
// Isolated copy of the single-board wrapper: only expose live BMP metadata.
// Its SD/FAT/PCM/resample implementation is otherwise unchanged.
module sd_card_bmp_remote #(
    parameter integer CLK_FREQ_HZ       = 100_000_000,
    parameter integer TOTAL_IMAGES      = 4,
    parameter [2:0]   SCAN_TARGET_COUNT = TOTAL_IMAGES,
    parameter integer SCAN_TIMEOUT_CYCLES = 1_000_000_000,
    parameter integer LOAD_TIMEOUT_CYCLES = 300_000_000,
    parameter integer ABORT_HOLD_CYCLES    = 32,
    parameter         AUTO_PLAY_DEFAULT    = 1'b0,
    parameter         ENABLE_RESAMPLE     = 0,
    parameter         FAST_AUDIO_START    = 0,
    parameter         PIPELINED_CLUSTER_ADDR = 0,
    parameter         DUAL_SONG = 0,
    parameter integer LOCAL_FIRST = 0,
    parameter integer OUT_WIDTH           = 640,
    parameter integer OUT_HEIGHT          = 480
)(
    input                       clk,
    input                       rst,
    input                       key_next,
    input                       key_auto,
    input                       I_warning_hold,
    input  [15:0]               bmp_width,
    input  [15:0]               bmp_height,
    output reg                  display_valid,
    output                      warning_image_ready,
    output      [3:0]           state_code,
    output      [3:0]           image_number,

    input                       write_finish_toggle,
    output reg [2:0]            write_buf_idx,
    output reg [2:0]            disp_buf_idx,
    output reg                  load_abort,

    output                      write_req,
    input                       write_req_ack,
    output                      write_en,
    output [31:0]               write_data,
    output                      write_top_down,
    output reg [127:0]          source_resolutions,
    output [31:0]              live_source_resolution,
    input                       write_pixel_ready,

    // Packed 48 kHz/16-bit/stereo PCM stream for the asynchronous audio FIFO.
    input                       audio_fifo_ready,
    input       [2:0]           audio_song_request,
    output      [2:0]           audio_selected_song,
    output reg                  audio_pcm_wr_en,
    output reg [31:0]           audio_pcm_data,
    output reg                  audio_stream_enable,
    output [31:0]               audio_file_bytes,

    output                      SD_nCS,
    output                      SD_DCLK,
    output                      SD_MOSI,
    input                       SD_MISO
);

localparam [2:0] IMAGE_LIMIT = (TOTAL_IMAGES > 7) ? 3'd7 : TOTAL_IMAGES;

wire key_next_press;
wire key_auto_press;

wire             sd_sec_read;
wire [31:0]      sd_sec_read_addr;
wire [7:0]       sd_sec_read_data;
wire             sd_sec_read_data_valid;
wire             sd_sec_read_end;
wire [3:0]       state_code_i;
wire             bmp_data_wr_en;
wire [23:0]      bmp_data;
wire             sd_init_done;
wire             bmp_ready;
wire             scan_done;
wire             scan_found_valid;
wire [31:0]      scan_found_sector;
wire [31:0]      scan_found_cluster;
wire [2:0]       scan_found_total;
wire             audio_file_found;
wire [5:0]       audio_songs_found;
wire             audio_idle, song_run, audio_abort;
wire [2:0]       selected_song;
assign audio_selected_song=selected_song;
song_stream_control u_song_switch (
    .clk(clk),.rst(rst),.requested_song(DUAL_SONG ? audio_song_request : 3'd0),
    .songs_found(audio_songs_found),.reader_idle(audio_idle),
    .selected_song(selected_song),.run_enable(song_run)
);
wire             audio_byte_valid;
wire [7:0]       audio_byte_data;
wire [15:0]      source_width, source_height;
assign live_source_resolution={source_width,source_height};

reg              scan_start_pulse;
reg              load_start_pulse;
reg [31:0]       load_sector;
reg [31:0]       load_cluster;
reg              scan_kicked;
reg              scan_complete_latched;
reg              auto_play_en;
reg [31:0]       auto_cnt;
reg [2:0]        img_found_count;
reg [2:0]        img_idx;              // 当前真正显示中的图片编号
reg [2:0]        load_idx;             // 当前正在写入的图片编号
reg [31:0]       img_sector0;
reg [31:0]       img_sector1;
reg [31:0]       img_sector2;
reg [31:0]       img_sector3;
reg [31:0]       img_sector4;
reg [31:0]       img_sector5;
reg [31:0]       img_sector6;
reg [31:0]       img_cluster0;
reg [31:0]       img_cluster1;
reg [31:0]       img_cluster2;
reg [31:0]       img_cluster3;
reg [31:0]       img_cluster4;
reg [31:0]       img_cluster5;
reg [31:0]       img_cluster6;
reg [2:0]        next_req_count;
reg              load_busy;
reg [31:0]       load_timeout_cnt;
reg [31:0]       scan_timeout_cnt;
reg [7:0]        abort_hold_cnt;
reg              reader_started;
reg [2:0]        preload_next_idx;     // 依次把扫描到的图片预载入 buffer0~3
reg              preload_done;
reg [6:0]        cache_valid;          // 对应已扫描/预载入的图片
reg [1:0]        audio_byte_idx;
reg [23:0]       audio_pack;
reg [1:0]        warning_hold_sync;
always @(posedge clk or posedge rst) begin
    if (rst) warning_hold_sync <= 2'b00;
    else warning_hold_sync <= {warning_hold_sync[0], I_warning_hold};
end

// bmp_ready 先表示“源文件读取/送 FIFO 完成”；真正切显示要等 write_finish_toggle 同步后
reg              source_done_seen;
reg              write_done_seen;

// 同步 mem_clk 域的 write_finish_toggle
reg [2:0]        wrfin_tgl_sync;
wire             write_finish_pulse;

wire auto_tick;
wire [2:0] next_cached_idx;
wire [2:0] first_cached_idx;
wire       multiple_cached;
wire source_done_now;
wire write_done_now;
wire load_complete_now;
wire load_timeout_hit;

assign write_en   = bmp_data_wr_en;
assign write_data = {bmp_data[23:16], bmp_data[15:8], bmp_data[7:0], 8'b0};
assign auto_tick  = (auto_cnt == (CLK_FREQ_HZ - 1));
assign next_cached_idx = next_cached_index(img_idx, cache_valid);
assign first_cached_idx = first_cached_index(cache_valid);
assign multiple_cached = (cache_valid[0] && (|cache_valid[6:1])) ||
                         (cache_valid[1] && (|cache_valid[6:2])) ||
                         (cache_valid[2] && (|cache_valid[6:3])) ||
                         (cache_valid[3] && (|cache_valid[6:4])) ||
                         (cache_valid[4] && (|cache_valid[6:5])) ||
                         (cache_valid[5] && cache_valid[6]);
assign write_finish_pulse = wrfin_tgl_sync[2] ^ wrfin_tgl_sync[1];
assign source_done_now = source_done_seen || (reader_started && bmp_ready);
assign write_done_now  = write_done_seen || write_finish_pulse;
assign load_complete_now = source_done_now && write_done_now;
assign load_timeout_hit = load_busy && !load_complete_now &&
                          (load_timeout_cnt >= LOAD_TIMEOUT_CYCLES - 1);
assign state_code = state_code_i;
wire audio_preload_ready = (TOTAL_IMAGES > 4) ?
                            (LOCAL_FIRST ? preload_done :
                             (preload_done || preload_next_idx >= 3'd4)) :
                            (FAST_AUDIO_START ? scan_complete_latched : preload_done);
// 20261019: registered. It was a combinational AND of reader/controller
// state used as the PCM packer's asynchronous reset (glitches could reset the
// packer mid-sample) and fed the reader's long audio-enable decode chain.
wire audio_stream_enable_next = audio_preload_ready &&
                             (DUAL_SONG ? audio_songs_found[selected_song] : audio_file_found) &&
                             (!DUAL_SONG || song_run) &&
                             sd_init_done && !load_abort && !audio_abort;
always @(posedge clk or posedge rst) begin
    if (rst) audio_stream_enable <= 1'b0;
    else audio_stream_enable <= audio_stream_enable_next;
end
// 对外显示采用 1~4 的图片序号；首帧尚未提交时显示 0。
// 预载完成后 img_idx 与 disp_buf_idx 同拍更新，序号始终对应当前读缓存。
assign image_number = display_valid ? ({1'b0, img_idx} + 4'd1) : 4'd0;
// This bit remains the legacy “first four images ready” indicator.
assign warning_image_ready = cache_valid[3];
// Publish metadata only with its fully committed SDRAM frame.
always @(posedge clk or posedge rst) begin
    if(rst) source_resolutions<=128'd0;
    else if(!sd_init_done) source_resolutions<=128'd0;
    else if(load_busy && load_complete_now && load_idx<3'd4)
        source_resolutions[load_idx[1:0]*32 +: 32]<={source_width,source_height};
end

// MUSIC.PCM byte order is L-low, L-high, R-low, R-high. Pack one complete
// stereo sample into each FIFO word without changing the byte order.
always @(posedge clk or posedge rst) begin
    if (rst || !audio_stream_enable) begin
        audio_byte_idx <= 2'd0;
        audio_pack     <= 24'd0;
        audio_pcm_wr_en<= 1'b0;
        audio_pcm_data <= 32'd0;
    end else begin
        audio_pcm_wr_en <= 1'b0;
        if (audio_byte_valid) begin
            case (audio_byte_idx)
                2'd0: audio_pack[7:0]   <= audio_byte_data;
                2'd1: audio_pack[15:8]  <= audio_byte_data;
                2'd2: audio_pack[23:16] <= audio_byte_data;
                2'd3: begin
                    audio_pcm_data  <= {audio_byte_data, audio_pack};
                    audio_pcm_wr_en <= 1'b1;
                end
                default: ;
            endcase
            audio_byte_idx <= audio_byte_idx + 2'd1;
        end
    end
end

key_press_debounce #(
    .CLK_FREQ_HZ (CLK_FREQ_HZ),
    .DEBOUNCE_MS (15)
) u_key_next (
    .clk        (clk),
    .rst        (rst),
    .button_in  (key_next),
    .press_pulse(key_next_press)
);

key_press_debounce #(
    .CLK_FREQ_HZ (CLK_FREQ_HZ),
    .DEBOUNCE_MS (20)
) u_key_auto (
    .clk        (clk),
    .rst        (rst),
    .button_in  (key_auto),
    .press_pulse(key_auto_press)
);

function [2:0] next_cached_index;
    input [2:0] cur;
    input [6:0] valid_mask;
    begin
        case (cur)
            3'd0: begin
                if (valid_mask[1]) next_cached_index=3'd1;
                else if (valid_mask[2]) next_cached_index=3'd2;
                else if (valid_mask[3]) next_cached_index=3'd3;
                else if (valid_mask[4]) next_cached_index=3'd4;
                else if (valid_mask[5]) next_cached_index=3'd5;
                else if (valid_mask[6]) next_cached_index=3'd6;
                else next_cached_index=3'd0;
            end
            3'd1: begin
                if (valid_mask[2]) next_cached_index=3'd2;
                else if (valid_mask[3]) next_cached_index=3'd3;
                else if (valid_mask[4]) next_cached_index=3'd4;
                else if (valid_mask[5]) next_cached_index=3'd5;
                else if (valid_mask[6]) next_cached_index=3'd6;
                else if (valid_mask[0]) next_cached_index=3'd0;
                else next_cached_index=3'd1;
            end
            3'd2: begin
                if (valid_mask[3]) next_cached_index=3'd3;
                else if (valid_mask[4]) next_cached_index=3'd4;
                else if (valid_mask[5]) next_cached_index=3'd5;
                else if (valid_mask[6]) next_cached_index=3'd6;
                else if (valid_mask[0]) next_cached_index=3'd0;
                else if (valid_mask[1]) next_cached_index=3'd1;
                else next_cached_index=3'd2;
            end
            3'd3: begin
                if (valid_mask[4]) next_cached_index=3'd4;
                else if (valid_mask[5]) next_cached_index=3'd5;
                else if (valid_mask[6]) next_cached_index=3'd6;
                else if (valid_mask[0]) next_cached_index=3'd0;
                else if (valid_mask[1]) next_cached_index=3'd1;
                else if (valid_mask[2]) next_cached_index=3'd2;
                else next_cached_index=3'd3;
            end
            3'd4: begin
                if (valid_mask[5]) next_cached_index=3'd5;
                else if (valid_mask[6]) next_cached_index=3'd6;
                else if (valid_mask[0]) next_cached_index=3'd0;
                else if (valid_mask[1]) next_cached_index=3'd1;
                else if (valid_mask[2]) next_cached_index=3'd2;
                else if (valid_mask[3]) next_cached_index=3'd3;
                else next_cached_index=3'd4;
            end
            3'd5: begin
                if (valid_mask[6]) next_cached_index=3'd6;
                else if (valid_mask[0]) next_cached_index=3'd0;
                else if (valid_mask[1]) next_cached_index=3'd1;
                else if (valid_mask[2]) next_cached_index=3'd2;
                else if (valid_mask[3]) next_cached_index=3'd3;
                else if (valid_mask[4]) next_cached_index=3'd4;
                else next_cached_index=3'd5;
            end
            default: begin
                if (valid_mask[0]) next_cached_index=3'd0;
                else if (valid_mask[1]) next_cached_index=3'd1;
                else if (valid_mask[2]) next_cached_index=3'd2;
                else if (valid_mask[3]) next_cached_index=3'd3;
                else if (valid_mask[4]) next_cached_index=3'd4;
                else if (valid_mask[5]) next_cached_index=3'd5;
                else next_cached_index=3'd6;
            end
        endcase
    end
endfunction

function [2:0] first_cached_index;
    input [6:0] valid_mask;
    begin
        if (valid_mask[0]) first_cached_index=3'd0;
        else if (valid_mask[1]) first_cached_index=3'd1;
        else if (valid_mask[2]) first_cached_index=3'd2;
        else if (valid_mask[3]) first_cached_index=3'd3;
        else if (valid_mask[4]) first_cached_index=3'd4;
        else if (valid_mask[5]) first_cached_index=3'd5;
        else first_cached_index=3'd6;
    end
endfunction

// Local-pair mode: B's dashboard (TF5) first, then A's home picture (TF1),
// then the rest (20261021: A's first picture no longer waits for all three
// B pages, about 1.5 s earlier at the 12.5 MHz SPI clock).
function [2:0] preload_order;
    input [2:0] seq;
    begin
        if (LOCAL_FIRST && TOTAL_IMAGES > 4) begin
            case (seq)
                3'd0: preload_order=3'd4;
                3'd1: preload_order=3'd0;
                3'd2: preload_order=3'd5;
                3'd3: preload_order=3'd6;
                3'd4: preload_order=3'd1;
                3'd5: preload_order=3'd2;
                default: preload_order=3'd3;
            endcase
        end else preload_order=seq;
    end
endfunction

function [31:0] sector_lut;
    input [2:0] idx;
    begin
        case (idx)
            3'd0: sector_lut=img_sector0;
            3'd1: sector_lut=img_sector1;
            3'd2: sector_lut=img_sector2;
            3'd3: sector_lut=img_sector3;
            3'd4: sector_lut=img_sector4;
            3'd5: sector_lut=img_sector5;
            3'd6: sector_lut=img_sector6;
            default: sector_lut = img_sector0;
        endcase
    end
endfunction

function [31:0] cluster_lut;
    input [2:0] idx;
    begin
        case (idx)
            3'd0: cluster_lut=img_cluster0;
            3'd1: cluster_lut=img_cluster1;
            3'd2: cluster_lut=img_cluster2;
            3'd3: cluster_lut=img_cluster3;
            3'd4: cluster_lut=img_cluster4;
            3'd5: cluster_lut=img_cluster5;
            3'd6: cluster_lut=img_cluster6;
            default: cluster_lut = img_cluster0;
        endcase
    end
endfunction

always @(posedge clk or posedge rst) begin
    if (rst) begin
        wrfin_tgl_sync        <= 3'b000;
        scan_start_pulse      <= 1'b0;
        load_start_pulse      <= 1'b0;
        load_sector           <= 32'd0;
        load_cluster          <= 32'd0;
        scan_kicked           <= 1'b0;
        scan_complete_latched <= 1'b0;
        auto_play_en          <= AUTO_PLAY_DEFAULT;
        auto_cnt              <= 32'd0;
        img_found_count       <= 3'd0;
        img_idx               <= 3'd0;
        load_idx              <= 3'd0;
        write_buf_idx         <= 3'd0;
        disp_buf_idx          <= 3'd0;
        img_sector0           <= 32'd0;
        img_sector1           <= 32'd0;
        img_sector2           <= 32'd0;
        img_sector3           <= 32'd0;
        img_sector4           <= 32'd0;
        img_sector5           <= 32'd0;
        img_sector6           <= 32'd0;
        img_cluster0          <= 32'd0;
        img_cluster1          <= 32'd0;
        img_cluster2          <= 32'd0;
        img_cluster3          <= 32'd0;
        img_cluster4          <= 32'd0;
        img_cluster5          <= 32'd0;
        img_cluster6          <= 32'd0;
        next_req_count        <= 3'd0;
        load_busy             <= 1'b0;
        load_timeout_cnt      <= 32'd0;
        scan_timeout_cnt      <= 32'd0;
        load_abort            <= 1'b0;
        abort_hold_cnt        <= 8'd0;
        reader_started        <= 1'b0;
        preload_next_idx      <= 3'd0;
        preload_done          <= 1'b0;
        cache_valid           <= 7'b0000000;
        source_done_seen      <= 1'b0;
        write_done_seen       <= 1'b0;
        display_valid         <= 1'b0;
    end else begin
        wrfin_tgl_sync   <= {wrfin_tgl_sync[1:0], write_finish_toggle};
        scan_start_pulse <= 1'b0;
        load_start_pulse <= 1'b0;
        if (abort_hold_cnt != 8'd0) begin
            load_abort     <= 1'b1;
            abort_hold_cnt <= abort_hold_cnt - 8'd1;
        end else begin
            load_abort <= 1'b0;
        end

        if (!sd_init_done) begin
            scan_kicked           <= 1'b0;
            scan_complete_latched <= 1'b0;
            auto_play_en          <= AUTO_PLAY_DEFAULT;
            auto_cnt              <= 32'd0;
            img_found_count       <= 3'd0;
            img_idx               <= 3'd0;
            load_idx              <= 3'd0;
            // Cached file addresses and the load request address are always
            // rewritten (gated by img_found_count/load_start) before use.
            write_buf_idx         <= 3'd0;
            disp_buf_idx          <= 3'd0;
            next_req_count        <= 3'd0;
            load_busy             <= 1'b0;
            load_timeout_cnt      <= 32'd0;
            scan_timeout_cnt      <= 32'd0;
            reader_started        <= 1'b0;
            preload_next_idx      <= 3'd0;
            preload_done          <= 1'b0;
            cache_valid           <= 7'b0000000;
            source_done_seen      <= 1'b0;
            write_done_seen       <= 1'b0;
            display_valid         <= 1'b0;
        end else begin
            // bmp_read asserts scan_done on the same cycle as the final
            // scan_found_valid item.  Latch completion so that the preload
            // controller consumes it on the following cycle, after the final
            // candidate address/count has been registered.
            if (scan_done)
                scan_complete_latched <= 1'b1;

            // 扫描阶段缓存前 4 张图的起始 sector
            if (scan_found_valid) begin
                case (img_found_count)
                    3'd0: img_sector0 <= scan_found_sector;
                    3'd1: img_sector1 <= scan_found_sector;
                    3'd2: img_sector2 <= scan_found_sector;
                    3'd3: img_sector3 <= scan_found_sector;
                    3'd4: img_sector4 <= scan_found_sector;
                    3'd5: img_sector5 <= scan_found_sector;
                    3'd6: img_sector6 <= scan_found_sector;
                    default: ;
                endcase

                case (img_found_count)
                    3'd0: img_cluster0 <= scan_found_cluster;
                    3'd1: img_cluster1 <= scan_found_cluster;
                    3'd2: img_cluster2 <= scan_found_cluster;
                    3'd3: img_cluster3 <= scan_found_cluster;
                    3'd4: img_cluster4 <= scan_found_cluster;
                    3'd5: img_cluster5 <= scan_found_cluster;
                    3'd6: img_cluster6 <= scan_found_cluster;
                    default: ;
                endcase

                if (img_found_count < IMAGE_LIMIT)
                    img_found_count <= img_found_count + 3'd1;
            end

            // 必须先见到读取器离开 IDLE，之后的 ready 才是真正的“源图发送完成”。
            if (load_busy && !bmp_ready)
                reader_started <= 1'b1;

            if (load_busy && reader_started && bmp_ready)
                source_done_seen <= 1'b1;

            // 记住写帧完成脉冲，避免“先写完后源结束”导致脉冲丢失而卡死
            if (load_busy && write_finish_pulse)
                write_done_seen <= 1'b1;

            // 扫描也设置独立看门狗；底层命令无应答时，中止当前 SPI 事务后重新扫描。
            if (scan_kicked && !scan_complete_latched && !scan_done) begin
                if (scan_timeout_cnt >= SCAN_TIMEOUT_CYCLES - 1) begin
                    scan_timeout_cnt <= 32'd0;
                    scan_kicked      <= 1'b0;
                    load_abort       <= 1'b1;
                    abort_hold_cnt   <= ABORT_HOLD_CYCLES - 1;
                end else begin
                    scan_timeout_cnt <= scan_timeout_cnt + 32'd1;
                end
            end else begin
                scan_timeout_cnt <= 32'd0;
            end

            // 只有“源图送完 + 整帧写完”都满足，才把对应缓存标记为可显示。
            // 四张图各占用独立 SDRAM 帧区；按键切图时无需再次访问 TF 卡。
            if (load_busy && load_complete_now) begin
                load_busy        <= 1'b0;
                load_timeout_cnt <= 32'd0;
                reader_started   <= 1'b0;
                source_done_seen <= 1'b0;
                write_done_seen  <= 1'b0;
                cache_valid[load_idx] <= 1'b1;
                preload_next_idx <= preload_next_idx + 3'd1;

                // 第一帧完整写入后立即提交显示，不再等待其余三帧全部预载。
                // 后续图片继续在后台装入，避免任一后续文件超时让数码管长期停在 0。
                if (!display_valid) begin
                    img_idx       <= load_idx;
                    disp_buf_idx  <= load_idx;
                    display_valid <= 1'b1;
                    // Ignore any power-up key transient accumulated while the
                    // card and first frame were still being initialized.
                    next_req_count<= 3'd0;
                end
            end else if (load_busy) begin
                if (load_timeout_hit) begin
                    // 超时后同时复位 BMP 读取器和 SDRAM 写通道，避免半帧任务残留导致永久卡死。
                    load_busy             <= 1'b0;
                    load_timeout_cnt      <= 32'd0;
                    reader_started        <= 1'b0;
                    source_done_seen      <= 1'b0;
                    write_done_seen       <= 1'b0;
                    load_abort            <= 1'b1;
                    abort_hold_cnt        <= ABORT_HOLD_CYCLES - 1;
                    // 坏文件只影响自己的缓存位，继续预载下一张，不阻塞其他图片。
                    preload_next_idx      <= preload_next_idx + 3'd1;
                end else begin
                    // Resize mode: timeout means no progress, not a large file.
                    load_timeout_cnt <= (ENABLE_RESAMPLE &&
                        (sd_sec_read_data_valid || bmp_data_wr_en)) ? 32'd0 : load_timeout_cnt+32'd1;
                end
            end else begin
                load_timeout_cnt <= 32'd0;
            end

            // 上电或扫描看门狗恢复后，自动发起一次“扫描前 4 张 BMP”。
            if (!scan_kicked && !scan_complete_latched && bmp_ready && !load_abort &&
                (abort_hold_cnt == 8'd0)) begin
                scan_start_pulse      <= 1'b1;
                scan_kicked           <= 1'b1;
                scan_complete_latched <= 1'b0;
                auto_cnt              <= 32'd0;
                img_found_count       <= 3'd0;
                img_idx               <= 3'd0;
                load_idx              <= 3'd0;
                write_buf_idx         <= 3'd0;
                disp_buf_idx          <= 3'd0;
                next_req_count        <= 3'd0;
                preload_next_idx      <= 3'd0;
                preload_done          <= 1'b0;
                cache_valid           <= 7'b0000000;
                // 文件地址在复位时已经清零；重新扫描会按 img_found_count 覆盖有效项。
                // 此处不重复清零，避免 abort/重扫条件形成高扇出的寄存器 CE 关键路径。
                display_valid         <= 1'b0;
                load_busy             <= 1'b0;
                reader_started        <= 1'b0;
                source_done_seen      <= 1'b0;
                write_done_seen       <= 1'b0;
            end else begin
                // 预载期间最多排队 7 次按键；预载结束后按缓存地址近即时切换。
                if (warning_hold_sync[1])
                    next_req_count <= 3'd0;
                else if (display_valid && key_next_press &&
                    (next_req_count != 3'd7))
                    next_req_count <= next_req_count + 3'd1;

                // 自动播放开/关
                if (display_valid && key_auto_press) begin
                    auto_play_en <= ~auto_play_en;
                    auto_cnt     <= 32'd0;
                end

                // 至少有两张完整缓存后即可自动播放，后台预载不阻塞轮播计时。
                if (auto_play_en && display_valid && multiple_cached &&
                    !warning_hold_sync[1]) begin
                    if (auto_tick)
                        auto_cnt <= 32'd0;
                    else
                        auto_cnt <= auto_cnt + 32'd1;
                end else begin
                    auto_cnt <= 32'd0;
                end

                // 手动切换优先，可在其余图片仍后台预载时切换到已完成的缓存。
                if (display_valid && !warning_hold_sync[1] &&
                    (next_req_count != 3'd0) &&
                    (next_cached_idx != img_idx)) begin
                    img_idx         <= next_cached_idx;
                    disp_buf_idx    <= next_cached_idx;
                    next_req_count  <= key_next_press ? next_req_count :
                                       (next_req_count - 3'd1);
                    auto_cnt        <= 32'd0;
                end else if (display_valid && !warning_hold_sync[1] &&
                             auto_play_en && !key_auto_press &&
                             auto_tick && multiple_cached) begin
                    img_idx      <= next_cached_idx;
                    disp_buf_idx <= next_cached_idx;
                    auto_cnt     <= 32'd0;
                // 扫描结束后依次把每张图装入同编号的 SDRAM 帧区。
                end else if (scan_complete_latched && !preload_done && !load_busy && bmp_ready &&
                    (abort_hold_cnt == 8'd0) &&
                    (preload_next_idx < img_found_count)) begin
                    load_idx         <= preload_order(preload_next_idx);
                    load_sector      <= sector_lut(preload_order(preload_next_idx));
                    load_cluster     <= cluster_lut(preload_order(preload_next_idx));
                    write_buf_idx    <= preload_order(preload_next_idx);
                    load_start_pulse <= 1'b1;
                    load_busy        <= 1'b1;
                    reader_started   <= 1'b0;
                    source_done_seen <= 1'b0;
                    write_done_seen  <= 1'b0;
                    auto_cnt         <= 32'd0;
                end else if (scan_complete_latched && !preload_done && !load_busy &&
                             (preload_next_idx >= img_found_count)) begin
                    preload_done <= 1'b1;
                    // 正常情况下首帧已在装载完成时提交显示；这里只为“尚未提交”
                    // 的兜底路径选择首个有效缓存，不能在后台预载结束时强制跳回第 1 张。
                    if (!display_valid && |cache_valid) begin
                        img_idx       <= first_cached_idx;
                        disp_buf_idx  <= first_cached_idx;
                        display_valid <= 1'b1;
                    end
                end
            end
        end
    end
end

bmp_read #(.ENABLE_RESAMPLE(ENABLE_RESAMPLE), .FAST_AUDIO_START(FAST_AUDIO_START),
           .DUAL_SONG(DUAL_SONG),
           .PIPELINED_CLUSTER_ADDR(PIPELINED_CLUSTER_ADDR), .OUT_WIDTH(OUT_WIDTH),
           .OUT_HEIGHT(OUT_HEIGHT)) bmp_read_m0(
    .clk                    (clk),
    .rst                    (rst),
    .ready                  (bmp_ready),
    .source_width           (source_width),
    .source_height          (source_height),
    .source_top_down        (write_top_down),
    .write_pixel_ready      (write_pixel_ready),

    .scan_start             (scan_start_pulse),
    .scan_target_count      (SCAN_TARGET_COUNT),
    .scan_done              (scan_done),
    .scan_found_valid       (scan_found_valid),
    .scan_found_sector      (scan_found_sector),
    .scan_found_cluster     (scan_found_cluster),
    .scan_found_total       (scan_found_total),

    .load_start             (load_start_pulse),
    .load_abort             (load_abort),
    .audio_abort            (audio_abort),
    .load_sector            (load_sector),
    .load_cluster           (load_cluster),

    .audio_enable           (audio_stream_enable),
    .audio_fifo_ready       (audio_fifo_ready),
    .audio_song_select      (selected_song),
    .audio_songs_found      (audio_songs_found),
    .audio_idle             (audio_idle),
    .audio_file_found       (audio_file_found),
    .audio_file_bytes       (audio_file_bytes),
    .audio_data_valid       (audio_byte_valid),
    .audio_data             (audio_byte_data),

    .sd_init_done           (sd_init_done),
    .state_code             (state_code_i),
    .bmp_width              (bmp_width),
    .bmp_height             (bmp_height),
    .write_req              (write_req),
    .write_req_ack          (write_req_ack),
    .sd_sec_read            (sd_sec_read),
    .sd_sec_read_addr       (sd_sec_read_addr),
    .sd_sec_read_data       (sd_sec_read_data),
    .sd_sec_read_data_valid (sd_sec_read_data_valid),
    .sd_sec_read_end        (sd_sec_read_end),
    .bmp_data_wr_en         (bmp_data_wr_en),
    .bmp_data               (bmp_data)
);

sd_card_top sd_card_top_m0(
    .clk                    (clk),
    .rst                    (rst),
    .io_abort               (load_abort || audio_abort),
    .SD_nCS                 (SD_nCS),
    .SD_DCLK                (SD_DCLK),
    .SD_MOSI                (SD_MOSI),
    .SD_MISO                (SD_MISO),
    .sd_init_done           (sd_init_done),
    .sd_sec_read            (sd_sec_read),
    .sd_sec_read_addr       (sd_sec_read_addr),
    .sd_sec_read_data       (sd_sec_read_data),
    .sd_sec_read_data_valid (sd_sec_read_data_valid),
    .sd_sec_read_end        (sd_sec_read_end),
    .sd_sec_write           (1'b0),
    .sd_sec_write_addr      (32'd0),
    .sd_sec_write_data      (),
    .sd_sec_write_data_req  (),
    .sd_sec_write_end       ()
);

endmodule

// Switch metadata only after all old sector activity has drained. A fixed
// 16-clock quiet window lets FIFO resets and bundled session metadata settle.
// A missing target file leaves the current track playing. Rapid presses use
// the latest requested state, not a queue of stale toggles.
module song_stream_control (
    input wire clk,rst,reader_idle,
    input wire [2:0] requested_song,
    input wire [5:0] songs_found,
    output reg [2:0] selected_song,
    output reg run_enable
);
reg stopping;
reg [4:0] quiet_count;
always @(posedge clk or posedge rst) begin
    if(rst) begin selected_song<=0; stopping<=0; quiet_count<=0; run_enable<=1; end
    else if(quiet_count!=0) begin
        quiet_count<=quiet_count-1'b1;
        if(quiet_count==1) run_enable<=1;
    end
    else if(stopping) begin
        if(reader_idle) begin
            if(requested_song<6 && songs_found[requested_song]) selected_song<=requested_song;
            stopping<=0; quiet_count<=16;
        end
    end else if(requested_song<6 && requested_song!=selected_song && songs_found[requested_song]) begin
        stopping<=1;
        run_enable<=0;
    end
end
endmodule

module key_press_debounce #(
    parameter integer CLK_FREQ_HZ = 100_000_000,
    parameter integer DEBOUNCE_MS = 20
)(
    input  wire clk,
    input  wire rst,
    input  wire button_in,    // 默认：松开=1，按下=0
    output reg  press_pulse
);

localparam integer DEBOUNCE_CYCLES = (CLK_FREQ_HZ / 1000) * DEBOUNCE_MS;

reg button_sync0;
reg button_sync1;
reg button_stable;
reg [31:0] cnt;

always @(posedge clk or posedge rst) begin
    if (rst) begin
        button_sync0  <= 1'b1;
        button_sync1  <= 1'b1;
        button_stable <= 1'b1;
        cnt           <= 32'd0;
        press_pulse   <= 1'b0;
    end else begin
        button_sync0 <= button_in;
        button_sync1 <= button_sync0;
        press_pulse  <= 1'b0;

        if (button_sync1 == button_stable) begin
            cnt <= 32'd0;
        end else begin
            if (cnt >= DEBOUNCE_CYCLES - 1) begin
                if (button_stable && !button_sync1)
                    press_pulse <= 1'b1;
                button_stable <= button_sync1;
                cnt           <= 32'd0;
            end else begin
                cnt <= cnt + 32'd1;
            end
        end
    end
end

endmodule
