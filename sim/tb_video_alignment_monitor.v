`timescale 1ns/1ps
module tb_video_alignment_monitor;
reg clk=0,rst=1,clear=0,enable=1;
reg vs=0,de=0,src_user=0,src_last=0,rd=0,empty=0;
reg [23:0] rgb=0;
reg av=0,au=0,al=0,fv=0,raw_de=0;
reg [23:0] ar=0,fr=0,raw_rgb=0;
integer fault=0,idx=0,cases=0;
reg test_passed=0;
wire [4:0] flags;
wire ready;
always #20 clk=~clk;
always @(posedge clk) begin
    if(rst) begin av<=0; au<=0; al<=0; ar<=0; fv<=0; fr<=0; raw_de<=0; raw_rgb<=0; end
    else begin
        av<=de; au<=src_user; al<=src_last; ar<=rgb;
        fv<=rd && !empty;
        if(rd && !empty) fr<=rgb ^ 24'h123400;
        raw_de<=fv; raw_rgb<=fr;
    end
end
video_alignment_monitor #(.H_ACTIVE(8),.V_ACTIVE(3)) dut(
 .I_clk(clk),.I_rst(rst),.I_clear(clear),.I_enable(enable),
 .I_source_vs(vs),.I_source_de(de),.I_source_rgb(rgb),
 .I_axis_valid(av && !(fault==4)),
 .I_axis_user(au ^ ((fault==1) && av)),
 .I_axis_last(al ^ ((fault==2) && av)),
 .I_axis_rgb(ar ^ ((fault==3) ? 24'h000001 : 24'd0)),
 .I_read_en(rd),.I_empty_a(empty),
 .I_fifo_valid(fv ^ ((fault==5) && rd)),.I_fifo_rgb(fr),
 .I_raw_de(raw_de ^ ((fault==6) && rd)),
 .I_raw_rgb(raw_rgb ^ ((fault==7) ? 24'h000080 : 24'd0)),
 .O_flags(flags),.O_ready(ready));
task tick;
 input v,d,u,l;
 input [23:0] p;
 begin
    @(negedge clk); vs=v; de=d; src_user=u; src_last=l; rgb=p; rd=d;
    @(posedge clk); #2;
 end
endtask
task boundary;
 begin
    repeat(4) tick(0,0,0,0,0);
    repeat(4) tick(1,0,0,0,0);
    repeat(4) tick(0,0,0,0,0);
 end
endtask
task pixels;
 input integer rows,width;
 integer x,y;
 begin
    idx=0;
    for(y=0;y<rows;y=y+1) begin
        for(x=0;x<width;x=x+1) begin
            tick(0,1,y==0 && x==0,x==7,24'h100000+idx); idx=idx+1;
        end
        repeat(5) tick(0,0,0,0,0);
    end
 end
endtask
task clear_flags;
 begin
    @(negedge clk); clear=1;
    @(posedge clk); #2;
    if(flags!==0 || ready!==0) $fatal(1,"clear failed flags=%b ready=%b",flags,ready);
    @(negedge clk); clear=0;
 end
endtask
task check_case;
 input integer f,rows,width;
 input [4:0] expected;
 begin
    fault=0; clear_flags; boundary;
    if(ready!==0) $fatal(1,"Ready before a complete frame");
    fault=f; pixels(rows,width); fault=0; boundary;
    if(flags!==expected || ready!==1)
        $fatal(1,"Monitor fault=%0d rows=%0d width=%0d flags=%b expected=%b ready=%b",f,rows,width,flags,expected,ready);
    // Good frames must never erase sticky error evidence.
    pixels(3,8); boundary;
    if(flags!==expected) $fatal(1,"Sticky flags lost");
    cases=cases+1;
 end
endtask
initial begin
    repeat(5) @(negedge clk); rst=0;
    check_case(0,3,8,5'b00000);
    check_case(1,3,8,5'b00001);
    check_case(2,3,8,5'b00010);
    check_case(3,3,8,5'b10000);
    check_case(4,3,8,5'b10000);
    check_case(5,3,8,5'b01000);
    check_case(6,3,8,5'b01000);
    check_case(7,3,8,5'b01000);
    check_case(0,3,7,5'b00010);
    check_case(0,3,9,5'b00010);
    check_case(0,2,8,5'b00100);
    check_case(0,4,8,5'b00100);
    clear_flags; enable=0; fault=3; boundary; pixels(3,8); boundary;
    if(flags!==0 || ready!==0) $fatal(1,"Disabled monitor raised flags");
    fault=0; enable=1; boundary; pixels(3,8); boundary;
    if(flags!==0 || ready!==1) $fatal(1,"Enable rearm failed");
    // Clear during active video, discard remainder without false SOF/length errors.
    tick(0,1,1,0,24'h200000); tick(0,1,0,0,24'h200004);
    clear_flags;
    repeat(3) tick(0,1,0,0,24'h200008);
    boundary; pixels(3,8); boundary;
    if(flags!==0 || ready!==1) $fatal(1,"Mid-frame clear/rearm failed");
    test_passed=1;
    $display("PASS ALIGNMENT_MONITOR cases=%0d S/L/F/R/E fault isolation, sticky flags, enable gate, mid-frame clear, ready",cases);
    $finish;
end
initial begin #2000000; $fatal(1,"timeout"); end
endmodule
