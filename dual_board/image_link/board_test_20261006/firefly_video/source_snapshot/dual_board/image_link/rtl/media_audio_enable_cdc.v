`timescale 1ns/1ps
// A session/FIFO reset can be only 16 UDP clocks (128 ns). Asynchronously
// clear the enable synchronizer so the 12.288 MHz serializer always observes
// disable, even when its input enable was already high for the previous song.
// Do NOT reset its I2S clock divider on a media-session change.
module media_audio_enable_cdc (
    input wire clk, fifo_reset, stream_enable,
    output reg [1:0] enable_sync
);
always @(posedge clk or posedge fifo_reset) begin
    if(fifo_reset) enable_sync<=0;
    else enable_sync<={enable_sync[0],stream_enable};
end
endmodule
