`timescale 1ns/1ps
// Pixel-clock control for the four remotely cached images. The existing
// transition module performs the actual frame-boundary display switch.
module image_remote_display_control #(
    parameter integer CLK_FREQ=25_000_000
) (
    input wire clk, rst, key_next, key_auto, warning_hold, music_on,
    input wire [3:0] cache_valid_async,
    output wire display_valid, warning_ready,
    output wire [1:0] requested_index
);
(* async_reg="true" *) reg [3:0] cache_sync0, cache_sync1;
reg auto_play;
reg [31:0] timer;
reg [1:0] page_index;
reg music_on_d, music_pending;
wire next_press, auto_press;
key_press_debounce #(.CLK_FREQ_HZ(CLK_FREQ)) u_next (
    .clk(clk),.rst(rst),.button_in(key_next),.press_pulse(next_press)
);
key_press_debounce #(.CLK_FREQ_HZ(CLK_FREQ)) u_auto (
    .clk(clk),.rst(rst),.button_in(key_auto),.press_pulse(auto_press)
);
// Turning B's music switch on (music_on 0->1, already synchronized) jumps
// once to page 2 (spectrum; B follows with its song list).  The jump waits
// for a cached page 2 and for any warning to clear; afterwards KEY3/KEY4
// change pages as usual while the music keeps playing.
assign requested_index=page_index;
assign display_valid=cache_sync1[requested_index];
assign warning_ready=cache_sync1[3];
wire [1:0] next_index=requested_index+2'd1;
always @(posedge clk or posedge rst) begin
    if(rst) begin
        cache_sync0<=0; cache_sync1<=0; page_index<=0; auto_play<=0; timer<=0;
        music_on_d<=0; music_pending<=0;
    end else begin
        cache_sync0<=cache_valid_async; cache_sync1<=cache_sync0;
        music_on_d<=music_on;
        if(auto_press) begin auto_play<=~auto_play; timer<=0; end
        else if(warning_hold || !auto_play || !display_valid) timer<=0;
        else if(timer==CLK_FREQ-1) timer<=0;
        else timer<=timer+1'b1;
        if(!music_on) music_pending<=0;
        else if(!music_on_d) music_pending<=1;
        if(music_pending && music_on && !warning_hold && cache_sync1[1]) begin
            page_index<=2'd1; music_pending<=0; timer<=0;
        end else if(!warning_hold &&
           (next_press || (auto_play && timer==CLK_FREQ-1)) &&
           cache_sync1[next_index]) page_index<=next_index;
    end
end
endmodule
