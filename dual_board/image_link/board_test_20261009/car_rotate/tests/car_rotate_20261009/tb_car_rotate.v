`timescale 1ns/1ps
module tb_car_rotate;
reg clk=0;always #20 clk=~clk;
reg rst=1,en=0,vs=0,de=0;reg [23:0] bg=0;
wire [23:0] rgb;wire ovs,ode;
video_car_intro dut(.I_clk(clk),.I_rst(rst),.I_enable(en),.I_vs(vs),.I_de(de),.I_rgb(bg),.O_rgb(rgb),.O_vs(ovs),.O_de(ode));
`include "sprite_reference.vh"
integer n,k,x,y,count_x,full,selected_frame,selected_pulse=85;
integer checks=0,mapping_checks=0,painted=0,cycles=0;
reg [23:0] expected;

// Independent projection: floating point cosine defines the intended 32 angles.
// Quantize once to Q8, cap edge-on width at 1/16. Do not copy the RTL gain LUT.
function integer projected_x;
 input integer xx,frame;
 real c;
 integer gain,product,sx,step;
 begin
  step=(frame%64)/2;
  c=$cos(6.283185307179586*step/32.0);if(c<0.0)c=-c;
  gain=c<0.0625?4096:$rtoi(256.0/c+0.5);
  product=(xx-320)*gain;
  sx=128+(product<0?(product-255)/256:product/256);
  projected_x=sx;
 end
endfunction

function [23:0] reference_pixel;
 input [23:0] background;
 input integer xx,yy,frame,pulse,enabled;
 integer r,g,b,dx,dy,rad,glow,breath,sx,sy,idx,shine,sep,step;
 reg [23:0] color;
 begin
  r=background[23:16];g=background[15:8];b=background[7:0];
  if(enabled)begin
   dx=xx>=320?xx-320:320-xx;dy=(yy>=457?yy-457:457-yy)*16;
   rad=dx>dy?dx+dy/2:dy+dx/2;
   breath=pulse>=64?127-pulse:pulse;
   glow=rad+6>=128?92:(rad+16>=128?48:12+breath/4);
   if(xx>=176&&xx<464&&yy>=443&&yy<473&&rad<=128)begin
    r=r+glow/8;if(r>255)r=255;g=g+glow/2;if(g>255)g=255;b=b+glow;if(b>255)b=255;
   end
   sx=frame<64?projected_x(xx,frame):xx-192;sy=yy-368;
   if(xx>=192&&xx<448&&sy>=0&&sy<96&&sx>=0&&sx<=255)begin
    step=frame/2;if(frame<64&&step>=8&&step<24)sx=255-sx;
    idx=ref_pixels[sy*256+sx];
    if(idx!=0)begin
     color=ref_color(idx);r=color[23:16];g=color[15:8];b=color[7:0];
     sep=xx-(192+(frame%64)*4);if(sep<0)sep=-sep;
     shine=frame<64&&sep<8?(sep<2?72:(sep<4?40:16)):0;
     r=r+shine/2;if(r>255)r=255;g=g+shine;if(g>255)g=255;b=b+shine;if(b>255)b=255;
    end
   end
  end
  reference_pixel={r[7:0],g[7:0],b[7:0]};
 end
endfunction

task frame_pulse;
 begin
  @(negedge clk);vs=1;de=0;bg=24'h8157bd;
  @(posedge clk);#2;if(ovs!==1||ode!==0||rgb!==bg)$fatal(1,"VS/bypass latency changed");
  repeat(2)@(negedge clk);vs=0;repeat(3)@(negedge clk);
 end
endtask

