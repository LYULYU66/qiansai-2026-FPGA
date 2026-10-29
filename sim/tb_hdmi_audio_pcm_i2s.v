`timescale 1ns/1ps

module tb_hdmi_audio_pcm_i2s;

reg mclk = 1'b0;
reg video_clk = 1'b0;
reg rst = 1'b1;
reg enable = 1'b0;
reg pcm_empty = 1'b0;
reg [8:0] pcm_level = 9'd1;
reg [3:0] volume_level = 4'd8;
wire pcm_read;
wire i2s_bclk;
wire i2s_lrck;
wire i2s_dout;
wire playing;
wire underflow;
wire audio_valid;
wire [23:0] audio_left;
wire [23:0] audio_right;
integer valid_count = 0;
integer read_count = 0;

// 12.288 MHz audio master clock and 25 MHz video clock.
always #40.690 mclk = ~mclk;
always #20.000 video_clk = ~video_clk;

hdmi_audio_pcm_i2s_64fs #(
    .START_LEVEL(1)
) dut (
    .I_mclk(mclk),
    .I_rst(rst),
    .I_enable(enable),
    .I_pcm_data({16'hfedc, 16'h1234}),
    .I_pcm_empty(pcm_empty),
    .I_pcm_level(pcm_level),
    .I_volume_level(volume_level),
    .O_pcm_read(pcm_read),
    .O_i2s_BCLK(i2s_bclk),
    .O_i2s_LRCK(i2s_lrck),
    .O_i2s_DOUT(i2s_dout),
    .O_playing(playing),
    .O_underflow(underflow)
);

I2S_receiver receiver (
    .I_clk(video_clk),
    .I_rst(rst),
    .I_i2s_BCLK(i2s_bclk),
    .I_i2s_LRCK(i2s_lrck),
    .I_i2s_DOUT(i2s_dout),
    .O_audio_valid(audio_valid),
    .O_audio_left_data(audio_left),
    .O_audio_right_data(audio_right)
);

always @(posedge mclk)
    if (pcm_read)
        read_count <= read_count + 1;

always @(posedge video_clk) begin
    if (audio_valid) begin
        valid_count <= valid_count + 1;
        // Check PCM words only while the PCM source is active.  During the
        // deliberate underflow interval the serializer correctly emits zero.
        if ((valid_count >= 1) && playing) begin
            if (audio_left !== 24'h123400)
                $fatal(1, "left channel mismatch got=%06x", audio_left);
            if (audio_right !== 24'hfedc00)
                $fatal(1, "right channel mismatch got=%06x", audio_right);
        end
    end
end

initial begin
    repeat (8) @(posedge mclk);
    rst = 1'b0;
    enable = 1'b1;

    wait (playing && (read_count >= 2));

    // UART-controlled gain values are synchronized and applied before I2S,
    // so HDMI audio and both visualization analysers observe the same level.
    volume_level = 4'd4;
    repeat (6) @(posedge mclk);
    #1;
    if (dut.pcm_left_24 !== 24'h091A00 ||
        dut.pcm_right_24 !== 24'hFF6E00)
        $fatal(1, "half-volume scaler mismatch L=%h R=%h",
               dut.pcm_left_24, dut.pcm_right_24);
    volume_level = 4'd0;
    repeat (6) @(posedge mclk);
    #1;
    if (dut.pcm_left_24 !== 24'h000000 ||
        dut.pcm_right_24 !== 24'h000000)
        $fatal(1, "mute scaler mismatch L=%h R=%h",
               dut.pcm_left_24, dut.pcm_right_24);
    volume_level = 4'd8;
    repeat (6) @(posedge mclk);

    @(negedge mclk);
    pcm_empty = 1'b1;
    pcm_level = 9'd0;
    wait (underflow);
    @(posedge mclk);
    #1;
    if (playing)
        $fatal(1, "PCM source remained selected after FIFO underflow");

    // Refill to the configured start level; playback must recover without a
    // global reset and must issue FIFO reads again.
    repeat (16) @(posedge mclk);
    pcm_empty = 1'b0;
    pcm_level = 9'd1;
    wait (playing);
    wait (read_count >= 3);
    $display("PASS PCM_I2S data=ok underflow_fallback=ok rebuffer_restart=ok reads=%0d",
             read_count);
    $finish;
end

initial begin
    #100000;
    $fatal(1, "timeout");
end

endmodule
