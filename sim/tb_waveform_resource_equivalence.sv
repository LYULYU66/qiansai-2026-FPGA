`timescale 1ns/1ps
module tb_waveform_resource_equivalence;
reg clk=0, rst=1, enable=0, valid=0;
reg [23:0] left=0, right=0;
reg [31:0] noise=32'h12345678;
wire [6:0] al, ar, bl, br;
wire [111:0] aw, bw;
integer cycle, publications=0;
reg [111:0] previous=0;
always #5 clk=~clk;
`define PORTS(L,R,W) .I_clk(clk),.I_rst(rst),.I_enable(enable), \
 .I_audio_valid(valid),.I_audio_left(left),.I_audio_right(right), \
 .O_vu_left_level(L),.O_vu_right_level(R),.O_wave_samples(W)
audio_waveform_analyzer dut(`PORTS(al,ar,aw));
audio_waveform_analyzer_resource2_reference ref_dut(`PORTS(bl,br,bw));
`undef PORTS
initial begin
    for(cycle=0;cycle<120000;cycle=cycle+1) begin
        @(negedge clk);
        rst=(cycle<4 || cycle==60000);
        enable=(cycle%17000>5);
        valid=(cycle%3!=0);
        noise={noise[30:0],noise[31]^noise[21]^noise[1]^noise[0]};
        // Silence, DC (timeout capture), alternating full-scale and noise.
        case((cycle/10000)%4)
            0: begin left=0; right=0; end
            1: begin left=24'h400000; right=24'h200000; end
            2: begin left=cycle[4]?24'h800000:24'h7fffff; right=~left; end
            3: begin left=noise[23:0]; right={noise[15:0],noise[31:24]}; end
        endcase
        @(posedge clk); #1;
        if({al,ar,aw} !== {bl,br,bw} || dut.wave_work !== ref_dut.wave_work)
            $fatal(1,"waveform equivalence mismatch cycle=%0d",cycle);
        if(aw!==previous) publications=publications+1;
        previous=aw;
    end
    if(publications<20) $fatal(1,"insufficient publication coverage");
    $display("PASS WAVEFORM_EQ 120000 cycles, %0d publications",publications);
    $finish;
end
endmodule