task render;
 input integer frame_value,enabled,full_frame;
 integer sx,expected_hit,step;
 begin
  selected_frame=frame_value;en=enabled;
  force dut.age=8'd191;force dut.idle_phase=selected_pulse;
  force dut.rotate_seen=1'b1;force dut.rotate_timer=selected_frame;
  frame_pulse;
  for(y=0;y<480;y=y+1)begin
   // All x across 16 car rows for each angle; also sample background line starts.
   count_x=full_frame||((y>=368&&y<464)&&((y-368)%6==0))?640:1;
   for(x=0;x<count_x;x=x+1)begin
    @(negedge clk);de=1;bg={x[7:0],y[7:0],8'h40};#1;
    expected=reference_pixel(bg,x,y,frame_value,selected_pulse,enabled);
    if(y>=368&&y<464&&x>=192&&x<448&&enabled)begin
     sx=frame_value<64?projected_x(x,frame_value):x-192;
     expected_hit=sx>=0&&sx<=255;
     if(dut.sprite_hit!==expected_hit[0])$fatal(1,"source crop angle=%0d xy=%0d/%0d",frame_value,x,y);
     step=frame_value/2;if(frame_value<64&&step>=8&&step<24)sx=255-sx;
     if(expected_hit&&dut.addressed_x!==sx[7:0])$fatal(1,"signed source/mirror angle=%0d x=%0d got=%0d expected=%0d",frame_value,x,dut.addressed_x,sx);
     mapping_checks=mapping_checks+1;
    end
    @(posedge clk);#2;
    if(ode!==1||ovs!==0||rgb!==expected)$fatal(1,"rotation RGB/DE/VS frame=%0d xy=%0d/%0d got=%h expected=%h",frame_value,x,y,rgb,expected);
    if(y<368&&rgb!==bg)$fatal(1,"rotation covers instrument dials");
    checks=checks+1;if(rgb!=bg)painted=painted+1;
   end
   @(negedge clk);de=0;bg=24'hfae2ff;
   @(posedge clk);#2;if(ode!==0||rgb!==bg)$fatal(1,"blanking overlay leaked");
  end
  release dut.age;release dut.idle_phase;release dut.rotate_seen;release dut.rotate_timer;
 end
endtask

initial begin
 repeat(5)@(negedge clk);rst=0;repeat(5)@(negedge clk);en=1;
 for(n=1;n<=144;n=n+1)begin
  frame_pulse;
  if(dut.age!==n||dut.rotate_seen!==0||dut.rotate_timer!==0)$fatal(1,"rotation started during original introduction n=%0d",n);
 end
 for(n=1;n<=297;n=n+1)begin
  frame_pulse;
  if(dut.rotate_seen!==0||dut.rotate_timer!==n||dut.rotating!==0)$fatal(1,"first wait n=%0d",n);
 end
 frame_pulse;
 if(dut.rotate_timer!==0||dut.rotating!==1)$fatal(1,"first rotation must begin after298 frames");
 for(k=0;k<3;k=k+1)begin
  for(n=1;n<=298;n=n+1)begin
   frame_pulse;cycles=cycles+1;
   if(dut.rotate_timer!==(n%298)||dut.rotating!==((n%298)<64))$fatal(1,"period/activity cycle=%0d frame=%0d",k,n);
  end
 end
 repeat(400)@(negedge clk);
 if(dut.rotate_timer!==0)$fatal(1,"turn timer advanced without VS");
 $display("PASS car rotation lifecycle:144-frame original introduction,298-frame first wait and three298-frame periods,64 active frames,VS-only advance");
 for(n=0;n<32;n=n+1)render(n*2,1,0);
 render(0,1,1);render(16,1,1);render(62,1,1);render(64,1,1);render(22,0,1);
 if(checks<1800000||mapping_checks<150000||painted<35000)$fatal(1,"insufficient rotation coverage %0d/%0d/%0d",checks,mapping_checks,painted);
 $display("PASS car rotation pixels:%0d RGB/DE/VS checks,%0d independent cosine signed-address/crop/mirror checks,all32 angles,edge-on,hold/off-page,no dial coverage",checks,mapping_checks);
 en=0;repeat(5)@(negedge clk);
 if(dut.rotate_timer!==0||dut.rotate_seen!==0||dut.age!==0)$fatal(1,"page exit not clean");
 en=1;frame_pulse;if(dut.age!==1||dut.rotating!==0)$fatal(1,"re-entry did not replay introduction");
 rst=1;#2;if(ode!==0||ovs!==0||dut.rotate_seen!==0||dut.rotate_timer!==0)$fatal(1,"asynchronous reset failed");
 $display("PASS car rotation reset:page exit and re-entry restart,asynchronous reset,unchanged one-clock output alignment");
 $finish;
end
initial begin #250000000;$fatal(1,"car rotation test timeout");end
endmodule
