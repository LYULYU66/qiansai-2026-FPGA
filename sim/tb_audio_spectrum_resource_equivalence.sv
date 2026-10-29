`timescale 1ns/1ps
module tb_audio_spectrum_resource_equivalence;
reg clk=0, rst=1, enable=0, valid=0;
reg [23:0] left=0, right=0;
wire [6:0] vl[0:1], vr[0:1];
wire [111:0] bands[0:1];
integer n, epoch, cycles=0, seed=32'h3157;
always #5 clk=~clk;
audio_spectrum_analyzer dut(clk,rst,enable,valid,left,right,vl[0],vr[0],bands[0]);
audio_spectrum_analyzer_resource_reference ref_dut(clk,rst,enable,valid,left,right,vl[1],vr[1],bands[1]);
always @(negedge clk) begin
    cycles=cycles+1;
    // Synchronous RAM adds one cycle per band. Compare every quiescent
    // cycle, after both versions have finished processing the same sample.
    if (dut.state==0 && ref_dut.state==0 &&
        {vl[0],vr[0],bands[0]} !== {vl[1],vr[1],bands[1]})
        $fatal(1,"spectrum output mismatch cycle=%0d state=%0d band=%0d",cycles,dut.state,dut.band_index);
end
initial begin
    repeat(4) @(negedge clk);
    rst=0;
    for(epoch=0;epoch<3;epoch=epoch+1) begin
        enable=1;
        for(n=0;n<2049;n=n+1) begin
            @(negedge clk);
            case(n%8)
                0: begin left=24'h7fffff; right=24'h800000; end
                1: begin left=24'h800000; right=24'h800000; end
                2: begin left=0; right=0; end
                default: begin left=$random(seed); right=$random(seed); end
            endcase
            valid=1;
            @(negedge clk); valid=0;
            repeat(198) @(negedge clk);
            #1;
            if(dut.state!=0 || ref_dut.state!=0)
                $fatal(1,"sample processing exceeded 200 cycles (<520 real cadence)");
            if({vl[0],vr[0],bands[0]} !== {vl[1],vr[1],bands[1]})
                $fatal(1,"settled spectrum mismatch sample=%0d epoch=%0d",n,epoch);
        end
        // Clear and restart to exercise RAM validity without memory reset.
        enable=0;
        repeat(5) @(negedge clk);
    end
    $display("PASS SPECTRUM_EQ 6147 stereo samples; settled outputs bit-identical within 200 cycles (<520 real cadence); extrema, random, partial-block mute/restart");
    $finish;
end
initial begin #20000000; $fatal(1,"spectrum equivalence timeout"); end
endmodule
