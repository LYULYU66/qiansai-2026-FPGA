`timescale 1ns/1ps
module tb_audio_status_guard;
reg clk=0,rst=1,event_valid=0,manual=0;
always #4 clk=~clk;
reg [31:0] played=500;
reg [3:0] volume=5;
reg enabled=1;
wire req,valid;
wire [7:0] data;
wire [15:0] length;
reg ack=0;
audio_receipt_tx #(.EXTENDED(1),.PERIODIC_CYCLES(150)) tx (
    .clk(clk),.rst(rst),.event_valid(event_valid),.event_session(32'd9),.event_sequence(16'd42),
    .played_words(played),.volume_level(volume),.analysis_enable(enabled),
    .udp_ready(1'b1),.udp_ack(ack),.udp_request(req),.udp_valid(valid),.udp_data(data),.udp_length(length)
);
reg manual_valid=0;
reg [7:0] manual_data=0;
reg [15:0] manual_length=18;
wire receipt_valid,analysis_enable;
wire [31:0] receipt_session,played_words;
wire [15:0] sequence_no;
wire [3:0] volume_level;
audio_receipt_rx #(.EXTENDED(1)) rx (
    .clk(clk),.rst(rst),.rx_valid(manual ? manual_valid : valid),.rx_data(manual ? manual_data : data),
    .rx_length(manual ? manual_length : length),.receipt_valid(receipt_valid),
    .receipt_session(receipt_session),.receipt_sequence(sequence_no),.played_words(played_words),
    .volume_level(volume_level),.analysis_enable(analysis_enable)
);
integer receipts=0;
always @(posedge clk) begin ack<=req; if(receipt_valid) receipts=receipts+1; end
function [15:0] crc_byte;
    input [15:0] old_crc; input [7:0] value;
    reg [15:0] c; integer i;
    begin c=old_crc^{value,8'd0};
        for(i=0;i<8;i=i+1) c=c[15]?(c<<1)^16'h1021:c<<1;
        crc_byte=c;
    end
endfunction
task send;
    input [7:0] control,reserved,magic;
    input integer declared,bytes; input corrupt;
    reg [7:0] b; reg [15:0] c; integer k;
    begin
        manual_length=declared; c=16'hffff;
        for(k=0;k<bytes;k=k+1) begin
            case(k)
                0,1:b="A";2:b="K";3:b=magic;4:b=9;
                8:b=42;10:b=8'h84;11:b=3;14:b=control;15:b=reserved;
                16:b=c[15:8];17:b=c[7:0] ^ (corrupt ? 8'h01 : 0);
                default:b=0;
            endcase
            @(negedge clk); manual_valid=1;manual_data=b;
            if(k<16) c=crc_byte(c,b);
        end
        @(negedge clk); manual_valid=0;repeat(5) @(negedge clk);
    end
endtask
integer before_count;
initial begin
    repeat(10) @(negedge clk);rst=0;repeat(200) @(negedge clk);
    if(receipts!=0) $fatal(1,"status sends ACK before any verified audio");
    event_valid=1;@(negedge clk);event_valid=0;
    wait(receipt_valid);@(negedge clk);
    if(receipt_session!=9 || sequence_no!=42 || played_words!=500 || volume_level!=5 || !analysis_enable)
        $fatal(1,"AAK3 field encoding failure");
    played=900;volume=0;enabled=0;
    wait(receipt_valid && played_words==900);repeat(3) @(negedge clk);
    if(volume_level!=0 || analysis_enable) $fatal(1,"periodic control/head feedback missing");
    manual=1;before_count=receipts;
    send(8'h18,0,"3",18,18,0);
    if(receipts!=before_count+1 || played_words!=900 || volume_level!=8 || !analysis_enable)
        $fatal(1,"manual status valid packet failure got=%0d before=%0d head=%0d vol=%0d en=%0d",receipts,before_count,played_words,volume_level,analysis_enable);
    before_count=receipts;
    send(8'h19,0,"3",18,18,0);send(8'h98,0,"3",18,18,0);
    send(8'h18,1,"3",18,18,0);send(8'h18,0,"2",18,18,0);
    send(8'h18,0,"3",16,18,0);send(8'h18,0,"3",18,12,0);send(8'h18,0,"3",18,18,1);
    if(receipts!=before_count || volume_level!=8 || !analysis_enable)
        $fatal(1,"invalid status changed remote gain/head");
    $display("PASS audio status: AAK3 field packing, no premature ACK, periodic frozen-head controls, CRC/length/truncation/reserved/gain/magic guards");
    $finish;
end
initial begin #100000; $fatal(1,"status timeout");end
endmodule
