`timescale 1ns/1ps
// A pixel chain after the page select, exactly as wired in top_dual_image_hw:
// photo/page mux -> status readout -> home logo -> clock -> hazard overlay.
// In photo-only mode the output must equal "photo + status readout" (a
// reference status overlay fed with the photo) everywhere, unless a hazard
// is active, which must still draw its border.
module tb_photo_mode_render;
reg clk=0,rst=1,vs=0,de=0; always #5 clk=~clk;
reg [23:0] page_bg[0:307199], photo_bg[0:307199];
reg [23:0] page_rgb=0, photo_rgb=0;
reg photo_req=0, hazard_left=0;
// Copy of the top-level frame-boundary register.
reg photo_only_frame=0, photo_vs_d=0;
always @(posedge clk) begin
    photo_vs_d<=vs;
    if(vs && !photo_vs_d) photo_only_frame<=photo_req;
end
wire photo_only_video=photo_only_frame;
wire first_image_home=1'b1;
wire [23:0] status_in = photo_only_video ? photo_rgb : page_rgb;
wire [23:0] status_rgb, logo_rgb, clock_rgb, out_rgb, ref_rgb;
video_status_overlay #(.ENABLE_RESOLUTION(1),.SELECT_HIGHLIGHT(1)) status(.I_clk(clk),.I_rst(rst),
  .I_enable(1'b1),.I_vs(vs),.I_de(de),.I_rgb(status_in),
  .I_brightness_level(2'd3),.I_contrast_level(2'd1),.I_volume_level(4'd8),
  .I_source_width(16'd640),.I_source_height(16'd480),.I_selected(2'd1),.O_rgb(status_rgb));
video_home_logo logo(.I_clk(clk),.I_rst(rst),.I_enable(first_image_home && !photo_only_video),
  .I_vs(vs),.I_de(de),.I_rgb(status_rgb),.O_rgb(logo_rgb));
video_clock_overlay #(.LOW_POWER(1)) clock(.I_clk(clk),.I_rst(rst),.I_vs(vs),.I_de(de),
  .I_enable(1'b1 && !photo_only_video),.I_picture_idx(2'd0),
  .I_frame_hhmm(16'h1234),.I_rgb(logo_rgb),.O_rgb(clock_rgb));
vehicle_hazard_overlay hazard(.I_clk(clk),.I_rst(rst),.I_vs(vs),.I_de(de),.I_rgb(clock_rgb),
  .I_warning_page(1'b0),.I_hazard_front(1'b0),.I_hazard_left(hazard_left),
  .I_hazard_right(1'b0),.I_hazard_rear(1'b0),.O_rgb(out_rgb));
video_status_overlay #(.ENABLE_RESOLUTION(1),.SELECT_HIGHLIGHT(1)) ref_status(.I_clk(clk),.I_rst(rst),
  .I_enable(1'b1),.I_vs(vs),.I_de(de),.I_rgb(photo_rgb),
  .I_brightness_level(2'd3),.I_contrast_level(2'd1),.I_volume_level(4'd8),
  .I_source_width(16'd640),.I_source_height(16'd480),.I_selected(2'd1),.O_rgb(ref_rgb));
integer x,y,fd,diff,diff_outside_left,errors=0;
task frame(input dump);
  begin
    diff=0; diff_outside_left=0;
    @(negedge clk);vs=1;repeat(4)@(negedge clk);vs=0;repeat(80)@(negedge clk);
    for(y=0;y<480;y=y+1)begin
      for(x=0;x<640;x=x+1)begin
        @(negedge clk);de=1;page_rgb=page_bg[y*640+x];photo_rgb=photo_bg[y*640+x];
        @(posedge clk);#2;
        if(out_rgb!==ref_rgb) begin diff=diff+1; if(x>=12) diff_outside_left=diff_outside_left+1; end
        if(dump) $fwrite(fd,"%06h\n",out_rgb);
      end
      @(negedge clk);de=0;repeat(3)@(negedge clk);
    end
  end
endtask
initial begin
  $readmemh("../dualsong_20261005/lyricfix_20261019/home_bg.hex",page_bg);
  $readmemh("../dualsong_20261005/lyricfix_20261019/music_bg.hex",photo_bg);
  fd=$fopen("render.hex","w");
  repeat(4)@(negedge clk);rst=0;
  frame(0); frame(1);   // normal page
  if(diff<1000) begin errors=errors+1; $display("FAIL normal mode looks like photo (diff=%0d)",diff); end
  else $display("ok   normal: page differs from photo+readout at %0d px",diff);
  photo_req=1; frame(0); frame(1);
  if(diff!=0) begin errors=errors+1; $display("FAIL photo-only: %0d px differ from photo+readout",diff); end
  else $display("ok   photo-only == photo + top-left readout (0 px differ)");
  hazard_left=1; frame(0); frame(1);
  if(diff==0 || diff_outside_left!=0) begin errors=errors+1;
    $display("FAIL photo-only+left hazard diff=%0d outside=%0d",diff,diff_outside_left); end
  else $display("ok   photo-only + SW3 left hazard: border drawn (%0d px, all x<12)",diff);
  hazard_left=0; photo_req=0; frame(0); frame(1);
  if(diff<1000) begin errors=errors+1; $display("FAIL back to normal diff=%0d",diff); end
  else $display("ok   SW2 off: normal page again (%0d px)",diff);
  $fclose(fd);
  if(errors==0) $display("PASS tb_photo_mode_render"); else $display("FAIL tb_photo_mode_render %0d",errors);
  $finish;
end
endmodule
