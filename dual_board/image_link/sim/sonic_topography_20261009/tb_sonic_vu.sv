`timescale 1ns/1ps
module tb_sonic_vu;
reg clk=0,rst=1,en=1,vs=0,de=0;reg [23:0] bg=0;
reg [6:0] l=96,r=48;reg [111:0] bands={16{7'd96}},wave={16{7'd32}};reg [3:0] volume=8;
wire [23:0] oldrgb,newrgb;
audio_visualizer_overlay baseline(clk,rst,en,vs,de,bg,l,r,bands,wave,volume,1'b0,1'b0,1'b0,oldrgb);
audio_visualizer_overlay #(.VU_ONLY(1)) candidate(clk,rst,en,vs,de,bg,l,r,bands,wave,volume,1'b0,1'b0,1'b0,newrgb);
always #20 clk=~clk;
integer checks=0,vuchanges=0,frame,x,y,px,py;
task tick;
 bit vu;
 begin @(posedge clk);#1;
  px=candidate.pixel_x;py=candidate.pixel_y;
  vu=py>=299&&py<388&&((px>=36&&px<50)||(px>=590&&px<604));
  if(vu&&newrgb!==oldrgb)$fatal(1,"VU changed x%0d y%0d",px,py);
  if(!vu&&newrgb!==bg)$fatal(1,"old spectrum/wave survived x%0d y%0d",px,py);
  if(newrgb!=bg)vuchanges=vuchanges+1;checks=checks+1;@(negedge clk);
 end
endtask
initial begin
 repeat(5)tick;rst=0;
 for(frame=0;frame<3;frame=frame+1)begin
  volume=frame==0?0:frame==1?4:8;vs=0;repeat(6)tick;vs=1;repeat(300)tick;vs=0;
  for(y=0;y<480;y=y+1)begin
   de=1;for(x=0;x<640;x=x+1)begin bg={8'(x),8'(y),8'(frame)};tick;end
   de=0;repeat(8)tick;
  end
 end
 en=0;de=1;repeat(100)tick;
 if(vuchanges<5000)$fatal(1,"VU never rendered");
 $display("PASS sonic VU: %0d pixel cycles, original left/right meters and labels preserved, bars/wave absent, volume0/4/8 and disable",checks);
 $finish;
end
endmodule
