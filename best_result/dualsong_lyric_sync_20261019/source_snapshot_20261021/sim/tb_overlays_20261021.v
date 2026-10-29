`timescale 1ns/1ps
// Renders the B dashboard subtitle (normal + hazard) over IMAGE1 and the A
// home logo badge over a gradient test photo; dumps the active pixels.
module tb_overlays_20261021;
reg clk=0, rst=1;
always #20 clk=~clk;
reg vs=0, de=0;
reg [10:0] hx; reg [9:0] vy;
reg [23:0] bg [0:307199];
reg [23:0] rgb_in;
reg hazard=0;
integer frame=0;
initial $readmemh("dash_bg.hex", bg);
// Same chain as b_hdmi_preview: the car overlay (sprite disabled, so its
// output is the background) supplies the raster position to the subtitle.
wire [23:0] car_rgb, sub_rgb; wire car_vs, car_de, sub_vs, sub_de;
wire [10:0] car_x; wire [9:0] car_y;
video_car_intro_light u_car (.I_clk(clk),.I_rst(rst),.I_enable(1'b0),.I_vs(vs),.I_de(de),.I_rgb(rgb_in),
    .O_rgb(car_rgb),.O_vs(car_vs),.O_de(car_de),.O_x(car_x),.O_y(car_y));
video_dashboard_subtitle #(.SCROLL_INIT(10'd`SCROLL0)) dut_b (
    .I_clk(clk),.I_rst(rst),.I_enable(1'b1),.I_hazard_async(hazard),
    .I_vs(car_vs),.I_de(car_de),.I_x(car_x),.I_y(car_y),.I_rgb(car_rgb),
    .O_rgb(sub_rgb),.O_vs(sub_vs),.O_de(sub_de));
wire [23:0] logo_rgb;
video_home_logo dut_a (.I_clk(clk),.I_rst(rst),.I_enable(1'b1),
    .I_vs(vs),.I_de(de),.I_rgb(rgb_in),.O_rgb(logo_rgb));
integer fb, fa;
// 800x525 raster, vs high on lines 0..1, active lines 35..514, x 0..639.
always @(posedge clk) begin
    if(rst) begin hx<=0; vy<=0; vs<=0; de<=0; end
    else begin
        if(hx==799) begin hx<=0; vy<=(vy==524)?0:vy+1'b1; end else hx<=hx+1'b1;
        vs<= (vy<2);
        de<= (vy>=35 && vy<515 && hx<640);
        rgb_in<= (vy>=35 && vy<515 && hx<640) ? bg[(vy-35)*640+hx] : 24'h0;
        if(hx==799 && vy==524) frame<=frame+1;
    end
end
// Frames 0..3 normal, 4..7 hazard (the async input is sampled at vs).
always @(posedge clk) if(hx==0 && vy==20) hazard<=(frame>=3);
initial begin
    fb=$fopen("out_b.hex","w"); fa=$fopen("out_a.hex","w");
    #200 rst=0;
end
always @(posedge clk) begin
    if(sub_de) $fwrite(fb,"%06x\n",sub_rgb);
    if(de) $fwrite(fa,"%06x\n",logo_rgb);
    if(frame==8) begin $fclose(fb); $fclose(fa); $display("TB DONE"); $finish; end
end
endmodule
