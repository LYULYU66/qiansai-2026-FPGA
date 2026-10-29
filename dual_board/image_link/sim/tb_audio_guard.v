`timescale 1ns/1ps
module tb_audio_guard;
reg clk=0, rst=1, valid=0, ready=0;
always #4 clk=~clk;
reg [7:0] data=0, bytes[0:529];
reg [15:0] length=530;
wire pcm_valid, stream_enable, fifo_reset, event_valid;
wire [31:0] pcm_data, file_samples, event_session;
wire [15:0] event_sequence;
audio_packet_rx dut (
    .clk(clk),.rst(rst),.rx_valid(valid),.rx_data(data),.rx_length(length),
    .pcm_ready(ready),.pcm_valid(pcm_valid),.pcm_data(pcm_data),.stream_enable(stream_enable),
    .file_samples(file_samples),.fifo_reset(fifo_reset),.receipt_event(event_valid),
    .stream_session(),
    .receipt_session(event_session),.receipt_sequence(event_sequence)
);
function [15:0] crc_byte;
    input [15:0] old_crc; input [7:0] value;
    reg [15:0] c; integer i;
    begin c=old_crc^{value,8'd0};
        for(i=0;i<8;i=i+1) c=c[15] ? (c<<1)^16'h1021 : c<<1;
        crc_byte=c;
    end
endfunction
task send;
    input [31:0] session_no;
    input [15:0] seq;
    input integer base, samples, bad_crc;
    reg [15:0] c; reg [31:0] word_value; integer i,j;
    begin
        bytes[0]="A"; bytes[1]="U"; bytes[2]="D"; bytes[3]="2";
        for(i=0;i<4;i=i+1) bytes[4+i]=session_no>>(8*i);
        bytes[8]=seq[7:0]; bytes[9]=seq[15:8]; bytes[10]=0; bytes[11]=0;
        for(i=0;i<4;i=i+1) bytes[12+i]=samples>>(8*i);
        for(i=0;i<128;i=i+1) begin
            word_value=32'ha5500000+base+i;
            for(j=0;j<4;j=j+1) bytes[16+i*4+j]=word_value>>(8*j);
        end
        c=16'hffff;
        for(i=0;i<528;i=i+1) c=crc_byte(c,bytes[i]);
        bytes[528]=c[15:8]; bytes[529]=c[7:0]^bad_crc;
        for(i=0;i<530;i=i+1) begin @(negedge clk); valid=1; data=bytes[i]; end
        @(negedge clk); valid=0;
        repeat(20) @(negedge clk);
    end
endtask
integer accepted=0, events=0, resets=0;
reg old_reset=1;
integer expected_base=0;
always @(posedge clk) if(!rst) begin
    old_reset<=fifo_reset;
    if(fifo_reset && !old_reset) resets=resets+1;
    if(pcm_valid && ready) begin
        if(pcm_data!==32'ha5500000+expected_base+accepted)
            $fatal(1,"busy retry overwrites PCM %0d got=%h",accepted,pcm_data);
        accepted=accepted+1;
    end
    if(event_valid) events=events+1;
end
initial begin
    repeat(5) @(negedge clk); rst=0;
    send(1,1,0,997,0); // no session can start at block 1
    send(1,0,0,997,1); // damaged first block
    send(1,0,0,0,0);   // invalid file size
    if(accepted!=0 || stream_enable) $fatal(1,"bad first block accepted");
    send(1,0,0,997,0);
    wait(pcm_valid); // writer paused while a retry tries to overwrite RAM
    send(1,0,9000,997,0);
    if(pcm_data!==32'ha5500000 || accepted!=0) $fatal(1,"stalled PCM changed");
    @(negedge clk); ready=1;
    wait(accepted==128); repeat(4) @(negedge clk);
    send(1,0,0,997,0);
    if(accepted!=128 || events!=2) $fatal(1,"duplicate was replayed or not ACKed");
    send(1,2,9000,997,0); // out of order
    length=529; send(1,1,9000,997,0); length=530;
    send(1,1,9000,998,0); // same session cannot change file metadata
    send(1,1,128,997,0); wait(accepted==256);
    // Deposit just the counter near wrap; do not simulate 65k identical blocks.
    @(negedge clk); dut.expected_sequence=16'hffff;
    send(1,16'hffff,256,997,0); wait(accepted==384);
    send(1,0,384,997,0); wait(accepted==512);
    if(resets!=0) $fatal(1,"sequence wrap incorrectly resets the stream");
    send(0,0,9000,997,0); // late packet from an older session
    send(2,1,9000,997,0); // new session must start at block 0
    if(accepted!=512 || resets!=0) $fatal(1,"stale session accepted");
    @(negedge clk); ready=0;
    send(2,0,10000,1998,0);
    wait(pcm_valid);
    accepted=0; expected_base=10000;
    @(negedge clk); ready=1;
    wait(accepted==128); repeat(4) @(negedge clk);
    if(file_samples!=1998 || event_session!=2 || events!=6 || resets!=1)
        $fatal(1,"new session/guard coverage failed events=%0d resets=%0d",events,resets);
    $display("PASS audio guard: bad CRC/length/metadata, busy duplicate, ordered drain, u16 wrap, stale-session rejection");
    $finish;
end
initial begin #500000; $fatal(1,"audio guard timeout"); end
endmodule

module tb_media_abort;
reg clk=0,rst=1,c0_request=0,c0_valid=0,c1_request=0,c1_valid=0;
always #4 clk=~clk;
reg [7:0] c0_data=0,c1_data=0;
wire c0_ack,c1_ack,request,valid;
wire [7:0] data;
wire [15:0] length;
reg ack=0,handled=0;
integer ack_delay=0;
media_udp_arbiter dut (
    .clk(clk),.rst(rst),.net_ready(1'b1),.net_ack(ack),.net_request(request),.net_valid(valid),.net_data(data),.net_length(length),
    .c0_request(c0_request),.c0_valid(c0_valid),.c0_data(c0_data),.c0_length(16'd20),.c0_ready(),.c0_ack(c0_ack),
    .c1_request(c1_request),.c1_valid(c1_valid),.c1_data(c1_data),.c1_length(16'd5),.c1_ready(),.c1_ack(c1_ack)
);
always @(posedge clk) begin
    ack<=0;
    if(!request) handled<=0;
    if(request && !handled) begin handled<=1; ack_delay<=3; end
    if(ack_delay!=0) begin ack_delay<=ack_delay-1; if(ack_delay==1) ack<=1; end
end
integer received0=0,received1=0;
reg [15:0] abort_crc=16'hffff;
function [15:0] crc_byte;
    input [15:0] old_crc; input [7:0] value;
    reg [15:0] c; integer j;
    begin c=old_crc^{value,8'd0};
        for(j=0;j<8;j=j+1) c=c[15] ? (c<<1)^16'h1021 : c<<1;
        crc_byte=c;
    end
endfunction
always @(posedge clk) if(valid) begin
    if(length==20) begin
        if(received0<18) begin
            if(data!==(received0<8 ? 8'ha0+received0 : 8'd0)) $fatal(1,"aborted packet padding wrong");
            abort_crc=crc_byte(abort_crc,data);
        end else if(received0==18) begin
            if(data!==abort_crc[15:8]) $fatal(1,"poison CRC high byte wrong");
        end else if(data!==(abort_crc[7:0]^8'h01)) $fatal(1,"aborted packet could pass CRC");
        received0=received0+1;
    end else if(length==5) begin
        if(received0!=20 || data!==8'hb0+received1) $fatal(1,"next packet starts before previous completes");
        received1=received1+1;
    end else $fatal(1,"invalid arbiter length");
end
integer i;
initial begin
    repeat(4) @(negedge clk); rst=0; c0_request=1;
    wait(c0_ack); @(negedge clk); c0_request=0;
    repeat(2) @(negedge clk);
    for(i=0;i<8;i=i+1) begin c0_valid=1; c0_data=8'ha0+i; @(negedge clk); end
    c0_valid=0; c1_request=1; // producer aborts after eight bytes
    wait(c1_ack); @(negedge clk); c1_request=0;
    repeat(2) @(negedge clk);
    for(i=0;i<5;i=i+1) begin c1_valid=1; c1_data=8'hb0+i; @(negedge clk); end
    c1_valid=0; repeat(10) @(negedge clk);
    if(received0!=20 || received1!=5 || dut.busy) $fatal(1,"arbiter wedged after local abort");
    $display("PASS media abort: finish UDP length, guaranteed bad CRC, next channel remains usable");
    $finish;
end
initial begin #10000; $fatal(1,"media abort timeout"); end
endmodule
