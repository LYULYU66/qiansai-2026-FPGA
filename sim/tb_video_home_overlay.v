`timescale 1ns/1ps
module tb_video_home_overlay;
reg clk=0;
always #5 clk=~clk;
reg rst=1, en=0, vs=0, de=0;
reg [23:0] rgb=24'h406080;
wire [23:0] out_rgb;
integer x,y,counts[0:3],i;
integer failed=0;
integer ppm;
video_home_overlay dut(
 .I_clk(clk),.I_rst(rst),.I_enable(en),.I_vs(vs),.I_de(de),.I_music_page(1'b0),
 .I_rgb(rgb),.O_rgb(out_rgb)
);
initial begin
 for(i=0;i<4;i=i+1) counts[i]=0;
 ppm=$fopen("sim/home_overlay_preview.ppm","wb");
 $fwrite(ppm,"P6\n640 480\n255\n");
 repeat(4) @(negedge clk);
 rst=0; en=1; vs=1;
 repeat(2) @(negedge clk);
 vs=0;
 for(y=0;y<480;y=y+1) begin
   for(x=0;x<640;x=x+1) begin
     @(negedge clk); de=1;
     @(posedge clk); #1;
     if(dut.pixel_x !== x || dut.pixel_y !== y) begin
       $display("FAIL coordinate x=%0d y=%0d got=%0d,%0d",x,y,dut.pixel_x,dut.pixel_y);
       failed=failed+1; $finish;
     end
     if(x==320 && y==100 && out_rgb !== rgb) begin
       $display("FAIL picture background"); failed=failed+1;
     end
     if(x==100 && y==350 && out_rgb === rgb) begin
       $display("FAIL destination card"); failed=failed+1;
     end
     if(x==300 && y==350 && out_rgb === rgb) begin
       $display("FAIL music card"); failed=failed+1;
     end
     if(x==500 && y==350 && out_rgb === rgb) begin
       $display("FAIL application card"); failed=failed+1;
     end
     if(x==320 && y==450 && out_rgb === rgb) begin
       $display("FAIL bottom navigation"); failed=failed+1;
     end
     if(dut.glyph_on) begin
       if(y>=54 && y<70) counts[2]=counts[2]+1;
       else if(y>=82 && y<98) counts[3]=counts[3]+1;
       else if(x<210) counts[0]=counts[0]+1;
       else if(x<418) counts[1]=counts[1]+1;
     end
     $fwrite(ppm,"%c%c%c",out_rgb[23:16],out_rgb[15:8],out_rgb[7:0]);
   end
   @(negedge clk); de=0;
   repeat(4) @(negedge clk);
 end
 en=0;
 $fclose(ppm);
 @(negedge clk); de=1;
 @(posedge clk); #1;
 if(out_rgb !== rgb) begin $display("FAIL disabled passthrough"); failed=failed+1; end
 for(i=0;i<4;i=i+1) begin
   if(counts[i]<50) begin $display("FAIL missing text region %0d count=%0d",i,counts[i]); failed=failed+1; end
 end
 if(failed==0) $display("PASS HOME OVERLAY cards/nav/clock/pass-through counts=%0d,%0d,%0d,%0d",counts[0],counts[1],counts[2],counts[3]);
 else $display("FAIL HOME OVERLAY errors=%0d",failed);
 $finish;
end
endmodule
