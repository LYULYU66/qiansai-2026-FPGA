`timescale 1ns/1ps
// Real project DMA/FIFO/delay; SDRAM is an ordered 8-cycle response model.
// +STARVE validates the underflow detector by preventing initial prefetch.
module tb_video_fifo_alignment;
reg mem_clk=0, video_clk=0, rst=1;
always #5 mem_clk=~mem_clk;
initial begin #3; forever #20 video_clk=~video_clk; end
reg de=0, hs=0, vs=0, read_req=0;
wire ack, aclr, app_rd, busy, want, finish;
wire [20:0] addr;
wire [8:0] wrusedw, rdusedw;
wire empty, full, fifo_valid, read_en, de_r, hs_r, vs_r;
wire [31:0] dout;
wire [23:0] rgb;
reg [7:0] response_valid=0;
reg [31:0] response_data[0:7];
integer mem_cycles=0, i;
reg starve=0, starve_hold=0;
wire grant=!starve_hold && (mem_cycles%1200>=310);
integer frame, y, x, read_count=0, pixel_count=0, total_pixels=0;
integer min_start=512, min_used=512, underflows=0, mismatch=0;
integer line_count=0;
reg read_en_d=0;
function [31:0] pattern;
    input [20:0] a;
    begin
        pattern={3'b000,a[4:0],3'b000,a[9:5],3'b000,a[14:10],8'h00};
    end
endfunction
frame_fifo_read #(.BURST_SIZE(256)) dma(
 .rst(rst),.mem_clk(mem_clk),.Sdr_init_done(!rst),
 .Sdr_init_ref_vld(1'b0),.Sdr_busy(1'b0),.Sdr_rd_en(response_valid[7]),
 .App_wr_busy(1'b0),.O_rd_busy(busy),.I_rd_grant(grant),.O_rd_want(want),
 .App_rd_en(app_rd),.App_rd_addr(addr),.read_req(read_req),.read_req_ack(ack),
 .read_finish(finish),.read_addr_0(21'd0),.read_addr_1(21'd0),
 .read_addr_2(21'd0),.read_addr_3(21'd0),.read_addr_index(2'd0),
 .read_len(21'd307200),.fifo_aclr(aclr),.wrusedw({1'b0,wrusedw}));
rfifo_32_32_512 fifo(
 .rst(rst|aclr),.clkw(mem_clk),.clkr(video_clk),
 .we(response_valid[7]),.di(response_data[7]),.re(read_en),.dout(dout),
 .valid(fifo_valid),.full_flag(full),.empty_flag(empty),
 .afull(),.aempty(),.wrusedw(wrusedw),.rdusedw(rdusedw));
video_delay delay(.video_clk(video_clk),.rst(rst),.read_en(read_en),
 .read_data(dout[31:8]),.hs(hs),.vs(vs),.de(de),
 .hs_r(hs_r),.vs_r(vs_r),.de_r(de_r),.vout_data(rgb));
always @(posedge mem_clk) begin
    mem_cycles<=mem_cycles+1;
    if(rst || aclr) response_valid<=0;
    else begin
        response_valid<={response_valid[6:0],app_rd};
        response_data[0]<=pattern(addr);
        for(i=1;i<8;i=i+1) response_data[i]<=response_data[i-1];
        if(response_valid[7] && full) $fatal(1,"FIFO overflow");
    end
end
always @(posedge video_clk) begin
    if(!rst) begin
        if(read_en) begin
            if(!read_en_d) begin
                if(rdusedw<min_start) min_start=rdusedw;
                if(line_count<3) $display("LINE_START frame=%0d line=%0d rdusedw=%0d empty=%b time=%0t",frame,line_count,rdusedw,empty,$time);
                line_count=line_count+1;
            end
            if(rdusedw<min_used) min_used=rdusedw;
            if(empty) underflows=underflows+1;
            read_count=read_count+1;
        end
        read_en_d=read_en;
        #1;
        if(de_r) begin
            if(rgb !== (pattern(pixel_count)>>8)) begin
                mismatch=mismatch+1;
                if(!starve) $fatal(1,"FIFO/RGB alignment frame=%0d pixel=%0d got=%h expected=%h",frame,pixel_count,rgb,pattern(pixel_count)>>8);
            end
            pixel_count=pixel_count+1;
            total_pixels=total_pixels+1;
        end
    end
end
initial begin
    starve=$test$plusargs("STARVE"); starve_hold=starve;
    if(starve) $dumpfile("sim/video_fifo_starvation.vcd");
    else $dumpfile("sim/video_fifo_alignment.vcd");
    // Ports only: never dump the FIFO RAM array.
    $dumpvars(1,tb_video_fifo_alignment); $dumpoff;
    repeat(8) @(negedge video_clk); rst=0;
    for(frame=0;frame<2;frame=frame+1) begin
        read_count=0; pixel_count=0; line_count=0;
        @(negedge video_clk); vs=1; read_req=1;
        wait(ack);
        @(negedge video_clk); read_req=0;
        repeat(1600) @(negedge video_clk); vs=0;
        repeat(26400) @(negedge video_clk);
        $dumpon;
        for(y=0;y<480;y=y+1) begin
            for(x=0;x<800;x=x+1) begin
                @(negedge video_clk);
                de=(x<640); hs=(x>=656 && x<752);
                if(starve && x==120) starve_hold=0;
            end
            if(y==2) $dumpoff;
            if(starve && y==2) begin
                if(underflows==0 || mismatch==0) $fatal(1,"Starvation not detected");
                $display("PASS STARVATION_DETECTED empty_reads=%0d corrupt_pixels=%0d",underflows,mismatch);
                $finish;
            end
        end
        repeat(32) @(negedge video_clk);
        if(read_count!=307200 || pixel_count!=307200)
            $fatal(1,"Frame length read=%0d display=%0d",read_count,pixel_count);
    end
    if(underflows!=0) $fatal(1,"Unexpected underflows=%0d",underflows);
    $display("PASS FIFO_ALIGNMENT frames=2 pixels=%0d line_start_min=%0d active_min=%0d empty_reads=%0d",total_pixels,min_start,min_used,underflows);
    $finish;
end
initial begin #100000000; $fatal(1,"timeout"); end
endmodule
