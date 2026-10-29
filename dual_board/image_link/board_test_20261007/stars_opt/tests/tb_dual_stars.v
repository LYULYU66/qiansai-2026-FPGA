`timescale 1ns/1ps
module tb_dual_stars;
reg clk=0;always #4 clk=~clk;
reg rst=1,vs=0,de=0,enable=1;
// Registered source, matching video_delay/video_image_adjust on both boards.
reg source_de=0,source_vs=0;
always @(posedge clk)begin de<=source_de;vs<=source_vs;end
reg [15:0] phase=0;
reg [23:0] bg=24'h091426;
wire [23:0] a,b;
integer xx,yy,f,ph,checked=0,lit_a=0,lit_b=0,seam_lights=0;
reg [23:0] expected_a,expected_b;
video_dual_star_overlay #(.VIEW_X(0)) dut_a(
 .I_clk(clk),.I_rst(rst),.I_vs(vs),.I_de(de),.I_enable(enable),.I_rgb(bg),.I_phase_q4(phase),.O_rgb(a));
video_dual_star_overlay #(.VIEW_X(640)) dut_b(
 .I_clk(clk),.I_rst(rst),.I_vs(vs),.I_de(de),.I_enable(enable),.I_rgb(bg),.I_phase_q4(phase),.O_rgb(b));
`include "star_reference.vh"
initial begin
 repeat(8)@(negedge clk);rst=0;
 for(f=0;f<10;f=f+1)begin
  //712 has an independently found two-sided seam light at y113.
  case(f)0:ph=0;1:ph=1;2:ph=2048;3:ph=16383;4:ph=712;5:ph=720;
   6:ph=4096;8:ph=20479;9:ph=20480;default:ph=0;endcase
  phase=ph;enable=f!=7;
  source_vs=1;repeat(3)@(negedge clk);source_vs=0;repeat(160)@(negedge clk);
  for(yy=0;yy<480;yy=yy+1)begin
   for(xx=0;xx<640;xx=xx+1)begin
    source_de=1;
    if(xx==0&&enable&&(!dut_a.row_ready||!dut_b.row_ready))$fatal(1,"129-clock row evaluator missed real160-clock blanking deadline");
    // Received phase changes inside active video must NOT tear this frame.
    if(xx==320 && yy==200)phase=16'd13000;
    @(posedge clk);#1;
    expected_a=enable ? star_reference(bg,xx,yy,ph) : bg;
    expected_b=enable ? star_reference(bg,xx+640,yy,ph) : bg;
    if(a!==expected_a || b!==expected_b)
     $fatal(1,"star RGB mismatch frame=%0d x=%0d y=%0d phase=%0d got=%h/%h expected=%h/%h",f,xx,yy,ph,a,b,expected_a,expected_b);
    if(a!=bg)lit_a=lit_a+1;if(b!=bg)lit_b=lit_b+1;
    if((xx==639 && a!=bg)||(xx==0 && b!=bg))seam_lights=seam_lights+1;
    checked=checked+2;
    @(negedge clk);
   end
   // Real VGA timing has160 blank clocks;129 shared-evaluator clocks must fit.
   source_de=0;repeat(160)@(negedge clk);
   if(a!==bg || b!==bg)$fatal(1,"stars changed RGB outside DE");
  end
 end
 if(lit_a<3000 || lit_b<3000 || seam_lights==0)$fatal(1,"empty viewport or untested cross-screen seam");
 $display("PASS dual stars pixels: %0d exact RGB comparisons, both 640x480 viewports, phase wrap/fractional shift, independent XY drift, 3 sizes, staggered breathing, frame atomicity, disabled passthrough, seam samples=%0d",checked,seam_lights);
 $finish;
end
initial begin #100000000;$fatal(1,"star pixel test timeout");end
endmodule
