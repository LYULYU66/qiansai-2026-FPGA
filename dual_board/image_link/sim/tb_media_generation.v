`timescale 1ns/1ps
module tb_media_generation;
reg clk=0;always #4 clk=~clk;
reg rst=1,iv=0,av=0;
reg [15:0] generation=16'h1234;
reg [7:0] data=0;
wire pv,done,pcm_valid,stream_enable;
wire [31:0] session;
integer pixels=0,packets=0,samples=0;
image_packet_rx #(.FRAME_PACKETS(4),.RELIABLE(1),.UI_TAG(1),.RESOLUTION(1),.SESSION_GUARD(1)) image (
    .clk(clk),.rst(rst),.generation(generation),.rx_valid(iv),.rx_data(data),.rx_length(16'd1042),
    .pixel_ready(1'b1),.pixel_valid(pv),.pixel_rgb(),.pixel_tag(),.frame_index(),.frame_top_down(),
    .frame_resolution(),.frame_start(),.frame_complete(),.frame_abort(),.good_packets(),.bad_packets(),
    .packet_done(done),.packet_duplicate(),.packet_token(),.packet_sequence());
audio_packet_rx #(.SESSION_GUARD(1)) audio (
    .clk(clk),.rst(rst),.generation(generation),.rx_valid(av),.rx_data(data),.rx_length(16'd530),
    .pcm_ready(1'b1),.pcm_valid(pcm_valid),.pcm_data(),.stream_enable(stream_enable),.file_samples(),
    .stream_session(session),.fifo_reset(),.receipt_event(),.receipt_session(),.receipt_sequence());
always @(posedge clk)if(!rst)begin
    if(pv)pixels=pixels+1;if(done)packets=packets+1;if(pcm_valid)samples=samples+1;
end
function [15:0] crc_byte(input [15:0] old_crc,input [7:0] value);
reg [15:0] c;integer i;
begin c=old_crc^{value,8'd0};for(i=0;i<8;i=i+1)c=c[15]?(c<<1)^16'h1021:c<<1;crc_byte=c;end
endfunction
task packet(input integer is_audio,input [31:0] token,input [15:0] seq);
reg [7:0] bytes[0:1041];reg [15:0] crc;integer i,n;
begin
    n=is_audio?530:1042;for(i=0;i<n;i=i+1)bytes[i]=i;
    if(is_audio)begin
        bytes[0]="A";bytes[1]="U";bytes[2]="D";bytes[3]="2";
        for(i=0;i<4;i=i+1)bytes[4+i]=token>>(8*i);
        bytes[8]=seq[7:0];bytes[9]=seq[15:8];bytes[10]=0;bytes[11]=0;
        bytes[12]=0;bytes[13]=4;bytes[14]=0;bytes[15]=0;
    end else begin
        bytes[0]="I";bytes[1]="M";bytes[2]="G";bytes[3]="4";
        bytes[4]=1;bytes[5]=seq[7:0];bytes[6]=seq[15:8];bytes[7]=1;
        for(i=0;i<4;i=i+1)bytes[8+i]=token>>(8*i);
        bytes[12]=0;bytes[13]=5;bytes[14]=8'hc0;bytes[15]=3;
    end
    crc=16'hffff;for(i=0;i<n-2;i=i+1)crc=crc_byte(crc,bytes[i]);
    bytes[n-2]=crc[15:8];bytes[n-1]=crc[7:0];
    for(i=0;i<n;i=i+1)begin @(negedge clk);iv=!is_audio;av=is_audio;data=bytes[i];end
    @(negedge clk);iv=0;av=0;repeat(1400)@(negedge clk);
end
endtask
initial begin
    repeat(8)@(negedge clk);rst=0;
    packet(0,32'h12330001,0);packet(1,32'h12330001,0);
    if(pixels || packets || samples || stream_enable)$fatal(1,"old generation accepted after reset");
    packet(0,32'h12340001,0);packet(1,32'h12340001,0);
    if(pixels!=256 || packets!=1 || samples!=128 || session!=32'h12340001)
        $fatal(1,"current generation rejected pixels=%0d packets=%0d samples=%0d session=%h incoming=%h header=%0d state=%0d",pixels,packets,samples,session,audio.incoming_session,audio.header_ok,audio.state);
    generation=16'h1235;
    packet(0,32'h12340001,0);packet(1,32'h12340001,1);
    if(pixels!=256 || packets!=1 || samples!=128)$fatal(1,"old duplicate accepted");
    rst=1;repeat(4)@(negedge clk);rst=0;
    packet(0,32'h12350001,0);packet(1,32'h12350001,0);
    if(pixels!=512 || packets!=2 || samples!=256)$fatal(1,"new generation after local reset");
    $display("PASS media generation: whole IMG4/AUD2 CRC packets, stale first/duplicate, new session after reset");$finish;
end
initial begin #1000000;$fatal(1,"generation guard timeout");end
endmodule

module tb_cache_recovery;
reg clk=0;always #4 clk=~clk;
reg rst=1,restart=0,start=0,pv=0,complete=0,finish=0;
reg [1:0] idx=2;
wire req,we,abort_write;
wire [3:0] cache;
wire [127:0] sizes;
integer writes=0;
image_sdram_sink #(.FRAME_PACKETS(1),.TIMEOUT_CYCLES(2000),.RESOLUTION(1),.RECOVERY(1)) dut (
    .clk(clk),.rst(rst),.restart_transfer(restart),.frame_start(start),.frame_complete(complete),.frame_abort(1'b0),
    .frame_index(idx),.frame_top_down(1'b1),.frame_resolution(32'h050003c0),
    .pixel_valid(pv),.pixel_rgb(24'habcdef),.pixel_tag(8'd0),.pixel_ready(),
    .packet_done(complete),.packet_token(32'h12340001),.packet_sequence(16'd0),
    .writer_ready(1'b1),.writer_ack(req),.writer_finish_toggle(finish),.protected_buffers(4'b0100),
    .write_req(req),.write_abort(abort_write),.write_en(we),.write_data(),.write_index(),.write_top_down(),
    .receipt_event(),.receipt_token(),.receipt_sequence(),.cache_valid(cache),.source_resolutions(sizes),
    .commit_toggle(),.receive_reset(),.fault());
always @(posedge clk)if(we)writes=writes+1;
initial begin
    repeat(8)@(negedge clk);rst=0;
    idx=1;start=1;@(negedge clk);start=0;wait(dut.pixel_ready);
    @(negedge clk);pv=1;repeat(256)@(negedge clk);pv=0;complete=1;
    @(negedge clk);complete=0;finish=1;repeat(10)@(negedge clk);
    if(cache!=2 || sizes[63:32]!=32'h050003c0 || writes!=256)$fatal(1,"setup frame did not commit");
    idx=0;start=1;@(negedge clk);start=0;wait(dut.pixel_ready);
    @(negedge clk);pv=1;repeat(12)@(negedge clk);restart=1;repeat(20)@(negedge clk);
    if(req || we || !abort_write || cache!=2 || sizes[63:32]!=32'h050003c0 || writes!=268)
        $fatal(1,"recovery erased committed page or leaked partial writes");
    pv=0;restart=0;repeat(4)@(negedge clk);
    if(dut.state!=0 || cache!=2)$fatal(1,"sink not reusable after restart");
    idx=2;start=1;@(negedge clk);start=0;repeat(5)@(negedge clk);
    if(req || we || cache!=2 || !dut.fault)$fatal(1,"recovery bypassed protected buffer");
    $display("PASS cache recovery: committed metadata survives, partial transfer aborted, writes blocked, visible buffer protected");$finish;
end
initial begin #100000;$fatal(1,"cache recovery timeout");end
endmodule
