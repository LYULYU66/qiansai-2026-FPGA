`timescale 1ns/1ps
module tb_wave_resource_equivalence;
reg clk=0, rst=1, enable=0, valid=0;
reg [23:0] left=0, right=0;
wire [6:0] old_l,old_r,new_l,new_r;
wire [111:0] old_wave,new_wave;
audio_waveform_analyzer_golden old_dut(clk,rst,enable,valid,left,right,old_l,old_r,old_wave);
audio_waveform_analyzer new_dut(clk,rst,enable,valid,left,right,new_l,new_r,new_wave);
always #5 clk=~clk;
integer cycle,checks=0,published=0,resets_in_capture=0;
reg [31:0] random_state=32'hd34b8e29;
reg signed [15:0] level;
always @(posedge clk) begin
    if(!rst && enable && valid && old_dut.capture_step && old_dut.capture_index==15)
        published=published+1;
    #1;
    if({new_l,new_r,new_wave} !== {old_l,old_r,old_wave}) begin
        $display("FAIL waveform equivalence cycle=%0d old=%h new=%h",checks,{old_l,old_r,old_wave},{new_l,new_r,new_wave});
        $fatal(1);
    end
    checks=checks+1;
end
initial begin
    repeat(4) @(negedge clk);
    rst=0; enable=1;
    for(cycle=0;cycle<800000;cycle=cycle+1) begin
        @(negedge clk);
        random_state={random_state[30:0],random_state[31]^random_state[21]^random_state[1]^random_state[0]};
        valid=(cycle<400000) ? 1'b1 : random_state[2:0]!=0;
        // Steady crossings, silence/timeout, full-range noise, asymmetric
        // stereo, and changing amplitudes cover partial and complete traces.
        if(cycle<200000) begin
            level=(cycle%128<64) ? -16'sd24000 : 16'sd24000;
            left={level,8'd0}; right={level>>>1,8'd0};
        end else if(cycle<300000) begin left=0; right=0; end
        else begin left={random_state[15:0],8'd0}; right={random_state[31:16],8'd0}; end
        if(cycle%7319==123 && old_dut.capture_active) begin
            rst=1; resets_in_capture=resets_in_capture+1;
        end else rst=0;
        enable=cycle%9991>=7;
    end
    @(negedge clk); rst=1;
    repeat(3) @(negedge clk);
    if(published<100 || resets_in_capture<3) $fatal(1,"Insufficient waveform coverage");
    $display("PASS waveform equivalence: %0d cycle comparisons, %0d published traces, %0d mid-capture resets",checks,published,resets_in_capture);
    $finish;
end
endmodule

module tb_status_resource_equivalence;
reg clk=0,rst=1,enable=1,vs=0,de=0;
reg [23:0] rgb=24'h214871;
reg [1:0] bri=3,con=0;
reg [3:0] vol=8;
reg [15:0] width=0,height=0;
wire [23:0] old_rgb,new_rgb;
video_status_overlay_golden #(.ENABLE_RESOLUTION(1)) old_dut(clk,rst,enable,vs,de,rgb,bri,con,vol,width,height,old_rgb);
video_status_overlay #(.ENABLE_RESOLUTION(1)) new_dut(clk,rst,enable,vs,de,rgb,bri,con,vol,width,height,new_rgb);
always #5 clk=~clk;
integer checks=0,value,frame,row,col,idx;
reg [10:0] forced_rel;
always @(posedge clk) begin
    #1;
    if(new_rgb !== old_rgb ||
        {new_dut.width_bcd,new_dut.height_bcd,new_dut.width_digits,new_dut.height_digits,
         new_dut.width_frame_bcd,new_dut.height_frame_bcd,new_dut.width_frame_digits,new_dut.height_frame_digits}
        !==
        {old_dut.width_bcd,old_dut.height_bcd,old_dut.width_digits,old_dut.height_digits,
         old_dut.width_frame_bcd,old_dut.height_frame_bcd,old_dut.width_frame_digits,old_dut.height_frame_digits}) begin
        $display("FAIL status equivalence check=%0d size=%0dx%0d pixel=%0d,%0d old=%h new=%h",checks,width,height,old_dut.pixel_x,old_dut.pixel_y,old_rgb,new_rgb);
        $fatal(1);
    end
    checks=checks+1;
end
task tick;
    begin @(negedge clk); end
endtask
initial begin
    repeat(4) tick;
    rst=0;
    // Exhaust the entire old decoder's 11-bit input, including out-of-row
    // coordinates; this is independent of font rendering.
    force old_dut.next_text_rel_x=forced_rel;
    force new_dut.next_text_rel_x=forced_rel;
    for(idx=0;idx<2048;idx=idx+1) begin
        forced_rel=idx; #1;
        if({old_dut.next_char_index,old_dut.next_char_cell_x} !==
           {new_dut.next_char_index,new_dut.next_char_cell_x}) $fatal(1,"Character decoder mismatch at %0d",idx);
    end
    release old_dut.next_text_rel_x;
    release new_dut.next_text_rel_x;
    // Every possible 16-bit dimension and all digit boundaries. Comparison
    // includes conversion completion timing, not just the final digits.
    for(value=0;value<65536;value=value+1) begin
        width=value; height=65535-value;
        repeat(23) tick;
    end
    // Actual raster text pixels with all 4x4x9 parameter combinations and
    // frame-boundary commits; random underlying background and enable.
    for(frame=0;frame<144;frame=frame+1) begin
        bri=frame/36; con=(frame/9)%4; vol=frame%9;
        width=(frame%2) ? 1280 : 640; height=(frame%2) ? 960 : 480;
        vs=1; de=0; repeat(40) tick; vs=0; repeat(10) tick;
        for(row=0;row<32;row=row+1) begin
            de=1;
            for(col=0;col<640;col=col+1) begin
                rgb={frame[7:0],row[7:0],col[7:0]};
                enable=(col%137!=0); tick;
            end
            de=0; repeat(10) tick;
        end
    end
    rst=1; repeat(4) tick;
    $display("PASS status equivalence: %0d cycle comparisons, 2048 decoder values, 65536 dimension pairs, 144 raster parameter combinations",checks);
    $finish;
end
endmodule
