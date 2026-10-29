`timescale 1ns/1ps
module tb_visualizer_equivalence;
reg clk=0,rst=1,enable=1,vs=0,de=0;
reg [23:0] rgb=0;
reg [6:0] vu_l=0,vu_r=0;
reg [111:0] bands=0,wave=0;
reg [3:0] volume=8;
reg front=0,left=0,right=0;
wire [23:0] old_rgb,new_rgb;
audio_visualizer_overlay_golden old_dut(clk,rst,enable,vs,de,rgb,vu_l,vu_r,bands,wave,volume,front,left,right,old_rgb);
audio_visualizer_overlay new_dut(clk,rst,enable,vs,de,rgb,vu_l,vu_r,bands,wave,volume,front,left,right,new_rgb);
always #5 clk=~clk;
integer checks=0,frame,row,col,lane,p,complete=0,abort_count=0;
reg [31:0] random_state=32'h84035bce;
always @(posedge clk) begin
    #1;
    if(new_rgb !== old_rgb ||
       {new_dut.spectrum_lane_valid,new_dut.wave_lane_valid,new_dut.wave_lane_updated,new_dut.wave_scaled_valid,new_dut.wave_smooth_busy}
       !==
       {old_dut.spectrum_lane_valid,old_dut.wave_lane_valid,old_dut.wave_lane_updated,old_dut.wave_scaled_valid,old_dut.wave_smooth_busy}) begin
        $display("FAIL visualizer equivalence at check=%0d frame=%0d x=%0d y=%0d old=%h new=%h",checks,frame,old_dut.pixel_x,old_dut.pixel_y,old_rgb,new_rgb);
        $fatal(1);
    end
    if(new_dut.wave_lane_updated==16'hffff && new_dut.wave_scaled_valid==0 && new_dut.wave_smooth_busy==0)
        complete=complete+1;
    checks=checks+1;
end
task tick;
    begin @(negedge clk); end
endtask
task parameters;
    begin
        random_state={random_state[30:0],random_state[31]^random_state[21]^random_state[1]^random_state[0]};
        vu_l=random_state[6:0]; vu_r=random_state[13:7];
        for(lane=0;lane<16;lane=lane+1) begin
            bands[lane*7+:7]=(random_state[7:0]+lane*17)%97;
            wave[lane*7+:7]=$signed((random_state[15:8]+lane*11)%89)-44;
        end
    end
endtask
initial begin
    repeat(5) tick; rst=0;
    // Break each of the possible partial shift passes by reset, disable,
    // and a new VS. The stale scratch data must never reach a valid pixel.
    for(p=0;p<18;p=p+1) begin
        parameters; vs=1; tick; vs=0; repeat(p) tick;
        rst=1; tick; rst=0; abort_count=abort_count+1;
        parameters; vs=1; tick; vs=0; repeat(p) tick;
        enable=0; parameters; vs=1; tick; vs=0; repeat(30) tick; enable=1;
    end
    // Full natural VGA raster; every waveform volume 0..8 is exercised twice,
    // with opposite hazard patterns and transparent/disabled pixels mixed in.
    for(frame=0;frame<18;frame=frame+1) begin
        parameters; volume=frame%9;
        front=frame[0]; left=frame[1]; right=frame[2];
        vs=1; de=0; repeat(160) tick; vs=0; repeat(160) tick;
        for(row=0;row<480;row=row+1) begin
            de=1;
            for(col=0;col<640;col=col+1) begin
                rgb={frame[7:0],row[7:0],col[7:0]};
                enable=(frame!=7 && col%131!=0); tick;
            end
            de=0; repeat(160) tick;
        end
    end
    rst=1; repeat(5) tick;
    if(complete<1000) $fatal(1,"No complete smoothing passes");
    $display("PASS visualizer equivalence: %0d cycle comparisons, 18 complete VGA frames, volumes 0..8, %0d mid-pass resets and VS restarts",checks,abort_count);
    $finish;
end
endmodule
