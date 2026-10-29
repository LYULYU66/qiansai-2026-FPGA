// Synchronize and debounce the four vehicle-hazard slide switches.
//
// The board switch outputs are high when moved to the position marked "1".
// STABLE_CYCLES defaults to 10 ms at the 25 MHz video clock.  A state is
// accepted only after it remains unchanged for the whole interval, which
// prevents contact bounce from restarting the visual/audio warning logic.
module alarm_switch_control #(
    parameter integer STABLE_CYCLES = 250000
)(
    input  wire I_clk,
    input  wire I_rst,
    input  wire I_sw_front,
    input  wire I_sw_left,
    input  wire I_sw_right,
    input  wire I_sw_rear,
    output reg  O_hazard_front,
    output reg  O_hazard_left,
    output reg  O_hazard_right,
    output reg  O_hazard_rear
);

reg [3:0] switch_meta;
reg [3:0] switch_sync;
reg [18:0] front_count;
reg [18:0] left_count;
reg [18:0] right_count;
reg [18:0] rear_count;

wire [18:0] stable_limit = STABLE_CYCLES - 1;

always @(posedge I_clk or posedge I_rst) begin
    if (I_rst) begin
        switch_meta   <= 4'b0000;
        switch_sync   <= 4'b0000;
        front_count   <= 19'd0;
        left_count    <= 19'd0;
        right_count   <= 19'd0;
        rear_count    <= 19'd0;
        O_hazard_front <= 1'b0;
        O_hazard_left  <= 1'b0;
        O_hazard_right <= 1'b0;
        O_hazard_rear  <= 1'b0;
    end else begin
        switch_meta <= {I_sw_rear, I_sw_front, I_sw_left, I_sw_right};
        switch_sync <= switch_meta;

        if (switch_sync[2] == O_hazard_front) begin
            front_count <= 19'd0;
        end else if (front_count >= stable_limit) begin
            O_hazard_front <= switch_sync[2];
            front_count    <= 19'd0;
        end else begin
            front_count <= front_count + 19'd1;
        end

        if (switch_sync[1] == O_hazard_left) begin
            left_count <= 19'd0;
        end else if (left_count >= stable_limit) begin
            O_hazard_left <= switch_sync[1];
            left_count    <= 19'd0;
        end else begin
            left_count <= left_count + 19'd1;
        end

        if (switch_sync[0] == O_hazard_right) begin
            right_count <= 19'd0;
        end else if (right_count >= stable_limit) begin
            O_hazard_right <= switch_sync[0];
            right_count    <= 19'd0;
        end else begin
            right_count <= right_count + 19'd1;
        end

        if (switch_sync[3] == O_hazard_rear) begin
            rear_count <= 19'd0;
        end else if (rear_count >= stable_limit) begin
            O_hazard_rear <= switch_sync[3];
            rear_count <= 19'd0;
        end else begin
            rear_count <= rear_count + 19'd1;
        end
    end
end

endmodule
