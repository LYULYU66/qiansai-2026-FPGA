`timescale 1ns/1ps
// Four A-board remote caches retain their original manual/automatic controls.
// PAGE_SYNC adds a latest-only TF6-entry event from B. Repeated CTL4 snapshots
// never drag a manually changed A page back into relaxation mode. Local hazard
// and cache validity have priority; one pending entry survives both waits.
module image_remote_display_control #(
    parameter integer CLK_FREQ=25_000_000,
    parameter PAGE_SYNC=0
) (
    input wire clk, rst, key_next, key_auto, warning_hold,
    input wire [3:0] cache_valid_async,
    input wire [7:0] remote_page_token,
    input wire remote_page_valid,
    output wire display_valid, warning_ready,
    output reg [1:0] requested_index
);
(* async_reg="true" *) reg [3:0] cache_sync0, cache_sync1;
reg auto_play;
reg [31:0] timer;
reg have_page_epoch;
reg [6:0] last_page_epoch;
reg remote_pending;
wire next_press, auto_press;
key_press_debounce #(.CLK_FREQ_HZ(CLK_FREQ)) u_next (
    .clk(clk),.rst(rst),.button_in(key_next),.press_pulse(next_press)
);
key_press_debounce #(.CLK_FREQ_HZ(CLK_FREQ)) u_auto (
    .clk(clk),.rst(rst),.button_in(key_auto),.press_pulse(auto_press)
);
assign display_valid=cache_sync1[requested_index];
assign warning_ready=cache_sync1[3];
wire [1:0] next_index=requested_index+2'd1;
// First received TF5 establishes the baseline without switching. If A starts
// while B already displays TF6, accept that current relaxation state once.
wire remote_enter=PAGE_SYNC && remote_page_valid && remote_page_token[7] &&
                  (!have_page_epoch || remote_page_token[6:0]!=last_page_epoch);
always @(posedge clk or posedge rst) begin
    if(rst) begin
        cache_sync0<=0;cache_sync1<=0;requested_index<=0;auto_play<=0;timer<=0;
        have_page_epoch<=0;last_page_epoch<=0;remote_pending<=0;
    end else begin
        cache_sync0<=cache_valid_async;cache_sync1<=cache_sync0;
        if(PAGE_SYNC && remote_page_valid) begin
            have_page_epoch<=1;
            last_page_epoch<=remote_page_token[6:0];
        end
        // A paired relaxation request pauses A autoplay. A later explicit
        // local KEY4 press can enable autoplay again, preserving A controls.
        if(remote_enter || remote_pending) begin auto_play<=0;timer<=0;end
        else if(auto_press) begin auto_play<=~auto_play;timer<=0;end
        else if(warning_hold || !auto_play || !display_valid) timer<=0;
        else if(timer==CLK_FREQ-1) timer<=0;
        else timer<=timer+1'b1;

        if(remote_enter) remote_pending<=1;
        else if(remote_pending && !warning_hold && cache_sync1[2]) begin
            requested_index<=2'd2;
            remote_pending<=0;
        end else if(!remote_pending && !warning_hold &&
                    (next_press || (auto_play && timer==CLK_FREQ-1)) &&
                    cache_sync1[next_index]) requested_index<=next_index;
    end
end
endmodule
