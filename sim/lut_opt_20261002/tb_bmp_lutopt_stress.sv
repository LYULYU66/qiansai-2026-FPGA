`timescale 1ns/1ps
// LUT-optimisation stress check: current bmp_read versus the pre-optimisation
// copy under random load aborts, SD re-initialisation, rescans, loads and
// audio enable changes. Every external output is compared on every cycle.
module tb_bmp_lutopt_stress;
reg clk=0, rst=1, scan_start=0, load_start=0, audio_enable=0, load_abort=0, init_done=1;
reg [31:0] load_sector=0, load_cluster=0;
reg [7:0] data=0;
reg data_valid=0, read_end=0, fifo_ready=1;
wire ready[0:1], scan_done[0:1], found_valid[0:1], music_found[0:1];
wire [31:0] found_sector[0:1], found_cluster[0:1], read_addr[0:1], file_bytes[0:1];
wire [2:0] found_total[0:1];
wire [3:0] state_code[0:1];
wire write_req[0:1], read_req[0:1], pcm_valid[0:1], pixel_valid[0:1];
wire [7:0] pcm[0:1];
wire [23:0] pixel[0:1];
integer spc=1, volume=0, config_id, cycles=0, audio_size, events=0, n;
integer rescans=0, aborts=0, reinits=0, loads=0, pixels=0, pcm_bytes=0;
reg [31:0] r;
reg [31:0] sectors[0:3], clusters[0:3];
integer found=0;
reg need_scan=0, scan_cleared=0;
reg sending=0, armed=1, end_pending=0;
reg [31:0] active_sector=0;
reg [8:0] byte_offset=0;
always #5 clk=~clk;
`define BMP_PORTS(N) \
 .clk(clk),.rst(rst),.ready(ready[N]),.scan_start(scan_start),.scan_target_count(3'd4), \
 .scan_done(scan_done[N]),.scan_found_valid(found_valid[N]),.scan_found_sector(found_sector[N]), \
 .scan_found_cluster(found_cluster[N]),.scan_found_total(found_total[N]), \
 .load_start(load_start),.load_abort(load_abort),.load_sector(load_sector),.load_cluster(load_cluster), \
 .audio_enable(audio_enable),.audio_fifo_ready(fifo_ready),.audio_file_found(music_found[N]), \
 .audio_file_bytes(file_bytes[N]), \
 .audio_data_valid(pcm_valid[N]),.audio_data(pcm[N]),.sd_init_done(init_done),.state_code(state_code[N]), \
 .bmp_width(16'd16),.bmp_height(16'd32),.write_req(write_req[N]),.write_req_ack(1'b1), \
 .sd_sec_read(read_req[N]),.sd_sec_read_addr(read_addr[N]),.sd_sec_read_data(data), \
 .sd_sec_read_data_valid(data_valid),.sd_sec_read_end(read_end), \
 .bmp_data_wr_en(pixel_valid[N]),.bmp_data(pixel[N])
bmp_read dut(`BMP_PORTS(0));
bmp_read_pre_lutopt ref_dut(`BMP_PORTS(1));
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
    // Like sd_card_top: io_abort (load_abort) cancels the active transfer.
    if(rst || !init_done || load_abort) begin sending<=0; armed<=1; end_pending<=0; byte_offset<=0; end
    else begin
        if(!read_req[0]) armed<=1;
        if(end_pending) begin read_end<=1; end_pending<=0; end
        else if(!sending && read_req[0] && armed) begin
            sending<=1; armed<=0; active_sector<=read_addr[0]; byte_offset<=0;
        end else if(sending && cycles%7!=0) begin
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
        if({ready[0],scan_done[0],found_valid[0],found_sector[0],found_cluster[0],found_total[0],
            music_found[0],file_bytes[0],state_code[0],write_req[0],read_req[0],read_addr[0],
            pcm_valid[0],pcm[0],pixel_valid[0],pixel[0]} !==
           {ready[1],scan_done[1],found_valid[1],found_sector[1],found_cluster[1],found_total[1],
            music_found[1],file_bytes[1],state_code[1],write_req[1],read_req[1],read_addr[1],
            pcm_valid[1],pcm[1],pixel_valid[1],pixel[1]})
        begin
            $display("rd %h/%h addr %h/%h fat %h/%h foff %0d/%0d rdcnt %0d/%0d lc %h/%h st %0d/%0d ready %b/%b px %b/%b pcm %b/%b",
              read_req[0],read_req[1],read_addr[0],read_addr[1],dut.fat_next_cluster,ref_dut.fat_next_cluster,
              dut.fat_entry_offset,ref_dut.fat_entry_offset,dut.rd_cnt,ref_dut.rd_cnt,
              dut.load_cluster_latched,ref_dut.load_cluster_latched,state_code[0],state_code[1],ready[0],ready[1],
              pixel_valid[0],pixel_valid[1],pcm_valid[0],pcm_valid[1]);
            $fatal(1,"BMP LUT-opt stress mismatch config=%0d cycle=%0d state=%0d/%0d",
                   config_id,cycles,dut.state,ref_dut.state);
        end
        if(!scan_done[0]) scan_cleared=1;
        if(scan_done[0] && scan_cleared && need_scan && init_done) need_scan=0;
        if(found_valid[0] && found_total[0]>=1 && found_total[0]<=4) begin
            sectors[found_total[0]-1]=found_sector[0]; clusters[found_total[0]-1]=found_cluster[0];
            if(found<found_total[0]) found=found_total[0];
        end
        if(pixel_valid[0]) pixels=pixels+1;
        if(pcm_valid[0]) pcm_bytes=pcm_bytes+1;
    end
