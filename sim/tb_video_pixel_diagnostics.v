`timescale 1ns/1ps
module tb_video_pixel_diagnostics;
reg clk=0, rst=1;
always #20 clk=~clk;
reg [1:0] mode=0;
reg clear_toggle=0, vs=0, de=0;
reg [23:0] image_rgb=24'h486888;
wire [23:0] image_out, adjusted, final_rgb;
wire adjusted_de;
wire [23:0] overlay_rgb=adjusted ^ 24'h040810;
reg monitor_en=0, rd=0, empty_a=0, empty_b=0, ben=0;
reg av=0, ar=1, locked=0;
wire [12:0] status;
integer k, y, errors=0;
reg [23:0] expected_rgb;
reg [7:0] grey;
video_pixel_diagnostics dut(
 .I_clk(clk),.I_rst(rst),.I_requested_mode(mode),.I_clear_toggle(clear_toggle),
 .I_vs(vs),.I_de(de),.I_image_rgb(image_rgb),.I_processed_rgb(overlay_rgb),
 .I_monitor_enable(monitor_en),.I_read_en(rd),.I_empty_a(empty_a),
 .I_empty_b(empty_b),.I_read_b_enable(ben),.I_axis_valid(av),
 .I_axis_ready(ar),.I_hdmi_locked(locked),.O_image_rgb(image_out),
 .O_final_rgb(final_rgb),.O_status(status),
 .I_crc_vs(vs),.I_crc_de(de),.I_crc_rgb(image_rgb),
 .I_crc_stable(1'b0),.I_crc_image_idx(2'd0),
 .I_axis_source_vs(1'b0),.I_axis_source_de(1'b0),.I_axis_source_rgb(24'd0),
 .I_axis_data(24'd0),.I_axis_user(1'b0),.I_axis_last(1'b0),
 .I_fifo_valid_a(1'b0),.I_fifo_rgb_a(24'd0));
video_image_adjust adjust(.I_clk(clk),.I_rst(rst),.I_hs(1'b0),.I_vs(vs),
 .I_de(de),.I_rgb(image_out),.I_brightness_level(2'd3),.I_contrast_level(2'd0),
 .O_hs(),.O_vs(),.O_de(adjusted_de),.O_rgb(adjusted));
task frame_boundary;
 begin
    @(negedge clk); de=0; vs=1;
    repeat(3) @(negedge clk); vs=0;
    repeat(3) @(negedge clk);
 end
endtask
task check_lines;
 input [1:0] active_mode;
 begin
    for(y=0;y<4;y=y+1) begin
        for(k=0;k<640;k=k+1) begin
            @(negedge clk); de=1;
            image_rgb={8'h48,8'h68,8'h88};
            grey=((k>>4)&7)*8;
            if(active_mode==0) expected_rgb=image_rgb ^ 24'h040810;
            else if(active_mode==1) expected_rgb={grey,grey,grey} ^ 24'h040810;
            else expected_rgb={grey,grey,grey};
            @(posedge clk); #1;
            if(!adjusted_de || final_rgb !== expected_rgb)
                $fatal(1,"Pixel alignment mode=%0d line=%0d x=%0d rgb=%h expected=%h",active_mode,y,k,final_rgb,expected_rgb);
        end
        @(negedge clk); de=0;
        repeat(6) @(negedge clk);
    end
 end
endtask
initial begin
    $dumpfile("sim/video_pixel_diagnostics.vcd");
    $dumpvars(0,tb_video_pixel_diagnostics);
    repeat(5) @(negedge clk); rst=0;
    check_lines(0);
    mode=1;
    repeat(8) @(negedge clk);
    if(status[4:3] !== 0) $fatal(1,"Mode changed outside frame boundary");
    frame_boundary;
    if(status[4:3] !== 1) $fatal(1,"Mode 1 not committed");
    check_lines(1);
    mode=2; repeat(8) @(negedge clk); frame_boundary;
    check_lines(2);
    mode=0; repeat(8) @(negedge clk); frame_boundary;
    check_lines(0);
    // Gate startup and disabled B; ready stalls count only after video lock.
    rd=1; empty_a=1; empty_b=1; av=1; ar=0;
    repeat(3) @(negedge clk);
    if(status[2:0] !== 0) $fatal(1,"Counted event before monitor enabled");
    monitor_en=1;
    repeat(3) @(negedge clk);
    if(status[2:0] !== 3'b001) $fatal(1,"Disabled B/unlocked H falsely set");
    ben=1; locked=1;
    repeat(3) @(negedge clk);
    if(status[2:0] !== 3'b111) $fatal(1,"Missing event");
    rd=0; av=0;
    repeat(3) @(negedge clk);
    if(status[2:0] !== 3'b111) $fatal(1,"Flags not sticky");
    clear_toggle=1; repeat(6) @(negedge clk);
    if(status[2:0] !== 0) $fatal(1,"DCLEAR not synchronized");
    rd=1; repeat(3) @(negedge clk); rd=0;
    if(status[2:0] !== 3'b011) $fatal(1,"Flags failed to re-arm");
    clear_toggle=0; repeat(6) @(negedge clk);
    if(status[2:0] !== 0) $fatal(1,"Second DCLEAR not synchronized");
    $display("PASS PIXEL_DIAGNOSTICS 10240 pixels; frame-boundary switching; sticky A/B/H; clear/re-arm");
    $finish;
end
initial begin #1000000; $fatal(1,"timeout"); end
endmodule
