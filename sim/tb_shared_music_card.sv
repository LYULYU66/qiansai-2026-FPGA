`timescale 1ns/1ps
// Compare page 1 with an immutable pre-change RTL snapshot at every pixel.
// Alternate modes and blank lengths, verify page-2 card-only confinement.
module tb_shared_music_card;
reg clk=0,rst=1,vs=0,de=0,en=1,music=0;
reg [23:0] rgb=0;
wire [23:0] actual,original;
integer frame,x,y,pixels=0,changes=0;
always #20 clk=~clk;
video_home_overlay dut(.I_clk(clk),.I_rst(rst),.I_enable(en),.I_music_page(music),
 .I_vs(vs),.I_de(de),.I_rgb(rgb),.O_rgb(actual));
video_home_overlay_before_music ref_home(.I_clk(clk),.I_rst(rst),.I_enable(en),
 .I_vs(vs),.I_de(de),.I_rgb(rgb),.O_rgb(original));
task tick;begin @(posedge clk);#1;end endtask
initial begin
 repeat(4)tick;@(negedge clk);rst=0;
 for(frame=0;frame<6;frame=frame+1)begin
  music=frame%2;en=(frame<4);
  @(negedge clk);vs=1;de=0;tick;
  @(negedge clk);vs=0;repeat(80)tick;
  for(y=0;y<480;y=y+1)begin
   for(x=0;x<640;x=x+1)begin
    @(negedge clk);de=1;rgb={8'(x+frame*7),8'(y+frame*11),8'(x^y^frame)};tick;
    if(!music && actual!==original)
     $fatal(1,"homepage changed frame=%0d x=%0d y=%0d new=%h old=%h",frame,x,y,actual,original);
    if(music && (x<144 || x>=496 || y<128 || y>=212) && actual!==rgb)
     $fatal(1,"page-2 dashboard leaked outside music card x=%0d y=%0d",x,y);
    if(!en && actual!==rgb)$fatal(1,"disabled overlay changed pixel");
    if(music && en && actual!==rgb)changes=changes+1;
    pixels=pixels+1;
   end
   @(negedge clk);de=0;repeat(frame%3+1)tick;
   if(actual!==rgb || original!==rgb)$fatal(1,"blanking changed");
  end
 end
 if(changes<50000)$fatal(1,"missing music card");
 $display("PASS shared music card: %0d pixels, homepage exact against pre-change RTL, page-2 confinement, alternating modes, enable bypass, 1/2/3-cycle blanking",pixels);
 $finish;
end
initial begin #90000000;$fatal(1,"shared music card timeout");end
endmodule