end
initial begin
    r=32'h1234_5678;
    for(config_id=0;config_id<8;config_id=config_id+1) begin
        @(posedge clk); #1;
        rst=1; scan_start=0; load_start=0; audio_enable=0; load_abort=0; init_done=1; found=0; need_scan=0; scan_cleared=0;
        spc=1<<config_id;
        case(config_id)
            1: volume=128; 3: volume=65536; 5: volume=16777216; 7: volume=32768;
            default: volume=0;
        endcase
        audio_size=spc*512+100;
        repeat(4) @(posedge clk); #1; rst=0;
        for(n=0;n<250000;n=n+1) begin
            r={r[30:0],r[31]^r[21]^r[1]^r[0]};
            scan_start=0; load_start=0; load_abort=0;
            case(r[13:0])
                14'd1,14'd2: begin scan_start=1; rescans=rescans+1; end
                14'd3,14'd4,14'd5: begin load_abort=1; aborts=aborts+1; end
                14'd6: begin init_done=0; reinits=reinits+1; end
                14'd7,14'd8,14'd9,14'd10: audio_enable=~audio_enable;
                default: if(r[13:6]==8'd1 && found!=0) begin
                    load_sector=sectors[r[15:14]%found]; load_cluster=clusters[r[15:14]%found];
                    load_start=1; loads=loads+1;
                end
            endcase
            // sd_card_bmp protocol after an SD re-initialisation: preload and
            // PCM streaming stay off until a fresh directory scan completes.
            if(!init_done) begin need_scan=1; scan_cleared=0; found=0; audio_enable=0; end
            if(!init_done && r[17:14]==4'd0) init_done=1;
            if(need_scan && init_done && ready[0] && r[4:0]==0) scan_start=1;
            // sd_card_bmp issues scan_start only from the idle reader; a new
            // scan invalidates loads/PCM until that same scan reports done.
            if(scan_start && !ready[0]) scan_start=0;
            if(scan_start) begin need_scan=1; scan_cleared=0; found=0; end
            if(need_scan) begin load_start=0; audio_enable=0; end
            // Keep the first scan of every configuration undisturbed so that
            // the later random loads have real file addresses.
            if(n<20) begin scan_start=(n==2); load_abort=0; load_start=0; init_done=1;
                if(n==2) begin need_scan=1; scan_cleared=0; end end
            if(n>=20 && n<60000 && found==0 && !need_scan) begin load_abort=0; init_done=1; end
            @(posedge clk); #1;
        end
        init_done=1;
        $display("PASS BMP_LUTOPT_STRESS spc=%0d MBR=%0d found=%0d",spc,volume,found);
    end
    $display("PASS BMP_LUTOPT_STRESS 2000000 cycles: rescans=%0d aborts=%0d reinits=%0d loads=%0d pixels=%0d pcm=%0d, all outputs identical every cycle",
             rescans,aborts,reinits,loads,pixels,pcm_bytes);
    $finish;
end
endmodule
