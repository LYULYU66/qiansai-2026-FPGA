module video_transition_effects #(
    parameter integer H_ACTIVE = 640,
    parameter integer V_ACTIVE = 480,
    parameter integer TRANSITION_STEPS = 32
)(
    input  wire        I_clk,
    input  wire        I_rst,
    input  wire        I_frame_vs,
    input  wire        I_hs,
    input  wire        I_vs,
    input  wire        I_de,
    input  wire [23:0] I_rgb_a,
    input  wire [23:0] I_rgb_b,
    input  wire        I_display_valid,
    input  wire [1:0]  I_requested_idx,
    input  wire        I_frame_read_req,
    input  wire        I_force_warning,
    input  wire        I_warning_ready,

    output wire [1:0]  O_read_idx_a,
    output wire [1:0]  O_read_idx_b,
    output wire        O_read_b_enable,
    output wire [1:0]  O_display_idx,
    output wire        O_transition_active,
    output wire [1:0]  O_transition_kind,
    output wire [5:0]  O_transition_step,

    output wire        O_hs,
    output wire        O_vs,
    output wire        O_de,
    output reg  [23:0] O_rgb
);

localparam [1:0] EFFECT_FADE       = 2'd0;
localparam [1:0] EFFECT_SLIDE_LEFT = 2'd1;
localparam [1:0] EFFECT_SLIDE_RIGHT= 2'd2;
localparam [1:0] EFFECT_GRID       = 2'd3;

reg [1:0] requested_sync0;
reg [1:0] requested_sync1;
reg       valid_sync0;
reg       valid_sync1;
reg       frame_vs_d;
reg [1:0] force_sync, ready_sync;
reg       frame_read_req_d;
reg       direct_armed, direct_force, warning_forced;
reg [1:0] direct_idx;

reg [1:0] active_idx;
reg [1:0] target_idx;
reg [1:0] effect_kind;
reg [5:0] effect_step;
reg       transition_active;
reg       transition_pending;
reg       valid_seen;

wire frame_tick = frame_vs_d && !I_frame_vs;

// The frame reader raises its request one pixel clock before frame_tick.  Point
// stream A at the target during the last (fully-new) transition frame so that
// the first post-transition frame is already fetched from the new buffer.
assign O_read_idx_a          = direct_armed ? direct_idx : (transition_active &&
                                (effect_step == TRANSITION_STEPS - 1)) ?
                               target_idx : active_idx;
assign O_read_idx_b          = target_idx;
// Preload stream B for one frame before the visual transition starts.  This
// prevents stale/empty B-FIFO pixels at the first fade or slide step.
assign O_read_b_enable       = transition_active | transition_pending;
assign O_display_idx         = active_idx;
assign O_transition_active   = transition_active;
assign O_transition_kind     = effect_kind;
assign O_transition_step     = effect_step;

// Requested image changes in the TF-card clock domain and remains stable for many
// video clocks. Synchronize it before committing a transition on a frame boundary.
always @(posedge I_clk or posedge I_rst) begin
    if (I_rst) begin
        requested_sync0 <= 2'd0;
        requested_sync1 <= 2'd0;
        valid_sync0     <= 1'b0;
        valid_sync1     <= 1'b0;
        frame_vs_d      <= 1'b0;
        force_sync      <= 2'b00;
        ready_sync      <= 2'b00;
    end else begin
        requested_sync0 <= I_requested_idx;
        requested_sync1 <= requested_sync0;
        valid_sync0     <= I_display_valid;
        valid_sync1     <= valid_sync0;
        frame_vs_d      <= I_frame_vs;
        force_sync      <= {force_sync[0], I_force_warning};
        ready_sync      <= {ready_sync[0], I_warning_ready};
    end
end

// Capture the emergency decision at the frame reader's request, one pixel
// clock before frame_tick. Both SDRAM address selection and the visible page
// then use this SAME latched decision, even if a switch changes between them.
// Never select an incompletely loaded warning frame. A warning interrupts any
// animation; release restores the normal player's page without an animation.
wire force_warning = force_sync[1] && ready_sync[1];
always @(posedge I_clk or posedge I_rst) begin
    if (I_rst) begin
        frame_read_req_d <= 1'b0;
        direct_armed <= 1'b0;
        direct_force <= 1'b0;
        direct_idx <= 2'd0;
    end else begin
        frame_read_req_d <= I_frame_read_req;
        if (!valid_sync1 || frame_tick) direct_armed <= 1'b0;
        if (I_frame_read_req && !frame_read_req_d && valid_sync1 && valid_seen &&
            (force_warning || warning_forced)) begin
            direct_armed <= 1'b1;
            direct_force <= force_warning;
            direct_idx <= force_warning ? 2'd3 : requested_sync1;
        end
    end
end

