// Independent integer equations. Cache only reference lane geometry per row,
// not RTL state: avoids evaluating all60 particles again for every RGB pixel.
integer ref_last_y=-1,ref_last_phase=-1;
integer ref_cx[0:9],ref_dy[0:9],ref_amp[0:9],ref_class[0:9];
function integer ease_reference;
 input integer p;integer t,seg,r;
 begin
  p=p%4096;t=p>=2048?4095-p:p;seg=t/512;r=t%512;
  case(seg)
   0:ease_reference=r/4;1:ease_reference=128+r*3/4;
   2:ease_reference=512+r*3/4;default:ease_reference=896+r/4;
  endcase
 end
endfunction
function [23:0] star_reference;
 input [23:0] bg;input integer xx,yy,phase;
 integer fast,lane,bx,by,seed,k,near,best,dy,py,offs,klass,xp,bp,px;
 integer u,dx,hi,lo,radius,core,halo,light,r,g,b;
 begin
  if(phase>=20480)phase=0;
  fast=(phase%4096)*4;
  if(ref_last_y!=yy||ref_last_phase!=phase)begin
   ref_last_y=yy;ref_last_phase=phase;
   for(lane=0;lane<10;lane=lane+1)begin
    case(lane)
     0:begin bx=43;by=55;seed=16;end
     1:begin bx=53;by=92;seed=107;end
     2:begin bx=40;by=38;seed=50;end
     3:begin bx=47;by=76;seed=185;end
     4:begin bx=56;by=64;seed=224;end
     5:begin bx=39;by=26;seed=141;end
     6:begin bx=50;by=88;seed=84;end
     7:begin bx=44;by=50;seed=12;end
     8:begin bx=54;by=104;seed=172;end
     default:begin bx=48;by=68;seed=61;end
    endcase
    best=100000;near=0;
    for(k=0;k<6;k=k+1)begin
     case(k)0:offs=0;1:offs=683;2:offs=1365;3:offs=2048;4:offs=2731;default:offs=3413;endcase
     py=(by+k*64-16)*4+ease_reference(fast/2+(seed^147)*16+offs)/8;
     dy=yy*4-py;if(dy<0)dy=-dy;
     if(dy<best)begin best=dy;near=k;end
    end
    klass=lane%3==0&&(near==0||near==3)?2:(lane%3!=0&&(near==1||near==4)?1:0);
    xp=(fast+seed*16+near*512)%4096;
    px=near==0||near==3?bx:(near==1||near==4?120-bx:bx+25);
    ref_cx[lane]=(px-16)*4+ease_reference(xp)/8;
    case(near)0:offs=0;1:offs=683;2:offs=1365;3:offs=2048;4:offs=2731;default:offs=3413;endcase
    bp=(klass==2?(fast%1024)*4:(fast%2048)*2)+seed*16+offs;
    ref_amp[lane]=klass==2?80+ease_reference(bp)/8:(klass==1?32+ease_reference(bp)/16:12+ease_reference(bp)/32);
    ref_dy[lane]=best>255?255:best;ref_class[lane]=klass;
   end
  end
  u=xx*16-3*ease_reference(phase%4096);if(u<0)u=u+20480;lane=u/2048;
  dx=(u%2048)/4-ref_cx[lane];if(dx<0)dx=-dx;
  dx=dx/(1<<ref_class[lane]);dy=ref_dy[lane]/(1<<ref_class[lane]);
  hi=dx>dy?dx:dy;lo=dx>dy?dy:dx;radius=hi+lo/2;
  core=ref_amp[lane]-radius*16;if(core<0)core=0;
  halo=ref_amp[lane]-radius*6;if(halo<0)halo=0;
  light=dx<64&&dy<64&&radius<32?core+halo/8:0;if(light>255)light=255;
  r=bg[23:16]+light-light/16;g=bg[15:8]+light;
  b=bg[7:0]+(radius<=2?light-light/4:light/16);
  if(r>255)r=255;if(g>255)g=255;if(b>255)b=255;
  star_reference={r[7:0],g[7:0],b[7:0]};
 end
endfunction
