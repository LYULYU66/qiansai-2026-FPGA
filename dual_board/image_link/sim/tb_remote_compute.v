`timescale 1ns/1ps
module tb_remote_compute;
reg clk=0, udp_clk=0, rst=1;
always #20 clk=~clk;
always #4 udp_clk=~udp_clk;
reg [31:0] session_id=1, file_samples=10043560;
reg source_valid=0, feedback_valid=0, feedback_enable=1;
reg [31:0] source_pcm=0, feedback_session=1, feedback_played=0;
reg [3:0] feedback_volume=8;
wire source_ready, settled;
wire [263:0] visual_state;
wire [31:0] analysed;
remote_audio_compute dut (
    .udp_clk(udp_clk),.clk(clk),.rst(rst),.session_id(session_id),.file_samples(file_samples),
    .source_valid(source_valid),.source_pcm(source_pcm),.source_ready(source_ready),
    .feedback_valid(feedback_valid),.feedback_session(feedback_session),.feedback_played(feedback_played),
    .feedback_volume(feedback_volume),.feedback_enable(feedback_enable),
    .visual_state(visual_state),.analysed_words(analysed),.settled(settled)
);
integer written=0, checked=0, gain;
function [31:0] sample_word;
    input integer n;
    reg signed [15:0] l,r;
    begin l=((n*773)%60000)-30000; r=((n*379)%54000)-27000; sample_word={r,l}; end
endfunction
function signed [15:0] scale;
    input signed [15:0] s; input [3:0] g;
    reg signed [18:0] x,y;
    begin x=s;
        case(g)
            0:y=0;1:y=x>>>3;2:y=x>>>2;3:y=(x>>>2)+(x>>>3);
            4:y=x>>>1;5:y=(x>>>1)+(x>>>3);6:y=(x>>>1)+(x>>>2);
            7:y=x-(x>>>3);default:y=x;
        endcase
        scale=y[15:0];
    end
endfunction
task push;
    input integer words; integer k;
    begin for(k=0;k<words;k=k+1) begin
        @(negedge udp_clk); if(!source_ready) $fatal(1,"unexpected history full");
        source_valid=1; source_pcm=sample_word(written); written=written+1;
    end
    @(negedge udp_clk); source_valid=0;
    end
endtask
task feedback;
    input [31:0] head, sess; input [3:0] vol; input en;
    begin
        @(negedge udp_clk); feedback_played=head; feedback_session=sess;
        feedback_volume=vol; feedback_enable=en; feedback_valid=1;
        @(negedge udp_clk); feedback_valid=0;
    end
endtask
task drain;
    input integer wanted;
    begin wait(analysed==wanted); wait(settled); repeat(16) @(negedge clk); end
endtask
wire [31:0] raw=sample_word(checked);
reg [3:0] reference_volume=8;
wire [15:0] expected_left=scale($signed(raw[15:0]),reference_volume);
wire [15:0] expected_right=scale($signed(raw[31:16]),reference_volume);
integer cycles=0,last_sample=-1000;
wire [31:0] remaining=dut.target-analysed;
wire [31:0] available=dut.written_local-analysed;
always @(posedge clk) begin
    cycles=cycles+1;
    if(rst) checked<=0;
    else begin
        if(dut.state==1) reference_volume<=dut.volume;
        if(dut.sample_valid) begin
            if(cycles-last_sample<256) $fatal(1,"analysis input too fast");
            last_sample=cycles;
            if(remaining==0 || remaining[31] || available==0 || available[31])
                $fatal(1,"future/unwritten sample read");
            if(dut.enabled && dut.u_spectrum.state!=0) $fatal(1,"Goertzel drops an input sample");
            if({dut.right_scaled,dut.left_scaled}!=={expected_right,expected_left})
                $fatal(1,"PCM/gain/order mismatch n=%0d gain=%0d",checked,reference_volume);
            checked<=checked+1;
        end
    end
end
initial begin
    repeat(10) @(negedge udp_clk); rst=0;
    push(896); repeat(20) @(negedge udp_clk);
    if(source_ready || analysed!=0) $fatal(1,"history backpressure/free-run failure");
    feedback(128,2,8,1); repeat(600) @(negedge clk);
    if(analysed!=0) $fatal(1,"wrong-session feedback accepted");
    feedback(897,1,8,1); repeat(600) @(negedge clk);
    if(analysed!=0) $fatal(1,"ahead-of-source feedback accepted");
    feedback(512,1,8,1); drain(512);
    for(gain=7;gain>=0;gain=gain-1) begin
        push(512); feedback(written-384,1,gain[3:0],1); drain(written-384);
    end
    if(checked!=4608) $fatal(1,"not all gain/wrap samples covered");
    feedback(analysed-1,1,8,0); repeat(600) @(negedge clk);
    if(dut.volume!=0 || !dut.enabled) $fatal(1,"stale progress changes controls");
    feedback(analysed,1,0,0); repeat(600) @(negedge clk);
    if(visual_state[237:0]!=0) $fatal(1,"disabled analysis not cleared");
    // Timeline advances on consumed samples even when the analyzer is asleep.
    if(dut.u_lyrics.sample_count!=4608) $fatal(1,"lyric count differs from playback");
    @(negedge clk);
    dut.u_lyrics.sample_count=24'd10043558;
    dut.u_lyrics.event_index=511; dut.u_lyrics.due_valid=0;
    dut.u_lyrics.rate=0; dut.u_lyrics.div_busy=0;
    feedback(4610,1,8,0); drain(4610);
    if(dut.u_lyrics.sample_count!=0 || visual_state[245:238]!=22 || visual_state[253:246]!=23)
        $fatal(1,"exact song EOF did not return to intro");
    rst=1; repeat(20) @(negedge udp_clk);
    written=0; session_id=2; file_samples=997; rst=0;
    push(32); feedback(32,1,8,1); repeat(600) @(negedge clk);
    if(analysed!=0) $fatal(1,"old session survived restart");
    feedback(32,2,8,1); drain(32);
    if(dut.u_lyrics.sample_count!=0 || visual_state[263:238]!=0)
        $fatal(1,"wrong PCM file has lyrics");
    // Deposit a near-wrap epoch to test serial counters without 24h playback.
    rst=1; repeat(20) @(negedge udp_clk); session_id=3; written=0; rst=0;
    repeat(30) @(negedge clk);
    dut.written=32'hfffffff0; dut.written_gray=(32'hfffffff0>>1)^32'hfffffff0;
    dut.analysed=32'hfffffff0; dut.analysed_gray=(32'hfffffff0>>1)^32'hfffffff0;
    dut.written_g0=dut.written_gray; dut.written_g1=dut.written_gray;
    dut.analysed_g0=dut.analysed_gray; dut.analysed_g1=dut.analysed_gray;
    dut.controls_udp={32'hfffffff0,4'd8,1'b0};
    dut.u_controls_cdc.mailbox=dut.controls_udp;
    dut.u_controls_cdc.frame_state=dut.controls_udp;
    repeat(40) @(negedge clk);
    push(24); feedback(8,3,8,1); drain(8);
    if(checked!=24) $fatal(1,"32-bit sample counter wrap failed");
    $display("PASS remote compute: 25/125 MHz history CDC, backpressure, 0-8 gains, RAM/32-bit wrap, invalid/stale/session guards, underflow freeze, lyric count and exact EOF");
    $finish;
end
initial begin #150000000; $fatal(1,"remote compute timeout n=%0d",analysed); end
endmodule
