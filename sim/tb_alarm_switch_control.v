`timescale 1ns/1ps

module tb_alarm_switch_control;

reg clk = 1'b0;
reg rst = 1'b1;
reg sw_front = 1'b0;
reg sw_left = 1'b0;
reg sw_right = 1'b0;
reg sw_rear = 1'b0;
wire hazard_front;
wire hazard_left;
wire hazard_right;
wire hazard_rear;

always #5 clk = ~clk;

alarm_switch_control #(
    .STABLE_CYCLES(4)
) dut (
    .I_clk(clk),
    .I_rst(rst),
    .I_sw_front(sw_front),
    .I_sw_left(sw_left),
    .I_sw_right(sw_right),
    .I_sw_rear(sw_rear),
    .O_hazard_front(hazard_front),
    .O_hazard_left(hazard_left),
    .O_hazard_right(hazard_right),
    .O_hazard_rear(hazard_rear)
);

task expect_state;
    input [2:0] expected;
    begin
        if ({hazard_front, hazard_left, hazard_right} !== expected) begin
            $display("FAIL expected=%b got=%b at %0t", expected,
                     {hazard_front, hazard_left, hazard_right}, $time);
            $fatal(1, "three original channels changed unexpectedly");
        end
    end
endtask

initial begin
    repeat (3) @(posedge clk);
    rst = 1'b0;
    repeat (3) @(posedge clk);
    expect_state(3'b000);

    // Bounce shorter than the qualification interval must be ignored.
    sw_front = 1'b1;
    repeat (2) @(posedge clk);
    sw_front = 1'b0;
    repeat (5) @(posedge clk);
    expect_state(3'b000);

    // A stable assertion is accepted independently on every channel.
    sw_front = 1'b1;
    repeat (8) @(posedge clk);
    expect_state(3'b100);

    sw_left = 1'b1;
    sw_right = 1'b1;
    repeat (8) @(posedge clk);
    expect_state(3'b111);

    // A bouncing release remains asserted until the release is stable.
    sw_left = 1'b0;
    repeat (2) @(posedge clk);
    sw_left = 1'b1;
    repeat (4) @(posedge clk);
    expect_state(3'b111);
    sw_left = 1'b0;
    repeat (8) @(posedge clk);
    expect_state(3'b101);

    sw_rear = 1;
    repeat (2) @(negedge clk);
    sw_rear = 0;
    repeat (8) @(negedge clk);
    if(hazard_rear) $fatal(1,"rear bounce was accepted");
    sw_rear = 1;
    repeat (8) @(negedge clk);
    if(!hazard_rear) $fatal(1,"rear danger was not accepted");
    expect_state(3'b101);
    sw_rear = 0;
    repeat (8) @(negedge clk);
    if(hazard_rear) $fatal(1,"rear release was not accepted");
    $display("PASS tb_alarm_switch_control: four independent debounced directions");
    $finish;
end

endmodule
