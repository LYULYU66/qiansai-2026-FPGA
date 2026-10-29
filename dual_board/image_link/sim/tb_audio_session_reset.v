`timescale 1ns/1ps
module tb_audio_session_reset;
reg clk=0;always #40.69 clk=~clk;
reg rst=1,fifo_reset=1,stream_enable=0;
reg [8:0] level=256;
wire [1:0] enable_sync;
wire read_sample,playing,bclk;
media_audio_enable_cdc sync_enable (
    .clk(clk),.fifo_reset(fifo_reset),.stream_enable(stream_enable),.enable_sync(enable_sync));
hdmi_audio_pcm_i2s_64fs #(.START_LEVEL(256)) serializer (
    .I_mclk(clk),.I_rst(rst),.I_enable(enable_sync[1]),.I_pcm_data(32'h1234abcd),
    .I_pcm_empty(1'b0),.I_pcm_level(level),.I_volume_level(4'd8),.O_pcm_read(read_sample),
    .O_i2s_BCLK(bclk),.O_i2s_LRCK(),.O_i2s_DOUT(),.O_playing(playing),.O_underflow());
integer reads=0,edges=0;
reg previous_bclk=0;
always @(posedge clk)if(!rst)begin
    if(read_sample)reads=reads+1;
    if(bclk!=previous_bclk)edges=edges+1;
    previous_bclk=bclk;
end
integer saved_reads,saved_edges,i;
initial begin
    repeat(8)@(negedge clk);rst=0;fifo_reset=0;stream_enable=1;
    wait(playing);repeat(40)@(negedge clk);
    // A packet receiver clears a session for 16*8 ns, less than two audio
    // clocks. Even with enable left high, this must clear previous O_playing.
    #13;fifo_reset=1;level=128;#128;fifo_reset=0;
    repeat(8)@(negedge clk);
    if(playing)$fatal(1,"previous session playback state survived short reset");
    saved_reads=reads;saved_edges=edges;repeat(800)@(negedge clk);
    if(playing || reads!=saved_reads || edges-saved_edges!=800)
        $fatal(1,"new session bypassed prebuffer or I2S clocks stopped");
    level=256;wait(playing);repeat(8)@(negedge clk);
    if(reads!=saved_reads+1)$fatal(1,"new session did not restart at prebuffer threshold");
    $display("PASS audio session reset: 128ns UDP flush observed at 12.288MHz, old playing cleared, 256-word prebuffer, uninterrupted I2S clocks");$finish;
end
initial begin #200000;$fatal(1,"audio session reset timeout");end
endmodule
