// Cross a long-lived image-valid flag into the pixel clock domain and commit
// it only on a vertical-frame boundary.  The first visible frame therefore
// starts with a fresh frame-buffer request instead of exposing a FIFO that was
// filled while image 1 was still being written.
module video_frame_valid_gate (
    input  wire I_clk,
    input  wire I_async_rst,
    input  wire I_frame_vs,
    input  wire I_async_valid,
    output reg  O_frame_valid
);

reg [2:0] reset_release_sync;
reg [1:0] valid_sync;
reg       frame_vs_d;

wire local_reset = reset_release_sync[2];
wire frame_boundary = frame_vs_d && !I_frame_vs;

// Asynchronous assertion guarantees an immediate safe state. Reset release is
// delayed through three pixel clocks so all following state leaves reset on a
// clock edge.
always @(posedge I_clk or posedge I_async_rst) begin
    if (I_async_rst)
        reset_release_sync <= 3'b111;
    else
        reset_release_sync <= {reset_release_sync[1:0], 1'b0};
end

always @(posedge I_clk) begin
    if (local_reset) begin
        valid_sync   <= 2'b00;
        frame_vs_d   <= 1'b0;
        O_frame_valid<= 1'b0;
    end else begin
        valid_sync <= {valid_sync[0], I_async_valid};
        frame_vs_d <= I_frame_vs;
        if (frame_boundary)
            O_frame_valid <= valid_sync[1];
    end
end

endmodule
