`timescale 1ns/1ps
module tb_bmp_resize_reader;
reg clk=0,rst=1,load=0,abort=0,sd_valid=0,sd_end=0;
reg [7:0] sd_byte=0;
wire req,wr_req,ready,pv,topdown;
wire [31:0] addr;
wire [15:0] source_width,source_height;
wire [23:0] rgb;
integer sw=2,sh=2,offset=54,bpp=24,compression=0,negative=0;
integer stride,filebytes,n=0,requests=0,tests=0,watch,i;
reg checking=0,sending=0,end_pending=0,cooldown=0;
integer active_addr,byte_index=0;
always #5 clk=~clk;
bmp_read #(.ENABLE_RESAMPLE(1),.OUT_WIDTH(7),.OUT_HEIGHT(5)) dut(
 .clk(clk),.rst(rst),.ready(ready),.scan_start(1'b0),.scan_target_count(3'd4),
 .load_start(load),.load_abort(abort),.load_sector(32'd21),.load_cluster(32'd3),
 .audio_enable(1'b0),.audio_fifo_ready(1'b1),.sd_init_done(1'b1),
 .bmp_width(16'd640),.bmp_height(16'd480),.write_req(wr_req),.write_req_ack(wr_req),
 .write_pixel_ready(1'b1),
 .sd_sec_read(req),.sd_sec_read_addr(addr),.sd_sec_read_data(sd_byte),
 .sd_sec_read_data_valid(sd_valid),.sd_sec_read_end(sd_end),
 .bmp_data_wr_en(pv),.bmp_data(rgb),.source_width(source_width),
 .source_height(source_height),.source_top_down(topdown));
function integer pattern(input integer x,y,c);
 pattern=(x*(13+c*27)+y*(31+c*17)+c*59+7)&255;
endfunction
function integer cluster(input integer file_sector);
 cluster=3+file_sector*3; // deliberately fragmented, one sector per cluster
endfunction
function [7:0] file_byte(input integer pos);
 integer q,x,y,c,value;
 begin
  file_byte=0; value=0;
  case(pos)
   0:file_byte="B"; 1:file_byte="M";
   14:file_byte=40; 26:file_byte=1;
   default: begin
    if(pos>=2 && pos<6) file_byte=filebytes>>((pos-2)*8);
    else if(pos>=10 && pos<14) file_byte=offset>>((pos-10)*8);
    else if(pos>=18 && pos<22) file_byte=sw>>((pos-18)*8);
    else if(pos>=22 && pos<26) begin value=negative ? -sh : sh; file_byte=value>>((pos-22)*8); end
    else if(pos>=28 && pos<30) file_byte=bpp>>((pos-28)*8);
    else if(pos>=30 && pos<34) file_byte=compression>>((pos-30)*8);
    else if(pos>=offset && pos<filebytes) begin
     q=pos-offset; y=q/stride; x=(q%stride)/3; c=(q%stride)%3;
     file_byte=(x<sw) ? pattern(x,y,c) : 8'hE7;
    end
   end
  endcase
 end
endfunction
function [7:0] sector_byte(input integer lba,pos);
 integer cl,nextcl,file_sector;
 begin
  if(lba==10) begin
   cl=pos/4; nextcl=cl+3; sector_byte=nextcl>>((pos%4)*8);
  end else begin
   cl=lba-18;
   if(cl<3 || (cl-3)%3!=0) $fatal(1,"bad fragmented address %d",lba);
   file_sector=(cl-3)/3; sector_byte=file_byte(file_sector*512+pos);
  end
 end
endfunction
function [23:0] expected(input integer dx,dy);
 integer qx,qy,x0,x1,y0,y1,fx,fy,c;
 reg [63:0] a,b,v;
 begin
  qx=dx*(sw-1)*256/6; qy=dy*(sh-1)*256/4;
  x0=qx>>8; x1=x0<sw-1 ? x0+1:x0; y0=qy>>8; y1=y0<sh-1 ? y0+1:y0;
  fx=qx&255; fy=qy&255; expected=0;
  for(c=0;c<3;c=c+1) begin
   a=pattern(x0,y0,c)*(256-fx)+pattern(x1,y0,c)*fx;
   b=pattern(x0,y1,c)*(256-fx)+pattern(x1,y1,c)*fx;
   v=(a*(256-fy)+b*fy+32768)>>16; expected[c*8 +: 8]=v[7:0];
  end
 end
endfunction
always @(negedge clk) begin
 sd_valid=0; sd_end=0;
 if(rst || abort) begin sending=0; end_pending=0; cooldown=0; end
 else if(sending) begin
  sd_byte=sector_byte(active_addr,byte_index); sd_valid=1;
  if(byte_index==511) begin sending=0; end_pending=1; end
  else byte_index=byte_index+1;
 end else if(end_pending) begin sd_end=1; end_pending=0; cooldown=1; end
 else if(cooldown) cooldown=0;
 else if(req) begin sending=1; active_addr=addr; byte_index=0; requests=requests+1; end
 if(checking && pv) begin
  if(n>=35 || rgb!==expected(n%7,n/7)) $fatal(1,"reader pixel %d got=%h want=%h",n,rgb,expected(n%7,n/7));
  n=n+1;
 end
end
task run_case(input integer w,h,o,neg,bits,comp);
 begin
  checking=0; load=0; rst=1;
  repeat(5) @(posedge clk); @(posedge clk); #1; rst=0;
  dut.fs_sectors_per_cluster=1; dut.fat_start_sector=10; dut.first_data_sector=20;
  sw=w; sh=h; offset=o; negative=neg; bpp=bits; compression=comp;
  stride=(w*3+3)&~3; filebytes=offset+stride*h; n=0; requests=0;
  checking=1; repeat(3) @(posedge clk); #1; load=1;
  @(posedge clk); #1; load=0; watch=0;
  while(ready) begin @(posedge clk); #1; watch=watch+1; if(watch>10) $fatal(1,"no start"); end
  while(!ready) begin @(posedge clk); #1; watch=watch+1;
   if(watch>200000) $fatal(1,"reader hung state=%d bytes=%d pixels=%d",dut.state,dut.bmp_len_cnt,n);
  end
  repeat(3) @(posedge clk);
  if(bits==24 && comp==0 && w<=65535 && w>=7 && h>=5) begin
   if(n!=35 || source_width!=w || source_height!=h || topdown!=neg) $fatal(1,"metadata/count");
  end else if(n!=0 || requests!=1) $fatal(1,"invalid header accepted");
  tests=tests+1; $display("PASS reader BMP %dx%d topdown=%d offset=%d bpp=%d",w,h,neg,o,bits);
 end
endtask
initial begin
 run_case(2,2,54,0,24,0); run_case(39,13,700,0,24,0);
 run_case(7,5,54,0,24,0); run_case(9,7,54,1,24,0);
 run_case(5,7,54,1,24,0); run_case(1,1,1024,1,24,0);
 run_case(33,1,54,0,24,0); run_case(1,31,54,0,24,0);
 run_case(2,2,54,0,32,0); run_case(2,2,54,0,24,1);
 run_case(70000,1,54,0,24,0);
 // Abort a sector in flight; restart must clear byte FIFO and row validity.
 checking=0; sw=17; sh=9; negative=0; bpp=24; compression=0;
 stride=(sw*3+3)&~3; filebytes=offset+stride*sh;
 @(posedge clk); #1; load=1;
 @(posedge clk); #1; load=0;
 wait(dut.state==4 && dut.bmp_len_cnt>200); @(posedge clk); #1; abort=1;
 repeat(4) @(posedge clk); #1; abort=0;
 run_case(17,9,54,1,24,0);
 $display("PASS BMP reader/header/padding/fragmentation/abort %d cases",tests); $finish;
end
initial begin #100000000; $fatal(1,"reader watchdog"); end
endmodule
