module bmp_read #(
    parameter ENABLE_RESAMPLE=0,
    parameter FAST_AUDIO_START=0,
    parameter PIPELINED_CLUSTER_ADDR=0,
    parameter OUT_WIDTH=640,
    parameter OUT_HEIGHT=480
)(
    input                       clk,
    input                       rst,
    output                      ready,

    // 上电扫描：读取 FAT32 根目录，寻找前 scan_target_count 张 BMP
    input                       scan_start,
    input  [2:0]                scan_target_count,
    output reg                  scan_done,
    output reg                  scan_found_valid,
    output reg [31:0]           scan_found_sector,
    output reg [31:0]           scan_found_cluster,
    output reg [2:0]            scan_found_total,

    // 按指定扇区加载一张图到 SDRAM
    input                       load_start,
    input                       load_abort,
    input  [31:0]               load_sector,
    input  [31:0]               load_cluster,

    // MUSIC.PCM streaming starts after the four pictures have been cached.
    // audio_fifo_ready guarantees room for at least one 512-byte sector.
    input                       audio_enable,
    input                       audio_fifo_ready,
    output reg                  audio_file_found,
    // Read-only metadata for recording-specific overlays; no reader FSM change.
    output wire [31:0]           audio_file_bytes,
    output wire                 audio_data_valid,
    output wire [7:0]           audio_data,

    input                       sd_init_done,
    output reg [3:0]            state_code,
    input  [15:0]               bmp_width,
    input  [15:0]               bmp_height,

    output reg                  write_req,
    input                       write_req_ack,

    output reg                  sd_sec_read,
    output reg [31:0]           sd_sec_read_addr,
    input  [7:0]                sd_sec_read_data,
    input                       sd_sec_read_data_valid,
    input                       sd_sec_read_end,

    output reg                  bmp_data_wr_en,
    output reg [23:0]           bmp_data,
    output wire [15:0]          source_width,
    output wire [15:0]          source_height,
    output wire                source_top_down
    ,input wire                write_pixel_ready
);

localparam [4:0] ST_IDLE          = 5'd0;
localparam [4:0] ST_LOAD_HDR      = 5'd2;
localparam [4:0] ST_LOAD_WAIT     = 5'd3;
localparam [4:0] ST_LOAD_DATA     = 5'd4;
localparam [4:0] ST_FS_PROBE      = 5'd5;
localparam [4:0] ST_FS_BOOT       = 5'd6;
localparam [4:0] ST_FS_CALC0      = 5'd7;
localparam [4:0] ST_FS_CALC1      = 5'd8;
localparam [4:0] ST_FS_CALC2      = 5'd9;
localparam [4:0] ST_DIR_SCAN      = 5'd10;
localparam [4:0] ST_DIR_FAT       = 5'd11;
localparam [4:0] ST_SCAN_PREP     = 5'd12;
localparam [4:0] ST_SCAN_CALC     = 5'd13;
localparam [4:0] ST_SCAN_EMIT     = 5'd14;
localparam [4:0] ST_FS_CHECK      = 5'd15;
localparam [4:0] ST_DIR_NEXT_CALC = 5'd16;
localparam [4:0] ST_DIR_NEXT_ADDR = 5'd17;
localparam [4:0] ST_LOAD_FAT      = 5'd18;
localparam [4:0] ST_LOAD_NEXT_CALC = 5'd19;
localparam [4:0] ST_LOAD_NEXT_ADDR = 5'd20;
localparam [4:0] ST_DIR_FAT_CHECK = 5'd21;
localparam [4:0] ST_AUDIO_START_CALC = 5'd22;
localparam [4:0] ST_AUDIO_START_ADDR = 5'd23;
localparam [4:0] ST_AUDIO_WAIT       = 5'd24;
localparam [4:0] ST_AUDIO_DATA       = 5'd25;
localparam [4:0] ST_AUDIO_FAT        = 5'd26;
localparam [4:0] ST_AUDIO_NEXT_CALC  = 5'd27;
localparam [4:0] ST_AUDIO_NEXT_ADDR  = 5'd28;
localparam [4:0] ST_LOAD_DRAIN       = 5'd29;
localparam [4:0] ST_LOAD_PAUSE       = 5'd30;
localparam [4:0] ST_CLUSTER_SHIFT    = 5'd31;
reg [4:0] cluster_return_state;
reg [31:0] cluster_offset_q;

reg [4:0]  state;
reg [9:0]  rd_cnt;

