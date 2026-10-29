`timescale 1ns/1ps
module tb_sonic_topography;
reg clk=0;always #20 clk=~clk;
reg rst=1,en=1,hs=0,vs=0,de=0;
reg [23:0] rgb=0;reg [111:0] bands=0;reg [3:0] vol=8;
wire [23:0] out;wire oh,ov,od;
video_sonic_topography dut(clk,rst,en,hs,vs,de,rgb,bands,vol,out,oh,ov,od);
wire [767:0] cache;
genvar rr,cc;
generate for(rr=0;rr<8;rr=rr+1)begin:rv
 for(cc=0;cc<16;cc=cc+1)begin:cv
  assign cache[(rr*16+cc)*6+:6]=dut.g_row[rr].tiles[{dut.display_bank,4'(cc)}];
 end
end endgenerate
integer levels[0:15],heights[0:127],rings[0:127];
integer errors=0,pixels=0,ticks=0,hits=0,frames=0;
reg [23:0] qrgb[0:2];reg [2:0] qh=0,qv=0,qd=0;
integer qvalid=0;
function integer scale(input integer a,v);
 begin case(v)
 0:scale=0;1:scale=a/8;2:scale=a/4;3:scale=a/4+a/8;
 4:scale=a/2;5:scale=a/2+a/8;6:scale=a/2+a/4;7:scale=a-a/8;default:scale=a;
 endcase end
endfunction
function integer ripple(input integer t);
 begin case((t%32)/4)0:ripple=0;1,3:ripple=2;2:ripple=3;4:ripple=0;5,7:ripple=-2;default:ripple=-3;endcase end
endfunction
function [23:0] expected_pixel(input integer px,py,input [23:0] bg);
 integer r,c,dx,dy,h,sh,face,shade,chosen,fg0,fg1,fg2;
 reg [23:0] color;reg edgehit;
 begin
 chosen=0;color=0;
 if(en&&de&&py>=96&&py<416)begin
  for(r=0;r<8;r=r+1)begin
   dx=px-(50+4*r);c=dx/32;
   if(dx>=0&&dx<512)begin
    h=heights[r*16+c];dy=py-(244+20*r-4*h);sh=(15-(dy%16))/4;
    if(dy>=0&&dy<4*h+16&&((dy<16&&(dx%32)>=sh&&(dx%32)<sh+28)||(dy>=16&&(dx%32)<30)))begin
     chosen=1;face=dy<16?0:((dx%32)<28?1:2);
     shade=h/4-((r+c)%2);if(shade<0)shade=0;
     case(shade)0:color=24'h102e4a;1:color=24'h075b80;2:color=24'h078ead;3:color=24'h00b6c9;
      4:color=24'h14d2d5;5:color=24'h55f2e4;default:color=24'hb8fff0;endcase
     edgehit=(dy<16&&(dy==0||(dx%32)==sh))||rings[r*16+c];
     if(edgehit)color=shade==0?24'h0d6a88:24'ha4ffff;
     else if(face==1)color={1'b0,color[23:17],1'b0,color[15:9],1'b0,color[7:1]};
     else if(face==2)color={2'b0,color[23:18],2'b0,color[15:10],2'b0,color[7:2]};
    end
   end
  end
 end
 if(chosen)begin
  fg0=(bg[23:16]+3*color[23:16]+2)/4;
  fg1=(bg[15:8]+3*color[15:8]+2)/4;fg2=(bg[7:0]+3*color[7:0]+2)/4;
  expected_pixel={8'(fg0),8'(fg1),8'(fg2)};
 end else expected_pixel=bg;
 end
endfunction
task tick(input bit dh,dv,dd,input [23:0] data,input integer px,py);
 reg [23:0] want;
 begin
 @(negedge clk);hs=dh;vs=dv;de=dd;rgb=data;
 want=expected_pixel(px,py,data);
 qrgb[2]=qrgb[1];qrgb[1]=qrgb[0];qrgb[0]=want;
 qh={qh[1:0],dh};qv={qv[1:0],dv};qd={qd[1:0],dd};
 @(posedge clk);#1;ticks=ticks+1;
 if(qvalid>=2)begin
  if({oh,ov,od,out}!=={qh[2],qv[2],qd[2],qrgb[2]})begin
   if(errors<8)$display("Mismatch t%0d input(%0d,%0d) expected%h got%h timing%h/%h",ticks,px,py,qrgb[2],out,{qh[2],qv[2],qd[2]},{oh,ov,od});
   errors=errors+1;
  end
 end else qvalid=qvalid+1;
 if(dd)begin pixels=pixels+1;if(want!=data)hits=hits+1;end
 if(dut.height_write&&de)$fatal(1,"active write");
 end
endtask
task new_frame;
 integer c,r,a,b,t,l,ri,h,rad,phase,ringrad;bit active;reg bank;
 begin
 bank=dut.display_bank;phase=dut.motion_phase/4;
 active=(scale((bands[6:0]>bands[13:7]?bands[6:0]:bands[13:7])>(bands[20:14]>bands[27:21]?bands[20:14]:bands[27:21])?
 (bands[6:0]>bands[13:7]?bands[6:0]:bands[13:7]):(bands[20:14]>bands[27:21]?bands[20:14]:bands[27:21]),vol)>8)&&
 (scale((bands[6:0]>bands[13:7]?bands[6:0]:bands[13:7])>(bands[20:14]>bands[27:21]?bands[20:14]:bands[27:21])?
 (bands[6:0]>bands[13:7]?bands[6:0]:bands[13:7]):(bands[20:14]>bands[27:21]?bands[20:14]:bands[27:21]),vol)>dut.last_low+8);
 ringrad=active?0:(dut.ring_age/2);
 active=vol!=0&&(active||(dut.ring_active&&dut.ring_age<31));
 tick(0,1,0,24'h010203,0,0);
 for(c=0;c<16;c=c+1)begin
  a=levels[c];b=bands[c*7+:7];if(b>96)b=96;b=scale(b,vol);
  levels[c]=b>=a?a+(b-a+1)/2:a-(a-b+7)/8;
 end
 for(t=0;t<144;t=t+1)begin
  tick(0,0,0,t,0,0);
  if(t<143&&dut.display_bank!=bank)$fatal(1,"partial bank publication");
 end
 if(dut.state!=0||dut.display_bank==bank)$fatal(1,"update failed");
 for(r=0;r<8;r=r+1)for(c=0;c<16;c=c+1)begin
  l=c==0?0:c-1;ri=c==15?15:c+1;
  a=(levels[l]+2*levels[c]+levels[ri])/4;b=a/2;
  case(r)0,7:b=b/4;1,6:b=b/2;2,5:b=b/2+b/4;endcase
  rad=(c>=7?c-7:7-c)+2*(r>=3?r-3:3-r);
  rings[r*16+c]=active&&rad==ringrad;
  h=b+(a>=16?ripple(phase+c+r*4):0)+(rings[r*16+c]&&a!=0?2:0);
  if(h<0)h=0;if(h>24)h=24;if(vol==0)h=0;
  heights[r*16+c]=h;
  if(cache[(r*16+c)*6+:6]!=={1'(rings[r*16+c]),5'(h)})$fatal(1,"tile mismatch r%0d c%0d got%0d expected%0d",r,c,cache[(r*16+c)*6+:6],{1'(rings[r*16+c]),5'(h)});
 end
 frames=frames+1;
 end
endtask
integer i,j,k,fd;reg [23:0] back;reg saved;
initial begin
 for(i=0;i<16;i=i+1)levels[i]=0;
 for(i=0;i<128;i=i+1)begin heights[i]=0;rings[i]=0;end
 repeat(4)@(posedge clk);@(negedge clk);rst=0;
 for(k=0;k<6;k=k+1)begin
  vol=k==3?0:k==4?1:k==5?4:8;
  for(i=0;i<16;i=i+1)bands[i*7+:7]=(k==0?32:(i%5==0?96:40+i*3));
  repeat(6)tick(0,0,0,24'h172238,0,0);
  new_frame;
  if(k==2)begin fd=$fopen("sonic_topography_20261009/terrain.ppm","wb");$fwrite(fd,"P6\n640 480\n255\n");end
  for(j=0;j<480;j=j+1)begin
   for(i=0;i<640;i=i+1)begin
    back={8'(12+j/18),8'(18+j/16),8'(33+j/12)};
    tick(0,0,1,back,i,j);
    if(k==2)begin back=expected_pixel(i,j,back);$fwrite(fd,"%c%c%c",back[23:16],back[15:8],back[7:0]);end
   end
   repeat(8)tick(1,0,0,24'h123456,0,j);
  end
  if(k==2)$fclose(fd);
 end
 // Aborted update must keep the previously visible complete bank.
 saved=dut.display_bank;tick(0,1,0,0,0,0);repeat(20)tick(0,0,0,0,0,0);
 tick(0,0,1,0,0,0);tick(0,0,0,0,0,0);
 if(dut.display_bank!=saved||dut.state!=0)$fatal(1,"short blank did not abort atomically");
 // Page bypass, including random DE/VS/HS patterns, remains bit exact.
 en=0;
 for(i=0;i<2000;i=i+1)tick(i%2,i%11==0,i%3!=0,$random,0,0);
 if(dut.height_valid||dut.level_valid||dut.state)$fatal(1,"page disable did not clear validity");
 en=1;for(i=0;i<16;i=i+1)levels[i]=0;
 vol=8;repeat(6)tick(0,0,0,0,0,0);new_frame;
 repeat(4)tick(0,0,0,0,0,0);
 if(errors!=0)$fatal(1,"%0d errors",errors);
 if(hits<10000)$fatal(1,"terrain never visible");
 $display("PASS sonic: %0d frames, %0d pixels, %0d pipeline ticks, %0d changed pixels; independent tile/pixel oracle, gain0/1/4/8, atomic abort and page reentry",frames,pixels,ticks,hits);
 $finish;
end
initial begin #150000000;$fatal(1,"timeout");end
endmodule
