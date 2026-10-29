`timescale 1ns/1ps
module tb_home_clock_replacement;
reg clk=0,rst=1,vs=0,de=0;
reg [23:0] rgb=0;
wire [23:0] old_rgb,new_rgb;
integer x,y,changed=0,checks=0;
always #5 clk=~clk;
video_home_overlay legacy(.I_clk(clk),.I_rst(rst),.I_enable(1'b1),.I_music_page(1'b0),.I_vs(vs),.I_de(de),.I_rgb(rgb),.O_rgb(old_rgb));
video_home_overlay #(.EXTERNAL_CLOCK(1)) current_home(.I_clk(clk),.I_rst(rst),.I_enable(1'b1),.I_music_page(1'b0),.I_vs(vs),.I_de(de),.I_rgb(rgb),.O_rgb(new_rgb));
initial begin
 repeat(3)@(negedge clk);rst=0;vs=1;
 @(negedge clk);vs=0;repeat(8)@(negedge clk);
 for(y=0;y<480;y=y+1)begin
  for(x=0;x<640;x=x+1)begin
   de=1;rgb={8'(x),8'(y),8'(x^y)};@(posedge clk);#1;
   if(x>=544 && x<624 && y>=82 && y<98)begin
    if(new_rgb!==rgb)$fatal(1,"FAIL fixed home clock remained");
    if(old_rgb!==new_rgb)changed=changed+1;
   end else if(old_rgb!==new_rgb)$fatal(1,"FAIL unrelated homepage pixel changed %d,%d",x,y);
   checks=checks+1;@(negedge clk);
  end
  de=0;repeat(3)@(negedge clk);
 end
 if(changed<100)$fatal(1,"FAIL old fixed time was not removed");
 $display("PASS HOME_CLOCK_REPLACE %d exact pixels; removed %d fixed-time pixels, all cards/date/sun/toolbar unchanged",checks,changed);$finish;
end
initial begin #10000000;$fatal(1,"FAIL homepage clock watchdog");end
endmodule
