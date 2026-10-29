`timescale 1ns/1ps
// Assert asynchronously even while the clock is stopped; release only after
// two local edges. Do not OR the raw request back onto the output reset net.
module player_domain_reset(input wire clk,request,output wire rst);
(* async_reg="true" *) reg [1:0] release_pipe;
always @(posedge clk or posedge request) begin
    if(request)release_pipe<=2'b11;
    else release_pipe<={release_pipe[0],1'b0};
end
assign rst=release_pipe[1];
endmodule

// File length is stable after the directory scan, BEFORE stream rises, and
// remains stable while streaming. Capture the bundled length on the existing
// three-edge stream handshake, not as a changing 32-bit bus at every consumer.
module player_audio_session(
    input wire clk,rst,stream_async,
    input wire [15:0] generation,
    input wire [31:0] file_bytes_async,
    output wire stream_active,
    output reg [31:0] session_id,file_samples
);
(* async_reg="true" *) reg [2:0] stream_sync;
assign stream_active=stream_sync[2];
always @(posedge clk or posedge rst)begin
    if(rst)begin stream_sync<=0;session_id<=0;file_samples<=0;end
    else begin
        stream_sync<={stream_sync[1:0],stream_async};
        if(stream_sync[1] && !stream_sync[2])begin
            session_id<={generation,session_id[15:0]+16'd1};
            file_samples<={2'd0,file_bytes_async[31:2]};
        end
    end
end
endmodule
