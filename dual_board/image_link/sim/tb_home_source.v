`timescale 1ns/1ps
// Exercise the real B source wrapper, CDC, row decoder and sender together.
// Only decoded SD-reader outputs are substituted; this is NOT a TF/FAT test.
module tb_home_source;
reg sd_clk=0;always #5 sd_clk=~sd_clk;
reg udp_clk=0;always #4 udp_clk=~udp_clk;
reg rst=1,sd_req=0,sd_valid=0,sd_top=0;
reg [1:0] sd_index=0;
reg [31:0] sd_word=0;
reg [31:0] sd_resolution=32'h050003c0;
wire [31:0] frame_resolution;
reg tx_ack=0,ack_ack=0;
wire tx_req,tx_valid,overflow,ack_req,ack_valid;
wire [7:0] tx_data,ack_data;
wire [15:0] tx_length,ack_length;
wire pixel_valid,packet_done,frame_complete;
wire [23:0] pixel_rgb;
wire [7:0] pixel_tag;
wire [1:0] frame_index;
wire frame_top;
wire [31:0] packet_token;
wire [15:0] packet_sequence;
integer udp_cycles=0,received=0,completed=0;
wire pixel_ready=udp_cycles%13>=2;
reg [7:0] expected[0:614399];
image_tf_source dut(.sd_clk(sd_clk),.udp_clk(udp_clk),.rst(rst),
    .key_next(1'b1),.key_auto(1'b1),.SD_nCS(),.SD_DCLK(),.SD_MOSI(),.SD_MISO(1'b1),
    .udp_ready(1'b1),.udp_ack(tx_ack),.udp_request(tx_req),.udp_valid(tx_valid),.udp_data(tx_data),.udp_length(tx_length),
    .rx_valid(ack_valid),.rx_data(ack_data),.rx_length(ack_length),.state_code(),.image_number(),.source_resolutions(),.overflow(overflow),
    .audio_fifo_ready(1'b0),.audio_pcm_wr_en(),.audio_stream_enable(),.audio_pcm_data(),.audio_file_bytes());
image_packet_rx #(.RELIABLE(1),.UI_TAG(1),.RESOLUTION(1)) receiver(.clk(udp_clk),.rst(rst),
    .rx_valid(tx_valid),.rx_data(tx_data),.rx_length(tx_length),.pixel_ready(pixel_ready),
    .pixel_valid(pixel_valid),.pixel_rgb(pixel_rgb),.pixel_tag(pixel_tag),.frame_index(frame_index),.frame_top_down(frame_top),
    .frame_start(),.frame_complete(frame_complete),.frame_abort(),.good_packets(),.bad_packets(),
    .frame_resolution(frame_resolution),
    .packet_done(packet_done),.packet_duplicate(),.packet_token(packet_token),.packet_sequence(packet_sequence));
image_receipt_tx receipt(.clk(udp_clk),.rst(rst),.event_valid(packet_done),.event_token(packet_token),.event_sequence(packet_sequence),
    .udp_ready(1'b1),.udp_ack(ack_ack),.udp_request(ack_req),.udp_valid(ack_valid),.udp_data(ack_data),.udp_length(ack_length));
integer y,x,pixels_in_frame;
always @(posedge udp_clk) if(!rst) begin
    udp_cycles=udp_cycles+1;tx_ack<=tx_req;ack_ack<=ack_req;
    if(overflow) $fatal(1,"source CDC overflow");
    if(pixel_valid && pixel_ready) begin
        pixels_in_frame=received%307200;x=pixels_in_frame%640;
        y=sd_top ? pixels_in_frame/640 : 479-pixels_in_frame/640;
        if(pixel_rgb!==pixels_in_frame[23:0] || pixel_tag!==expected[sd_index*307200+y*640+x])
            $fatal(1,"source RGB/tag mismatch page=%0d pixel=%0d got=%h/%h",sd_index,pixels_in_frame,pixel_rgb,pixel_tag);
        if(frame_index!=sd_index || frame_top!=sd_top) $fatal(1,"source metadata mismatch");
        if(frame_resolution!=sd_resolution || tx_length!=1042) $fatal(1,"source resolution mismatch");
        received=received+1;
    end
    if(dut.frame_sent) completed=completed+1;
end
integer p,n,ticks;
initial begin
    $readmemh("home_reference_indices.hex",expected);
    force dut.write_req=sd_req;force dut.write_en=sd_valid;force dut.write_data=sd_word;
    force dut.write_index=sd_index;force dut.top_down=sd_top;force dut.load_abort=1'b0;
    force dut.live_source_resolution=sd_resolution;
    repeat(8) @(negedge sd_clk);rst=0;
    repeat(6) @(negedge sd_clk);
    for(p=0;p<2;p=p+1) begin
        sd_index=p;sd_top=p;sd_resolution=p ? 32'h07800438 : 32'h050003c0;sd_req=1;
        while(!dut.write_ack) @(negedge sd_clk);
        sd_req=0;n=0;ticks=0;
        while(n<307200) begin
            sd_valid=dut.fifo_ready && ticks%7!=0;
            sd_word={n[23:0],8'd0};
            if(sd_valid) n=n+1;
            ticks=ticks+1;@(negedge sd_clk);
        end
        sd_valid=0;
        while(completed<p+1) @(negedge sd_clk);
        repeat(10) @(negedge sd_clk);
    end
    if(received!=614400) $fatal(1,"source frame incomplete");
    $display("PASS home source: actual 100/125 MHz CDC + indexed sender, 614400 words, both storage directions and backpressure");$finish;
end
initial begin #100000000;$fatal(1,"home source timeout");end
endmodule
