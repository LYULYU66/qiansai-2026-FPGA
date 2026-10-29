`timescale 1ns/1ps
module tb_home_light_apps;
reg clk=0, rst=1, en=1, vs=0, de=0;
reg [23:0] rgb=24'h406080;
wire [23:0] actual, before_rgb, final_rgb;
integer x,y,errors=0,ppm,f,n,b0,b1,b2,idx,card;
integer app_pixels[0:3], date_ink=0, weekday_ink=0, nav_ink=0;
reg [23:0] frame[0:307199], old_frame[0:307199], background[0:307199];
always #5 clk=~clk;
video_home_overlay dut(.I_clk(clk),.I_rst(rst),.I_enable(en),.I_vs(vs),
 .I_de(de),.I_rgb(rgb),.O_rgb(actual));
video_home_overlay_before_light ref_ui(.I_clk(clk),.I_rst(rst),.I_enable(en),
 .I_vs(vs),.I_de(de),.I_rgb(rgb),.O_rgb(before_rgb));
// Match the production layer order: status text is above the home dashboard.
video_status_overlay status(.I_clk(clk),.I_rst(rst),.I_enable(en),.I_vs(vs),
 .I_de(de),.I_rgb(actual),.I_brightness_level(2'd3),.I_contrast_level(2'd0),
 .I_volume_level(4'd8),.O_rgb(final_rgb));
task fail;
 input [511:0] reason;
 begin
  if(errors<10) $display("FAIL %0s x=%0d y=%0d",reason,x,y);
  errors=errors+1;
 end
endtask
initial begin
 for(idx=0;idx<4;idx=idx+1) app_pixels[idx]=0;
 // Real TF-card wallpaper, not an independent drawing of the new UI.
 f=$fopen("best_result/CAR01.BMP","rb");
 if(!f) $fatal(1,"home wallpaper unavailable");
 n=$fseek(f,54,0);
 for(y=479;y>=0;y=y-1) for(x=0;x<640;x=x+1) begin
  b0=$fgetc(f);b1=$fgetc(f);b2=$fgetc(f);
  background[y*640+x]={b2[7:0],b1[7:0],b0[7:0]};
 end
 $fclose(f);
 ppm=$fopen("sim/home_nav_app_20260930/preview.ppm","w");
 $fwrite(ppm,"P3\n640 480\n255\n");
 repeat(4) @(negedge clk); rst=0; vs=1;
 repeat(2) @(negedge clk); vs=0;
 for(y=0;y<480;y=y+1) begin
  for(x=0;x<640;x=x+1) begin
   @(negedge clk); de=1; rgb=background[y*640+x];
   @(posedge clk); #1;
   frame[y*640+x]=actual;old_frame[y*640+x]=before_rgb;
   if(dut.pixel_x!==x || dut.pixel_y!==y) fail("raster alignment");
   if(actual!==before_rgb && !((x>=16 && x<624 && y>=322 && y<408) ||
      (x>=504 && x<624 && y>=54 && y<70) ||
      (x>=544 && x<624 && y>=82 && y<98) ||
      (x>=500 && x<532 && y>=74 && y<106) || y>=416))
      fail("unrelated home pixels changed");
   if(x>=584 && x<592 && y>=54 && y<70 && actual!==rgb)
      fail("date weekday gap is not transparent");
   if(y>=416 && y<440 && actual!==rgb) fail("old tall bottom bar remains");
   if(y>=440) begin
    if(dut.nav_icon) begin
     nav_ink=nav_ink+1;
     if(actual!==dut.nav_rgb)
      fail("bottom icon contrast");
    end else if(actual!==24'hFFFFFF) fail("bottom bar is not solid white");
   end
   if(dut.glyph_on && y>=54 && y<70) begin
    if(x<584) date_ink=date_ink+1;else weekday_ink=weekday_ink+1;
   end
   if(dut.app_pixel) begin
    if(dut.pixel_x>=438 && dut.pixel_x<478) app_pixels[0]=app_pixels[0]+1;
    else if(dut.pixel_x>=484 && dut.pixel_x<524) app_pixels[1]=app_pixels[1]+1;
    else if(dut.pixel_x>=530 && dut.pixel_x<570) app_pixels[2]=app_pixels[2]+1;
    else if(dut.pixel_x>=576 && dut.pixel_x<616) app_pixels[3]=app_pixels[3]+1;
    else fail("app overflow outside layout");
   end
   $fwrite(ppm,"%0d %0d %0d\n",final_rgb[23:16],final_rgb[15:8],final_rgb[7:0]);
  end
  @(negedge clk); de=0; repeat(4) @(negedge clk);
 end
 $fclose(ppm);
 // Crisp font pixels intentionally differ from the former rasterizer.
 // Date origin/gap are checked above; the independent Python checker checks
 // every glyph ROM word and all date/time output pixels.
 // Independent symmetric round-corner check over all three white cards.
 for(card=0;card<3;card=card+1) begin
  idx=(card==0)?16:(card==1)?222:430;
  for(y=0;y<8;y=y+1) for(x=0;x<10;x=x+1) begin
   n=(y==0)?8:(y==1)?5:(y==2)?4:(y==3)?3:(y==4)?2:1;
   if(x<n) begin
    if(frame[(322+y)*640+idx+x]!==background[(322+y)*640+idx+x]) fail("rounded top corner");
    if(frame[(407-y)*640+idx+x]!==background[(407-y)*640+idx+x]) fail("rounded bottom corner");
   end else begin
    if(frame[(322+y)*640+idx+x]!==((y==0 || x==n)?24'hDCE4EB:24'hFFFFFF))
     fail("white card edge or fill");
   end
  end
 end
 for(idx=0;idx<4;idx=idx+1) if(app_pixels[idx]<1300) fail("missing high-detail app");
 if(date_ink<80 || weekday_ink<40 || nav_ink<200) fail("missing text or navigation");
 // Home layer is completely disabled on the other three picture pages.
 en=0; @(negedge clk); de=1;rgb=24'h123456; @(posedge clk);#1;
 if(actual!==rgb) fail("disabled home passthrough");
 if(errors) $fatal(1,"light dashboard errors=%0d",errors);
 $display("PASS LIGHT HOME: 307200 pixels, four 40px apps, rounded white cards, 40px rectangular white navbar, 8px date gap, disabled passthrough");
 $finish;
end
initial begin #10000000; $fatal(1,"light dashboard timeout"); end
endmodule
