// Independent integer reference, shared only by test benches (not synthesis).
function [23:0] star_reference;
 input [23:0] bg;
 input integer xx,yy,phase;
 integer u,lane,bx,by,seed,d0,d1,d2,near,px,dy,dx,pulse,triangle_ref,amp;
 integer hi,lo,radius,core,halo,light,r,g,b;
 begin
  u=xx*16-phase;if(u<0)u=u+20480;
  lane=u/2048;
  case(lane)
   0:begin bx=29;by=95;seed=16;end
   1:begin bx=39;by=172;seed=107;end
   2:begin bx=26;by=78;seed=50;end
   3:begin bx=33;by=206;seed=185;end
   4:begin bx=42;by=134;seed=224;end
   5:begin bx=25;by=66;seed=141;end
   6:begin bx=36;by=188;seed=84;end
   7:begin bx=30;by=120;seed=12;end
   8:begin bx=40;by=164;seed=172;end
   default:begin bx=34;by=88;seed=61;end
  endcase
  d0=yy-by;if(d0<0)d0=-d0;
  d1=yy-by-112;if(d1<0)d1=-d1;
  d2=yy-by-224;if(d2<0)d2=-d2;
  near=(d0<=d1 && d0<=d2) ? 0 : (d1<=d2 ? 1 : 2);
  px=near==0 ? bx : (near==1 ? 120-bx : bx+25);
  dy=4*(near==0 ? d0 : (near==1 ? d1 : d2));
  dx=(u%2048)/4-px*4;if(dx<0)dx=-dx;
  pulse=((phase>>3)%256+seed+near*64)%256;
  triangle_ref=pulse>=128 ? 255-pulse : pulse;
  amp=86+triangle_ref/2+((lane==0 || lane==3 || lane==6) ? 46 : 0);
  hi=dx>dy ? dx : dy;lo=dx>dy ? dy : dx;radius=hi+lo/2;
  core=amp-radius*16;if(core<0)core=0;
  halo=amp-radius*8;if(halo<0)halo=0;
  light=dx<64 && radius<32 ? core+halo/4 : 0;if(light>255)light=255;
  r=bg[23:16]+light;g=bg[15:8]+light-light/8;
  b=bg[7:0]+(radius<=2 ? light/2 : light/8);
  if(r>255)r=255;if(g>255)g=255;if(b>255)b=255;
  star_reference={r[7:0],g[7:0],b[7:0]};
 end
endfunction