// Transition order:
// image 1 -> 2: alpha fade, 2 -> 3: slide left,
// image 3 -> 4: slide right, 4 -> 1: 16x16 grid reveal.
function [1:0] select_effect;
    input [1:0] from_idx;
    input [1:0] to_idx;
    begin
        if ((from_idx == 2'd0) && (to_idx == 2'd1))
            select_effect = EFFECT_FADE;
        else if ((from_idx == 2'd1) && (to_idx == 2'd2))
            select_effect = EFFECT_SLIDE_LEFT;
        else if ((from_idx == 2'd2) && (to_idx == 2'd3))
            select_effect = EFFECT_SLIDE_RIGHT;
        else if ((from_idx == 2'd3) && (to_idx == 2'd0))
            select_effect = EFFECT_GRID;
        else
            select_effect = EFFECT_FADE;
    end
endfunction

always @(posedge I_clk or posedge I_rst) begin
    if (I_rst) begin
        active_idx        <= 2'd0;
        target_idx        <= 2'd0;
        effect_kind       <= EFFECT_FADE;
        effect_step       <= 6'd0;
        transition_active <= 1'b0;
        transition_pending<= 1'b0;
        valid_seen        <= 1'b0;
        warning_forced    <= 1'b0;
    end else if (!valid_sync1) begin
        active_idx        <= 2'd0;
        target_idx        <= 2'd0;
        effect_step       <= 6'd0;
        transition_active <= 1'b0;
        transition_pending<= 1'b0;
        valid_seen        <= 1'b0;
        warning_forced    <= 1'b0;
    end else if (!valid_seen) begin
        // The first complete frame has no valid predecessor. Select it
        // directly instead of animating from reset buffer 0, which may still
        // contain stale SDRAM/FIFO data when image 1 was unavailable or late.
        active_idx         <= requested_sync1;
        target_idx         <= requested_sync1;
        effect_step        <= 6'd0;
        transition_active  <= 1'b0;
        transition_pending <= 1'b0;
        valid_seen         <= 1'b1;
    end else if (frame_tick && direct_armed) begin
        active_idx         <= direct_idx;
        target_idx         <= direct_idx;
        effect_step        <= 6'd0;
        transition_active  <= 1'b0;
        transition_pending <= 1'b0;
        warning_forced     <= direct_force;
    end else if (warning_forced) begin
        transition_active  <= 1'b0;
        transition_pending <= 1'b0;
    end else if (transition_active) begin
        if (frame_tick) begin
            if (effect_step == TRANSITION_STEPS - 1) begin
                active_idx        <= target_idx;
                effect_step       <= 6'd0;
                transition_active <= 1'b0;
            end else begin
                effect_step <= effect_step + 6'd1;
            end
        end
    end else if (transition_pending) begin
        // A changed request restarts preparation.  The transition cannot begin
        // until the selected target has remained stable through a frame edge.
        if (requested_sync1 == active_idx) begin
            transition_pending <= 1'b0;
        end else if (requested_sync1 != target_idx) begin
            target_idx        <= requested_sync1;
            effect_kind       <= select_effect(active_idx, requested_sync1);
            effect_step       <= 6'd0;
        end else if (frame_tick) begin
            transition_active <= 1'b1;
            transition_pending<= 1'b0;
        end
    end else if (requested_sync1 != active_idx) begin
        target_idx         <= requested_sync1;
        effect_kind        <= select_effect(active_idx, requested_sync1);
        effect_step        <= 6'd0;
        transition_pending <= 1'b1;
    end
end

// Active-area coordinates for masks and line-buffer addressing.
reg [9:0] pixel_x;
reg [8:0] pixel_y;
reg       input_de_d;
reg       line_bank;

wire line_end = input_de_d && !I_de;

always @(posedge I_clk or posedge I_rst) begin
    if (I_rst) begin
        pixel_x    <= 10'd0;
        pixel_y    <= 9'd0;
        input_de_d <= 1'b0;
        line_bank  <= 1'b0;
    end else begin
        input_de_d <= I_de;

        if (frame_tick) begin
            pixel_x   <= 10'd0;
            pixel_y   <= 9'd0;
            line_bank <= 1'b0;
        end else if (I_de) begin
            if (pixel_x < H_ACTIVE - 1)
                pixel_x <= pixel_x + 10'd1;
        end else begin
            pixel_x <= 10'd0;
            if (line_end) begin
                line_bank <= ~line_bank;
                if (pixel_y < V_ACTIVE - 1)
                    pixel_y <= pixel_y + 9'd1;
            end
        end
    end
end

wire [5:0] motion_step = effect_step + 6'd1;
wire [10:0] shift_x = {1'b0, motion_step, 4'b0000} +
                       {3'b000, motion_step, 2'b00};

