`timescale 1ns/1ps
module tb_car_intro;
reg clk=0;always #20 clk=~clk;
reg rst=1,en=0,vs=0,de=0;reg [23:0] bg=0;
wire [23:0] rgb;wire ovs,ode;
video_car_intro dut(.I_clk(clk),.I_rst(rst),.I_enable(en),.I_vs(vs),.I_de(de),.I_rgb(bg),.O_rgb(rgb),.O_vs(ovs),.O_de(ode));
reg rom_en=0;reg [14:0] addr=0;wire [3:0] idx;wire [23:0] color;
car_intro_rom check_rom(.clk(clk),.enable(rom_en),.address(addr),.index(idx),.rgb(color));
`include "sprite_reference.vh"
`include "car_reference.vh"
integer selected_age=0,selected_pulse=0,n,x,y,a,checks=0,painted=0,rom_checks=0,seed=2468,pick,last_idx;
reg [23:0] expected;
task frame_pulse;
 begin @(negedge clk);vs=1;de=0;repeat(3)@(negedge clk);vs=0;repeat(3)@(negedge clk);end
endtask
task render;
 input integer age_value,pulse_value,enabled;
 begin
  en=enabled;selected_age=age_value;selected_pulse=pulse_value;
  force dut.age=selected_age;force dut.idle_phase=selected_pulse;
  frame_pulse;
  for(y=0;y<480;y=y+1)begin
   for(x=0;x<640;x=x+1)begin
    @(negedge clk);de=1;bg={x[7:0],y[7:0],8'h40};
    expected=car_reference(bg,x,y,age_value,pulse_value,enabled);
    @(posedge clk);#2;
    if(ode!==1||ovs!==0||rgb!==expected)$fatal(1,"car pixel age=%0d xy=%0d/%0d got=%h expected=%h de/vs=%b/%b",age_value,x,y,rgb,expected,ode,ovs);
    checks=checks+1;if(rgb!=bg)painted=painted+1;
    if(y<368&&rgb!==bg)$fatal(1,"car covered instrument dials");
   end
   @(negedge clk);de=0;bg=24'h51b987;
   @(posedge clk);#2;if(ode!==0||rgb!==bg)$fatal(1,"blanking not bypassed");
   repeat(159)@(negedge clk);
  end
  release dut.age;release dut.idle_phase;
 end
endtask
initial begin
 repeat(5)@(negedge clk);rst=0;repeat(5)@(negedge clk);
 for(n=0;n<24576;n=n+1)begin
  @(negedge clk);rom_en=1;addr=n;
  @(posedge clk);#2;if(idx!==ref_pixels[n]||color!==ref_color(ref_pixels[n]))$fatal(1,"ROM bank/nibble n=%0d idx=%h ref=%h",n,idx,ref_pixels[n]);rom_checks=rom_checks+1;
 end
 for(n=0;n<700;n=n+1)begin
  pick=($random(seed)&32'h7fffffff)%24576;
  @(negedge clk);addr=pick;rom_en=1;
  @(posedge clk);#2;if(idx!==ref_pixels[pick]||color!==ref_color(ref_pixels[pick]))$fatal(1,"random ROM address %0d",pick);
  last_idx=idx;rom_checks=rom_checks+1;
  @(negedge clk);rom_en=0;addr=0;
  @(posedge clk);#2;if(idx!==last_idx)$fatal(1,"ROM enable did not hold");
 end
 $display("PASS car sprite ROM: %0d native BRAM bank/nibble/palette checks and700 enable holds",rom_checks);
 render(0,0,1);render(15,15,1);render(16,16,1);render(24,24,1);
 render(64,64,1);render(96,96,1);render(128,0,1);render(143,15,1);
 render(144,16,1);render(191,63,1);render(191,127,0);
 if(checks!=3379200||painted<50000)$fatal(1,"insufficient pixel coverage %0d/%0d",checks,painted);
 $display("PASS car pixels: %0d exact full-frame RGB/DE/VS checks, fade wrap128/full opacity, rise, moving highlight, platform pulse, off-page passthrough and no dial coverage",checks);
 en=0;frame_pulse;if(dut.age!==0||dut.idle_phase!==0)$fatal(1,"exit did not reset animation");
 en=1;
 for(n=1;n<=230;n=n+1)begin
  frame_pulse;
  if(dut.age!==(n<191?n:191))$fatal(1,"age lifetime/saturation n=%0d age=%0d",n,dut.age);
 end
 repeat(100)@(negedge clk);if(dut.age!==191)$fatal(1,"animation advanced without frame");
 en=0;repeat(4)@(negedge clk);en=1;frame_pulse;if(dut.age!==1)$fatal(1,"manual return did not replay");
 rst=1;@(negedge clk);if(ode!==0||dut.age!==0)$fatal(1,"reset not clean");
 $display("PASS car lifecycle: frame-only progression, saturated hold, exit reset, manual re-entry replay and asynchronous reset");
 $finish;
end
initial begin #300000000;$fatal(1,"car test timeout");end
endmodule
