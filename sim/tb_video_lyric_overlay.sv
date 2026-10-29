`timescale 1ns/1ps
module tb_video_lyric_overlay;
parameter LOW_POWER=0;
reg clk=0,rst=1,enable=1,card_enable=1,vs=0,de=0;
reg [23:0] rgb=0;
reg [7:0] line=1,nextline=2;
reg [9:0] red=15;
wire [23:0] out_rgb;
video_lyric_overlay #(.LOW_POWER(LOW_POWER)) dut(.I_clk(clk),.I_rst(rst),.I_enable(enable),.I_card_enable(card_enable),
 .I_vs(vs),.I_de(de),.I_rgb(rgb),.I_line(line),.I_next_line(nextline),.I_red_pixels(red),.O_rgb(out_rgb));
always #20 clk=~clk;
integer x,y,scenario,pixels=0,cur,nxt,sweep,oldcur=0,oldnxt=0,slide=0;
integer r,gy,len,leftedge,idx,col,row,gid,cov,stage,rel,cursor;
reg [23:0] expected,ink,bg;
function integer length_of(input integer id);
 begin length_of=(id==1)?2:(id==2)?3:(id==22)?10:(id==23 || id==24)?5:(id==25)?6:(id==26)?4:0;end
endfunction
function [7:0] mix(input [7:0] b,f,input integer c);
 begin case(c)
  1:mix=(b>>1)+(b>>2)+(f>>2);
  2:mix=(b>>2)+(f>>1)+(f>>2)+(f&1);
  3:mix=f;default:mix=b;
 endcase end
endfunction
task tick;begin @(posedge clk);#1;end endtask
initial begin
 repeat(4) tick;rst=0;
 for(scenario=0;scenario<16;scenario=scenario+1) begin
  line=(scenario==0 || scenario==11)?1:(scenario<5 || scenario==14)?2:
       (scenario==5 || scenario==6 || scenario==15)?23:
       (scenario==7 || scenario==8)?24:(scenario==9 || scenario==10)?25:0;
  nextline=(line==1)?2:(line==2)?1:(line==23)?24:(line==24)?25:0;
  red=(scenario==0)?15:(scenario==2)?40:(scenario==3)?64:
      (scenario==6 || scenario==7)?81:(scenario==8)?160:
      (scenario==9)?97:(scenario==10)?192:0;
  enable=(scenario!=4 && scenario!=14);
  card_enable=(scenario!=4 && scenario!=13 && scenario!=15);
  cur=line;nxt=nextline;sweep=red;
  if(cur!=oldcur) begin
   if(cur==oldnxt &&cur>0&&cur<26&&oldcur>0&&oldcur<26) slide=36;
   else slide=0;
  end else if(slide>3) slide=slide-3;else slide=0;
  oldcur=cur;oldnxt=nxt;
  @(negedge clk);vs=1;de=0;tick;
  @(negedge clk);vs=0;repeat(80) tick;
  for(y=0;y<480;y=y+1) begin
   for(x=0;x<640;x=x+1) begin
    @(negedge clk);de=1;rgb={8'(x),8'(y),8'(x^y)};
    if(scenario==0 && y==80 &&x==7)begin line=2;nextline=1;red=80;end
    tick;bg=rgb;ink=24'hFFFFFF;cov=0;r=0;gy=232+slide;len=length_of(cur);
    if(y>=144&&y<168)begin r=2;gy=144;len=4;ink=24'h1D3042;end
    else if(y>=268+slide)begin r=1;gy=268+slide;len=length_of(nxt);end
    leftedge=(r==2)?248:320-len*16;rel=x-leftedge;idx=rel/32;col=rel%32-5;row=y-gy-2;
    if((r==2?card_enable:enable) &&len>0&&x>=leftedge&&x<leftedge+len*32&&y>=gy+2&&y<gy+24&&
       col>=0&&col<22&&y<304) begin
     gid=(r==2)?26:(r==0)?cur:nxt;
     cov=(gid%2)?((col==row)?3:0):((col==21-row)?2:0);
     if(r==0&&sweep>0)begin
      cursor=sweep+4;
      if(rel+2<cursor)ink=24'hFF4040;
      else if(rel+1<cursor)ink=24'hFF7070;
      else if(rel<cursor)ink=24'hFFB8B8;
     end
    end
    expected={mix(bg[23:16],ink[23:16],cov),mix(bg[15:8],ink[15:8],cov),mix(bg[7:0],ink[7:0],cov)};
    if(out_rgb!==expected)$fatal(1,"smooth pixel s=%0d x=%0d y=%0d got=%h exp=%h slide=%0d",scenario,x,y,out_rgb,expected,slide);
    pixels=pixels+1;
   end
   @(negedge clk);de=0;repeat(scenario%3+1)tick;
   if(out_rgb!==rgb)$fatal(1,"blanking changed");
  end
 end
 $display("PASS smooth 24px overlay: %0d pixels, two-row credits, shared card title, independent gates, per-pixel red feather, line-slide, frame-atomic updates, 1/2/3 blanks, exact bypass",pixels);$finish;
end
initial begin #240000000;$fatal(1,"overlay timeout");end
endmodule
module lyric_line_rom(input I_clk,input [10:0] I_addr,input [7:0] I_line,I_next_line,
 output reg [7:0] O_char,output wire [4:0] O_length,O_next_length);
function [4:0] len(input [7:0] id);
 begin len=(id==1)?2:(id==2)?3:(id==22)?10:(id==23||id==24)?5:(id==25)?6:(id==26)?4:0;end
endfunction
assign O_length=len(I_line);assign O_next_length=len(I_next_line);
always @(posedge I_clk)O_char<=I_addr[10:5];
endmodule
module lyric_font_packed_rom(input I_clk,input [7:0] I_glyph,
 input [4:0] I_row,I_col,output reg [1:0] O_cov);
integer gid,pos,x,y;
always @(posedge I_clk)begin
 gid=I_glyph;x=I_col;y=I_row;
 O_cov<=(gid%2 &&x==y)?3:(!(gid%2)&&x==21-y)?2:0;
end
endmodule
