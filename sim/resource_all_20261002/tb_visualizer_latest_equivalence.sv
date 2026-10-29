`timescale 1ns/1ps
module tb_visualizer_latest_equivalence;
reg clk=0,rst=1,en=1,vs=0,de=0;
reg [23:0] rgb=24'h456789;
reg [111:0] bands=0,waves=0;
reg [3:0] volume=8;
reg [2:0] hazard=0;
wire [23:0] actual,expected;
integer x,y,f,i,pixels=0;
always #5 clk=~clk;
`define VIS_PORTS(OUT) .I_clk(clk),.I_rst(rst),.I_enable(en),.I_vs(vs),.I_de(de), \
 .I_rgb(rgb),.I_vu_left_level(7'd96),.I_vu_right_level(7'd39), \
 .I_spectrum_levels(bands),.I_wave_samples(waves),.I_volume_level(volume), \
 .I_hazard_front(hazard[2]),.I_hazard_left(hazard[1]),.I_hazard_right(hazard[0]),.O_rgb(OUT)
audio_visualizer_overlay dut(`VIS_PORTS(actual));
audio_visualizer_overlay_resopt_reference ref_dut(`VIS_PORTS(expected));
`undef VIS_PORTS
initial begin
    repeat(4) @(negedge clk); rst=0;
    for(f=0;f<4;f=f+1) begin
        volume=(f==0)?0:(f==1)?3:8; hazard=f; en=(f!=3);
        for(i=0;i<16;i=i+1) begin
            bands[i*7+:7]=(i*13+f*29)%97;
            waves[i*7+:7]=(i*17+f*11)%89-44;
        end
        repeat(6) @(negedge clk); vs=1;
        repeat(2) @(negedge clk); vs=0;
        repeat(32) @(negedge clk);
        for(y=0;y<480;y=y+1) begin
            for(x=0;x<640;x=x+1) begin
                @(negedge clk); de=1;
                rgb={rgb[22:0],rgb[23]^rgb[22]^rgb[21]^rgb[16]};
                @(posedge clk); #1;
                if(actual !== expected)
                    $fatal(1,"visual pixel mismatch f=%0d x=%0d y=%0d got=%h expected=%h",f,x,y,actual,expected);
                if(dut.spectrum_x_hit !== ref_dut.spectrum_x_hit ||
                   (dut.spectrum_x_hit && dut.spectrum_index !== ref_dut.spectrum_index))
                    $fatal(1,"spectrum geometry mismatch x=%0d",x);
                pixels=pixels+1;
            end
            @(negedge clk); de=0;
            repeat(4) @(negedge clk);
        end
    end
    $display("PASS VISUAL_EQ %0d pixels bit-identical: spectrum, waveform, VU, volume, hazards, bypass",pixels);
    $finish;
end
initial begin #20000000; $fatal(1,"visual equivalence timeout"); end
endmodule
