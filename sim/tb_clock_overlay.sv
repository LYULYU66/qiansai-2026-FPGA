`timescale 1ns/1ps
module tb_clock_overlay;
parameter LOW_POWER=0;
reg clk=0,rst=1,en=1,vs=0,de=0;
reg [1:0] page=0;
reg [15:0] hhmm=16'h0900;
reg [23:0] rgb=0;
wire [23:0] result;
integer p,x,y,checks=0,ink[0:3],local_x,glyph_cell,row,col,digit,cov,rr,gg,bb;
integer read_cycles=0,total_cycles=0;
reg [15:0] held_row;
always @(posedge clk)if(!rst)begin
 total_cycles=total_cycles+1;
 if(!LOW_POWER || dut.font.I_read_enable)read_cycles=read_cycles+1;
 if(LOW_POWER && !dut.font.I_read_enable)begin
  held_row=dut.font.O_row;#1;
  if(dut.font.O_row!==held_row)$fatal(1,"disabled font port changed");
 end
end
reg hit,colon;
reg [31:0] word_value;
reg [23:0] expected_rgb;
always #5 clk=~clk;
video_clock_overlay #(.LOW_POWER(LOW_POWER)) dut(.I_clk(clk),.I_rst(rst),.I_enable(en),.I_vs(vs),.I_de(de),
 .I_picture_idx(page),.I_frame_hhmm(hhmm),.I_rgb(rgb),.O_rgb(result));
function integer brighten(input integer channel,a);
 integer remain,third;
 begin remain=255-channel;third=(remain>>2)+(remain>>4)+(remain>>6);
 case(a)1:brighten=channel+third;2:brighten=255-third;3:brighten=255;default:brighten=channel;endcase
 end
endfunction
task scan(input integer which,enabled);
 begin
  page=which;en=enabled;ink[which]=0;
  @(negedge clk);de=0;vs=1;@(posedge clk);#1;@(negedge clk);vs=0;
  repeat(8)@(negedge clk);
  for(y=0;y<480;y=y+1)begin
   for(x=0;x<640;x=x+1)begin
    de=1;rgb={8'(x),8'(y),8'(x^y)};
    @(posedge clk);#1;
    hit=0;colon=0;local_x=0;row=0;digit=0;glyph_cell=0;col=0;cov=0;
    if(which==2)begin
     if(x>=544 && x<576 && ((y>=152 && y<176)||(y>=180 && y<204)))begin
      hit=1;local_x=x-544;col=local_x%16;
      if(y<176)begin row=y-152;digit=local_x<16 ? hhmm[15:12]:hhmm[11:8];end
      else begin row=y-180;digit=local_x<16 ? hhmm[7:4]:hhmm[3:0];end
     end
    end else if(x>=544 && x<624 && ((which==0 && y>=82 && y<106)||(which!=0 && y>=38 && y<62)))begin
     hit=1;local_x=x-544;glyph_cell=local_x/16;col=local_x%16;row=which==0 ? y-82:y-38;
     case(glyph_cell)0:digit=hhmm[15:12];1:digit=hhmm[11:8];2:colon=1;3:digit=hhmm[7:4];default:digit=hhmm[3:0];endcase
    end
    if(hit)begin
     word_value=dut.font.rom[(digit*24+row)*2+(col/8)];cov=(word_value>>((7-(col%8))*2))&3;
     if(colon)cov=(col>=7 && col<10 && ((row>=7 && row<10)||(row>=15 && row<18)))?3:0;
    end
    expected_rgb=(enabled && hit && cov!=0)?(cov==3?24'hFFFFFF:cov==2?24'hE1E1E1:24'hAAAAAA):rgb;
    if(result!==expected_rgb)$fatal(1,"FAIL clock page%d pixel %d,%d got%h expected%h",which,x,y,result,expected_rgb);
    if(result!==rgb)ink[which]=ink[which]+1;
    checks=checks+1;@(negedge clk);
   end
   de=0;repeat(3)@(negedge clk);
  end
  if(enabled && ink[which]<100)$fatal(1,"FAIL missing clock digits");
  if(!enabled && ink[which]!=0)$fatal(1,"FAIL disabled clock not transparent");
  $display("PASS clock raster page=%d enabled=%d ink=%d",which,enabled,ink[which]);
 end
endtask
initial begin
 repeat(3)@(negedge clk);rst=0;
 for(p=0;p<4;p=p+1)scan(p,1);
 hhmm=16'h2359;scan(2,1);scan(0,0);
 $display("PASS CLOCK_OVERLAY %d pixels, four page layouts, native antialias, no box, exact RGB pass-through",checks);
 $display("PASS CLOCK_READ_ENABLE enabled=%d / total=%d LOW_POWER=%d",read_cycles,total_cycles,LOW_POWER);$finish;
end
initial begin #50000000;$fatal(1,"FAIL raster timeout");end
endmodule
