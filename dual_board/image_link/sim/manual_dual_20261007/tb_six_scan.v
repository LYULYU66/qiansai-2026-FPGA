`timescale 1ns/1ps
// Actual FAT scanner, sector-only transport model. Root spans two noncontiguous
// clusters; deleted/LFN/volume/non-BMP entries must not consume image indices.
module tb_six_scan;
parameter integer MAX_IMAGES=6,PICTURE_COUNT=6,MUSIC_COUNT=2;
localparam integer EXPECTED=(PICTURE_COUNT<MAX_IMAGES)?PICTURE_COUNT:MAX_IMAGES;
reg clk=0,rst=1,scan_start=0;
wire ready,scan_done,found_valid,audio_found;
wire [31:0] found_sector,found_cluster;
wire [2:0] found_total;
wire [1:0] songs;
wire rd;
wire [31:0] rd_addr;
reg [7:0] data=0;
reg data_valid=0,sector_end=0;
integer found_count=0,root_tail_reads=0,fat_reads=0,cycle=0;
reg [7:0] card[0:65535];
integer k,base,id;
always #5 clk=~clk;
bmp_read #(.MAX_IMAGES(MAX_IMAGES),.DUAL_SONG(1),.PIPELINED_CLUSTER_ADDR(1)) dut (
 .clk(clk),.rst(rst),.ready(ready),.scan_start(scan_start),.scan_target_count(3'd6),
 .scan_done(scan_done),.scan_found_valid(found_valid),.scan_found_sector(found_sector),
 .scan_found_cluster(found_cluster),.scan_found_total(found_total),
 .load_start(1'b0),.load_abort(1'b0),.load_sector(32'd0),.load_cluster(32'd0),
 .audio_enable(1'b0),.audio_fifo_ready(1'b1),.audio_song_select(1'b0),
 .audio_songs_found(songs),.audio_idle(),.audio_file_found(audio_found),
 .audio_file_bytes(),.audio_data_valid(),.audio_data(),.sd_init_done(1'b1),
 .state_code(),.bmp_width(16'd640),.bmp_height(16'd480),.write_req(),.write_req_ack(1'b0),
 .sd_sec_read(rd),.sd_sec_read_addr(rd_addr),.sd_sec_read_data(data),
 .sd_sec_read_data_valid(data_valid),.sd_sec_read_end(sector_end),
 .bmp_data_wr_en(),.bmp_data(),.source_width(),.source_height(),.source_top_down(),
 .write_pixel_ready(1'b1)
);
task put32;
 input integer a,v;
 begin card[a]=v;card[a+1]=v>>8;card[a+2]=v>>16;card[a+3]=v>>24;end
endtask
task picture;
 input integer a,n;
 begin
  card[a]="P";card[a+1]="I";card[a+2]="C";card[a+3]="1"+n;
  card[a+4]=" ";card[a+5]=" ";card[a+6]=" ";card[a+7]=" ";
  card[a+8]="B";card[a+9]="M";card[a+10]="P";card[a+11]=8'h20;
  put32(a+26,27+n);put32(a+28,921654);
 end
endtask
task music;
 input integer a,n;
 begin
  card[a]="M";card[a+1]="U";card[a+2]="S";card[a+3]="I";card[a+4]="C";
  card[a+5]=(n==0)?" ":"2";card[a+6]=" ";card[a+7]=" ";
  card[a+8]="P";card[a+9]="C";card[a+10]="M";card[a+11]=8'h20;
  put32(a+26,60+n);put32(a+28,1024);
 end
endtask
initial begin
 for(k=0;k<65536;k=k+1) card[k]=0;
 card[11]=0;card[12]=2;card[13]=1;card[14]=1;card[16]=1;
 put32(36,1);put32(44,2);put32(512+2*4,20);put32(512+20*4,32'h0fffffff);
 for(id=0;id<4;id=id+1) picture(1024+id*32,id);
 for(id=4;id<16;id=id+1)begin
  picture(1024+id*32,id);card[1024+id*32]=8'he5;
 end
 // All remaining first-sector entries are non-terminating invalid entries.
 card[1024+5*32]="L";card[1024+5*32+11]=8'h0f;
 card[1024+6*32]="V";card[1024+6*32+11]=8'h08;
 card[1024+7*32]="D";card[1024+7*32+11]=8'h10;
 base=20*512;
 for(id=4;id<PICTURE_COUNT;id=id+1) picture(base+(id-4)*32,id);
 base=base+(PICTURE_COUNT-4)*32;
 for(id=0;id<MUSIC_COUNT;id=id+1) music(base+id*32,id);
 // A seventh image proves the configured limit is honored.
 if(PICTURE_COUNT==6) picture(base+MUSIC_COUNT*32,6);
 repeat(6) @(negedge clk);rst=0;
 @(negedge clk);scan_start=1;@(negedge clk);scan_start=0;
 wait(scan_done);repeat(3) @(negedge clk);
 if(found_count!=EXPECTED || found_total!=EXPECTED)
  $fatal(1,"scanner count expected=%d actual=%d total=%d",EXPECTED,found_count,found_total);
 if(songs!=((MUSIC_COUNT==2)?2'b11:((MUSIC_COUNT==1)?2'b01:2'b00)))
  $fatal(1,"music discovery mismatch %b",songs);
 if(root_tail_reads!=1 || fat_reads!=1 || !ready)
  $fatal(1,"noncontiguous root traversal/ready mismatch");
 $display("PASS SIX_SCAN: MAX=%d, candidates=%d, ordered emits=%d, songs=%b, deleted/LFN/volume/directory skipped, cross-cluster root",MAX_IMAGES,PICTURE_COUNT,found_count,songs);
 $finish;
end
always @(posedge clk) if(!rst && found_valid)begin
 if(found_cluster!==27+found_count || found_sector!==27+found_count || found_total!==found_count+1)
  $fatal(1,"ordered candidate mismatch at %d cluster=%d sector=%d total=%d",found_count,found_cluster,found_sector,found_total);
 found_count=found_count+1;
 if(found_count>EXPECTED)$fatal(1,"extra candidate emit");
end
reg sending=0,ending=0,cooldown=0;
integer lba,byte_index,byte_wait=0;
always @(negedge clk)begin
 data_valid=0;sector_end=0;cycle=cycle+1;
 if(rst)begin sending=0;ending=0;cooldown=0;byte_wait=0;end
 else if(sending && byte_wait!=0) byte_wait=byte_wait-1;
 else if(sending)begin
  data=card[lba*512+byte_index];data_valid=1;
  byte_wait=(byte_index%11==0)?3:1;
  if(byte_index==511)begin sending=0;ending=1;end else byte_index=byte_index+1;
 end else if(ending)begin sector_end=1;ending=0;cooldown=1;end
 else if(cooldown)cooldown=0;
 else if(rd)begin
  if(rd_addr>=128)$fatal(1,"unexpected LBA %d",rd_addr);
  lba=rd_addr;byte_index=0;sending=1;byte_wait=2;
  if(lba==20)root_tail_reads=root_tail_reads+1;
  if(lba==1)fat_reads=fat_reads+1;
 end
end
initial begin #5000000;$fatal(1,"scanner watchdog");end
endmodule
