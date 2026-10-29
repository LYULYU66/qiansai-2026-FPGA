`timescale 1ns/1ps
module tb_player_domain_resets;
reg clk=0,run_clock=1,request=1;
always #4 if(run_clock)clk=~clk;
wire rst;
player_domain_reset dut(.clk(clk),.request(request),.rst(rst));
integer edges=0,n,assertions=0;
always @(posedge clk)begin
    if(request)edges=0;else edges=edges+1;
    #0.01;if(rst!==(request || edges<2))$fatal(1,"local reset release not second clock edge");
end
always @(posedge request)begin edges=0;#0.01;
    if(rst!==1)$fatal(1,"reset must assert without clock");assertions=assertions+1;end
initial begin
    #1;request=0;wait(!rst);
    for(n=0;n<32;n=n+1)begin
        @(negedge clk);#(0.25*n+0.05);request=1;#0.20;request=0;
        wait(!rst);@(negedge clk);
    end
    @(negedge clk);run_clock=0;#3;request=1;#0.5;request=0;#80;
    if(rst!==1)$fatal(1,"reset released with stopped clock");
    run_clock=1;wait(!rst);
    $display("PASS player domain resets: 32 phase offsets, short pulses, stopped clock and exact synchronous release");$finish;
end
initial begin #10000;$fatal(1,"domain reset timeout");end
endmodule

module tb_player_audio_metadata;
reg clk=0,rst=1,stream=0;
always #4 clk=~clk;
reg [15:0] generation=16'h1234;
reg [31:0] bytes=0;
wire active;
wire [31:0] session,samples;
player_audio_session dut(.clk(clk),.rst(rst),.stream_async(stream),.generation(generation),
    .file_bytes_async(bytes),.stream_active(active),.session_id(session),.file_samples(samples));
integer n;
task start;
    input [31:0] size;
    input [31:0] token;
    begin
        bytes=size;repeat(4)@(negedge clk);stream=1;
        wait(active);#0.01;
        if(samples!==size>>2 || session!==token)$fatal(1,"session/length not atomically committed");
        // A later live bus change must never change the current song length.
        for(n=0;n<50;n=n+1)begin @(negedge clk);bytes=$random;
            #0.01;if(samples!==size>>2 || session!==token)$fatal(1,"metadata torn/changed during stream");end
    end
endtask
initial begin
    repeat(4)@(negedge clk);rst=0;
    start(32'd40174240,32'h12340001);
    stream=0;wait(!active);repeat(4)@(negedge clk);
    start(32'd8000,32'h12340002);
    rst=1;#0.01;if(active!==0 || samples!==0 || session!==0)$fatal(1,"metadata reset");
    stream=0;repeat(3)@(negedge clk);rst=0;generation=16'h4321;
    start(32'd16384,32'h43210001);
    $display("PASS player audio metadata: coherent length/session, stream restart, stable song length and generation reset");$finish;
end
initial begin #10000;$fatal(1,"metadata test timeout");end
endmodule