reg [7:0]  header_0;
reg [7:0]  header_1;
reg [31:0] file_len;
reg [31:0] pixel_offset;
reg [31:0] width;
reg [31:0] height;
reg [15:0] bit_count;
reg [31:0] compression;
reg [31:0] dib_size;
reg [15:0] planes;
wire [31:0] height_abs=height[31] ? (~height+32'd1) : height;
assign source_width=width[15:0];
assign source_height=height_abs[15:0];
assign source_top_down=height[31];
wire resample_ready, resample_done;
reg load_sector_active;
always @(posedge clk or posedge rst) begin
    if(rst) load_sector_active<=0;
    else if(state!=ST_LOAD_DATA || sd_sec_read_end || load_abort) load_sector_active<=0;
    else if(sd_sec_read) load_sector_active<=1;
end

reg [31:0] load_sector_latched;
reg [31:0] load_cluster_latched;
reg [7:0]  load_sector_in_cluster;
reg [31:0] bmp_len_cnt;
reg [1:0]  bmp_byte_idx;

// FAT32 卷信息。优先读取根目录定位 BMP，避免只扫描卡前 64 MiB 时漏掉后面的文件。
reg [31:0] volume_lba;
reg [31:0] mbr_partition_lba;
reg [3:0] mbr_lba_nonzero_bytes;
reg [15:0] fs_bytes_per_sector;
reg [7:0]  fs_sectors_per_cluster;
reg [15:0] fs_reserved_sectors;
reg [7:0]  fs_num_fats;
reg [31:0] fs_fat_size;
reg [31:0] fs_root_cluster;
reg [31:0] fat_start_sector;
reg [31:0] fat_area_sectors;
reg [31:0] first_data_sector;

// FAT32 根目录扫描与候选图片缓存。
reg [31:0] dir_cluster;
reg [7:0]  dir_sector_in_cluster;
reg [7:0]  dir_cluster_hops;
reg [3:0]  dir_post_bmp_sectors;
reg [7:0]  dir_first_byte;
reg [7:0]  dir_name1;
reg [7:0]  dir_name2;
reg [7:0]  dir_name3;
reg [7:0]  dir_name4;
reg [7:0]  dir_name5;
reg [7:0]  dir_name6;
reg [7:0]  dir_name7;
reg [7:0]  dir_ext0;
reg [7:0]  dir_ext1;
reg [7:0]  dir_ext2;
reg [7:0]  dir_attr;
reg [15:0] dir_cluster_hi;
reg [15:0] dir_cluster_lo;
reg [31:0] dir_file_size;
reg        dir_end_seen;
reg [2:0]  dir_candidate_count;
reg [31:0] dir_candidate0;
reg [31:0] dir_candidate1;
reg [31:0] dir_candidate2;
reg [31:0] dir_candidate3;
reg        dir_candidate_pending;
reg [31:0] dir_candidate_pending_cluster;
reg [2:0]  emit_idx;
reg [31:0] emit_cluster;
reg [8:0]  fat_entry_offset;
reg [31:0] fat_next_cluster;
reg        bpb_valid_latched;
reg        fs_check_is_boot;

// Audio file metadata and streaming cursor.
reg [31:0] audio_file_cluster;
reg [31:0] audio_file_size;
assign audio_file_bytes = audio_file_size;
reg [31:0] audio_current_cluster;
reg [7:0]  audio_sector_in_cluster;
// The FSM computes one cluster address at a time.  CALC registers the
// cluster-minus-two result; the following ADDR/EMIT state shifts and adds it.
// This uses the existing state boundary to split the SD-clock critical path.
reg [31:0] selected_address_cluster;
reg [31:0] cluster_index;
reg        cluster_index_ok;   // selected cluster >= 2 when cluster_index was taken
always @(*) begin
    case (state)
        ST_FS_CALC0:     selected_address_cluster = fs_root_cluster;
        ST_DIR_NEXT_CALC:selected_address_cluster = dir_cluster;
        ST_SCAN_CALC:    selected_address_cluster = emit_cluster;
        ST_LOAD_NEXT_CALC:selected_address_cluster = load_cluster_latched;
        default:        selected_address_cluster = audio_current_cluster;
    endcase
end
// The CALC state registers cluster-2 and the cluster>=2 test side by side
// (|cluster[31:1] is exactly cluster>=2). The following state applies the
// clamp through the sectors-per-cluster select: an unknown size gives the
// same zero offset as the former clamped index, without a 32-bit mux after
// the subtract on the 100 MHz path.
wire [31:0] next_cluster_index = selected_address_cluster - 32'd2;
wire        next_cluster_index_ok = |selected_address_cluster[31:1];
wire [31:0] cluster_offset = cluster_sector_offset(cluster_index,
                          cluster_index_ok ? fs_sectors_per_cluster : 8'd0);
// A dedicated existing-width FSM state separates the variable shift from
// the 32-bit sector adder. No sector request occurs in this extra cycle.
wire [31:0] cluster_data_sector = first_data_sector +
    (PIPELINED_CLUSTER_ADDR ? cluster_offset_q : cluster_offset);

// A FAT entry address also has only one consumer at a time.
reg [31:0] selected_fat_cluster;
always @(*) begin
    case (state)
        ST_DIR_SCAN: selected_fat_cluster = dir_cluster;
        ST_LOAD_DATA:selected_fat_cluster = load_cluster_latched;
        default:    selected_fat_cluster = audio_current_cluster;
    endcase
end
wire [31:0] cluster_fat_sector = fat_start_sector + (selected_fat_cluster >> 7);
reg [31:0] audio_byte_count;
// Sector-boundary audio prefetch saves only addresses/state, not image data.
reg audio_cursor_valid, load_paused, idle_seen, load_pending;
reg [4:0] load_resume_state;
reg [31:0] load_resume_addr, audio_resume_addr;
always @(posedge clk or posedge rst) begin
    if(rst) idle_seen<=0;
    else idle_seen<=state==ST_IDLE;
end

wire header_match;
wire bmp_data_valid;
wire        fat32_bpb_valid;
wire [31:0] dir_entry_cluster;
wire        dir_entry_is_bmp;
wire        dir_entry_is_music;
wire [31:0] fat_next_cluster_masked;
wire fat_next_cluster_invalid;

function is_valid_cluster_size;
    input [7:0] sectors_per_cluster;
    begin
        case (sectors_per_cluster)
            8'd1, 8'd2, 8'd4, 8'd8, 8'd16, 8'd32, 8'd64, 8'd128:
                is_valid_cluster_size = 1'b1;
            default:
                is_valid_cluster_size = 1'b0;
        endcase
    end
endfunction

function [31:0] cluster_sector_offset;
    input [31:0] index;
    input [7:0]  sectors_per_cluster;
    begin
        case (sectors_per_cluster)
            8'd1:   cluster_sector_offset = index;
            8'd2:   cluster_sector_offset = index << 1;
            8'd4:   cluster_sector_offset = index << 2;
            8'd8:   cluster_sector_offset = index << 3;
            8'd16:  cluster_sector_offset = index << 4;
            8'd32:  cluster_sector_offset = index << 5;
            8'd64:  cluster_sector_offset = index << 6;
            8'd128: cluster_sector_offset = index << 7;
            default: cluster_sector_offset = 32'd0;
        endcase
    end
endfunction

assign ready = (state == ST_IDLE) && (!FAST_AUDIO_START || !load_pending);
assign header_match = (header_0 == "B") &&
                      (header_1 == "M") &&
                      (ENABLE_RESAMPLE ?
                        ((width[31:16]==0) && (width[15:0]>=OUT_WIDTH) &&
                         (height_abs[31:16]==0) && (height_abs[15:0]>=OUT_HEIGHT) &&
                         (dib_size>=40) && (planes==1) &&
                         (pixel_offset>=54) && (pixel_offset<file_len)) :
                        ((width[15:0]==bmp_width) && (height[15:0]==bmp_height))) &&
                      (bit_count    == 16'd24) &&
                      (compression  == 32'd0);
assign bmp_data_valid = (sd_sec_read_data_valid == 1'b1) &&
                        (bmp_len_cnt >= pixel_offset) &&
                        (bmp_len_cnt <  file_len);
assign fat32_bpb_valid = (fs_bytes_per_sector == 16'd512) &&
                         is_valid_cluster_size(fs_sectors_per_cluster) &&
                         (fs_reserved_sectors != 16'd0) &&
                         ((fs_num_fats == 8'd1) || (fs_num_fats == 8'd2)) &&
                         (fs_fat_size != 32'd0) &&
                         (|fs_root_cluster[31:1]);
assign dir_entry_cluster = {dir_cluster_hi, dir_cluster_lo};
assign dir_entry_is_bmp  = (dir_first_byte != 8'h00) &&
                           (dir_first_byte != 8'he5) &&
                           (dir_attr != 8'h0f) &&
                           ((dir_attr & 8'h18) == 8'h00) &&
                           ((dir_ext0 == "B") || (dir_ext0 == "b")) &&
                           ((dir_ext1 == "M") || (dir_ext1 == "m")) &&
                           ((dir_ext2 == "P") || (dir_ext2 == "p")) &&
                           (|dir_entry_cluster[31:1]);
// Accept the first normal .PCM or .WAV directory entry instead of requiring
// the base name to be exactly MUSIC. Windows may generate an 8.3 alias, and
// the supplied preview file may have been copied as WAV. The generated WAV's
// 44-byte header is word-aligned and only causes a sub-millisecond transient.
assign dir_entry_is_music = (dir_first_byte != 8'h00) &&
                            (dir_first_byte != 8'he5) &&
                            ((((dir_ext0 == "P") || (dir_ext0 == "p")) &&
                              ((dir_ext1 == "C") || (dir_ext1 == "c")) &&
                              ((dir_ext2 == "M") || (dir_ext2 == "m"))) ||
                             (((dir_ext0 == "W") || (dir_ext0 == "w")) &&
                              ((dir_ext1 == "A") || (dir_ext1 == "a")) &&
                              ((dir_ext2 == "V") || (dir_ext2 == "v")))) &&
                            (dir_attr != 8'h0f) && ((dir_attr & 8'h18) == 8'h00) &&
                            (|dir_entry_cluster[31:1]);
// Name/attribute/cluster fields are complete after byte 27 of an entry and
// bytes 28..30 always arrive before byte 31, so the classification can be
// registered one clock earlier without changing the byte-31 decision. This
// keeps the wide name compares off the SD data-valid -> enable path.
reg dir_entry_is_bmp_q, dir_entry_is_music_q;
always @(posedge clk or posedge rst) begin
    if (rst) begin
        dir_entry_is_bmp_q   <= 1'b0;
        dir_entry_is_music_q <= 1'b0;
    end else begin
        dir_entry_is_bmp_q   <= dir_entry_is_bmp;
        dir_entry_is_music_q <= dir_entry_is_music;
    end
end
assign fat_next_cluster_masked = fat_next_cluster & 32'h0fff_ffff;
// FAT32 uses only 28 bits. Detect 0/1 and the reserved/EOF range
// without a wide carry-chain comparator in the SD clock domain.
assign fat_next_cluster_invalid = (~|fat_next_cluster_masked[27:1]) ||
                                  (&fat_next_cluster_masked[27:4]);
assign audio_data_valid = (state == ST_AUDIO_DATA) &&
                          sd_sec_read_data_valid &&
                          (audio_byte_count < audio_file_size);
assign audio_data = sd_sec_read_data;

always @(posedge clk or posedge rst) begin
    if (rst) begin
        rd_cnt <= 10'd0;
    end else if ((state == ST_LOAD_HDR) ||
                 (state == ST_FS_PROBE) ||
                 (state == ST_FS_BOOT) ||
                 (state == ST_DIR_SCAN) ||
                 (state == ST_DIR_FAT) ||
                 (state == ST_LOAD_FAT) ||
                 (state == ST_AUDIO_FAT)) begin
        if (sd_sec_read_data_valid)
            rd_cnt <= rd_cnt + 10'd1;
        else if (sd_sec_read_end)
            rd_cnt <= 10'd0;
    end else begin
        rd_cnt <= 10'd0;
    end
end

always @(posedge clk or posedge rst) begin
    if (rst) begin
        header_0     <= 8'd0;
        header_1     <= 8'd0;
        file_len     <= 32'd0;
        pixel_offset <= 32'd54;
        width        <= 32'd0;
        height       <= 32'd0;
        bit_count    <= 16'd0;
        compression  <= 32'd0;
        dib_size     <= 32'd0;
        planes       <= 16'd0;
    end else if ((state == ST_LOAD_HDR) && sd_sec_read_data_valid) begin
        case (rd_cnt)
            10'd0 : header_0 <= sd_sec_read_data;
            10'd1 : header_1 <= sd_sec_read_data;

            10'd2 : file_len[7:0] <= sd_sec_read_data;
            10'd3 : file_len[15:8] <= sd_sec_read_data;
            10'd4 : file_len[23:16] <= sd_sec_read_data;
            10'd5 : file_len[31:24] <= sd_sec_read_data;

            10'd10: pixel_offset[7:0] <= sd_sec_read_data;
            10'd11: pixel_offset[15:8] <= sd_sec_read_data;
            10'd12: pixel_offset[23:16] <= sd_sec_read_data;
            10'd13: pixel_offset[31:24] <= sd_sec_read_data;
            10'd14: dib_size[7:0] <= sd_sec_read_data;
            10'd15: dib_size[15:8] <= sd_sec_read_data;
            10'd16: dib_size[23:16] <= sd_sec_read_data;
            10'd17: dib_size[31:24] <= sd_sec_read_data;

            10'd18: width[7:0] <= sd_sec_read_data;
            10'd19: width[15:8] <= sd_sec_read_data;
            10'd20: width[23:16] <= sd_sec_read_data;
            10'd21: width[31:24] <= sd_sec_read_data;

            10'd22: height[7:0] <= sd_sec_read_data;
            10'd23: height[15:8] <= sd_sec_read_data;
            10'd24: height[23:16] <= sd_sec_read_data;
            10'd25: height[31:24] <= sd_sec_read_data;
            10'd26: planes[7:0] <= sd_sec_read_data;
            10'd27: planes[15:8] <= sd_sec_read_data;

            10'd28: bit_count[7:0] <= sd_sec_read_data;
            10'd29: bit_count[15:8] <= sd_sec_read_data;

            10'd30: compression[7:0] <= sd_sec_read_data;
            10'd31: compression[15:8] <= sd_sec_read_data;
            10'd32: compression[23:16] <= sd_sec_read_data;
            10'd33: compression[31:24] <= sd_sec_read_data;
            default: ;
        endcase
    end
end

// 读取 FAT32 BPB；若 sector 0 是 MBR，则先记录第一分区起始 LBA，再读取分区引导扇区。
always @(posedge clk or posedge rst) begin
    if (rst) begin
        mbr_partition_lba    <= 32'd0;
        mbr_lba_nonzero_bytes <= 4'd0;
        fs_bytes_per_sector  <= 16'd0;
        fs_sectors_per_cluster <= 8'd0;
        fs_reserved_sectors  <= 16'd0;
        fs_num_fats          <= 8'd0;
        fs_fat_size          <= 32'd0;
        fs_root_cluster      <= 32'd0;
    end else if (((state == ST_FS_PROBE) || (state == ST_FS_BOOT)) && sd_sec_read_data_valid) begin
        case (rd_cnt)
            10'd11: fs_bytes_per_sector[7:0]   <= sd_sec_read_data;
            10'd12: fs_bytes_per_sector[15:8]  <= sd_sec_read_data;
            10'd13: fs_sectors_per_cluster     <= sd_sec_read_data;
            10'd14: fs_reserved_sectors[7:0]   <= sd_sec_read_data;
            10'd15: fs_reserved_sectors[15:8]  <= sd_sec_read_data;
            10'd16: fs_num_fats                <= sd_sec_read_data;
            10'd36: fs_fat_size[7:0]           <= sd_sec_read_data;
            10'd37: fs_fat_size[15:8]          <= sd_sec_read_data;
            10'd38: fs_fat_size[23:16]         <= sd_sec_read_data;
            10'd39: fs_fat_size[31:24]         <= sd_sec_read_data;
            10'd44: fs_root_cluster[7:0]        <= sd_sec_read_data;
            10'd45: fs_root_cluster[15:8]       <= sd_sec_read_data;
            10'd46: fs_root_cluster[23:16]      <= sd_sec_read_data;
            10'd47: fs_root_cluster[31:24]      <= sd_sec_read_data;
            // Track zero/nonzero as each byte arrives. This is exactly the
            // 32-bit LBA zero test, without a wide decode on the state/CE path.
            10'd454: if (state == ST_FS_PROBE) begin
                mbr_partition_lba[7:0] <= sd_sec_read_data;
                mbr_lba_nonzero_bytes[0] <= |sd_sec_read_data;
            end
            10'd455: if (state == ST_FS_PROBE) begin
                mbr_partition_lba[15:8] <= sd_sec_read_data;
                mbr_lba_nonzero_bytes[1] <= |sd_sec_read_data;
            end
            10'd456: if (state == ST_FS_PROBE) begin
                mbr_partition_lba[23:16] <= sd_sec_read_data;
                mbr_lba_nonzero_bytes[2] <= |sd_sec_read_data;
            end
            10'd457: if (state == ST_FS_PROBE) begin
                mbr_partition_lba[31:24] <= sd_sec_read_data;
                mbr_lba_nonzero_bytes[3] <= |sd_sec_read_data;
            end
            default: ;
        endcase
    end
end

// 收集根目录中的最多四个短目录项（长文件名项会被跳过）。
always @(posedge clk or posedge rst) begin
    if (rst) begin
        dir_first_byte       <= 8'd0;
        dir_name1            <= 8'd0;
        dir_name2            <= 8'd0;
        dir_name3            <= 8'd0;
        dir_name4            <= 8'd0;
        dir_name5            <= 8'd0;
        dir_name6            <= 8'd0;
        dir_name7            <= 8'd0;
        dir_ext0             <= 8'd0;
        dir_ext1             <= 8'd0;
        dir_ext2             <= 8'd0;
        dir_attr             <= 8'd0;
        dir_cluster_hi       <= 16'd0;
        dir_cluster_lo       <= 16'd0;
        dir_file_size        <= 32'd0;
        dir_end_seen         <= 1'b0;
        dir_candidate_count  <= 3'd0;
        dir_candidate0       <= 32'd0;
        dir_candidate1       <= 32'd0;
        dir_candidate2       <= 32'd0;
        dir_candidate3       <= 32'd0;
        dir_candidate_pending <= 1'b0;
        dir_candidate_pending_cluster <= 32'd0;
        audio_file_found     <= 1'b0;
        audio_file_cluster   <= 32'd0;
        audio_file_size      <= 32'd0;
    end else if ((state == ST_IDLE) && scan_start) begin
        // Entry fields, candidates and the audio cluster are always rewritten
        // before they are consumed; only the bookkeeping must restart.
        dir_end_seen         <= 1'b0;
        dir_candidate_count  <= 3'd0;
        dir_candidate_pending <= 1'b0;
        audio_file_found     <= 1'b0;
        audio_file_size      <= 32'd0;
    end else begin
        // 将目录项合法性判断与四选一候选写入拆成两拍，避免比较链直接
        // 进入候选寄存器的使能端；下一目录项的读取可同时继续进行。
        dir_candidate_pending <= 1'b0;
        if (dir_candidate_pending) begin
            case (dir_candidate_count)
                3'd0: dir_candidate0 <= dir_candidate_pending_cluster;
                3'd1: dir_candidate1 <= dir_candidate_pending_cluster;
                3'd2: dir_candidate2 <= dir_candidate_pending_cluster;
                3'd3: dir_candidate3 <= dir_candidate_pending_cluster;
                default: ;
            endcase
            dir_candidate_count <= dir_candidate_count + 3'd1;
        end

        if ((state == ST_DIR_SCAN) && sd_sec_read_data_valid) begin
            case (rd_cnt[4:0])
                5'd0:  dir_first_byte     <= sd_sec_read_data;
                5'd1:  dir_name1          <= sd_sec_read_data;
                5'd2:  dir_name2          <= sd_sec_read_data;
                5'd3:  dir_name3          <= sd_sec_read_data;
                5'd4:  dir_name4          <= sd_sec_read_data;
                5'd5:  dir_name5          <= sd_sec_read_data;
                5'd6:  dir_name6          <= sd_sec_read_data;
                5'd7:  dir_name7          <= sd_sec_read_data;
                5'd8:  dir_ext0           <= sd_sec_read_data;
                5'd9:  dir_ext1           <= sd_sec_read_data;
                5'd10: dir_ext2           <= sd_sec_read_data;
                5'd11: dir_attr           <= sd_sec_read_data;
                5'd20: dir_cluster_hi[7:0]  <= sd_sec_read_data;
                5'd21: dir_cluster_hi[15:8] <= sd_sec_read_data;
                5'd26: dir_cluster_lo[7:0]  <= sd_sec_read_data;
                5'd27: dir_cluster_lo[15:8] <= sd_sec_read_data;
                5'd28: dir_file_size[7:0]   <= sd_sec_read_data;
                5'd29: dir_file_size[15:8]  <= sd_sec_read_data;
                5'd30: dir_file_size[23:16] <= sd_sec_read_data;
                5'd31: begin
                    dir_file_size[31:24] <= sd_sec_read_data;
                    if (dir_first_byte == 8'h00) begin
                        dir_end_seen <= 1'b1;
                    end else if (!dir_end_seen && !audio_file_found &&
                                 dir_entry_is_music_q &&
                                 ((|sd_sec_read_data) || (|dir_file_size[23:2]))) begin
                        audio_file_found   <= 1'b1;
                        audio_file_cluster <= dir_entry_cluster;
                        audio_file_size    <= {sd_sec_read_data, dir_file_size[23:0]};
                    end else if (!dir_end_seen && dir_entry_is_bmp_q &&
                                 (dir_candidate_count < scan_target_count) &&
                                 (dir_candidate_count < 3'd4)) begin
                        dir_candidate_pending <= 1'b1;
                        dir_candidate_pending_cluster <= dir_entry_cluster;
                    end
                end
                default: ;
            endcase
        end
    end
end

// 读取根目录簇在 FAT 中的下一簇号，以支持根目录跨簇。
// fat_entry_offset is always {cluster[6:0],2'b00}, so all four bytes of the
// entry are rewritten by every FAT sector read before they are checked.
always @(posedge clk or posedge rst) begin
    if (rst) begin
        fat_next_cluster <= 32'd0;
    end else if (((state == ST_DIR_FAT) || (state == ST_LOAD_FAT) ||
                  (state == ST_AUDIO_FAT)) &&
                 sd_sec_read_data_valid &&
                 (rd_cnt[8:2] == fat_entry_offset[8:2])) begin
        case (rd_cnt[1:0])
            2'd0: fat_next_cluster[7:0]   <= sd_sec_read_data;
            2'd1: fat_next_cluster[15:8]  <= sd_sec_read_data;
            2'd2: fat_next_cluster[23:16] <= sd_sec_read_data;
            default: fat_next_cluster[31:24] <= sd_sec_read_data;
        endcase
    end
end

always @(posedge clk or posedge rst) begin
    if (rst) begin
        bmp_len_cnt <= 32'd0;
    end else if (state == ST_LOAD_DATA) begin
        if (sd_sec_read_data_valid)
            bmp_len_cnt <= bmp_len_cnt + 32'd1;
    end else if ((state == ST_LOAD_FAT) ||
                 (state == ST_LOAD_NEXT_CALC) ||
                 (state == ST_LOAD_NEXT_ADDR) ||
                 (PIPELINED_CLUSTER_ADDR && state==ST_CLUSTER_SHIFT && cluster_return_state==ST_LOAD_NEXT_ADDR) ||
                 (FAST_AUDIO_START && load_paused)) begin
        bmp_len_cnt <= bmp_len_cnt;
    end else begin
        bmp_len_cnt <= 32'd0;
    end
end

always @(posedge clk or posedge rst) begin
    if (rst) begin
        bmp_byte_idx <= 2'd0;
    end else if (state == ST_LOAD_DATA) begin
        if (bmp_data_valid)
            bmp_byte_idx <= (bmp_byte_idx == 2'd2) ? 2'd0 : (bmp_byte_idx + 2'd1);
    end else if ((state == ST_LOAD_FAT) ||
                 (state == ST_LOAD_NEXT_CALC) ||
                 (state == ST_LOAD_NEXT_ADDR) ||
                 (PIPELINED_CLUSTER_ADDR && state==ST_CLUSTER_SHIFT && cluster_return_state==ST_LOAD_NEXT_ADDR) ||
                 (FAST_AUDIO_START && load_paused)) begin
        bmp_byte_idx <= bmp_byte_idx;
    end else begin
        bmp_byte_idx <= 2'd0;
    end
end

generate if(!ENABLE_RESAMPLE) begin : g_legacy_decode
assign resample_ready=1'b1;
assign resample_done=1'b1;
always @(posedge clk or posedge rst) begin
    if (rst) begin
        bmp_data_wr_en <= 1'b0;
        bmp_data       <= 24'd0;
    end else if (state == ST_LOAD_DATA) begin
        if (bmp_data_valid) begin
            case (bmp_byte_idx)
                2'd0: begin
                    bmp_data_wr_en <= 1'b0;
                    bmp_data[7:0]  <= sd_sec_read_data;
                end
                2'd1: begin
                    bmp_data_wr_en <= 1'b0;
                    bmp_data[15:8] <= sd_sec_read_data;
                end
                2'd2: begin
                    bmp_data_wr_en  <= 1'b1;
                    bmp_data[23:16] <= sd_sec_read_data;
                end
                default: begin
                    bmp_data_wr_en <= 1'b0;
                end
            endcase
        end else begin
            bmp_data_wr_en <= 1'b0;
        end
    end else begin
        bmp_data_wr_en <= 1'b0;
    end
end
end else begin : g_resample
wire scaler_valid, scaler_busy, scaler_overflow;
wire [23:0] scaler_rgb;
// Do not derive asynchronous reset from combinational FSM decoding. Start
// clears pointers/validity synchronously; abort and SD re-init cancel a load.
wire scaler_reset=rst || load_abort || !sd_init_done;
bmp_bilinear_stream #(.OUT_WIDTH(OUT_WIDTH), .OUT_HEIGHT(OUT_HEIGHT)) u_scaler (
    .clk(clk), .rst(scaler_reset), .start(state==ST_LOAD_WAIT && write_req_ack),
    .source_width(source_width), .source_height(source_height),
    .byte_valid(state==ST_LOAD_DATA && bmp_data_valid), .byte_data(sd_sec_read_data),
    .pixel_ready(write_pixel_ready),
    .sector_ready(resample_ready), .busy(scaler_busy), .done(resample_done),
    .overflow(scaler_overflow), .pixel_valid(scaler_valid), .pixel_rgb(scaler_rgb));
always @(*) begin
    bmp_data_wr_en=scaler_valid && !load_abort && !scaler_overflow;
    bmp_data=scaler_rgb;
end
end endgenerate

always @(posedge clk or posedge rst) begin
    if (rst) begin
        state               <= ST_IDLE;
        cluster_return_state<= ST_IDLE;
        cluster_offset_q    <= 32'd0;
        state_code          <= 4'd0;
        sd_sec_read         <= 1'b0;
        sd_sec_read_addr    <= 32'd0;
        write_req           <= 1'b0;
        scan_done           <= 1'b0;
        scan_found_valid    <= 1'b0;
        scan_found_sector   <= 32'd0;
        scan_found_cluster  <= 32'd0;
        scan_found_total    <= 3'd0;
        load_sector_latched <= 32'd0;
        load_cluster_latched <= 32'd0;
        load_sector_in_cluster <= 8'd0;
        cluster_index       <= 32'd0;
        cluster_index_ok    <= 1'b0;
        volume_lba          <= 32'd0;
        fat_start_sector    <= 32'd0;
        fat_area_sectors    <= 32'd0;
        first_data_sector   <= 32'd0;
        dir_cluster         <= 32'd0;
        dir_sector_in_cluster <= 8'd0;
        dir_cluster_hops    <= 8'd0;
        dir_post_bmp_sectors <= 4'd0;
        emit_idx            <= 3'd0;
        emit_cluster        <= 32'd0;
        fat_entry_offset    <= 9'd0;
        bpb_valid_latched   <= 1'b0;
        fs_check_is_boot    <= 1'b0;
        audio_current_cluster <= 32'd0;
        audio_sector_in_cluster <= 8'd0;
        audio_byte_count    <= 32'd0;
        audio_cursor_valid  <= 1'b0;
        load_pending        <= 1'b0;
        load_paused         <= 1'b0;
        load_resume_state   <= ST_LOAD_DATA;
        load_resume_addr    <= 32'd0;
        audio_resume_addr   <= 32'd0;
    end else if (!sd_init_done) begin
        load_pending<=1'b0;
        audio_cursor_valid<=1'b0;
        load_paused<=1'b0;
        // Internal cursors are always reloaded before use; only the control
        // state and the externally visible outputs need to be cleared here.
        state               <= ST_IDLE;
        state_code          <= 4'd0;
        sd_sec_read         <= 1'b0;
        sd_sec_read_addr    <= 32'd0;
        write_req           <= 1'b0;
        scan_done           <= 1'b0;
        scan_found_valid    <= 1'b0;
        scan_found_sector   <= 32'd0;
        scan_found_cluster  <= 32'd0;
        scan_found_total    <= 3'd0;
    end else if (load_abort) begin
        load_pending<=1'b0;
        audio_cursor_valid<=1'b0;
        load_paused<=1'b0;
        // 只终止本次装载；保留已经完成的目录扫描结果，避免一次坏图后永久禁止切换。
        state               <= ST_IDLE;
        state_code          <= 4'd1;
        sd_sec_read         <= 1'b0;
        sd_sec_read_addr    <= 32'd0;
        write_req           <= 1'b0;
        scan_found_valid    <= 1'b0;
    end else begin
        scan_found_valid <= 1'b0;
        // A one-cycle request can coincide with the reader leaving IDLE for
        // audio. Retain it until a sector boundary; controller holds metadata.
        if(FAST_AUDIO_START && load_start && state!=ST_IDLE) load_pending<=1'b1;

        case (state)
            ST_IDLE: begin
                state_code  <= 4'd1;
                sd_sec_read <= 1'b0;
                write_req   <= 1'b0;

                if (scan_start) begin
                    load_pending<=1'b0;
                    audio_cursor_valid<=1'b0;
                    load_paused<=1'b0;
                    scan_done        <= 1'b0;
                    scan_found_total <= 3'd0;
                    dir_cluster_hops <= 8'd0;
                    dir_post_bmp_sectors <= 4'd0;
                    bpb_valid_latched <= 1'b0;
                    fs_check_is_boot  <= 1'b0;
                    sd_sec_read_addr <= 32'd0;
                    state            <= ST_FS_PROBE;
                end else if (load_start || (FAST_AUDIO_START && load_pending)) begin
                    load_pending<=1'b0;
                    load_paused<=1'b0;
                    load_sector_latched <= load_sector;
                    load_cluster_latched <= load_cluster;
                    load_sector_in_cluster <= 8'd0;
                    sd_sec_read_addr    <= load_sector;
                    state               <= ST_LOAD_HDR;
                end else if (audio_enable && audio_file_found &&
                             audio_fifo_ready && (!FAST_AUDIO_START || idle_seen)) begin
                    if(FAST_AUDIO_START && audio_cursor_valid) begin
                        sd_sec_read_addr<=audio_resume_addr;
                        state<=ST_AUDIO_WAIT;
                    end else begin
                        audio_current_cluster   <= audio_file_cluster;
                        audio_sector_in_cluster <= 8'd0;
                        audio_byte_count        <= 32'd0;
                        audio_cursor_valid      <= 1'b1;
                        state                   <= ST_AUDIO_START_CALC;
                    end
                end
            end

            // sector 0 可能直接是 FAT32 引导扇区，也可能是带分区表的 MBR。
            ST_FS_PROBE: begin
                state_code  <= 4'd2;
                sd_sec_read <= 1'b1;

                if (sd_sec_read_end) begin
                    sd_sec_read          <= 1'b0;
                    bpb_valid_latched    <= fat32_bpb_valid;
                    fs_check_is_boot     <= 1'b0;
                    state                <= ST_FS_CHECK;
                end
            end

            ST_FS_BOOT: begin
                state_code  <= 4'd2;
                sd_sec_read <= 1'b1;

                if (sd_sec_read_end) begin
                    sd_sec_read          <= 1'b0;
                    bpb_valid_latched    <= fat32_bpb_valid;
                    fs_check_is_boot     <= 1'b1;
                    state                <= ST_FS_CHECK;
                end
            end

            // 将多字段 BPB 合法性判断锁存后再分支，避免校验组合链进入寄存器使能端。
            ST_FS_CHECK: begin
                state_code  <= 4'd2;
                sd_sec_read <= 1'b0;

                if (bpb_valid_latched) begin
                    if (!fs_check_is_boot)
                        volume_lba <= 32'd0;
                    state <= ST_FS_CALC0;
                end else if (!fs_check_is_boot && (|mbr_lba_nonzero_bytes)) begin
                    volume_lba       <= mbr_partition_lba;
                    sd_sec_read_addr <= mbr_partition_lba;
                    state            <= ST_FS_BOOT;
                end else begin
                    scan_done <= 1'b1;
                    state     <= ST_IDLE;
                end
            end

            // 分三拍计算 FAT、数据区和根目录起始扇区，缩短 100 MHz 域组合路径。
            ST_FS_CALC0: begin
                state_code          <= 4'd2;
                sd_sec_read         <= 1'b0;
                fat_start_sector    <= volume_lba + {16'd0, fs_reserved_sectors};
                fat_area_sectors    <= (fs_num_fats == 8'd2) ?
                                       (fs_fat_size << 1) : fs_fat_size;
                cluster_index       <= next_cluster_index;
                cluster_index_ok    <= next_cluster_index_ok;
                cluster_return_state<= ST_FS_CALC1;
                state <= PIPELINED_CLUSTER_ADDR ? ST_CLUSTER_SHIFT : ST_FS_CALC1;
            end

            ST_FS_CALC1: begin
                state_code        <= 4'd2;
                first_data_sector <= fat_start_sector + fat_area_sectors;
                state             <= ST_FS_CALC2;
            end

            ST_FS_CALC2: begin
                state_code            <= 4'd2;
                dir_cluster           <= fs_root_cluster;
                dir_sector_in_cluster <= 8'd0;
                dir_cluster_hops      <= 8'd0;
                sd_sec_read_addr      <= cluster_data_sector;
                state                 <= ST_DIR_SCAN;
            end

            ST_DIR_SCAN: begin
                state_code  <= 4'd2;
                sd_sec_read <= 1'b1;

                if (sd_sec_read_end) begin
                    sd_sec_read <= 1'b0;
                    // After four BMPs, search only a bounded window for audio.
                    // A missing/renamed audio entry must not hold the picture
                    // preload at display number 0 until the global watchdog.
                    if (dir_end_seen ||
                        (((dir_candidate_count >= scan_target_count) ||
                          (dir_candidate_count >= 3'd4)) &&
                         (audio_file_found ||
                          (dir_post_bmp_sectors >= 4'd7)))) begin
                        emit_idx <= 3'd0;
                        state    <= ST_SCAN_PREP;
                    end else if ((dir_sector_in_cluster + 8'd1) < fs_sectors_per_cluster) begin
                        if ((dir_candidate_count >= scan_target_count) ||
                            (dir_candidate_count >= 3'd4))
                            dir_post_bmp_sectors <= dir_post_bmp_sectors + 4'd1;
                        dir_sector_in_cluster <= dir_sector_in_cluster + 8'd1;
                        sd_sec_read_addr      <= sd_sec_read_addr + 32'd1;
                    end else begin
                        if ((dir_candidate_count >= scan_target_count) ||
                            (dir_candidate_count >= 3'd4))
                            dir_post_bmp_sectors <= dir_post_bmp_sectors + 4'd1;
                        fat_entry_offset <= {dir_cluster[6:0], 2'b00};
                        sd_sec_read_addr <= cluster_fat_sector;
                        state            <= ST_DIR_FAT;
                    end
                end
            end

            ST_DIR_FAT: begin
                state_code  <= 4'd2;
                sd_sec_read <= 1'b1;

                if (sd_sec_read_end) begin
                    sd_sec_read <= 1'b0;
                    state       <= ST_DIR_FAT_CHECK;
                end
            end

            // FAT 扇区读完后再单独判断下一簇，避免 28 位比较链进入状态寄存器使能端。
            ST_DIR_FAT_CHECK: begin
                state_code  <= 4'd2;
                sd_sec_read <= 1'b0;

                if (fat_next_cluster_invalid ||
                    (fat_next_cluster_masked == dir_cluster) ||
                    (dir_cluster_hops == 8'hff)) begin
                    emit_idx <= 3'd0;
                    state    <= ST_SCAN_PREP;
                end else begin
                    dir_cluster           <= fat_next_cluster_masked;
                    dir_sector_in_cluster <= 8'd0;
                    dir_cluster_hops      <= dir_cluster_hops + 8'd1;
                    state                 <= ST_DIR_NEXT_CALC;
                end
            end

            ST_DIR_NEXT_CALC: begin
                state_code         <= 4'd2;
                sd_sec_read        <= 1'b0;
                cluster_index      <= next_cluster_index;
                cluster_index_ok   <= next_cluster_index_ok;
                cluster_return_state<= ST_DIR_NEXT_ADDR;
                state <= PIPELINED_CLUSTER_ADDR ? ST_CLUSTER_SHIFT : ST_DIR_NEXT_ADDR;
            end

            ST_DIR_NEXT_ADDR: begin
                state_code       <= 4'd2;
                sd_sec_read      <= 1'b0;
                sd_sec_read_addr <= cluster_data_sector;
                state            <= ST_DIR_SCAN;
            end

            // 先选择候选簇，再分拍完成减法/移位和地址加法。
            ST_SCAN_PREP: begin
                state_code  <= 4'd2;
                sd_sec_read <= 1'b0;

                if (dir_candidate_count == 3'd0) begin
                    scan_found_total <= 3'd0;
                    scan_done        <= 1'b1;
                    state            <= ST_IDLE;
                end else begin
                    case (emit_idx)
                        3'd0: emit_cluster <= dir_candidate0;
                        3'd1: emit_cluster <= dir_candidate1;
                        3'd2: emit_cluster <= dir_candidate2;
                        3'd3: emit_cluster <= dir_candidate3;
                        default: emit_cluster <= dir_candidate0;
                    endcase
                    state <= ST_SCAN_CALC;
                end
            end

            ST_SCAN_CALC: begin
                state_code          <= 4'd2;
                sd_sec_read         <= 1'b0;
                cluster_index       <= next_cluster_index;
                cluster_index_ok    <= next_cluster_index_ok;
                cluster_return_state<= ST_SCAN_EMIT;
                state <= PIPELINED_CLUSTER_ADDR ? ST_CLUSTER_SHIFT : ST_SCAN_EMIT;
            end

            // 将根目录中找到的扇区逐拍送给上层，接口与原扫描方式保持兼容。
            ST_SCAN_EMIT: begin
                state_code        <= 4'd2;
                sd_sec_read       <= 1'b0;
                scan_found_valid  <= 1'b1;
                scan_found_sector <= cluster_data_sector;
                scan_found_cluster <= emit_cluster;
                scan_found_total  <= emit_idx + 3'd1;

                if (((emit_idx + 3'd1) >= dir_candidate_count) ||
                    ((emit_idx + 3'd1) >= scan_target_count)) begin
                    scan_done <= 1'b1;
                    state     <= ST_IDLE;
                end else begin
                    emit_idx <= emit_idx + 3'd1;
                    state    <= ST_SCAN_PREP;
                end
            end

            ST_LOAD_HDR: begin
                state_code  <= 4'd2;
                sd_sec_read <= 1'b1;

                if (sd_sec_read_end) begin
                    sd_sec_read <= 1'b0;
                    if (header_match) begin
                        write_req        <= 1'b1;
                        sd_sec_read_addr <= load_sector_latched;
                        state            <= ST_LOAD_WAIT;
                    end else begin
                        state <= ST_IDLE;
                    end
                end
            end

            ST_LOAD_WAIT: begin
                state_code <= 4'd3;
                if (write_req_ack) begin
                    write_req <= 1'b0;
                    state     <= ST_LOAD_DATA;
                end
            end

            ST_LOAD_DATA: begin
                state_code  <= 4'd4;
                sd_sec_read <= !ENABLE_RESAMPLE || load_sector_active || resample_ready;

                if (sd_sec_read_end) begin
                    sd_sec_read <= 1'b0;
                    if (ENABLE_RESAMPLE && (resample_done || bmp_len_cnt>=file_len)) begin
                        state <= ST_LOAD_DRAIN;
                    end else if (bmp_len_cnt >= file_len) begin
                        state <= ST_IDLE;
                    end else if ((load_sector_in_cluster + 8'd1) <
                                 fs_sectors_per_cluster) begin
                        load_sector_in_cluster <= load_sector_in_cluster + 8'd1;
                        sd_sec_read_addr <= sd_sec_read_addr + 32'd1;
                        if(FAST_AUDIO_START && audio_enable && audio_fifo_ready) begin
                            load_resume_state<=ST_LOAD_DATA;
                            state<=ST_LOAD_PAUSE;
                            load_paused<=1'b1;
                        end
                    end else begin
                        fat_entry_offset <= {load_cluster_latched[6:0], 2'b00};
                        sd_sec_read_addr <= cluster_fat_sector;
                        state <= ST_LOAD_FAT;
                        if(FAST_AUDIO_START && audio_enable && audio_fifo_ready) begin
                            load_resume_state<=ST_LOAD_FAT;
                            state<=ST_LOAD_PAUSE;
                            load_paused<=1'b1;
                        end
                    end
                end
            end

            ST_LOAD_DRAIN: begin
                // The last SD sector can end before the last scaled output row.
                state_code<=4'd4;
                sd_sec_read<=1'b0;
                if(resample_done) state<=ST_IDLE;
            end

            // 文件可以跨越不连续簇：到簇尾后查询 FAT，再跳到下一数据簇。
            ST_LOAD_PAUSE: begin
                sd_sec_read<=1'b0;
                load_resume_addr<=sd_sec_read_addr;
                if(audio_cursor_valid) begin
                    sd_sec_read_addr<=audio_resume_addr;
                    state<=ST_AUDIO_WAIT;
                end else begin
                    audio_cursor_valid<=1'b1;
                    audio_current_cluster<=audio_file_cluster;
                    audio_sector_in_cluster<=0;
                    audio_byte_count<=0;
                    state<=ST_AUDIO_START_CALC;
                end
            end

            ST_LOAD_FAT: begin
                state_code  <= 4'd4;
                sd_sec_read <= 1'b1;

                if (sd_sec_read_end) begin
                    sd_sec_read <= 1'b0;
                    if (fat_next_cluster_invalid ||
                        (fat_next_cluster_masked == load_cluster_latched)) begin
                        // 文件链提前结束或损坏；上层超时恢复后会自动尝试下一张。
                        state <= ST_IDLE;
                    end else begin
                        load_cluster_latched <= fat_next_cluster_masked;
                        state <= ST_LOAD_NEXT_CALC;
                    end
                end
            end

            ST_LOAD_NEXT_CALC: begin
                state_code          <= 4'd4;
                sd_sec_read         <= 1'b0;
                cluster_index       <= next_cluster_index;
                cluster_index_ok    <= next_cluster_index_ok;
                cluster_return_state<= ST_LOAD_NEXT_ADDR;
                state <= PIPELINED_CLUSTER_ADDR ? ST_CLUSTER_SHIFT : ST_LOAD_NEXT_ADDR;
            end

            ST_LOAD_NEXT_ADDR: begin
                state_code             <= 4'd4;
                sd_sec_read            <= 1'b0;
                load_sector_in_cluster <= 8'd0;
                sd_sec_read_addr       <= cluster_data_sector;
                state                  <= ST_LOAD_DATA;
            end

            // Compute the first sector from the FAT32 cluster instead of
            // assuming MUSIC.PCM is contiguous or placed at a fixed LBA.
            ST_AUDIO_START_CALC: begin
                state_code           <= 4'd5;
                sd_sec_read          <= 1'b0;
                cluster_index        <= next_cluster_index;
                cluster_index_ok     <= next_cluster_index_ok;
                cluster_return_state<= ST_AUDIO_START_ADDR;
                state <= PIPELINED_CLUSTER_ADDR ? ST_CLUSTER_SHIFT : ST_AUDIO_START_ADDR;
            end

            ST_AUDIO_START_ADDR: begin
                state_code              <= 4'd5;
                sd_sec_read             <= 1'b0;
                audio_sector_in_cluster <= 8'd0;
                sd_sec_read_addr        <= cluster_data_sector;
                state                   <= ST_AUDIO_DATA;
            end

            // Pause only between sectors. The FIFO threshold leaves at least
            // 512 bytes free, so a sector already in progress never overflows.
            ST_AUDIO_WAIT: begin
                state_code  <= 4'd5;
                sd_sec_read <= 1'b0;

                if (!audio_enable) begin
                    audio_cursor_valid<=1'b0;
                    load_paused<=1'b0;
                    state            <= ST_IDLE;
                end else if (audio_fifo_ready) begin
                    if (audio_byte_count >= audio_file_size) begin
                        audio_current_cluster   <= audio_file_cluster;
                        audio_sector_in_cluster <= 8'd0;
                        audio_byte_count        <= 32'd0;
                        state                   <= ST_AUDIO_START_CALC;
                    end else if ((audio_sector_in_cluster + 8'd1) <
                                 fs_sectors_per_cluster) begin
                        audio_sector_in_cluster <= audio_sector_in_cluster + 8'd1;
                        sd_sec_read_addr        <= sd_sec_read_addr + 32'd1;
                        state                   <= ST_AUDIO_DATA;
                    end else begin
                        fat_entry_offset <= {audio_current_cluster[6:0], 2'b00};
                        sd_sec_read_addr <= cluster_fat_sector;
                        state            <= ST_AUDIO_FAT;
                    end
                end else if(FAST_AUDIO_START && load_paused) begin
                    sd_sec_read_addr<=load_resume_addr;
                    fat_entry_offset<={load_cluster_latched[6:0],2'b00};
                    state<=load_resume_state;
                    load_paused<=1'b0;
                end else if(FAST_AUDIO_START) begin
                    // Yield to a pending next-image request with one idle
                    // cycle of lookahead before restarting audio service.
                    state<=ST_IDLE;
                end
            end

            ST_AUDIO_DATA: begin
                state_code  <= 4'd5;
                sd_sec_read <= 1'b1;

                if (sd_sec_read_data_valid &&
                    (audio_byte_count < audio_file_size))
                    audio_byte_count <= audio_byte_count + 32'd1;

                if (sd_sec_read_end) begin
                    sd_sec_read <= 1'b0;
                    state       <= ST_AUDIO_WAIT;
                    if(FAST_AUDIO_START) audio_resume_addr<=sd_sec_read_addr;
                end
            end

            ST_AUDIO_FAT: begin
                state_code  <= 4'd5;
                sd_sec_read <= 1'b1;

                if (sd_sec_read_end) begin
                    sd_sec_read <= 1'b0;
                    if (fat_next_cluster_invalid ||
                        (fat_next_cluster_masked == audio_current_cluster)) begin
                        // Truncated/bad chain: restart at the beginning. This
                        // keeps HDMI audio alive instead of locking the reader.
                        audio_current_cluster   <= audio_file_cluster;
                        audio_sector_in_cluster <= 8'd0;
                        audio_byte_count        <= 32'd0;
                        state                   <= ST_AUDIO_START_CALC;
                    end else begin
                        audio_current_cluster <= fat_next_cluster_masked;
                        state                 <= ST_AUDIO_NEXT_CALC;
                    end
                end
            end

            ST_AUDIO_NEXT_CALC: begin
                state_code           <= 4'd5;
                sd_sec_read          <= 1'b0;
                cluster_index        <= next_cluster_index;
                cluster_index_ok     <= next_cluster_index_ok;
                cluster_return_state<= ST_AUDIO_NEXT_ADDR;
                state <= PIPELINED_CLUSTER_ADDR ? ST_CLUSTER_SHIFT : ST_AUDIO_NEXT_ADDR;
            end

            ST_AUDIO_NEXT_ADDR: begin
                state_code              <= 4'd5;
                sd_sec_read             <= 1'b0;
                audio_sector_in_cluster <= 8'd0;
                sd_sec_read_addr        <= cluster_data_sector;
                state                   <= ST_AUDIO_DATA;
            end

            ST_CLUSTER_SHIFT: begin
                sd_sec_read <= 1'b0;
                cluster_offset_q <= cluster_offset;
                state <= cluster_return_state;
            end

            default: begin
                state       <= ST_IDLE;
                state_code  <= 4'd1;
                sd_sec_read <= 1'b0;
                write_req   <= 1'b0;
            end
        endcase
    end
end

endmodule
