`timescale 1ns/1ps
module tb_bram32_font;
reg clk=0;always #20 clk=~clk;
reg [7:0] glyph=0;reg [4:0] row=0,col=0;
reg [10:0] char_addr=0;wire [7:0] char_data;
wire [4:0] current_length,next_length;
reg [7:0] char_reference[0:2047];
lyric_line_rom actual_chars(clk,char_addr,8'd0,8'd0,char_data,current_length,next_length);
wire [1:0] actual,expected;
wire [15:0] address=glyph*16'd484+row*16'd22+col;
lyric_font_packed_rom dut(clk,glyph,row,col,actual);
lyric_font_rom reference_font(clk,address,expected);
integer g,r,c,n,count=0;reg [31:0] rng=32'h2f6173a9;
task check;
begin @(posedge clk);#1;
 if(actual!==expected)$fatal(1,"Native BRAM32K mismatch glyph=%0d row=%0d col=%0d got=%0d expected=%0d",glyph,row,col,actual,expected);
 if(char_data!==char_reference[char_addr])$fatal(1,"Native character table mismatch addr=%0d got=%0d expected=%0d",char_addr,char_data,char_reference[char_addr]);
 count=count+1;
end endtask
initial begin
 $readmemh("assets/lyrics/char_bram32_reference.hex",char_reference);
 repeat(3)@(negedge clk);
 for(g=0;g<133;g=g+1)for(r=0;r<22;r=r+1)for(c=0;c<22;c=c+1)begin
  @(negedge clk);glyph=g;row=r;col=c;char_addr=count%2048;check();
 end
 for(n=0;n<64372;n=n+1)begin
  @(negedge clk);rng=(rng<<1)^((rng[31])?32'h04c11db7:32'd0);
  glyph=rng%133;row=(rng>>8)%22;col=(rng>>16)%22;char_addr=rng%2048;check();
 end
 $display("PASS native BRAM32K font and character table: %0d sequential/random reads each, every original coverage pixel, all 2048 character addresses, one-clock ports",count);$finish;
end
endmodule
