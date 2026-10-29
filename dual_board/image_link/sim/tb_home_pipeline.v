`timescale 1ns/1ps
// Actual A video_delay -> transition -> brightness LUT -> palette pipeline.
// The storage test above verifies RGB+tag together; this test verifies that
// the unused SDRAM byte stays aligned all the way to the overlay position.
module tb_home_pipeline;
reg clk=0;always #20 clk=~clk;
reg rst=1,vs=0,de=0;
reg [31:0] read_word=0;
wire [31:0] raw_word;
wire raw_vs,raw_de,raw_hs,transition_vs,transition_de,transition_hs;
wire [23:0] transition_rgb,adjusted_rgb,output_rgb;
wire adjusted_de,adjusted_vs,adjusted_hs,transition_active;
reg [7:0] transition_index;
reg [7:0] indices[0:614399];
reg [1:0] picture=0,requested=0,brightness=3,contrast=0;
reg force_warning=0;
wire enable=picture<2 && !transition_active && !force_warning;
video_delay #(.DATA_WIDTH(32)) delay(
    .video_clk(clk),.rst(rst),.read_en(),.read_data(read_word),
    .hs(1'b0),.vs(vs),.de(de),.hs_r(raw_hs),.vs_r(raw_vs),.de_r(raw_de),.vout_data(raw_word));
video_transition_effects #(.TRANSITION_STEPS(2)) transition(
    .I_clk(clk),.I_rst(rst),.I_frame_vs(vs),.I_hs(raw_hs),.I_vs(raw_vs),.I_de(raw_de),
    .I_rgb_a(raw_word[31:8]),.I_rgb_b(~raw_word[31:8]),.I_display_valid(1'b1),
    .I_requested_idx(requested),.I_frame_read_req(1'b0),.I_force_warning(force_warning),.I_warning_ready(1'b1),
    .O_read_idx_a(),.O_read_idx_b(),.O_read_b_enable(),.O_display_idx(),
    .O_transition_active(transition_active),.O_transition_kind(),.O_transition_step(),
    .O_hs(transition_hs),.O_vs(transition_vs),.O_de(transition_de),.O_rgb(transition_rgb));
always @(posedge clk or posedge rst) begin
    if(rst) transition_index<=0;
    else transition_index<=raw_word[7:0];
end
video_image_adjust #(.USE_LUT_ROM(1)) adjustment(
    .I_clk(clk),.I_rst(rst),.I_hs(transition_hs),.I_vs(transition_vs),.I_de(transition_de),
    .I_rgb(transition_rgb),.I_brightness_level(brightness),.I_contrast_level(contrast),
    .O_hs(adjusted_hs),.O_vs(adjusted_vs),.O_de(adjusted_de),.O_rgb(adjusted_rgb));
video_remote_home_overlay dut(.I_clk(clk),.I_rst(rst),.I_enable(enable),
    .I_de(adjusted_de),.I_index(transition_index),.I_rgb(adjusted_rgb),.O_rgb(output_rgb));
integer frame,x,y,read_count=0,visible_count=0,checked=0;
integer out_x=0,out_y=0;
reg out_de_d=0,out_seen=0;
reg [7:0] expected_index;
reg [23:0] expected_rgb;
integer hidden_pixels=0,opaque_pixels=0;
always @(negedge clk) begin
    if(!rst && delay.de_d[19]) begin
        if(read_count>=307200) $fatal(1,"too many read-side pixels");
        read_word={read_count[23:0],indices[picture*307200+read_count]};
        read_count=read_count+1;
    end else read_word=0;
end
always @(posedge clk) begin
    #2;
    if(!rst) begin
        if(adjusted_vs) begin out_seen=0;out_x=0;out_y=0;end
        if(adjusted_de) begin
            if(!out_de_d) begin out_x=0;if(out_seen)out_y=out_y+1;else out_seen=1;end
            else out_x=out_x+1;
            if(out_x>=640 || out_y>=480) $fatal(1,"unexpected output raster");
            expected_index=indices[picture*307200+out_y*640+out_x];
            expected_rgb=enable && expected_index!=0 ? dut.palette.mem[expected_index] : adjusted_rgb;
            if(output_rgb!==expected_rgb)
                $fatal(1,"pipeline p=%0d x=%0d y=%0d index=%h expected=%h got=%h rgb=%h",picture,out_x,out_y,expected_index,expected_rgb,output_rgb,adjusted_rgb);
            if(!enable) hidden_pixels=hidden_pixels+1;
            if(enable && expected_index!=0) opaque_pixels=opaque_pixels+1;
            visible_count=visible_count+1;checked=checked+1;
        end else if(output_rgb!==adjusted_rgb) $fatal(1,"overlay active in blanking");
        out_de_d=adjusted_de;
    end
end
initial begin
    $readmemh("home_reference_indices.hex",indices);
    repeat(5) @(negedge clk);rst=0;
    for(frame=0;frame<6;frame=frame+1) begin
        picture=frame%2;read_count=0;visible_count=0;
        brightness=frame%4;contrast=(frame+1)%4;
        requested=frame>=3 ? 1 : 0;force_warning=frame==5;
        vs=1;de=0;repeat(5) @(negedge clk);vs=0;repeat(40) @(negedge clk);
        for(y=0;y<480;y=y+1) begin
            de=1;repeat(640) @(negedge clk);
            de=0;repeat(160) @(negedge clk);
        end
        repeat(40) @(negedge clk);
        if(read_count!=307200 || visible_count!=307200) $fatal(1,"frame count %0d/%0d",read_count,visible_count);
    end
    if(hidden_pixels==0 || opaque_pixels==0) $fatal(1,"missing transition/warning/opaque coverage");
    $display("PASS home pipeline: %0d pixels, actual delay/transition/brightness, row/frame edges and warning bypass",checked);$finish;
end
initial begin #100000000;$fatal(1,"home pipeline timeout");end
endmodule
