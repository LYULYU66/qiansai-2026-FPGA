`timescale 1ns/1ps
module tb_control_guard;
reg clk=0;always #4 clk=~clk;
reg rst=1,valid=0;
reg [7:0] data=0;
reg [15:0] length=12;
wire update_valid;
wire [7:0] settings;
integer accepted=0;
media_control_rx #(.REBASE_CYCLES(500)) dut (.clk(clk),.rst(rst),.rx_valid(valid),.rx_data(data),.rx_length(length),
    .update_valid(update_valid),.settings(settings));
always @(posedge clk) if(!rst && update_valid) accepted=accepted+1;
function [15:0] crc_byte(input [15:0] old_crc,input [7:0] value);
reg [15:0] c;integer i;
begin c=old_crc^{value,8'd0};for(i=0;i<8;i=i+1)c=c[15]?(c<<1)^16'h1021:c<<1;crc_byte=c;end
endfunction
task packet(input [31:0] seq,input [7:0] s,input integer mode);
reg [7:0] bytes[0:11];reg [15:0] crc;integer i;
begin
    bytes[0]="C";bytes[1]="T";bytes[2]="L";bytes[3]="2";
    bytes[4]=seq[7:0];bytes[5]=seq[15:8];bytes[6]=seq[23:16];bytes[7]=seq[31:24];
    bytes[8]=s;bytes[9]=(mode==2)?1:0;
    if(mode==5)bytes[0]="X";
    crc=16'hffff;for(i=0;i<10;i=i+1)crc=crc_byte(crc,bytes[i]);
    bytes[10]=crc[15:8];bytes[11]=crc[7:0]^(mode==1);
    length=mode==3?13:12;
    for(i=0;i<(mode==4?9:12);i=i+1) begin @(negedge clk);valid=1;data=bytes[i];end
    @(negedge clk);valid=0;repeat(4)@(negedge clk);
end
endtask
initial begin
    repeat(5)@(negedge clk);rst=0;
    packet(100,8'hb4,0);if(settings!==8'hb4 || accepted!=1)$fatal(1,"first control");
    packet(101,8'h38,1);packet(101,8'h38,2);packet(101,8'h38,3);packet(101,8'h38,4);packet(101,8'h38,5);
    packet(101,8'h39,0);packet(99,8'h38,0);
    if(settings!==8'hb4 || accepted!=1)$fatal(1,"bad/stale control applied");
    packet(101,8'hc2,0);if(settings!==8'hc2 || accepted!=2)$fatal(1,"valid new control");
    // A B-only restart sends sequence 0. Hold until expiry, then rebase.
    packet(0,8'h38,0);if(accepted!=2)$fatal(1,"early restart bypassed ordering");
    repeat(500)@(negedge clk);if(settings!==8'hc2)$fatal(1,"timeout changed state");
    packet(0,8'h38,0);if(settings!==8'h38 || accepted!=3)$fatal(1,"restart rebase failed");
    rst=1;repeat(4)@(negedge clk);rst=0;
    packet(32'hfffffffe,8'h25,0);packet(32'hffffffff,8'h14,0);packet(0,8'hb2,0);
    if(settings!==8'hb2 || accepted!=6)$fatal(1,"sequence wrap failed");
    $display("PASS control guard: CRC, reserved, length, truncation, magic, bounds, ordering, link-loss hold, B restart rebase, sequence wrap");$finish;
end
endmodule
