`timescale 1ns/1ps
module tb_nav_toolbar_alignment;
reg clk=0,rst=1,en=1,vs=0,de=0;
reg [23:0] rgb=24'h123456;
wire [23:0] actual;
integer f,x,y,i,file_handle,b0,b1,b2,errors=0,checks=0,car_checks=0;
reg [255:0] header;
reg [23:0] expected[0:25599];
reg [23:0] car_expected[0:2047];
always #5 clk=~clk;
video_home_overlay dut(.I_clk(clk),.I_rst(rst),.I_enable(en),.I_vs(vs),
 .I_de(de),.I_music_page(1'b0),.I_rgb(rgb),.O_rgb(actual));
initial begin
 file_handle=$fopen("assets/bottom_nav_icons_20260930/toolbar_native.ppm","rb");
 if(!file_handle) $fatal(1,"missing reference toolbar");
 i=$fgets(header,file_handle);i=$fgets(header,file_handle);i=$fgets(header,file_handle);
 for(i=0;i<25600;i=i+1) begin
  b0=$fgetc(file_handle);b1=$fgetc(file_handle);b2=$fgetc(file_handle);
  expected[i]={b0[7:0],b1[7:0],b2[7:0]};
 end
 $fclose(file_handle);
 file_handle=$fopen("assets/tpms_car_20260930/car_indexed32x64.ppm","rb");
 if(!file_handle) $fatal(1,"missing realistic car reference");
 i=$fgets(header,file_handle);i=$fgets(header,file_handle);i=$fgets(header,file_handle);
 for(i=0;i<2048;i=i+1) begin
  b0=$fgetc(file_handle);b1=$fgetc(file_handle);b2=$fgetc(file_handle);
  car_expected[i]={b0[7:0],b1[7:0],b2[7:0]};
 end
 $fclose(file_handle);
 repeat(4) @(negedge clk);rst=0;
 for(f=0;f<3;f=f+1) begin
  en=(f!=1);vs=1;de=0;
  repeat(2+f) @(negedge clk);vs=0;
  for(y=0;y<480;y=y+1) begin
   for(x=0;x<640;x=x+1) begin
    @(negedge clk);de=1;rgb={x[7:0],y[7:0],8'h56};
    @(posedge clk);#1;
    if(dut.pixel_x!==x || dut.pixel_y!==y) errors=errors+1;
    if(!en && actual!==rgb) errors=errors+1;
    if(en && y>=440) begin
     if(actual!==expected[(y-440)*640+x]) begin
      if(errors<8) $display("FAIL toolbar f=%0d x=%0d y=%0d actual=%h expected=%h",f,x,y,actual,expected[(y-440)*640+x]);
      errors=errors+1;
     end
     checks=checks+1;
    end
    if(en && x>=540 && x<572 && y>=327 && y<391) begin
     if(actual!==car_expected[(y-327)*32+x-540]) begin
      if(errors<8) $display("FAIL car f=%0d x=%0d y=%0d actual=%h expected=%h",f,x,y,actual,car_expected[(y-327)*32+x-540]);
      errors=errors+1;
     end
     car_checks=car_checks+1;
    end
   end
   @(negedge clk);de=0;repeat(1+f) @(negedge clk);
   if(actual!==rgb) errors=errors+1;
  end
 end
 if(errors) $fatal(1,"toolbar alignment errors=%0d",errors);
 $display("PASS NAV/CAR ALIGNMENT: %0d footer pixels, %0d realistic-car pixels, three full frames, 1/2/3-cycle blanking, enable/pass-through",checks,car_checks);
 $finish;
end
initial begin #20000000;$fatal(1,"toolbar alignment timeout");end
endmodule
