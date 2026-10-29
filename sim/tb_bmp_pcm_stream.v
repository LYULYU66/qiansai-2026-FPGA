module tb_bmp_pcm_stream;

reg clk = 1'b0;
reg rst = 1'b1;
reg scan_start = 1'b0;
reg audio_enable = 1'b0;
wire ready;
wire scan_done;
wire audio_file_found;
wire [31:0] audio_file_bytes;
wire audio_data_valid;
wire [7:0] audio_data;
wire sd_sec_read;
wire [31:0] sd_sec_read_addr;
reg [7:0] sd_sec_read_data = 8'd0;
reg sd_sec_read_data_valid = 1'b0;
reg sd_sec_read_end = 1'b0;

integer audio_count = 0;
integer bmp_count = 0;
reg sending = 1'b0;
reg end_pending = 1'b0;
reg request_armed = 1'b1;
reg [31:0] active_sector = 32'd0;
reg [8:0] byte_offset = 9'd0;

always #5 clk = ~clk;

bmp_read dut (
    .clk(clk),
    .rst(rst),
    .ready(ready),
    .scan_start(scan_start),
    .scan_target_count(3'd4),
    .scan_done(scan_done),
    .scan_found_valid(),
    .scan_found_sector(),
    .scan_found_cluster(),
    .scan_found_total(),
    .load_start(1'b0),
    .load_abort(1'b0),
    .load_sector(32'd0),
    .load_cluster(32'd0),
    .audio_enable(audio_enable),
    .audio_fifo_ready(1'b1),
    .audio_file_found(audio_file_found),
    .audio_file_bytes(audio_file_bytes),
    .audio_data_valid(audio_data_valid),
    .audio_data(audio_data),
    .sd_init_done(1'b1),
    .state_code(),
    .bmp_width(16'd640),
    .bmp_height(16'd480),
    .write_req(),
    .write_req_ack(1'b0),
    .sd_sec_read(sd_sec_read),
    .sd_sec_read_addr(sd_sec_read_addr),
    .sd_sec_read_data(sd_sec_read_data),
    .sd_sec_read_data_valid(sd_sec_read_data_valid),
    .sd_sec_read_end(sd_sec_read_end),
    .bmp_data_wr_en(),
    .bmp_data()
);

function [7:0] root_entry_byte;
    input [3:0] entry;
    input [4:0] pos;
    begin
        root_entry_byte = 8'h00;
        if (entry < 4) begin
            case (pos)
                5'd0: root_entry_byte = "P";
                5'd1: root_entry_byte = "I";
                5'd2: root_entry_byte = "C";
                5'd3: root_entry_byte = "1" + entry;
                5'd4, 5'd5, 5'd6, 5'd7: root_entry_byte = 8'h20;
                5'd8: root_entry_byte = "B";
                5'd9: root_entry_byte = "M";
                5'd10: root_entry_byte = "P";
                5'd11: root_entry_byte = 8'h20;
                5'd26: root_entry_byte = 8'd3 + entry;
                default: root_entry_byte = 8'h00;
            endcase
        end else if (entry == 4) begin
            case (pos)
                // Deliberately do not call the file MUSIC.PCM: the reader must
                // accept Windows-generated/renamed 8.3 base names.
                5'd0: root_entry_byte = "A";
                5'd1: root_entry_byte = "U";
                5'd2: root_entry_byte = "D";
                5'd3: root_entry_byte = "I";
                5'd4: root_entry_byte = "O";
                5'd5: root_entry_byte = "0";
                5'd6: root_entry_byte = "0";
                5'd7: root_entry_byte = "1";
`ifdef TEST_WAV
                5'd8: root_entry_byte = "W";
                5'd9: root_entry_byte = "A";
                5'd10: root_entry_byte = "V";
`else
                5'd8: root_entry_byte = "P";
                5'd9: root_entry_byte = "C";
                5'd10: root_entry_byte = "M";
`endif
                5'd11: root_entry_byte = 8'h20;
                5'd26: root_entry_byte = 8'd7;
                5'd28: root_entry_byte = 8'h00;
                5'd29: root_entry_byte = 8'h04;
                5'd30: root_entry_byte = 8'h00;
                5'd31: root_entry_byte = 8'h00;
                default: root_entry_byte = 8'h00;
            endcase
        end
    end
endfunction

function [7:0] sector_byte;
    input [31:0] sector;
    input [8:0] offset;
    reg [3:0] entry;
    reg [4:0] pos;
    begin
        sector_byte = 8'h00;
        case (sector)
            32'd0: begin
                case (offset)
                    9'd11: sector_byte = 8'h00;
                    9'd12: sector_byte = 8'h02;
                    9'd13: sector_byte = 8'h01;
                    9'd14: sector_byte = 8'h01;
                    9'd15: sector_byte = 8'h00;
                    9'd16: sector_byte = 8'h01;
                    9'd36: sector_byte = 8'h01;
                    9'd44: sector_byte = 8'h02;
                    default: sector_byte = 8'h00;
                endcase
            end
            32'd1: begin
                if (offset == 9'd28)
                    sector_byte = 8'h09;
                else if ((offset >= 9'd36) && (offset <= 9'd39))
                    sector_byte = 8'hff;
            end
            32'd2: begin
                entry = offset[8:5];
                pos = offset[4:0];
                sector_byte = root_entry_byte(entry, pos);
            end
            32'd7: sector_byte = offset[7:0];
            32'd9: sector_byte = offset[7:0] ^ 8'ha5;
            default: sector_byte = 8'h00;
        endcase
    end
endfunction

always @(posedge clk) begin
    sd_sec_read_data_valid <= 1'b0;
    sd_sec_read_end <= 1'b0;

    if (!sd_sec_read)
        request_armed <= 1'b1;

    if (end_pending) begin
        sd_sec_read_end <= 1'b1;
        end_pending <= 1'b0;
    end else if (!sending && sd_sec_read && request_armed) begin
        sending <= 1'b1;
        request_armed <= 1'b0;
        active_sector <= sd_sec_read_addr;
        byte_offset <= 9'd0;
    end else if (sending) begin
        sd_sec_read_data <= sector_byte(active_sector, byte_offset);
        sd_sec_read_data_valid <= 1'b1;
        if (byte_offset == 9'd511) begin
            sending <= 1'b0;
            end_pending <= 1'b1;
        end else begin
            byte_offset <= byte_offset + 9'd1;
        end
    end
end

always @(posedge clk) begin
    if (dut.scan_found_valid)
        bmp_count <= bmp_count + 1;

    if (audio_data_valid) begin
        if (audio_count < 512) begin
            if (audio_data !== audio_count[7:0])
                $fatal(1, "cluster7 mismatch byte=%0d got=%02x", audio_count, audio_data);
        end else if (audio_count < 1024) begin
            if (audio_data !== (((audio_count - 512) & 8'hff) ^ 8'ha5))
                $fatal(1, "cluster9 mismatch byte=%0d got=%02x", audio_count, audio_data);
        end else begin
            if (audio_data !== ((audio_count - 1024) & 8'hff))
                $fatal(1, "loop mismatch byte=%0d got=%02x", audio_count, audio_data);
        end
        audio_count <= audio_count + 1;
        if (audio_count == 1039) begin
            $display("PASS PCM_SCAN bmp=4 music=found fragmented=7_to_9 loop=ok bytes=1040");
            $finish;
        end
    end
end

initial begin
    repeat (5) @(posedge clk);
    rst = 1'b0;
    @(posedge clk);
    scan_start = 1'b1;
    @(posedge clk);
    scan_start = 1'b0;
    wait (scan_done);
    repeat (2) @(posedge clk);
    if (!audio_file_found || bmp_count != 4) begin
        $display("scan audio=%b bmp=%0d", audio_file_found, bmp_count);
        $display("bps=%h spc=%h", dut.fs_bytes_per_sector, dut.fs_sectors_per_cluster);
        $display("res=%h fats=%h", dut.fs_reserved_sectors, dut.fs_num_fats);
        $display("fatsz=%h root=%h", dut.fs_fat_size, dut.fs_root_cluster);
        $fatal(1, "scan failed");
    end
    audio_enable = 1'b1;
    if(audio_file_bytes !== 32'd1024)
        $fatal(1,"PCM size metadata mismatch: %0d",audio_file_bytes);
end

initial begin
    #500000;
    $fatal(1, "timeout");
end

endmodule
