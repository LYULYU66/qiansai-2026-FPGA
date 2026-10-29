// Independent integer pixel equations; deliberately use integer multiply/divide
// instead of the RTL shift/add datapath. ROM indices come from offline packing.
function [23:0] car_reference;
 input [23:0] bg;input integer xx,yy,frame_age,pulse,en;
 integer alpha,lift,sy,sx,idx,r,g,b,rr,gg,bb,dx,dy,hi,lo,rad,reach,breath,glow,sweep,separation,shine;
 reg [23:0] color;
 begin
  r=bg[23:16];g=bg[15:8];b=bg[7:0];
  if(en&&yy>=368)begin
   alpha=frame_age<16?0:(frame_age>=144?16:(frame_age-16)/8);
   lift=alpha>=12?0:12-alpha;
   dx=xx>=320?xx-320:320-xx;dy=(yy>=457?yy-457:457-yy)*16;
   hi=dx>dy?dx:dy;lo=dx>dy?dy:dx;rad=hi+lo/2;
   reach=frame_age<16?(frame_age+1)*8:128;
   breath=pulse>=64?127-pulse:pulse;
   glow=rad+6>=reach?92:(rad+16>=reach?48:12+breath/4);
   if(xx>=176&&xx<464&&yy>=443&&yy<473&&rad<=reach)begin
    r=r+glow/8;if(r>255)r=255;g=g+glow/2;if(g>255)g=255;b=b+glow;if(b>255)b=255;
   end
   sy=yy-(368+lift);sx=xx-192;
   if(alpha>0&&sx>=0&&sx<256&&sy>=0&&sy<96)begin
    idx=ref_pixels[sy*256+sx];
    if(idx!=0)begin
     color=ref_color(idx);rr=color[23:16];gg=color[15:8];bb=color[7:0];
     sweep=192+(frame_age%64)*4;separation=xx>sweep?xx-sweep:sweep-xx;
     shine=frame_age>=64&&frame_age<128&&separation<8?(separation<2?72:(separation<4?40:16)):0;
     rr=rr+shine/2;if(rr>255)rr=255;gg=gg+shine;if(gg>255)gg=255;bb=bb+shine;if(bb>255)bb=255;
     r=(r*(16-alpha)+rr*alpha+8)/16;g=(g*(16-alpha)+gg*alpha+8)/16;b=(b*(16-alpha)+bb*alpha+8)/16;
    end
   end
  end
  car_reference={r[7:0],g[7:0],b[7:0]};
 end
endfunction
