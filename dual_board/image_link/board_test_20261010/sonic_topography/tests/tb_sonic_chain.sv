`timescale 1ns/1ps
// Natural VGA raster through real image adjustment, terrain, synchronous home
// palette, VU-only overlay and AXIS. Six registered stages from raw to AXIS.
module tb_sonic_chain;
reg clk=0;always #20 clk=~clk;
reg rst=1,hs=0,vs=0,de=0,terrain_on=0,home_on=1;
reg [23:0] rgb=0;reg [7:0] index=0;
reg [23:0] transition_rgb;reg th,tv,td;
reg [7:0] index_transition,d0,d1,index_sonic;
always @(posedge clk)begin
 transition_rgb<=rgb;th<=hs;tv<=vs;td<=de;
 index_transition<=index;d0<=index_transition;d1<=d0;index_sonic<=d1;
end
wire ah,av,ad,sh,sv,sd;wire [23:0] adjusted,stage,home,vumix,axis_rgb;
wire user,valid,last;
video_image_adjust adjust(.I_clk(clk),.I_rst(rst),.I_hs(th),.I_vs(tv),.I_de(td),.I_rgb(transition_rgb),
 .I_brightness_level(2'd3),.I_contrast_level(2'd0),.O_hs(ah),.O_vs(av),.O_de(ad),.O_rgb(adjusted));
video_sonic_topography sonic(clk,rst,terrain_on,ah,av,ad,adjusted,{16{7'd80}},4'd8,stage,sh,sv,sd);
video_remote_home_overlay atlas(clk,rst,home_on,sd,index_sonic,stage,home);
audio_visualizer_overlay #(.VU_ONLY(1)) vu(.I_clk(clk),.I_rst(rst),.I_enable(terrain_on),.I_vs(sv),.I_de(sd),.I_rgb(home),
 .I_vu_left_level(7'd96),.I_vu_right_level(7'd48),.I_spectrum_levels({16{7'd96}}),.I_wave_samples({16{7'd32}}),
 .I_volume_level(4'd8),.I_hazard_front(1'b0),.I_hazard_left(1'b0),.I_hazard_right(1'b0),.O_rgb(vumix));
video_rgb_to_axis_640x480 axis(clk,rst,sv,sd,vumix,user,valid,last,axis_rgb);
reg [23:0] qcolor[0:5];reg [5:0] qde=0,qvs=0,qhs=0;
integer ox=0,oy=0,framepixels=0,sofs=0,lineends=0,comparisons=0,cycle=0,vu_checks=0;
integer frame,x,y,k,active_frames=0;
function [23:0] pal(input [7:0] a);
 begin case(a)1:pal=24'hdce9f0;2:pal=24'hf2f7fa;3:pal=24'h07131c;default:pal=0;endcase end
endfunction
function bit vu_region(input integer px,py);
 begin vu_region=((px>=36&&px<50)||(px>=590&&px<604))&&py>=316&&py<388 ||
   ((px>=39&&px<49)||(px>=592&&px<600))&&py>=299&&py<313;end
endfunction
task tick(input bit h,v,d,input [23:0] data,input [7:0] tag);
 reg [23:0] expected;integer i;
 begin
 @(negedge clk);hs=h;vs=v;de=d;rgb=data;index=tag;
 expected=d?(home_on&&tag!=0?pal(tag):(data&24'hfcfcfc)):0;
 for(i=5;i>0;i=i-1)qcolor[i]=qcolor[i-1];qcolor[0]=expected;
 qde={qde[4:0],d};qvs={qvs[4:0],v};qhs={qhs[4:0],h};
 @(posedge clk);#1;cycle=cycle+1;
 if(cycle>8)begin
  if(valid!==qde[5]||{sh,sv,sd}!=={qhs[4],qvs[4],qde[4]})$fatal(1,"timing pipeline mismatch cycle%0d",cycle);
  if(valid)begin
   if(user!==(ox==0&&oy==0))$fatal(1,"SOF x%0d y%0d",ox,oy);
   if(last!==(ox==639))$fatal(1,"TLAST x%0d y%0d",ox,oy);
   if(!terrain_on&&axis_rgb!==qcolor[5])$fatal(1,"home palette/background misaligned x%0d y%0d expected%h actual%h",ox,oy,qcolor[5],axis_rgb);
   if(terrain_on&&!vu_region(ox,oy)&&vu.spectrum_fill)$fatal(1,"old bars visible");
   sofs=sofs+user;lineends=lineends+last;framepixels=framepixels+1;comparisons=comparisons+1;
   if(terrain_on&&vu_region(ox,oy))vu_checks=vu_checks+1;
   if(ox==639)begin ox=0;oy=oy+1;end else ox=ox+1;
  end else if(user||last)$fatal(1,"sideband asserted during blanking");
 end
 end
endtask
initial begin
 repeat(8)@(posedge clk);@(negedge clk);rst=0;
 for(frame=0;frame<3;frame=frame+1)begin
  terrain_on=frame==1;home_on=!terrain_on;cycle=0;
  tick(0,1,0,0,0);repeat(400)tick(0,0,0,0,0);
  for(y=0;y<480;y=y+1)begin
   for(x=0;x<640;x=x+1)tick(0,0,1,{8'(frame*50+x),8'(y),8'(x^y)},x%9==0?8'(1+(x/9)%3):0);
   repeat(160)tick(1,0,0,0,0);
  end
  repeat(8)tick(0,0,0,0,0);
  if(framepixels!=307200||sofs!=1||lineends!=480||oy!=480||ox!=0)$fatal(1,"VGA frame loss pixels%0d SOF%0d last%0d",framepixels,sofs,lineends);
  active_frames=active_frames+1;framepixels=0;sofs=0;lineends=0;ox=0;oy=0;
 end
 if(vu_checks<1800)$fatal(1,"VU not checked");
 $display("PASS sonic chain: %0d natural VGA frames, %0d AXIS pixels; first/last pixels, synchronous atlas indices, enable/disable page return and VU region",active_frames,comparisons);
 $finish;
end
initial begin #100000000;$fatal(1,"chain timeout");end
endmodule
