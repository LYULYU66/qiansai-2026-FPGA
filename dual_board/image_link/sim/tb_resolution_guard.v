`timescale 1ns/1ps
module tb_resolution_guard;
reg clk=0;always #4 clk=~clk;
reg rst=1,valid=0;
reg [7:0] data=0;
reg [15:0] length=1042;
wire frame_start,done,pixel_valid;
wire [31:0] resolution;
wire [15:0] bad;
integer starts=0,packets=0,pixels=0;
image_packet_rx #(.FRAME_PACKETS(4),.RELIABLE(1),.UI_TAG(1),.RESOLUTION(1)) dut(
    .clk(clk),.rst(rst),.rx_valid(valid),.rx_data(data),.rx_length(length),.pixel_ready(1'b1),
    .pixel_valid(pixel_valid),.pixel_rgb(),.pixel_tag(),.frame_index(),.frame_top_down(),
    .frame_resolution(resolution),.frame_start(frame_start),.frame_complete(),.frame_abort(),
    .good_packets(),.bad_packets(bad),.packet_done(done),.packet_duplicate(),.packet_token(),.packet_sequence());
always @(posedge clk) if(!rst)begin
    if(frame_start)starts=starts+1;
    if(done)packets=packets+1;
    if(pixel_valid)pixels=pixels+1;
end
function [15:0] crc_byte(input [15:0] old_crc,input [7:0] value);
reg [15:0] c;integer i;
begin c=old_crc^{value,8'd0};for(i=0;i<8;i=i+1)c=c[15]?(c<<1)^16'h1021:c<<1;crc_byte=c;end
endfunction
task packet(input [15:0] seq,input [31:0] size,input integer mode);
reg [7:0] bytes[0:1041];reg [15:0] crc;integer i;
begin
    bytes[0]="I";bytes[1]="M";bytes[2]="G";bytes[3]="4";
    bytes[4]=1;bytes[5]=seq[7:0];bytes[6]=seq[15:8];bytes[7]=1;
    bytes[8]=1;bytes[9]=0;bytes[10]=0;bytes[11]=0;
    bytes[12]=size[23:16];bytes[13]=size[31:24];bytes[14]=size[7:0];bytes[15]=size[15:8];
    for(i=16;i<1040;i=i+1)bytes[i]=i;
    crc=16'hffff;for(i=0;i<1040;i=i+1)crc=crc_byte(crc,bytes[i]);
    bytes[1040]=crc[15:8];bytes[1041]=crc[7:0]^(mode==1);
    length=mode==3?1038:1042;
    for(i=0;i<(mode==2?500:1042);i=i+1)begin @(negedge clk);valid=1;data=bytes[i];end
    @(negedge clk);valid=0;repeat(540)@(negedge clk);
end
endtask
initial begin
    repeat(5)@(negedge clk);rst=0;
    packet(0,32'h027f01e0,0);packet(0,32'h028001df,0);
    packet(0,32'h050003c0,1);packet(0,32'h050003c0,2);packet(0,32'h050003c0,3);
    if(starts!=0 || packets!=0 || pixels!=0 || bad!=5)$fatal(1,"invalid resolution packet accepted");
    packet(0,32'h050003c0,0);
    if(resolution!==32'h050003c0 || starts!=1 || pixels!=256)$fatal(1,"valid metadata/pixels");
    packet(0,32'h07800438,0); // wrong dimensions on a duplicate
    packet(1,32'h07800438,0); // wrong dimensions mid-frame
    if(starts!=1 || packets!=1 || pixels!=256 || bad!=7)$fatal(1,"inconsistent size accepted");
    packet(0,32'h050003c0,0); // unchanged duplicate is re-ACKed, not written twice
    if(packets!=2 || pixels!=256)$fatal(1,"duplicate not safely ACKed");
    packet(1,32'h050003c0,0);
    if(packets!=3 || pixels!=512 || resolution!==32'h050003c0)$fatal(1,"retry recovery");
    $display("PASS resolution guard: lower-bound, CRC, truncation, length, duplicate/mid-frame consistency, retry, no damaged pixels");$finish;
end
endmodule
