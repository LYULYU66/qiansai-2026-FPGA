// Test-only integer reference: direct three-point geometry, independent of
// the RTL's 30-cycle line-cache implementation and bit-sliced arithmetic.
function integer ease_reference;
 input integer p;
 integer t,segment,remainder;
 begin
  p=p%4096;t=p>=2048?4095-p:p;
  segment=t/512;remainder=t%512;
  case(segment)
   0:ease_reference=remainder/4;
   1:ease_reference=128+remainder*3/4;
   2:ease_reference=512+remainder*3/4;
   default:ease_reference=896+remainder/4;
  endcase
 end
endfunction
function [23:0] star_reference;
 input [23:0] bg;
 input integer xx,yy,phase;
 integer u,lane,bx,by,seed,k,best,near,px,py,delta_y,best_dist;
 integer xp,yp,bp,cx,dy,dx,amp,klass,hi,lo,radius,core,halo,light,r,g,b;
 begin
  if(phase>=20480)phase=0;phase=phase%16384;
  u=xx*16-3*ease_reference(phase/4);if(u<0)u=u+20480;lane=u/2048;
  case(lane)
   0:begin bx=43;by=95;seed=16;end
   1:begin bx=53;by=172;seed=107;end
   2:begin bx=40;by=78;seed=50;end
   3:begin bx=47;by=206;seed=185;end
   4:begin bx=56;by=134;seed=224;end
   5:begin bx=39;by=66;seed=141;end
   6:begin bx=50;by=188;seed=84;end
   7:begin bx=44;by=120;seed=12;end
   8:begin bx=54;by=164;seed=172;end
   default:begin bx=48;by=88;seed=61;end
  endcase
  best_dist=100000;near=0;
  for(k=0;k<3;k=k+1)begin
   yp=(phase/2+(seed^147)*16+k*1365)%4096;
   py=(by+k*112-16)*4+ease_reference(yp)/8;
   delta_y=yy*4-py;if(delta_y<0)delta_y=-delta_y;
   if(delta_y<best_dist)begin best_dist=delta_y;near=k;end
  end
  klass=lane%3==0&&near==0?2:(lane%3!=0&&near==1?1:0);
  xp=(phase+seed*16+near*1024)%4096;
  px=near==0?bx:(near==1?120-bx:bx+25);
  cx=(px-16)*4+ease_reference(xp)/8;
  dx=(u%2048)/4-cx;if(dx<0)dx=-dx;
  dy=best_dist>255?255:best_dist;
  dx=dx/(1<<klass);dy=dy/(1<<klass);
  bp=((klass==2?(phase%1024)*4:(phase%2048)*2)+seed*16+near*1365)%4096;
  amp=klass==2?40+ease_reference(bp)/8:(klass==1?18+ease_reference(bp)/16:6+ease_reference(bp)/32);
  hi=dx>dy?dx:dy;lo=dx>dy?dy:dx;radius=hi+lo/2;
  core=amp-radius*16;if(core<0)core=0;
  halo=amp-radius*6;if(halo<0)halo=0;
  light=dx<64&&dy<64&&radius<32?core+halo/8:0;if(light>255)light=255;
  r=bg[23:16]+light-light/16;g=bg[15:8]+light;
  b=bg[7:0]+(radius<=2?light-light/4:light/16);
  if(r>255)r=255;if(g>255)g=255;if(b>255)b=255;
  star_reference={r[7:0],g[7:0],b[7:0]};
 end
endfunction
