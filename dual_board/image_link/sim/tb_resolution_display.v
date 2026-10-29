`timescale 1ns/1ps
// The actual A sink publishes cache validity and dimensions as one VS bundle.
module tb_resolution_display;
reg clk=0,video_clk=0;
always #4 clk=~clk;
always #20 video_clk=~video_clk;
reg rst=1,start=0,complete=0,abort_frame=0,valid=0,packet_done=0,finish_toggle=0,vs=0;
reg [1:0] index=0;
reg [31:0] size=32'h050003c0;
wire req,ready;
wire [3:0] cache;
wire [127:0] resolutions;
wire [131:0] shown;
reg [3:0] usable_meta=0,usable_cache=0;
// Mirrors A's fast invalidation path and the display controller's two flops.
always @(posedge video_clk)begin
    if(rst)begin usable_meta<=0;usable_cache<=0;end
    else begin usable_meta<=shown[131:128]&cache;usable_cache<=usable_meta;end
end
integer cycles=0,video_cycles=0;
wire writer_ready=cycles%3!=0;
image_sdram_sink #(.FRAME_PACKETS(1),.RESOLUTION(1),.TIMEOUT_CYCLES(2000)) sink (
    .clk(clk),.rst(rst),.frame_start(start),.frame_complete(complete),.frame_abort(abort_frame),
    .frame_index(index),.frame_top_down(1'b1),.frame_resolution(size),
    .pixel_valid(valid),.pixel_rgb(24'd0),.pixel_tag(8'd0),.pixel_ready(ready),
    .packet_done(packet_done),.packet_token(32'd1),.packet_sequence(16'd0),
    .writer_ready(writer_ready),.writer_ack(req),.writer_finish_toggle(finish_toggle),.protected_buffers(4'd0),
    .write_req(req),.write_abort(),.write_en(),.write_data(),.write_index(),.write_top_down(),
    .receipt_event(),.receipt_token(),.receipt_sequence(),.cache_valid(cache),.source_resolutions(resolutions),
    .commit_toggle(),.receive_reset(),.fault());
audio_visual_cdc #(.WIDTH(132)) cdc (
    .udp_clk(clk),.video_clk(video_clk),.rst(rst),.frame_vs(vs),.update_valid(1'b0),
    .publish_enable(1'b1),.visual_state({cache,resolutions}),.frame_state(shown),.capture_valid());
always @(posedge clk)if(!rst)cycles=cycles+1;
always @(negedge video_clk)begin
    if(rst)begin video_cycles=0;vs=0;end
    else begin video_cycles=video_cycles+1;vs=video_cycles%31==0;end
end
reg [131:0] previous=0;
always @(posedge video_clk)begin
    #1;
    if(!rst)begin
        if(shown!==previous && !vs)$fatal(1,"size/cache changed outside VS");
        if(shown[128] && shown[31:0]!==32'h050003c0)$fatal(1,"picture 1 exposed with stale size");
        if(shown[131] && shown[127:96]!==32'h07800438)$fatal(1,"picture 4 exposed with stale size");
        if(shown[129])$fatal(1,"aborted picture exposed");
    end
    previous=shown;
end
task upload(input [1:0] idx,input [31:0] dimensions);
integer n;
begin
    @(negedge clk);index=idx;size=dimensions;start=1;
    @(negedge clk);start=0;
    while(!ready)@(negedge clk);
    valid=1;n=0;
    while(n<256)begin
        @(posedge clk);if(ready)n=n+1;
        @(negedge clk);
    end
    valid=0;complete=1;packet_done=1;
    @(negedge clk);complete=0;packet_done=0;
    repeat(100)@(negedge clk);
    if(cache[idx] || shown[128+idx] || resolutions[idx*32 +:32]!=0)$fatal(1,"size committed before SDRAM finish");
    finish_toggle=~finish_toggle;
    repeat(400)@(negedge clk);
    if(!cache[idx] || !shown[128+idx] || shown[idx*32 +:32]!==dimensions)$fatal(1,"size/cache commit missing");
end
endtask
initial begin
    repeat(8)@(negedge clk);rst=0;
    upload(0,32'h050003c0);upload(3,32'h07800438);
    index=1;size=32'h03200258;start=1;
    @(negedge clk);start=0;
    repeat(30)@(negedge clk);abort_frame=1;
    @(negedge clk);abort_frame=0;
    repeat(400)@(negedge clk);
    if(shown[131:128]!=4'b1001 || shown[63:32]!=0)$fatal(1,"abort corrupted committed metadata");
    // Reload a non-visible cached page: revoke eligibility before the next VS,
    // but do not expose the replacement size before its SDRAM completion.
    while(vs)@(negedge video_clk);
    @(negedge clk);index=3;start=1;
    @(negedge clk);start=0;
    repeat(3)@(negedge video_clk);
    if(usable_cache[3])$fatal(1,"invalidation waited for next VS");
    abort_frame=1;@(negedge clk);abort_frame=0;
    repeat(400)@(negedge clk);
    if(usable_cache!=1 || resolutions[127:96]!=32'h07800438)$fatal(1,"reload abort metadata retention");
    $display("PASS resolution display: actual sink, SDRAM finish gating, 125/25 MHz coherent cache+size CDC, VS-only update, fast invalidation and abort retention");$finish;
end
initial begin #1000000;$fatal(1,"resolution display timeout");end
endmodule
