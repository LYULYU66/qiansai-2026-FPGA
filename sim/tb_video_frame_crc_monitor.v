`timescale 1ns/1ps
module tb_video_frame_crc_monitor;
reg clk=0, rst=1, clear=0, vs=0, de=0, stable=1;
reg [23:0] rgb=0;
reg [1:0] idx=0;
wire changed, valid;
integer k;
reg [15:0] known;
always #20 clk=~clk;
video_frame_crc_monitor #(.FRAME_PIXELS(32)) dut(
 .I_clk(clk),.I_rst(rst),.I_clear(clear),.I_vs(vs),.I_de(de),
 .I_stable(stable),.I_rgb(rgb),.I_image_idx(idx),
 .O_changed(changed),.O_valid(valid));
task boundary;
 begin
    @(negedge clk); de=0; vs=1;
    repeat(3) @(negedge clk); vs=0;
    repeat(3) @(negedge clk);
 end
endtask
task pixels;
 input [23:0] seed;
 input integer count;
 input integer corrupt_at;
 begin
    for(k=0;k<count;k=k+1) begin
        @(negedge clk); de=1;
        rgb=seed ^ (k*24'h010307);
        if(k==corrupt_at) rgb=rgb ^ 24'h000001;
        if(k%8==7) begin
            @(negedge clk); de=0;
            repeat(3) @(negedge clk);
        end
    end
    @(negedge clk); de=0;
 end
endtask
task frame;
 input [23:0] seed;
 input integer count;
 input integer corrupt_at;
 begin pixels(seed,count,corrupt_at); boundary; end
endtask
task clear_flags;
 begin
    @(negedge clk); clear=1;
    repeat(2) @(negedge clk); clear=0;
    if(changed || valid) $fatal(1,"clear did not invalidate baseline");
    boundary;
 end
endtask
task check;
 input c, v;
 begin
    if(changed !== c || valid !== v)
        $fatal(1,"CRC flags got C=%b V=%b expected C=%b V=%b",changed,valid,c,v);
 end
endtask
initial begin
    // Known CRC of ASCII 123456789, initial ffff, polynomial 1021, MSB first.
    known=dut.crc24(16'hffff,24'h313233);
    known=dut.crc24(known,24'h343536);
    known=dut.crc24(known,24'h373839);
    if(known !== 16'h29b1) $fatal(1,"CRC known vector failed: %h",known);
    repeat(4) @(negedge clk); rst=0;
    boundary;
    frame(24'h102030,32,-1); check(0,0);
    frame(24'h102030,32,-1); check(0,1);
    frame(24'h102030,32,0); check(1,1);
    frame(24'h102030,32,-1); check(1,1);
    clear_flags;
    frame(24'h102030,32,-1); frame(24'h102030,32,31); check(1,1);
    // A clear in the middle of active video must discard the partial frame.
    @(negedge clk); clear=1; de=1;
    @(negedge clk); clear=0;
    pixels(24'h222222,23,-1); boundary; check(0,0);
    frame(24'h333333,32,-1); check(0,0);
    frame(24'h333333,32,-1); check(0,1);
    // Transition and image-index changes must not report legitimate changes.
    stable=0; frame(24'h555555,32,-1); check(0,0);
    stable=1; boundary;
    frame(24'h666666,32,-1); check(0,0);
    frame(24'h666666,32,-1); check(0,1);
    idx=1; boundary;
    frame(24'h777777,32,-1); check(0,0);
    frame(24'h777777,32,-1); check(0,1);
    // Incomplete and overlong rasters never produce a valid comparison.
    frame(24'h777777,31,-1); check(0,0);
    frame(24'h777777,32,-1); check(0,0);
    frame(24'h777777,32,-1); check(0,1);
    frame(24'h777777,33,-1); check(0,0);
    frame(24'h777777,32,-1); check(0,0);
    frame(24'h777777,32,-1); check(0,1);
    $display("PASS FRAME_CRC vector, first/last pixel bit faults, clear mid-frame, transition/index exclusions, missing/extra pixels");
    $finish;
end
initial begin #1000000; $fatal(1,"timeout"); end
endmodule

module tb_video_frame_crc_full;
reg clk=0, rst=1, vs=0, de=0;
reg [23:0] rgb=0;
wire changed, valid;
integer f, y, x;
always #20 clk=~clk;
video_frame_crc_monitor dut(.I_clk(clk),.I_rst(rst),.I_clear(1'b0),
 .I_vs(vs),.I_de(de),.I_stable(1'b1),.I_rgb(rgb),.I_image_idx(2'd0),
 .O_changed(changed),.O_valid(valid));
task boundary;
 begin
    @(negedge clk); de=0; vs=1;
    repeat(3) @(negedge clk); vs=0;
    repeat(3) @(negedge clk);
 end
endtask
initial begin
    repeat(4) @(negedge clk); rst=0; boundary;
    for(f=0;f<3;f=f+1) begin
        for(y=0;y<480;y=y+1) begin
            for(x=0;x<640;x=x+1) begin
                @(negedge clk); de=1;
                rgb={x[7:0],y[7:0],x[7:0]^y[7:0]};
                if(f==2 && y==1 && x==5) rgb=rgb ^ 24'h000004;
            end
            @(negedge clk); de=0;
            repeat(159) @(negedge clk);
        end
        boundary;
        if(f==0 && valid) $fatal(1,"full raster baseline early");
        if(f==1 && (!valid || changed)) $fatal(1,"identical full frames mismatch");
        if(f==2 && (!valid || !changed)) $fatal(1,"full-frame pixel fault not detected");
    end
    $display("PASS FRAME_CRC_FULL 3 x 640x480; upper-half single-pixel error detected");
    $finish;
end
initial begin #60000000; $fatal(1,"timeout"); end
endmodule
