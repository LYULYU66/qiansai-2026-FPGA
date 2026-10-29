`timescale 1ns/1ps
module tb_image_sink_guard;
reg clk=0; always #4 clk=~clk;
reg rst=1, frame_start=0;
reg [1:0] index=1;
reg [3:0] protected_mask=4'b0010;
wire req, abort_write, receipt, reset_rx, fault;
wire [3:0] cache;
image_sdram_sink #(.FRAME_PACKETS(4),.TIMEOUT_CYCLES(50)) dut (
    .clk(clk),.rst(rst),.frame_start(frame_start),.frame_complete(1'b0),
    .frame_abort(1'b0),.frame_index(index),.frame_top_down(1'b1),
    .pixel_valid(1'b0),.pixel_rgb(24'd0),.pixel_ready(),
    .packet_done(1'b0),.packet_token(32'd1),.packet_sequence(16'd0),
    .writer_ready(1'b0),.writer_ack(req),.writer_finish_toggle(1'b0),
    .protected_buffers(protected_mask),.write_req(req),.write_abort(abort_write),
    .write_en(),.write_data(),.write_index(),.write_top_down(),
    .receipt_event(receipt),.receipt_token(),.receipt_sequence(),
    .cache_valid(cache),.commit_toggle(),.receive_reset(reset_rx),.fault(fault)
);
initial begin
    repeat(5) @(negedge clk); rst=0;
    @(negedge clk); frame_start=1;
    @(negedge clk); frame_start=0;
    // 20261019: the frame-start decision is registered, so the rejection
    // (one-clock receive_reset pulse) appears one clock after frame_start.
    @(negedge clk);
    if(!fault || !reset_rx || req || !abort_write)
        $fatal(1,"protected visible buffer was not rejected");
    rst=1;
    repeat(5) @(negedge clk); rst=0; protected_mask=0; index=0;
    @(negedge clk); frame_start=1;
    @(negedge clk); frame_start=0;
    repeat(80) @(negedge clk);
    if(!fault || req || !abort_write || cache!=0 || receipt)
        $fatal(1,"stalled transfer failed to abort safely");
    $display("PASS image sink guard: protected buffer, stalled writer timeout, no partial commit");
    $finish;
end
always @(posedge clk) if(!rst && cache!=0) $fatal(1,"partial frame was published");
endmodule
