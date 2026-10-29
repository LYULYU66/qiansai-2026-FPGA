`timescale 1ns/1ps
module tb_video_relax_overlay;
parameter LOW_POWER=0;
reg clk=0,rst=1,en=0,vs=0,de=0,audio_active=1;
reg [23:0] rgb=24'h18252A;
reg [6:0] vu_left=0,vu_right=0;
reg [111:0] spectrum=0;
wire [23:0] out_rgb;
integer f,i,x,y,dx,dy,d,amp,core,halo,light,g,b,rr,gg,bb,changed;
integer err=0,checks=0,old_x[0:7],old_y[0:7],old_amp[0:7],old_energy[0:7];
integer px[0:7],py[0:7],pa[0:7],cx,cy,idx,dy2,amp2;
reg [50:0] snapshot[0:7];
reg [23:0] expected;
always #5 clk=~clk;
video_relax_overlay #(.LOW_POWER(LOW_POWER)) dut(.I_clk(clk),.I_rst(rst),.I_enable(en),.I_vs(vs),.I_de(de),
 .I_rgb(rgb),.I_audio_active(audio_active),.I_vu_left(vu_left),.I_vu_right(vu_right),
 .I_spectrum_levels(spectrum),.O_rgb(out_rgb));
task tick; begin @(posedge clk); #1; end endtask
task pulse_frame;
 begin @(negedge clk); de=0;vs=1;tick;
  @(negedge clk);vs=0;repeat(40) tick;
  if((!LOW_POWER || en) && (!dut.row_ready || dut.update_busy)) $fatal(1,"FAIL blanking did not complete");
  if(LOW_POWER && !en && (dut.row_busy || dut.row_ready || dut.update_busy))$fatal(1,"FAIL hidden row still active");
 end
endtask
task scan_frame;
 input integer bright,check_pixels;
 begin
  changed=0;
  for(i=0;i<8;i=i+1) begin
   snapshot[i]=dut.points[i]; px[i]=(dut.points[i]>>11)&2047;
   py[i]=(dut.points[i]>>22)&8191;pa[i]=(dut.points[i]>>43)&255;
  end
  for(y=0;y<480;y=y+1) begin
   for(x=0;x<640;x=x+1) begin
    @(negedge clk);de=1;
    // Vary source RGB to catch latency errors, including full-white saturation.
    rgb=bright ? 24'hFFFDFB : {8'(x),8'(y),8'(x^y)};
    tick;
    if(dut.pixel_x!==x || dut.pixel_y!==y || dut.tile_index!==x/80 || dut.tile_x!==x%80)
     $fatal(1,"FAIL raster coordinate at %0d,%0d",x,y);
    for(i=0;i<8;i=i+1) if(snapshot[i]!==dut.points[i])
     $fatal(1,"FAIL point state changed during active frame");
    idx=x/80;cx=px[idx]/4;cy=py[idx]/4;
    dx=(x%80)*4-cx;if(dx<0)dx=-dx;
    dy=y*4-cy;if(dy<0)dy=-dy;
    dy2=y*4-cy-448;if(dy2<0)dy2=-dy2;
    amp2=pa[idx];
    if(dy2<dy) begin
     dy=dy2;dx=(x%80)*4-(316-cx);if(dx<0)dx=-dx;
     amp2=pa[idx]-pa[idx]/4;
    end
    d=(dx>dy) ? dx+dy/2 : dy+dx/2;
    light=0;
    if(d<32) begin
     core=amp2-d*16;if(core<0)core=0;
     halo=amp2-d*8;if(halo<0)halo=0;
     light=core+halo/4;if(light>255)light=255;
    end
    g=light-light/8;b=d<=2 ? light/2 : light/8;
    rr=rgb[23:16]+light;gg=rgb[15:8]+g;bb=rgb[7:0]+b;
    if(rr>255)rr=255;if(gg>255)gg=255;if(bb>255)bb=255;
    expected=en ? {8'(rr),8'(gg),8'(bb)} : rgb;
    if(check_pixels && out_rgb!==expected)
     $fatal(1,"FAIL glow pixel at %0d,%0d expected=%h got=%h d=%0d amp=%0d",x,y,expected,out_rgb,d,pa[idx]);
    if(out_rgb!==rgb) begin
     changed=changed+1;
     if(y<50) $fatal(1,"FAIL glow intrudes into top-left status row");
     if(out_rgb[23:16]<rgb[23:16] || out_rgb[15:8]<rgb[15:8] || out_rgb[7:0]<rgb[7:0])
      $fatal(1,"FAIL additive light darkened photo");
    end
    checks=checks+1;
   end
   @(negedge clk);de=0;repeat(32) tick;
  end
  if(en && !bright && changed<20) $fatal(1,"FAIL no visible particles");
  if(!en && changed!=0) $fatal(1,"FAIL disabled overlay not transparent");
  $display("PASS exact glow raster enabled=%0d saturated=%0d changed=%0d",en,bright,changed);
 end
endtask
initial begin
 if(LOW_POWER)en=1;
 repeat(4) tick;@(negedge clk);rst=0;repeat(30)tick;
 if(!dut.initialized) $fatal(1,"FAIL RAM initialization");
 // Silence versus music: follow actual band energies, not an arbitrary timer.
 en=1;pulse_frame;
 for(i=0;i<8;i=i+1) old_amp[i]=(dut.points[i]>>43)&255;
 vu_left=80;vu_right=50;spectrum={16{7'd90}};
 for(f=0;f<32;f=f+1) pulse_frame;
 for(i=0;i<8;i=i+1) begin
  if(((dut.points[i]>>43)&255)<=old_amp[i]+25) $fatal(1,"FAIL music did not increase brightness");
 end
 $display("PASS music-driven glow intensity");
 scan_frame(0,1);
 pulse_frame;scan_frame(1,1);
 en=0;pulse_frame;scan_frame(0,1);
 if(LOW_POWER)begin en=1;pulse_frame;end
 // Isolate the frequency lanes with VU disabled. Point2 consumes band4.
 vu_left=0;vu_right=0;spectrum=0;
 for(f=0;f<100;f=f+1)pulse_frame;
 spectrum[4*7+:7]=7'd96;
 for(f=0;f<50;f=f+1)pulse_frame;
 for(i=0;i<8;i=i+1) begin
  amp=dut.points[i]&2047;
  if(i==2 && amp<1400) $fatal(1,"FAIL target spectral lane did not respond");
  if(i!=2 && amp>40) $fatal(1,"FAIL wrong spectral lane responded");
 end
 $display("PASS independent spectral lanes");
 // Music motion remains bounded and sub-pixel positions slew rather than jump.
 spectrum={16{7'd96}};vu_left=96;en=1;
 for(i=0;i<8;i=i+1) begin old_x[i]=(dut.points[i]>>11)&2047;old_y[i]=(dut.points[i]>>22)&8191;end
 for(f=0;f<600;f=f+1) begin
  pulse_frame;
  for(i=0;i<8;i=i+1) begin
   cx=(dut.points[i]>>11)&2047;cy=(dut.points[i]>>22)&8191;
   if(cx<7*16 || cx>68*16 || cy<40*16 || cy>320*16) $fatal(1,"FAIL point out of safe bounds");
   dx=cx-old_x[i];dy=cy-old_y[i];if(dx<0)dx=-dx;if(dy<0)dy=-dy;
   if(dx>40 || dy>80) $fatal(1,"FAIL unsmoothed motion x=%0d y=%0d",dx,dy);
   old_x[i]=cx;old_y[i]=cy;
  end
 end
 $display("PASS 600-frame bounded smooth motion");
 // A sudden PCM loss releases the energy and does not leave stale bright dots.
 audio_active=0;
 for(f=0;f<100;f=f+1)pulse_frame;
 for(i=0;i<8;i=i+1) if((dut.points[i]&2047)>10) $fatal(1,"FAIL no audio energy release");
 @(negedge clk);de=0;rgb=24'hABCDEF;repeat(4)tick;
 if(out_rgb!==rgb) $fatal(1,"FAIL blanking pass-through");
 // Reset has no memory-clear loops; validity and initialization prevent stale reads.
 @(negedge clk);rst=1;tick;@(negedge clk);rst=0;repeat(40)tick;
 pulse_frame;
 for(i=0;i<8;i=i+1) if((dut.points[i]&2047)!=0) $fatal(1,"FAIL restart energy not cleared");
 $display("PASS video_relax_overlay %0d pixels / reset / silence / saturation / audio loss",checks);
 $finish;
end
initial begin #100000000;$fatal(1,"FAIL simulation timeout");end
endmodule
