`timescale 1ns/1ps
// Full-rate producer stresses the readiness pipeline, not only quiet packets.
module tb_player_pipeline_guard;
reg udp_clk=0,clk=0,audio_clk=0,rst=1,sample_read=0;
always #4 udp_clk=~udp_clk;
always #20 clk=~clk;
always #40.667 audio_clk=~audio_clk;
always @(negedge audio_clk)sample_read=($random & 3)!=0;
function [31:0] pcm;
    input integer n;
    begin pcm={(16'h9876 ^ n[15:0]),(16'h1234 ^ n[15:0])};end
endfunction
integer sent=0,checked=0,cycles=0,max_occupancy=0,total_checked=0;
reg feedback_valid=0;
reg [31:0] feedback_played=0;
wire source_ready,settled;
wire [31:0] analysed;
remote_audio_compute #(.SAMPLE_GAP(16)) dut (
    .udp_clk(udp_clk),.clk(clk),.rst(rst),.session_id(32'd1),.file_samples(32'd997),
    .source_valid(sent<4096 && !rst),.source_pcm(pcm(sent)),.source_ready(source_ready),
    .feedback_valid(feedback_valid),.feedback_session(32'd1),.feedback_played(feedback_played),
    .feedback_volume(4'd8),.feedback_enable(1'b0),.visual_state(),.analysed_words(analysed),.settled(settled));
always @(posedge udp_clk)begin
    if(rst)begin sent<=0;cycles<=0;end
    else begin
        cycles<=cycles+1;
        if(sent<4096 && source_ready)sent<=sent+1;
    end
    #1;
    if(!rst)begin
        if((dut.written-dut.analysed)>896)$fatal(1,"history reserve violated: %0d",dut.written-dut.analysed);
        if((dut.written-dut.analysed)>max_occupancy)max_occupancy=dut.written-dut.analysed;
    end
end
always @(negedge udp_clk)begin
    feedback_valid=!rst && sent>=896 && cycles%17==0;
    feedback_played=dut.written;
end
always @(posedge clk)begin
    if(rst)checked=0;
    else if(dut.sample_valid)begin
        if(dut.analysed>=dut.written)$fatal(1,"future history read");
        if({dut.right_scaled,dut.left_scaled}!==pcm(checked))$fatal(1,"history overwrite/order at %0d",checked);
        checked=checked+1;total_checked=total_checked+1;
    end
end
function [31:0] decode;
    input [31:0] g;
    integer k;
    begin for(k=0;k<32;k=k+1)decode[k]=^(g>>k);end
endfunction
wire [31:0] played;
reg [31:0] oracle_count=0,oracle_g0=0,oracle_g1=0,oracle_played=0;
audio_playback_progress u_progress (.audio_clk(audio_clk),.udp_clk(udp_clk),.rst(rst),.sample_read(sample_read),.played_words(played));
always @(posedge audio_clk or posedge rst)
    if(rst)oracle_count<=0;else if(sample_read)oracle_count<=oracle_count+1;
always @(posedge udp_clk or posedge rst)begin
    if(rst)begin oracle_g0<=0;oracle_g1<=0;oracle_played<=0;end
    else begin oracle_g0<=(oracle_count>>1)^oracle_count;oracle_g1<=oracle_g0;oracle_played<=decode(oracle_g1);end
end
always @(negedge udp_clk)if(played!==oracle_played)$fatal(1,"registered playback decode/reset mismatch");
initial begin
    repeat(10)@(negedge udp_clk);rst=0;
    wait(sent>=1000);#3 rst=1;
    repeat(16)@(negedge udp_clk);#1 rst=0;
    wait(analysed==4096);wait(settled);repeat(20)@(negedge udp_clk);
    if(checked!=4096 || max_occupancy!=896)$fatal(1,"missing capacity/order stress");
    $display("PASS player pipeline guard: full-rate bursts preserve 896/1024 history capacity, sample order and reset; registered playback Gray decode matches oracle (%0d samples checked)",total_checked);
    $finish;
end
initial begin #30000000;$fatal(1,"pipeline guard timeout sent=%0d analysed=%0d",sent,analysed);end
endmodule
