`timescale 1ns/1ps
// Real RTL composition on the generated 640x480 TF background. Audio levels
// here are controlled fixtures for visual review, not a replay of MUSIC.PCM.
module tb_relax_clock_preview;
parameter LOW_POWER=0;
parameter OUTPUT_DIR="sim/unified_clock_20261002";
reg clk=0,rst=1,vs=0,de=0,audio_active=1;
reg [23:0] rgb=0;
reg [6:0] vu_left=0,vu_right=0;
reg [111:0] spectrum=0;
wire [23:0] glow_rgb,page_rgb,status_rgb,clock_rgb;
wire [23:0] actual_time;
wire [15:0] frame_time;
video_unified_clock shared_clock(.I_clk(clk),.I_rst(rst),.I_vs(vs),.O_time_bcd(actual_time),.O_frame_hhmm(frame_time));
video_clock_overlay #(.LOW_POWER(LOW_POWER)) clock_layer(.I_clk(clk),.I_rst(rst),.I_enable(1'b1),.I_vs(vs),.I_de(de),.I_picture_idx(2'd2),.I_frame_hhmm(frame_time),.I_rgb(status_rgb),.O_rgb(clock_rgb));
wire draw;
reg [7:0] bitmap[0:921653];
reg [23:0] rendered[0:307199];
integer input_file,n,x,y,k,f,file_handle,glow_pixels,status_pixels;
always #5 clk=~clk;
video_relax_overlay #(.LOW_POWER(LOW_POWER)) glow(.I_clk(clk),.I_rst(rst),.I_enable(draw),.I_vs(vs),.I_de(de),
 .I_rgb(rgb),.I_audio_active(audio_active),.I_vu_left(vu_left),.I_vu_right(vu_right),
 .I_spectrum_levels(spectrum),.O_rgb(glow_rgb));
video_playback_overlay_select page(.I_valid(1'b1),.I_transition_active(1'b0),
 .I_pcm_available(audio_active),.I_picture_idx(2'd2),
 .I_regular_rgb(24'hFF00FF),.I_relax_rgb(glow_rgb),.O_relax_draw(draw),.O_rgb(page_rgb),
 .O_home(),.O_music(),.O_warning_selected(),.O_warning_draw(),.O_relax_selected(),
 .O_osd(),.O_visualizer());
video_status_overlay #(.ENABLE_RESOLUTION(1)) status(.I_clk(clk),.I_rst(rst),.I_enable(1'b1),
 .I_vs(vs),.I_de(de),.I_rgb(page_rgb),.I_brightness_level(2'd3),.I_contrast_level(2'd0),
 .I_volume_level(4'd8),.I_source_width(16'd1280),.I_source_height(16'd960),.O_rgb(status_rgb));
task tick;begin @(posedge clk);#1;end endtask
task frame;
 begin @(negedge clk);de=0;vs=1;tick;@(negedge clk);vs=0;repeat(80)tick;end
endtask
task render_scene;
 input integer loud;
 begin
  frame;glow_pixels=0;status_pixels=0;
  for(y=0;y<480;y=y+1)begin
   for(x=0;x<640;x=x+1)begin
    k=54+((479-y)*640+x)*3;
    @(negedge clk);de=1;rgb={bitmap[k+2],bitmap[k+1],bitmap[k]};tick;
    if(glow_rgb!==rgb)glow_pixels=glow_pixels+1;
    if(status_rgb!==page_rgb)status_pixels=status_pixels+1;
    if(page_rgb!==glow_rgb)$fatal(1,"FAIL third page did not bypass other overlays");
    if(y>=390 && status_rgb!==page_rgb)$fatal(1,"FAIL old bottom strip remained");
    rendered[y*640+x]=clock_rgb;
    if(clock_rgb!==status_rgb && !(x>=544 && x<576 && ((y>=152 && y<176)||(y>=180 && y<204))))$fatal(1,"FAIL clock outside stacked region");
   end
   @(negedge clk);de=0;repeat(160)tick;
  end
  // Silence deliberately leaves only dim tiny particles; music must visibly
  // increase the luminous area. The exact per-pixel equation is gated by the
  // separate exhaustive raster bench, not by an arbitrary silence-area limit.
  if(status_pixels<100 || (loud && glow_pixels<100) || (!loud && (glow_pixels==0 || glow_pixels>=100)))
   $fatal(1,"FAIL status/music visual response status=%0d glow=%0d music=%0d",status_pixels,glow_pixels,loud);
  file_handle=$fopen(loud==2 ? {OUTPUT_DIR,"/relax_clock_later.bmp"} :
                    loud==1 ? {OUTPUT_DIR,"/relax_clock.bmp"} : {OUTPUT_DIR,"/relax_clock_quiet.bmp"},"wb");
  if(!file_handle)$fatal(1,"FAIL cannot write preview");
  for(k=0;k<54;k=k+1)$fwrite(file_handle,"%c",bitmap[k]);
  for(y=479;y>=0;y=y-1)for(x=0;x<640;x=x+1)begin
   $fwrite(file_handle,"%c%c%c",rendered[y*640+x][7:0],rendered[y*640+x][15:8],rendered[y*640+x][23:16]);
  end
  $fclose(file_handle);
  $display("PASS actual relax/status scene music=%0d glow=%0d status=%0d, no bottom playback layers",loud,glow_pixels,status_pixels);
 end
endtask
initial begin
 input_file=$fopen("output/imagegen/night_hills_20261002/night_hills_640x480.bmp","rb");
 if(!input_file)$fatal(1,"FAIL missing preview background");
 n=$fread(bitmap,input_file);$fclose(input_file);
 if(n!=921654 || bitmap[28]!=24 || bitmap[30]!=0)$fatal(1,"FAIL invalid background");
 repeat(4)tick;@(negedge clk);rst=0;repeat(40)tick;
 for(f=0;f<30;f=f+1)frame;render_scene(0);
 vu_left=80;vu_right=65;
 for(k=0;k<16;k=k+1)spectrum[k*7+:7]=25+((k*11)%65);
 for(f=0;f<36;f=f+1)frame;render_scene(1);
 for(f=0;f<96;f=f+1)frame;render_scene(2);
 if(frame_time!==16'h0900)$fatal(1,"FAIL shared default time not09:00");
 $display("PASS CLOCK_SCENE 921600 actual RTL pixels: shared09:00, stacked hour/minute, 16 music stars, frameless parameters");$finish;
end
initial begin #50000000;$fatal(1,"FAIL preview timeout");end
endmodule
