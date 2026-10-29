`timescale 1ns/1ps
module tb_video_sof_boundaries;
reg clk=0, rst=1, vs=0, de=0;
reg [23:0] rgb=0;
reg expect_sof=0, expect_last=0;
wire user, valid, last;
wire [23:0] data;
integer frames=0, pixels=0, x, y, f;
always #20 clk=~clk;
video_rgb_to_axis_640x480 dut(clk,rst,vs,de,rgb,user,valid,last,data);
always @(posedge clk) begin
    #1;
    if (!rst) begin
        if (valid !== de || user !== expect_sof || last !== expect_last)
            $fatal(1,"SOF/DE/EOL mismatch frame=%0d pixel=%0d de=%b user=%b expected_user=%b last=%b expected_last=%b",
                   frames,pixels,de,user,expect_sof,last,expect_last);
        if (valid) begin
            if (data !== rgb) $fatal(1,"RGB not aligned with VALID");
            pixels=pixels+1;
        end
    end
end
task line;
    input first;
    input coincident_vs;
    begin
        for (x=0;x<640;x=x+1) begin
            @(negedge clk);
            de=1; rgb=24'h010203+x;
            expect_sof=first && x==0; expect_last=x==639;
            if (coincident_vs && x==0) vs=~vs;
        end
        @(negedge clk);
        de=0; expect_sof=0; expect_last=0;
        repeat (7) @(negedge clk);
    end
endtask
initial begin
    $dumpfile("sim/video_sof_boundaries.vcd");
    $dumpvars(0,tb_video_sof_boundaries);
    repeat (4) @(negedge clk); rst=0;
    line(1,0); line(0,0); frames=frames+1;
    // VS and the first pixel arrive together while frame_arm is clear.
    line(1,1); line(0,0); frames=frames+1;
    for(f=0;f<8;f=f+1) begin
        @(negedge clk); vs=~vs;
        repeat (f%4) @(negedge clk);
        line(1,0); line(0,0); frames=frames+1;
    end
    // Both edges in vertical blanking, followed by a complete frame.
    @(negedge clk); vs=1;
    repeat (1600) @(negedge clk); vs=0;
    repeat (26400) @(negedge clk);
    $dumpoff;
    for(y=0;y<480;y=y+1) line(y==0,0);
    frames=frames+1;
    $display("PASS SOF_BOUNDARIES frames=%0d pixels=%0d",frames,pixels);
    $finish;
end
endmodule