reg [9:0] slide_addr_a;
reg [9:0] slide_addr_b;

always @(*) begin
    slide_addr_a = pixel_x;
    slide_addr_b = pixel_x;

    if (effect_kind == EFFECT_SLIDE_LEFT) begin
        if ({1'b0, pixel_x} < (H_ACTIVE - shift_x))
            slide_addr_a = pixel_x + shift_x[9:0];
        else
            slide_addr_b = pixel_x - (H_ACTIVE - shift_x);
    end else if (effect_kind == EFFECT_SLIDE_RIGHT) begin
        if ({1'b0, pixel_x} >= shift_x)
            slide_addr_a = pixel_x - shift_x[9:0];
        else
            slide_addr_b = pixel_x + (H_ACTIVE - shift_x);
    end
end

// True horizontal translation uses a previous raster line while the current
// line is written. Keep the existing RGB666 precision. For widths <= 768,
// pack both ping-pong line tails into one 9K BRAM (three BRAMs per image).
// Wider configurations retain the original two 1024x18 banks per image.
wire [17:0] line_data_a = {I_rgb_a[23:18], I_rgb_a[15:10], I_rgb_a[7:2]};
wire [17:0] line_data_b = {I_rgb_b[23:18], I_rgb_b[15:10], I_rgb_b[7:2]};
wire [17:0] slide_data_a;
wire [17:0] slide_data_b;

generate if (H_ACTIVE <= 768) begin : packed_line_buffers
    // Two 640-pixel lines fit into three 512x18 BRAMs: two 512-pixel
    // heads and one shared tail. Select the bank that will be active after
    // this edge, matching the former post-clock line_bank output mux.
    wire read_bank = frame_tick ? 1'b1 : ~(line_bank ^ line_end);
    transition_packed_lines line_a (
        .clk(I_clk), .we(I_de), .wbank(line_bank), .waddr(pixel_x),
        .wdata(line_data_a), .rbank(read_bank), .raddr(slide_addr_a),
        .rdata(slide_data_a)
    );
    transition_packed_lines line_b (
        .clk(I_clk), .we(I_de), .wbank(line_bank), .waddr(pixel_x),
        .wdata(line_data_b), .rbank(read_bank), .raddr(slide_addr_b),
        .rdata(slide_data_b)
    );
end else begin : full_line_buffers
wire [17:0] line_a0_q, line_a1_q, line_b0_q, line_b1_q;

transition_line_ram line_a_bank0 (
    .clk(I_clk), .we(I_de && !line_bank), .waddr(pixel_x),
    .wdata(line_data_a), .raddr(slide_addr_a), .rdata(line_a0_q)
);
transition_line_ram line_a_bank1 (
    .clk(I_clk), .we(I_de && line_bank), .waddr(pixel_x),
    .wdata(line_data_a), .raddr(slide_addr_a), .rdata(line_a1_q)
);
transition_line_ram line_b_bank0 (
    .clk(I_clk), .we(I_de && !line_bank), .waddr(pixel_x),
    .wdata(line_data_b), .raddr(slide_addr_b), .rdata(line_b0_q)
);
transition_line_ram line_b_bank1 (
    .clk(I_clk), .we(I_de && line_bank), .waddr(pixel_x),
    .wdata(line_data_b), .raddr(slide_addr_b), .rdata(line_b1_q)
);

assign slide_data_a = line_bank ? line_a0_q : line_a1_q;
assign slide_data_b = line_bank ? line_b0_q : line_b1_q;
end endgenerate
wire [23:0] slide_pixel_a = {
    slide_data_a[17:12], slide_data_a[17:16],
    slide_data_a[11:6],  slide_data_a[11:10],
    slide_data_a[5:0],   slide_data_a[5:4]
};
wire [23:0] slide_pixel_b = {
    slide_data_b[17:12], slide_data_b[17:16],
    slide_data_b[11:6],  slide_data_b[11:10],
    slide_data_b[5:0],   slide_data_b[5:4]
};

// One-clock pipeline aligns direct pixels and timing with synchronous BRAM reads.
reg        hs_d;
reg        vs_d;
reg        de_d;
reg [23:0] rgb_a_d;
reg [23:0] rgb_b_d;
reg [9:0]  pixel_x_d;
reg [8:0]  pixel_y_d;
reg [1:0]  kind_d;
reg [5:0]  step_d;
reg        transition_d;

always @(posedge I_clk or posedge I_rst) begin
    if (I_rst) begin
        hs_d         <= 1'b0;
        vs_d         <= 1'b0;
        de_d         <= 1'b0;
        rgb_a_d      <= 24'd0;
        rgb_b_d      <= 24'd0;
        pixel_x_d    <= 10'd0;
        pixel_y_d    <= 9'd0;
        kind_d       <= EFFECT_FADE;
        step_d       <= 6'd0;
        transition_d <= 1'b0;
    end else begin
        hs_d         <= I_hs;
        vs_d         <= I_vs;
        de_d         <= I_de;
        rgb_a_d      <= I_rgb_a;
        rgb_b_d      <= I_rgb_b;
        pixel_x_d    <= pixel_x;
        pixel_y_d    <= pixel_y;
        kind_d       <= effect_kind;
        step_d       <= effect_step;
        transition_d <= transition_active;
    end
end

assign O_hs = hs_d;
assign O_vs = vs_d;
assign O_de = de_d;

wire [5:0] alpha     = step_d + 6'd1;
wire [5:0] alpha_inv = 6'd32 - alpha;

wire [13:0] fade_r_sum = rgb_a_d[23:16] * alpha_inv + rgb_b_d[23:16] * alpha;
wire [13:0] fade_g_sum = rgb_a_d[15:8]  * alpha_inv + rgb_b_d[15:8]  * alpha;
wire [13:0] fade_b_sum = rgb_a_d[7:0]   * alpha_inv + rgb_b_d[7:0]   * alpha;
wire [23:0] fade_rgb = {fade_r_sum[12:5], fade_g_sum[12:5], fade_b_sum[12:5]};

wire [5:0] grid_x = pixel_x_d[9:4];
wire [4:0] grid_y = pixel_y_d[8:4];
wire [6:0] grid_hash_full = {1'b0, grid_x} + {2'b00, grid_y} +
                            {1'b0, grid_y, 1'b0};
wire [4:0] grid_rank = grid_hash_full[4:0];
wire       grid_show_new = ({1'b0, grid_rank} < alpha);

wire [10:0] shift_d = ({1'b0, alpha, 4'b0000} + {3'b000, alpha, 2'b00});
wire left_uses_a  = ({1'b0, pixel_x_d} <  (H_ACTIVE - shift_d));
wire right_uses_a = ({1'b0, pixel_x_d} >= shift_d);

always @(*) begin
    O_rgb = rgb_a_d;

    if (!de_d)
        O_rgb = 24'd0;
    else if (transition_d) begin
        case (kind_d)
            EFFECT_FADE:
                O_rgb = fade_rgb;

            EFFECT_SLIDE_LEFT: begin
                // The first active row has no previous line; use a same-row wipe
                // there to avoid a one-pixel black seam.
                if (pixel_y_d == 9'd0)
                    O_rgb = left_uses_a ? rgb_a_d : rgb_b_d;
                else
                    O_rgb = left_uses_a ? slide_pixel_a : slide_pixel_b;
            end

            EFFECT_SLIDE_RIGHT: begin
                if (pixel_y_d == 9'd0)
                    O_rgb = right_uses_a ? rgb_a_d : rgb_b_d;
                else
                    O_rgb = right_uses_a ? slide_pixel_a : slide_pixel_b;
            end

            EFFECT_GRID:
                O_rgb = grid_show_new ? rgb_b_d : rgb_a_d;

            default:
                O_rgb = rgb_a_d;
        endcase
    end
end

endmodule

// Synchronous simple dual-port RAM template recognized by Tang Dynasty.
module transition_packed_lines (
    input wire clk, we, wbank, rbank,
    input wire [9:0] waddr, raddr,
    input wire [17:0] wdata,
    output wire [17:0] rdata
);
reg [17:0] head0 [0:511]; /* fehdl force_ram=1, ram_style="bram" */
reg [17:0] head1 [0:511]; /* fehdl force_ram=1, ram_style="bram" */
reg [17:0] tails [0:511]; /* fehdl force_ram=1, ram_style="bram" */
reg [17:0] q0, q1, qt;
reg [1:0] read_select;
always @(posedge clk) begin
    if (we && !waddr[9] && !wbank) head0[waddr[8:0]] <= wdata;
    if (we && !waddr[9] &&  wbank) head1[waddr[8:0]] <= wdata;
    if (we &&  waddr[9]) tails[{wbank,waddr[7:0]}] <= wdata;
    q0 <= head0[raddr[8:0]];
    q1 <= head1[raddr[8:0]];
    qt <= tails[{rbank,raddr[7:0]}];
    read_select <= {raddr[9],rbank};
end
assign rdata = read_select[1] ? qt : (read_select[0] ? q1 : q0);
endmodule

module transition_line_ram (
    input  wire        clk,
    input  wire        we,
    input  wire [9:0]  waddr,
    input  wire [17:0] wdata,
    input  wire [9:0]  raddr,
    output reg  [17:0] rdata
);

reg [17:0] memory [0:1023]; /* fehdl force_ram=1, ram_style="bram" */

always @(posedge clk) begin
    if (we)
        memory[waddr] <= wdata;
    rdata <= memory[raddr];
end

endmodule
