`timescale 1ns/1ps

module tb_video_transition_effects;

reg clk = 1'b0;
reg rst = 1'b1;
reg frame_vs = 1'b1;
reg hs = 1'b1;
reg vs = 1'b1;
reg de = 1'b0;
reg [23:0] rgb_a = 24'h000000;
reg [23:0] rgb_b = 24'hffffff;
reg display_valid = 1'b0;
reg [1:0] requested_idx = 2'd0;

wire [1:0] read_idx_a;
wire [1:0] read_idx_b;
wire read_b_enable;
wire [1:0] display_idx;
wire transition_active;
wire [1:0] transition_kind;
wire [5:0] transition_step;
wire out_hs;
wire out_vs;
wire out_de;
wire [23:0] out_rgb;

always #5 clk = ~clk;

video_transition_effects dut (
    .I_clk(clk),
    .I_rst(rst),
    .I_frame_vs(frame_vs),
    .I_hs(hs),
    .I_vs(vs),
    .I_de(de),
    .I_rgb_a(rgb_a),
    .I_rgb_b(rgb_b),
    .I_display_valid(display_valid),
    .I_requested_idx(requested_idx),
    .I_frame_read_req(1'b0), .I_force_warning(1'b0), .I_warning_ready(1'b0),
    .O_read_idx_a(read_idx_a),
    .O_read_idx_b(read_idx_b),
    .O_read_b_enable(read_b_enable),
    .O_display_idx(display_idx),
    .O_transition_active(transition_active),
    .O_transition_kind(transition_kind),
    .O_transition_step(transition_step),
    .O_hs(out_hs),
    .O_vs(out_vs),
    .O_de(out_de),
    .O_rgb(out_rgb)
);

task frame_edge;
begin
    frame_vs = 1'b1;
    repeat (2) @(posedge clk);
    frame_vs = 1'b0;
    repeat (2) @(posedge clk);
    frame_vs = 1'b1;
    repeat (2) @(posedge clk);
end
endtask

task finish_transition;
integer i;
begin
    for (i = 0; i < 31; i = i + 1)
        frame_edge;
    if (transition_step != 6'd31 || read_idx_a != read_idx_b)
        $fatal(1, "final transition frame did not preselect target A stream");
    frame_edge;
    if (transition_active)
        $fatal(1, "transition did not finish");
end
endtask

task start_transition;
input [1:0] next_idx;
input [1:0] expected_kind;
begin
    requested_idx = next_idx;
    repeat (4) @(posedge clk);
    if (!read_b_enable || transition_active || read_idx_b != next_idx)
        $fatal(1, "target frame was not prefetched before transition");
    frame_edge;
    if (!transition_active || transition_kind != expected_kind)
        $fatal(1, "bad transition start old=%0d new=%0d kind=%0d", display_idx, next_idx, transition_kind);
    if (!read_b_enable || read_idx_b != next_idx)
        $fatal(1, "second frame stream not enabled");
end
endtask

initial begin
    repeat (4) @(posedge clk);
    rst = 1'b0;

    // First valid image is selected directly, even if image 1 was unavailable;
    // there must be no transition from an uninitialized reset buffer.
    requested_idx = 2'd2;
    display_valid = 1'b1;
    repeat (6) @(posedge clk);
    if ((display_idx != 2'd2) || transition_active || read_b_enable)
        $fatal(1, "first valid image did not lock directly");

    // Return to image 1 as a fresh startup, then run the normal sequence.
    display_valid = 1'b0;
    repeat (4) @(posedge clk);
    requested_idx = 2'd0;
    display_valid = 1'b1;
    repeat (6) @(posedge clk);
    if ((display_idx != 2'd0) || transition_active)
        $fatal(1, "fresh image 1 startup failed");

    // 1 -> 2: real alpha blend. At step zero white contributes 1/32.
    start_transition(2'd1, 2'd0);
    de = 1'b1;
    @(posedge clk);
    #1;
    if (out_rgb !== 24'h070707)
        $fatal(1, "fade alpha mismatch rgb=%h", out_rgb);
    de = 1'b0;
    finish_transition;
    if (display_idx != 2'd1)
        $fatal(1, "1->2 commit failed");

    // 2 -> 3: old frame moves left, new frame enters from the right.
    start_transition(2'd2, 2'd1);
    finish_transition;
    if (display_idx != 2'd2)
        $fatal(1, "2->3 commit failed");

    // 3 -> 4: old frame moves right, new frame enters from the left.
    start_transition(2'd3, 2'd2);
    finish_transition;
    if (display_idx != 2'd3)
        $fatal(1, "3->4 commit failed");

    // 4 -> 1: 16x16 block-grid reveal.
    start_transition(2'd0, 2'd3);
    finish_transition;
    if (display_idx != 2'd0)
        $fatal(1, "4->1 commit failed");

    $display("PASS TRANSITIONS fade=1->2 left=2->3 right=3->4 grid=4->1 steps=32");
    $finish;
end

endmodule
