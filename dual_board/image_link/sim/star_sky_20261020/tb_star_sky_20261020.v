`timescale 1ns/1ps
// Renders frames for VIEW_X=0 (A) and VIEW_X=640 (B) with real 640x480
// timing (800x525). Inputs change 1 ns after the clock like a registered
// upstream stage; the output is sampled mid-cycle.
module tb_star_sky_20261020;
reg clk=0; always #20 clk=~clk;
reg rst=1, vs=0, de=0;
reg [23:0] rgb_a=0, rgb_b=0;
reg [14:0] near_q4=0, far_q4=0; reg [7:0] tw=0; reg mon=0;
reg signed [15:0] mx=0; reg [12:0] my=0; reg [7:0] env=0;
wire [23:0] oa, ob;
video_star_sky #(.VIEW_X(0)) ua(.I_clk(clk),.I_rst(rst),.I_enable(1'b1),.I_vs(vs),.I_de(de),.I_rgb(rgb_a),
 .I_near_q4(near_q4),.I_far_q4(far_q4),.I_twinkle(tw),.I_meteor_on(mon),.I_meteor_x_q4(mx),
 .I_meteor_y_q4(my),.I_meteor_env(env),.O_rgb(oa));
video_star_sky #(.VIEW_X(640)) ub(.I_clk(clk),.I_rst(rst),.I_enable(1'b1),.I_vs(vs),.I_de(de),.I_rgb(rgb_b),
 .I_near_q4(near_q4),.I_far_q4(far_q4),.I_twinkle(tw),.I_meteor_on(mon),.I_meteor_x_q4(mx),
 .I_meteor_y_q4(my),.I_meteor_env(env),.O_rgb(ob));
reg [23:0] bga [0:307199];
reg [23:0] bgb [0:307199];
reg [79:0] fr [0:15];
integer f,x,y,l,fa,fb,NF;
task blank_line(input integer v); integer k; begin
  for(k=0;k<800;k=k+1) begin @(posedge clk); #1 de=0; vs=v; end end endtask
initial begin
  $readmemh("star_sky_20261020/bg_a.hex",bga);
  $readmemh("star_sky_20261020/bg_b.hex",bgb);
  $readmemh("star_sky_20261020/frames.hex",fr);
  NF=`NFRAMES;
  fa=$fopen("star_sky_20261020/out_a.hex","w"); fb=$fopen("star_sky_20261020/out_b.hex","w");
  repeat(5) @(posedge clk); rst=0;
  for(f=0;f<NF;f=f+1) begin
    {near_q4,far_q4,tw,mon,mx,my,env}=fr[f][75:0];
    for(l=0;l<45;l=l+1) blank_line(l>=10 && l<12);
    for(y=0;y<480;y=y+1) begin
      for(x=0;x<640;x=x+1) begin
        @(posedge clk); #1 de=1; vs=0; rgb_a=bga[y*640+x]; rgb_b=bgb[y*640+x];
        #6 $fwrite(fa,"%06h\n",oa); $fwrite(fb,"%06h\n",ob);
      end
      for(x=0;x<160;x=x+1) begin @(posedge clk); #1 de=0; end
    end
  end
  $fclose(fa); $fclose(fb);
  $display("PASS star sky render: %0d frames x 2 views", NF);
  $finish;
end
endmodule
