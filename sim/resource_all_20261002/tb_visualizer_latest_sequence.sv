`timescale 1ns/1ps
module tb_visualizer_latest_sequence;
reg clk=0,rst=1,vs=0;
reg [111:0] waves=0,bands=0;
reg [3:0] volume=0;
reg [31:0] noise=32'h983a21f5;
integer f,i,c,cycles=0;
always #5 clk=~clk;
`define PORTS .I_clk(clk),.I_rst(rst),.I_enable(1'b1),.I_vs(vs),.I_de(1'b0), \
 .I_rgb(24'd0),.I_vu_left_level(7'd0),.I_vu_right_level(7'd0), \
 .I_spectrum_levels(bands),.I_wave_samples(waves),.I_volume_level(volume), \
 .I_hazard_front(1'b0),.I_hazard_left(1'b0),.I_hazard_right(1'b0),.O_rgb()
audio_visualizer_overlay dut(`PORTS);
audio_visualizer_overlay_resopt_reference ref_dut(`PORTS);
`undef PORTS
always @(posedge clk) begin
    #1;
    if({dut.wave_samples_frame,dut.spectrum_levels_frame,dut.wave_samples_previous_frame} !==
       {ref_dut.wave_samples_frame,ref_dut.spectrum_levels_frame,ref_dut.wave_samples_previous_frame})
        $fatal(1,"visual sequence mismatch frame=%0d cycle=%0d",f,cycles);
    cycles=cycles+1;
end
initial begin
    repeat(4) @(negedge clk); rst=0;
    for(f=0;f<512;f=f+1) begin
        for(i=0;i<16;i=i+1) begin
            noise={noise[30:0],noise[31]^noise[21]^noise[1]^noise[0]};
            waves[i*7+:7]=noise[6:0];
            bands[i*7+:7]=noise[14:8];
        end
        volume=f%16;
        vs=1; @(negedge clk); vs=0;
        // Include interruption by a new frame before the old update drains.
        for(c=0;c<((f%11==0)?5:25);c=c+1) begin
            @(negedge clk);
            if(c==3) begin waves=~waves; bands=~bands; end
        end
        if(f==255) begin rst=1; @(negedge clk); rst=0; end
    end
    $display("PASS VISUAL_SEQUENCE_EQ %0d cycles; all volumes, saturation, snapshot isolation, interrupted frames",cycles);
    $finish;
end
endmodule
