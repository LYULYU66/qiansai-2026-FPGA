`timescale 1ns/1ps
// Simulation-only candidate; production source remains the rollback version.
module sof_same_beat_candidate(input clk,rst,vs,de,output reg user);
reg vs_d,de_d,pending;
wire edge_now=vs!=vs_d;
always @(posedge clk or posedge rst)
    if(rst) begin vs_d<=0; de_d<=0; pending<=1; user<=0; end
    else begin
        vs_d<=vs; de_d<=de;
        user<=de && !de_d && (pending || edge_now);
        if(de && !de_d && (pending || edge_now)) pending<=0;
        else if(edge_now) pending<=1;
    end
endmodule
module tb_sof_phase_sweep;
reg clk=0,rst=1,vs=0,de=0;
reg [23:0] rgb=0;
reg expect_user=0,expect_last=0,allow_boundary_error=0;
wire user,valid,last,candidate_user;
wire [23:0] data;
integer offset=-8,polarity,x,frame_count=0,baseline_errors=0,candidate_errors=0;
reg test_passed=0;
always #20 clk=~clk;
video_rgb_to_axis_640x480 dut(clk,rst,vs,de,rgb,user,valid,last,data);
sof_same_beat_candidate candidate(clk,rst,vs,de,candidate_user);
always @(posedge clk) begin
    #1;
    if(!rst) begin
        if(valid!==de || data!==rgb || last!==expect_last) $fatal(1,"DATA/VALID/LAST alignment failure");
        if(user!==expect_user) begin
            baseline_errors=baseline_errors+1;
            $display("BASELINE_SOF_ERROR offset=%0d polarity=%0d time=%0t user=%b expected=%b",offset,polarity,$time,user,expect_user);
            if(!allow_boundary_error) $fatal(1,"Unexpected normal-blanking SOF error");
        end
        if(candidate_user!==expect_user) candidate_errors=candidate_errors+1;
    end
end
task line;
 input first;
 input toggle_at_first;
 begin
    for(x=0;x<640;x=x+1) begin
        @(negedge clk); de=1; rgb=24'h100000+x;
        expect_user=first && x==0; expect_last=x==639;
        if(toggle_at_first && x==0) vs=~vs;
    end
    @(negedge clk); de=0; expect_user=0; expect_last=0;
    repeat(160) @(negedge clk);
 end
endtask
initial begin
    repeat(4) @(negedge clk); rst=0;
    line(1,0); line(0,0);
    for(offset=-8;offset<=0;offset=offset+1) begin
        for(polarity=0;polarity<2;polarity=polarity+1) begin
            allow_boundary_error=(offset==0);
            if(offset<0) begin
                @(negedge clk); vs=~vs;
                repeat(-offset-1) @(negedge clk);
            end
            line(1,offset==0); line(0,0);
            frame_count=frame_count+1;
        end
    end
    if(baseline_errors!=4 || candidate_errors!=0)
        $fatal(1,"Unexpected sweep result baseline=%0d candidate=%0d",baseline_errors,candidate_errors);
    test_passed=1;
    $display("PASS SOF_SWEEP cases=%0d normal_cases=16 coincident_cases=2 baseline_errors=%0d candidate_errors=%0d",frame_count,baseline_errors,candidate_errors);
    $finish;
end
initial begin #5000000; $fatal(1,"timeout"); end
endmodule
