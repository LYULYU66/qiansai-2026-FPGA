`timescale 1ns/1ps
module tb_bmp_bilinear_stream;
parameter W=7,H=5,FULL=0;
reg clk=0,rst=1,start=0,valid=0;
reg [15:0] sw=1,sh=1;
reg [7:0] data=0;
wire credit,busy,done,overflow,pv;
wire [23:0] rgb;
integer count=0,tests=0,seed=32'h18745;
reg checking=0;
reg pixel_ready=1;
integer stalls=0;
always #5 clk=~clk;
bmp_bilinear_stream #(.OUT_WIDTH(W),.OUT_HEIGHT(H)) dut(
 .clk(clk),.rst(rst),.start(start),.source_width(sw),.source_height(sh),
 .byte_valid(valid),.byte_data(data),.pixel_ready(pixel_ready),.sector_ready(credit),.busy(busy),
 .done(done),.overflow(overflow),.pixel_valid(pv),.pixel_rgb(rgb));
function integer sample(input integer x,y,c);
    sample=(x*(17+c*31)+y*(37+c*13)+c*67+11)&255;
endfunction
function [23:0] reference_pixel(input integer dx,dy);
    integer qx,qy,x0,x1,y0,y1,fx,fy,c;
    reg [63:0] a,b,v;
    begin
        qx=(64'(dx)*(sw-1)*256)/(W-1); qy=(64'(dy)*(sh-1)*256)/(H-1);
        x0=qx>>8; x1=(x0<sw-1)?x0+1:x0;
        y0=qy>>8; y1=(y0<sh-1)?y0+1:y0; fx=qx&255; fy=qy&255;
        reference_pixel=0;
        for(c=0;c<3;c=c+1) begin
            a=sample(x0,y0,c)*(256-fx)+sample(x1,y0,c)*fx;
            b=sample(x0,y1,c)*(256-fx)+sample(x1,y1,c)*fx;
            v=(a*(256-fy)+b*fy+32768)>>16;
            reference_pixel[c*8 +: 8]=v[7:0];
        end
    end
endfunction
always @(negedge clk) if(checking) begin
    if(overflow) $fatal(1,"FIFO overflow");
    if(pv) begin
        if(count>=W*H || rgb!==reference_pixel(count%W,count/W))
            $fatal(1,"case %0dx%0d out=%0d got=%h expected=%h xq=%h yq=%h",sw,sh,count,rgb,reference_pixel(count%W,count/W),dut.x_pos,dut.y_pos);
        count=count+1;
    end
end
always @(negedge clk) begin
    if(!FULL && checking) begin
        if(stalls>0) begin pixel_ready=0; stalls=stalls-1; end
        else if(($random(seed)&127)==0) begin stalls=200; pixel_ready=0; end
        else pixel_ready=1;
    end else pixel_ready=1;
end
task run_case(input integer sx,sy);
    integer n,limit,stride,row,col,c,sector_left,watch;
    begin
        checking=0; valid=0; start=0; rst=1;
        repeat(5) @(posedge clk); @(negedge clk); rst=0; sw=sx; sh=sy; count=0;
        repeat(4) @(posedge clk); @(negedge clk); checking=1; start=1;
        @(negedge clk); start=0;
        stride=((sx*3+3)/4)*4; limit=stride*sy; n=0;
        while(n<limit) begin
            valid=0; watch=0;
            while(!credit) begin
                @(negedge clk); watch=watch+1;
                if(watch>W*H*30+10000) $fatal(1,"credit timeout");
            end
            sector_left=(limit-n>512)?512:limit-n;
            repeat(sector_left) begin
                row=n/stride; col=(n%stride)/3; c=(n%stride)%3;
                data=(col<sx)?sample(col,row,c):8'hA5; valid=1; n=n+1;
                @(negedge clk);
                if(($random(seed)&7)==0 && !FULL) begin valid=0; @(negedge clk); end
            end
        end
        valid=0; watch=0;
        while(!done) begin @(negedge clk); watch=watch+1;
            if(watch>W*H*30+10000) $fatal(1,"output timeout state=%d count=%d src=%dx%d",dut.state,count,dut.source_x,dut.source_y);
        end
        repeat(3) @(negedge clk);
        if(count!=W*H) $fatal(1,"wrong pixel count %d",count);
        tests=tests+1; $display("PASS bilinear %0dx%0d -> %0dx%0d (%0d pixels)",sx,sy,W,H,count);
    end
endtask
integer i,abort_stage,warm_count;
initial begin
    if(FULL==3) begin run_case(1280,960); end
    else if(FULL==2) begin run_case(1280,720); run_case(1920,1080); end
    else if(FULL) begin run_case(640,480); end
    else begin
        run_case(W,H); run_case(W+1,H); run_case(W,H+1); run_case(W*2,H*2);
        run_case(W*3+5,H); run_case(W,H*3+1); run_case(31,17); run_case(19,17);
        run_case(128,19); run_case(17,33);
        for(i=1;i<=21;i=i+1) run_case(W+i,H+22-i);
        // Abort at each pipeline region, then prove stale RAM is inaccessible.
        for(i=0;i<11;i=i+1) begin
            case(i)
                0:abort_stage=1; 1:abort_stage=3; 2:abort_stage=4;
                3:abort_stage=6; 4:abort_stage=7; 5:abort_stage=8;
                6:abort_stage=9; 7:abort_stage=14; 8:abort_stage=15;
                9:abort_stage=19; default:abort_stage=20;
            endcase
            @(negedge clk); checking=0; valid=0; rst=1;
            repeat(5) @(negedge clk); rst=0; start=1; sw=W+6; sh=H+5;
            @(negedge clk); start=0; data=8'h55; warm_count=0;
            while(dut.state!=abort_stage) begin
                valid=warm_count<512; @(negedge clk); warm_count=warm_count+1;
                if(warm_count>20000) $fatal(1,"cannot reach abort stage %d",abort_stage);
            end
            valid=0; rst=1; #1;
            if(pv || busy || done) $fatal(1,"abort failed at stage %d",abort_stage);
            run_case(W+i%4,H+i%3);
        end
    end
    $display("PASS scaler regression %0d cases",tests); $finish;
end
initial begin #2000000000; $fatal(1,"global watchdog"); end
endmodule
