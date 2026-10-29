`timescale 1ns/1ps
module tb_bmp_resource_equivalence;
reg clk=0, rst=1, scan_start=0, load_start=0, audio_enable=0;
reg [31:0] load_sector=0, load_cluster=0;
reg [7:0] data=0;
reg data_valid=0, read_end=0, fifo_ready=1;
wire ready[0:1], scan_done[0:1], found_valid[0:1], music_found[0:1];
wire [31:0] found_sector[0:1], found_cluster[0:1], read_addr[0:1];
wire [2:0] found_total[0:1];
wire [3:0] state_code[0:1];
wire write_req[0:1], read_req[0:1], pcm_valid[0:1], pixel_valid[0:1];
wire [7:0] pcm[0:1];
wire [23:0] pixel[0:1];
integer spc=1, volume=0, config_id, image_id, count_found=0;
integer pixel_count=0, audio_count=0, audio_size, cycles=0;
integer phase=0, ofs, b;
integer high_nibble, edge_value, random_case;
reg [31:0] cluster_probe, cluster_masked;
reg [31:0] sectors[0:3], clusters[0:3];
reg sending=0, armed=1, end_pending=0;
reg [31:0] active_sector=0;
reg [8:0] byte_offset=0;
always #5 clk=~clk;
`define BMP_PORTS(N) \
 .clk(clk),.rst(rst),.ready(ready[N]),.scan_start(scan_start),.scan_target_count(3'd4), \
 .scan_done(scan_done[N]),.scan_found_valid(found_valid[N]),.scan_found_sector(found_sector[N]), \
 .scan_found_cluster(found_cluster[N]),.scan_found_total(found_total[N]), \
 .load_start(load_start),.load_abort(1'b0),.load_sector(load_sector),.load_cluster(load_cluster), \
 .audio_enable(audio_enable),.audio_fifo_ready(fifo_ready),.audio_file_found(music_found[N]), \
 .audio_data_valid(pcm_valid[N]),.audio_data(pcm[N]),.sd_init_done(1'b1),.state_code(state_code[N]), \
 .bmp_width(16'd16),.bmp_height(16'd32),.write_req(write_req[N]),.write_req_ack(1'b1), \
 .sd_sec_read(read_req[N]),.sd_sec_read_addr(read_addr[N]),.sd_sec_read_data(data), \
 .sd_sec_read_data_valid(data_valid),.sd_sec_read_end(read_end), \
 .bmp_data_wr_en(pixel_valid[N]),.bmp_data(pixel[N])
