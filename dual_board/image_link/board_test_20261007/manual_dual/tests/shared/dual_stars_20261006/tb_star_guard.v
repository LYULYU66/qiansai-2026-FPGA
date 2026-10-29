`timescale 1ns/1ps
module tb_star_guard;
reg clk=0;always #4 clk=~clk;
reg rst=1,valid=0;
reg [7:0] data=0;
reg [15:0] length=14;
wire update;wire [7:0] settings;wire [15:0] phase;
integer accepted=0;
media_control_rx #(.STAR_SYNC(1),.REBASE_CYCLES(1000)) dut(.clk(clk),.rst(rst),
 .rx_valid(valid),.rx_data(data),.rx_length(length),.update_valid(update),.settings(settings),.star_phase(phase));
always @(posedge clk)if(update)accepted=accepted+1;
function [15:0] crc_byte(input [15:0] old,input [7:0] b);
reg [15:0] c;integer i;
begin c=old^{b,8'd0};for(i=0;i<8;i=i+1)c=c[15]?(c<<1)^16'h1021:c<<1;crc_byte=c;end
endfunction
task packet(input [31:0] seq,input [7:0] s,input [15:0] ph,input integer mode);
reg [7:0] p[0:14];reg [15:0] crc;integer i;
begin
 p[0]="C";p[1]="T";p[2]="L";p[3]=mode==5 ? "2" : "3";
 p[4]=seq[7:0];p[5]=seq[15:8];p[6]=seq[23:16];p[7]=seq[31:24];
 p[8]=s;p[9]=ph[7:0];p[10]=ph[15:8];p[11]=mode==2 ? 1 : 0;
 crc=16'hffff;for(i=0;i<12;i=i+1)crc=crc_byte(crc,p[i]);
 p[12]=crc[15:8];p[13]=crc[7:0]^(mode==1);p[14]=0;
 length=mode==3 ? 12 : 14;
 for(i=0;i<(mode==4 ? 11 : (mode==6 ? 15 : 14));i=i+1)begin
  @(negedge clk);valid=1;data=p[i];end
 @(negedge clk);valid=0;repeat(4)@(negedge clk);
end
endtask
integer i;
initial begin
 repeat(5)@(negedge clk);rst=0;
 packet(100,8'hb4,12345,0);
 if(accepted!=1 || settings!=8'hb4 || phase!=12345)$fatal(1,"CTL3 valid baseline");
 for(i=1;i<=6;i=i+1)packet(101,8'h38,18000,i);
 packet(101,8'h39,18000,0);packet(101,8'h38,20480,0);
 packet(101,8'h38,65535,0);packet(99,8'h38,0,0);
 if(accepted!=1 || settings!=8'hb4 || phase!=12345)$fatal(1,"malformed/stale star phase applied");
 packet(101,8'hd0,20479,0);packet(102,8'hd8,0,0);
 if(accepted!=3 || phase!=0 || settings!=8'hd8)$fatal(1,"phase wrap or controls");
 packet(0,8'h38,9000,0);if(accepted!=3)$fatal(1,"restart bypassed sequence ordering");
 repeat(1000)@(negedge clk);
 if(phase!=0 || settings!=8'hd8)$fatal(1,"timeout changed state");
 packet(0,8'h38,9000,0);
 if(accepted!=4 || phase!=9000)$fatal(1,"B restart rebase failed");
 $display("PASS CTL3 guard: CRC, reserved, legacy magic, lengths, truncation/extra bytes, volume/phase bounds, stale sequence, phase wrap and B restart rebase");
 $finish;
end
endmodule
