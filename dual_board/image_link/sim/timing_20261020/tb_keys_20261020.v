`timescale 1ns/1ps
// A-board keys: KEY2 cycles brightness/contrast/volume, KEY1 steps the
// selected value with wrap; the status row draws the selected group purple.
module tb_keys_20261020;
reg clk=0,rst=1,ksel=1,kstep=1,vs=0,de=0; always #20 clk=~clk;
wire [1:0] sel,bri,con; wire [3:0] vol; wire [23:0] rgb;
local_av_settings #(.CLK_FREQ_HZ(100000)) dut(.clk(clk),.rst(rst),.key_select(ksel),.key_step(kstep),
 .selected(sel),.brightness_level(bri),.contrast_level(con),.volume_level(vol));
video_status_overlay #(.SELECT_HIGHLIGHT(1)) ov(.I_clk(clk),.I_rst(rst),.I_enable(1'b1),.I_vs(vs),.I_de(de),
 .I_rgb(24'h102030),.I_brightness_level(bri),.I_contrast_level(con),.I_volume_level(vol),
 .I_source_width(16'd640),.I_source_height(16'd480),.I_selected(sel),.O_rgb(rgb));
task press(input which); begin
 if(which) kstep=0; else ksel=0; repeat(3000)@(negedge clk); kstep=1; ksel=1; repeat(3000)@(negedge clk); end endtask
integer x,y,purple[0:2],k,i;
task frame; begin
 for(k=0;k<3;k=k+1) purple[k]=0;
 @(negedge clk); vs=1; repeat(4)@(negedge clk); vs=0; repeat(20)@(negedge clk);
 for(y=0;y<40;y=y+1) begin for(x=0;x<640;x=x+1) begin @(negedge clk); de=1; @(posedge clk); #2;
   if(rgb[23:16]>8'h70 && rgb[15:8]<rgb[23:16]-8'h30 && rgb[7:0]>rgb[15:8]+8'h40)
     purple[(x<114)?0:(x<210)?1:2]=purple[(x<114)?0:(x<210)?1:2]+1; end
   @(negedge clk); de=0; repeat(3)@(negedge clk); end
end endtask
initial begin
 repeat(10)@(negedge clk); rst=0; repeat(10)@(negedge clk);
 if(sel!=0||bri!=3||con!=0||vol!=8) $fatal(1,"power-up state");
 frame; if(purple[0]<20||purple[1]||purple[2]) $fatal(1,"brightness not purple at power-up %0d/%0d/%0d",purple[0],purple[1],purple[2]);
 press(1); if(bri!=0) $fatal(1,"brightness max must wrap to min (got %0d)",bri);
 press(1); if(bri!=1) $fatal(1,"brightness step");
 press(0); if(sel!=1) $fatal(1,"select contrast"); frame;
 if(purple[1]<20||purple[0]||purple[2]) $fatal(1,"contrast not purple %0d/%0d/%0d",purple[0],purple[1],purple[2]);
 for(i=0;i<4;i=i+1) press(1); if(con!=0) $fatal(1,"contrast wrap");
 press(0); if(sel!=2) $fatal(1,"select volume");
 press(1); if(vol!=0) $fatal(1,"volume 8 must wrap to 0 (got %0d)",vol);
 for(i=0;i<8;i=i+1) press(1); if(vol!=8) $fatal(1,"volume steps to 8");
 frame; if(purple[2]<10||purple[0]||purple[1]) $fatal(1,"volume not purple %0d/%0d/%0d",purple[0],purple[1],purple[2]);
 press(0); if(sel!=0) $fatal(1,"select wraps to brightness");
 if(bri!=1||con!=0||vol!=8) $fatal(1,"other values changed");
 $display("PASS keys: select cycle, per-parameter wrap (bri/con 0..3, vol 0..8), purple selected group");
 $finish;
end
endmodule