bmp_read dut(`BMP_PORTS(0));
bmp_read_resource_reference ref_dut(`BMP_PORTS(1));
`undef BMP_PORTS

function [7:0] sector_byte;
    input integer sector, offset;
    integer cl, within_cl, entry, pos, first_cluster, size, fpos, fat_value;
    begin
        sector_byte=0;
        if(volume!=0 && sector==0) begin
            if(offset>=454 && offset<458) sector_byte=volume >> ((offset-454)*8);
        end else if(sector==volume) begin
            case(offset)
                12: sector_byte=2;
                13: sector_byte=spc;
                14,16,36: sector_byte=1;
                44: sector_byte=2;
            endcase
        end else if(sector==volume+1) begin
            cl=offset/4;
            fat_value=32'h0fffffff;
            if(cl==2) fat_value=4;
            if(cl>=10 && cl<50 && cl%10<6) fat_value=cl+2;
            if(cl==100) fat_value=110;
            sector_byte=fat_value >> ((offset%4)*8);
        end else if(sector>=volume+2) begin
            cl=(sector-volume-2)/spc+2;
            within_cl=(sector-volume-2)%spc;
            if(cl==2) begin
                // Fill the complete first root cluster with deleted entries.
                // The real entries are in non-contiguous root cluster 4.
                if(offset%32==0) sector_byte=8'he5;
            end else if(cl==4 && within_cl==0) begin
                entry=offset/32; pos=offset%32;
                first_cluster=(entry<4)? (entry+1)*10:100;
                size=(entry<4)?1590:audio_size;
                if(entry<5) begin
                    case(pos)
                        0: sector_byte="F";
                        1: sector_byte="0"+entry;
                        2,3,4,5,6,7: sector_byte=" ";
                        8: sector_byte=(entry<4)?"B":"P";
                        9: sector_byte=(entry<4)?"M":"C";
                        10:sector_byte=(entry<4)?"P":"M";
                        11:sector_byte=8'h20;
                        26:sector_byte=first_cluster;
                        28,29,30,31:sector_byte=size >> ((pos-28)*8);
                    endcase
                end
            end else if(cl>=10 && cl<50) begin
                fpos=((cl%10)/2*spc+within_cl)*512+offset;
                if(fpos>=54) sector_byte=(fpos-54)&255;
                else case(fpos)
                    0: sector_byte="B";
                    1: sector_byte="M";
                    2: sector_byte=8'h36; // 1590 bytes
                    3: sector_byte=8'h06;
                    10:sector_byte=54;
                    14:sector_byte=40;
                    18:sector_byte=16;
                    22:sector_byte=32;
                    26:sector_byte=1;
                    28:sector_byte=24;
                endcase
            end else if(cl==100 || cl==110) begin
                fpos=((cl==110)?spc*512:0)+within_cl*512+offset;
                sector_byte=(fpos ^ (fpos>>8) ^ 8'h5a)&255;
            end
        end
    end
endfunction

always @(posedge clk) begin
    data_valid<=0; read_end<=0;
    if(rst) begin sending<=0; armed<=1; end_pending<=0; byte_offset<=0; end
    else begin
        if(!read_req[0]) armed<=1;
        if(end_pending) begin read_end<=1; end_pending<=0; end
        else if(!sending && read_req[0] && armed) begin
            sending<=1; armed<=0; active_sector<=read_addr[0]; byte_offset<=0;
        end else if(sending && cycles%7!=0) begin
            // SD byte-valid gaps and PCM backpressure exercise state holding.
            data<=sector_byte(active_sector,byte_offset); data_valid<=1;
            if(byte_offset==511) begin sending<=0; end_pending<=1; end
            else byte_offset<=byte_offset+1'b1;
        end
    end
end
always @(negedge clk) begin
    cycles=cycles+1;
    fifo_ready=(cycles%31)<19;
    if(!rst) begin
        if ((|dut.mbr_lba_nonzero_bytes) !== (|dut.mbr_partition_lba))
            $fatal(1,"MBR byte flags differ from actual partition LBA");
        if({ready[0],scan_done[0],found_valid[0],found_sector[0],found_cluster[0],found_total[0],
            music_found[0],state_code[0],write_req[0],read_req[0],read_addr[0],
            pcm_valid[0],pcm[0],pixel_valid[0],pixel[0]} !==
           {ready[1],scan_done[1],found_valid[1],found_sector[1],found_cluster[1],found_total[1],
            music_found[1],state_code[1],write_req[1],read_req[1],read_addr[1],
            pcm_valid[1],pcm[1],pixel_valid[1],pixel[1]})
            $fatal(1,"BMP equivalence mismatch config=%0d cycle=%0d state=%0d",config_id,cycles,dut.state);
        if(found_valid[0]) begin
            if(count_found>=4) $fatal(1,"too many images");
            sectors[count_found]=found_sector[0]; clusters[count_found]=found_cluster[0];
            if(found_cluster[0] !== (count_found+1)*10 ||
               found_sector[0] !== volume+2+((count_found+1)*10-2)*spc)
                $fatal(1,"wrong scan address");
            count_found=count_found+1;
        end
        if(pixel_valid[0]) begin
            b=(pixel_count*3)&255;
            if(pixel[0] !== {8'((b+2)&255),8'((b+1)&255),8'(b)})
                $fatal(1,"BMP pixel order/data mismatch pixel=%0d got=%h",pixel_count,pixel[0]);
            pixel_count=pixel_count+1;
        end
        if(pcm_valid[0]) begin
            ofs=audio_count%audio_size;
            if(pcm[0] !== 8'((ofs ^ (ofs>>8) ^ 8'h5a)&255))
                $fatal(1,"PCM mismatch offset=%0d got=%h",ofs,pcm[0]);
            audio_count=audio_count+1;
        end
    end
end
initial begin
    for(config_id=0;config_id<8;config_id=config_id+1) begin
        @(posedge clk); #1;
        rst=1; scan_start=0; load_start=0; audio_enable=0;
        count_found=0; pixel_count=0; audio_count=0;
        spc=1<<config_id;
        // Exercise each nonzero MBR byte separately, plus superfloppy mode.
        case(config_id)
            1: volume=128;
            3: volume=65536;
            5: volume=16777216;
            7: volume=32768;
            default: volume=0;
        endcase
        audio_size=spc*512+100;
        repeat(4) @(posedge clk); #1; rst=0; scan_start=1;
        @(posedge clk); #1; scan_start=0;
        wait(scan_done[0]); repeat(3) @(posedge clk); #1;
        if(count_found!=4 || !music_found[0]) $fatal(1,"scan failed");
        for(image_id=0;image_id<4;image_id=image_id+1) begin
            pixel_count=0; load_sector=sectors[image_id]; load_cluster=clusters[image_id];
            load_start=1; @(posedge clk); #1; load_start=0;
            wait(!ready[0]); wait(ready[0]); repeat(2) @(posedge clk); #1;
            if(pixel_count!=512) $fatal(1,"wrong pixel count %0d",pixel_count);
        end
        audio_enable=1;
        wait(audio_count>=audio_size+32);
        @(posedge clk); #1;
        $display("PASS BMP_EQ spc=%0d MBR=%0d directory_fragment=ok images=4 pixels=2048 PCM_fragment_and_loop=ok",spc,volume);
    end
    $display("PASS BMP_RESOURCE_EQ all 8 FAT cluster sizes, all external outputs identical every cycle");
    // Check the actual optimized DUT predicate, including masked high bits,
    // the 0/1 boundary, every reserved/EOF code, and random valid clusters.
    rst=1; audio_enable=0;
    force dut.fat_next_cluster=cluster_probe;
    for(high_nibble=0;high_nibble<16;high_nibble=high_nibble+1) begin
        for(edge_value=0;edge_value<32;edge_value=edge_value+1) begin
            cluster_probe=(high_nibble<<28)|edge_value;
            check_cluster_predicate;
            cluster_probe=(high_nibble<<28)|(32'h0fffffe0+edge_value);
            check_cluster_predicate;
        end
    end
    for(random_case=0;random_case<10000;random_case=random_case+1) begin
        cluster_probe=$random;
        check_cluster_predicate;
    end
    release dut.fat_next_cluster;
    $display("PASS FAT_CLUSTER_BOUNDS 1024 boundary/masking and 10000 random checks");
    $finish;
end
task check_cluster_predicate;
    begin
        #1;
        cluster_masked=cluster_probe & 32'h0fffffff;
        if(dut.fat_next_cluster_invalid !==
           ((cluster_masked<32'd2)||(cluster_masked>=32'h0ffffff0)))
            $fatal(1,"FAT validity mismatch for %h",cluster_probe);
    end
endtask
initial begin #20000000; $fatal(1,"BMP equivalence timeout"); end
endmodule
