`timescale 1ns/1ps
module tb_cover_rgb565;
reg clk=0;always #5 clk=~clk;
reg rst=1,source_de=0,source_vs=0,de=0,vs=0;
reg home=0,music=0,song=1;
reg [23:0] source_rgb=0,rgb=0;
always @(posedge clk)begin de<=source_de;vs<=source_vs;rgb<=source_rgb;end
wire [23:0] out;
video_song_cover_overlay dut(clk,rst,vs,de,home,music,song,rgb,out);
reg [15:0] reference[0:4095];
integer f,x,y,sx,sy,hits=0,checks=0;
reg frame_song,hit;
reg [15:0] w;
reg [23:0] expected;
initial begin
 $readmemh("../../../assets/lyrics/yilu_replace_20261006/cover_rgb565.hex",reference);
 repeat(8)@(negedge clk);rst=0;
 for(f=0;f<6;f=f+1)begin
  home=f==1||f==3;music=f==0||f==2||f==5;song=f!=2&&f!=3;frame_song=song;
  source_vs=1;repeat(3)@(negedge clk);source_vs=0;repeat(16)@(negedge clk);
  for(y=0;y<480;y=y+1)begin
   for(x=0;x<640;x=x+1)begin
    source_de=1;source_rgb={x[7:0],y[7:0],8'h5a};
    if(f==5&&x==320&&y==100)song=0;
    @(posedge clk);#1;
    expected=source_rgb;
    hit=frame_song&&((music&&x>=160&&x<224&&y>=136&&y<200)||(home&&x>=184&&x<224&&y>=336&&y<376));
    if(hit)begin
     sx=music?x-160:((x-184)*8+4)/5;
     sy=music?y-136:((y-336)*8+4)/5;
     w=reference[sy*64+sx];
     expected={w[15:11],w[15:13],w[10:5],w[10:9],w[4:0],w[4:2]};hits=hits+1;
    end
    if(out!==expected)$fatal(1,"cover misalignment f=%0d xy=%0d,%0d got=%h expected=%h",f,x,y,out,expected);
    checks=checks+1;@(negedge clk);
   end
   source_de=0;repeat(12)@(negedge clk);
   if(out!==rgb)$fatal(1,"cover changed blanking RGB");
  end
 end
 if(hits!=9792)$fatal(1,"wrong covered pixel count %0d",hits);
 $display("PASS RGB565 cover: %0d full-frame pixels, %0d cover pixels, both banks, native64/home40, song1 passthrough, frame-atomic switch, no DE/RGB delay",checks,hits);
 $finish;
end
initial begin #30000000;$fatal(1,"cover timeout");end
endmodule
