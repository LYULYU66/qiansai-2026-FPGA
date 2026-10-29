`timescale 1ns/1ps
module tb_resize_cache_pcm;
reg clk=0,rst=1,key_next=1,key_auto=1,finish_toggle=0;
wire wr_req,we,topdown,display_valid,audio_enable,pcm_valid,abort;
wire [31:0] wd,pcm;
wire [1:0] wi,di;
wire [127:0] metadata;
integer pixels=0,commits=0,pcm_count=0,drain=0,i,c;
always #5 clk=~clk;
sd_card_bmp #(.ENABLE_RESAMPLE(1),.OUT_WIDTH(8),.OUT_HEIGHT(4),
 .CLK_FREQ_HZ(1000),.LOAD_TIMEOUT_CYCLES(20000),.SCAN_TIMEOUT_CYCLES(100000)) dut(
 .clk(clk),.rst(rst),.key_next(key_next),.key_auto(key_auto),.I_warning_hold(1'b0),
 .bmp_width(16'd640),.bmp_height(16'd480),.display_valid(display_valid),
 .warning_image_ready(),.state_code(),.image_number(),
 .write_finish_toggle(finish_toggle),.write_buf_idx(wi),.disp_buf_idx(di),.load_abort(abort),
 .write_req(wr_req),.write_req_ack(wr_req),.write_en(we),.write_data(wd),
 .write_top_down(topdown),.source_resolutions(metadata),
 .write_pixel_ready(1'b1),
 .audio_fifo_ready(1'b1),.audio_pcm_wr_en(pcm_valid),.audio_pcm_data(pcm),
 .audio_stream_enable(audio_enable),.audio_file_bytes(),.SD_nCS(),.SD_DCLK(),.SD_MOSI(),.SD_MISO(1'b1));
function integer width_for(input integer id);
 case(id) 0:width_for=16; 1:width_for=13; 2:width_for=9; default:width_for=8; endcase
endfunction
function integer height_for(input integer id);
 case(id) 0:height_for=8; 1:height_for=9; 2:height_for=11; default:height_for=4; endcase
endfunction
function integer sample(input integer id,x,y,ch);
 sample=(id*67+x*(17+ch*7)+y*(11+ch*13))&255;
endfunction
function [23:0] expected(input integer id,n);
 integer dx,dy,qx,qy,x0,x1,y0,y1,fx,fy,ch;
 reg [63:0] a,b,v;
 begin
  dx=n%8; dy=n/8; qx=dx*(width_for(id)-1)*256/7; qy=dy*(height_for(id)-1)*256/3;
  x0=qx>>8; y0=qy>>8; x1=(x0<width_for(id)-1)?x0+1:x0;
  y1=(y0<height_for(id)-1)?y0+1:y0; fx=qx&255; fy=qy&255; expected=0;
  for(ch=0;ch<3;ch=ch+1) begin
   a=sample(id,x0,y0,ch)*(256-fx)+sample(id,x1,y0,ch)*fx;
   b=sample(id,x0,y1,ch)*(256-fx)+sample(id,x1,y1,ch)*fx;
   v=(a*(256-fy)+b*fy+32768)>>16; expected[ch*8 +: 8]=v[7:0];
  end
 end
endfunction
always @(negedge clk) if(!rst) begin
 if(abort) $fatal(1,"unexpected image load timeout");
 if(we) begin
  if(wd!=={expected(wi,pixels%32),8'd0} || topdown!=(wi==2)) $fatal(1,"cache pixel/orientation %d/%d",wi,pixels);
  if(metadata[wi*32 +: 32]!==0) $fatal(1,"metadata published before write commit");
  pixels=pixels+1;
  if(pixels%32==0) drain=30;
 end
 if(drain>0) begin
  drain=drain-1;
  if(drain==0) begin finish_toggle=~finish_toggle; commits=commits+1; end
 end
 if(pcm_valid) begin
  c=(pcm_count%16)*4;
  if(pcm!==((c+3)*16777216+(c+2)*65536+(c+1)*256+c)) $fatal(1,"PCM corrupted at %d",pcm_count);
  pcm_count=pcm_count+1;
 end
end
initial begin
 repeat(5) @(negedge clk); rst=0;
 wait(dut.preload_done); repeat(10) @(negedge clk);
 if(pixels!=128 || commits!=4 || !display_valid || di!=0) $fatal(1,"cache preload/first image");
 for(i=0;i<4;i=i+1) begin
  if(metadata[i*32 +: 32]!==((width_for(i)<<16)|height_for(i))) $fatal(1,"per-image metadata %d",i);
 end
 wait(pcm_count>=32);
 for(i=1;i<=4;i=i+1) begin
  @(negedge clk); key_next=0; repeat(20) @(negedge clk);
  key_next=1; repeat(20) @(negedge clk);
  if(di!=(i%4)) $fatal(1,"manual cached switch");
 end
 @(negedge clk); key_auto=0; repeat(20) @(negedge clk);
 key_auto=1; repeat(1040) @(negedge clk);
 if(!dut.auto_play_en || di!=1 || pcm_count<64) $fatal(1,"auto/PCM concurrency");
 $display("PASS real reader four resized caches / committed original dimensions / manual-auto switches / PCM loop frames=%d",pcm_count);
 $finish;
end
initial begin #5000000; $fatal(1,"cache watchdog"); end
endmodule

// Card-sector transport model only. FAT/BMP/PCM parser and playback FSM are
// the production RTL; no forced scan, load, or completion internals.
module sd_card_top #(parameter SPI_LOW_SPEED_DIV=0,SPI_HIGH_SPEED_DIV=0)(
 input clk,rst,io_abort,output SD_nCS,SD_DCLK,SD_MOSI,input SD_MISO,
 output wire sd_init_done,input sd_sec_read,input [31:0] sd_sec_read_addr,
 output reg [7:0] sd_sec_read_data,output reg sd_sec_read_data_valid,sd_sec_read_end,
 input sd_sec_write,input [31:0] sd_sec_write_addr,input [7:0] sd_sec_write_data,
 output sd_sec_write_data_req,sd_sec_write_end);
reg [7:0] card [0:4095];
integer k,id,w,h,stride,base,bytes,x,y,ch,pos;
reg sending=0,ending=0,cooldown=0;
integer lba,index;
assign sd_init_done=!rst; assign SD_nCS=1; assign SD_DCLK=0; assign SD_MOSI=1;
assign sd_sec_write_data_req=0; assign sd_sec_write_end=0;
task put32(input integer a,v);
 begin card[a]=v; card[a+1]=v>>8; card[a+2]=v>>16; card[a+3]=v>>24; end
endtask
initial begin
 for(k=0;k<4096;k=k+1) card[k]=0;
 card[11]=0; card[12]=2; card[13]=1; card[14]=1; card[16]=1;
 put32(36,1); put32(44,2);
 for(id=0;id<5;id=id+1) begin
  base=1024+id*32; card[base]="P"; card[base+11]=8'h20; card[base+26]=3+id;
  card[base+8]=id==4 ? "P":"B"; card[base+9]=id==4 ? "C":"M"; card[base+10]=id==4 ? "M":"P";
  if(id==4) begin put32(base+28,64); end
  else begin
   w=tb_resize_cache_pcm.width_for(id); h=tb_resize_cache_pcm.height_for(id);
   stride=(w*3+3)&~3; bytes=54+stride*h; put32(base+28,bytes); base=(id+3)*512;
   card[base]="B"; card[base+1]="M"; put32(base+2,bytes); put32(base+10,54);
   put32(base+14,40); put32(base+18,w); put32(base+22,id==2 ? -h:h);
   card[base+26]=1; card[base+28]=24;
   for(y=0;y<h;y=y+1) for(x=0;x<w;x=x+1) for(ch=0;ch<3;ch=ch+1)
    card[base+54+y*stride+x*3+ch]=tb_resize_cache_pcm.sample(id,x,y,ch);
  end
 end
 for(k=0;k<64;k=k+1) card[3584+k]=k;
end
always @(negedge clk) begin
 sd_sec_read_data_valid=0; sd_sec_read_end=0;
 if(rst||io_abort) begin sending=0; ending=0; cooldown=0; end
 else if(sending) begin
  sd_sec_read_data=card[lba*512+index]; sd_sec_read_data_valid=1;
  if(index==511) begin sending=0; ending=1; end else index=index+1;
 end else if(ending) begin sd_sec_read_end=1; ending=0; cooldown=1; end
 else if(cooldown) cooldown=0;
 else if(sd_sec_read) begin
  if(sd_sec_read_addr>=8) $fatal(1,"unexpected sector %d",sd_sec_read_addr);
  sending=1; lba=sd_sec_read_addr; index=0;
 end
end
endmodule
