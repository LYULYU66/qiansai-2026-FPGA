`timescale 1ns/1ps
// Production raster, read controller, FIFO, delay, static transition,
// image adjustment and AXIS adapter. SDRAM responses are ORDERED MODEL data;
// this is not a physical SDRAM/HDMI timing or metastability simulation.
module tb_video_read_axis_stress;
reg mem_clk=0, video_clk=0, rst=1;
integer phase=3, latency=8, pause_cycles=310, frames_to_check=2;
integer read_shift=0, data_delay=0, mem_cycles=0, j;
reg starve=0, started=0, async_valid=0;
reg [15:0] response_valid=0;
reg [31:0] response_data[0:15];
reg [31:0] delayed_dout=0;
wire hs,vs,de,read_req,ack,aclr,app_rd,busy,want,finish;
wire [20:0] addr;
wire [8:0] wrusedw,rdusedw;
wire empty,full,fifo_valid,read_en,actual_re;
wire [31:0] dout;
wire dh,dv,dd,th,tv,td,ah,av,ad,frame_valid;
wire [23:0] raw_rgb,transition_rgb,adjusted_rgb,axis_rgb;
wire user,valid,last;
wire [1:0] idx_a;
integer read_index=0,raw_index=0,axis_index=0,frames=0;
wire grant=(!starve || read_index>=120) && (mem_cycles%1200>=pause_cycles);
reg test_passed=0;
wire [4:0] alignment_flags;
wire alignment_ready;
integer underflows=0,raw_errors=0,axis_errors=0,sof_errors=0;
integer min_start=512,min_used=512,starts=0,checked_pixels=0;
integer video_cycle=0,first_read_cycle=-1,first_raw_cycle=-1;
reg re_prev=0,raw_vs_prev=0,axis_vs_prev=0,req_prev=0;
reg exp_valid=0,exp_user=0,exp_last=0;
reg [23:0] exp_rgb=0;
integer csv;
reg [1023:0] outbase="sim/alignment_20260926/read_axis";
reg fault_expected;
always #5 mem_clk=~mem_clk;
initial begin
    if($value$plusargs("PHASE=%d",phase)) begin end
    #(phase); forever #20 video_clk=~video_clk;
end
function [31:0] pattern;
    input [20:0] a;
    // Adjacent pixels always differ; dark values with RGB low bits zero.
    begin pattern={2'b00,a[3:0],2'b00,2'b00,a[7:4],2'b00,
                   2'b00,a[11:8],2'b00,8'h00}; end
endfunction
video_timing_data timing(video_clk,rst,read_req,ack,hs,vs,de);
video_frame_valid_gate gate(video_clk,rst,vs,async_valid,frame_valid);
frame_fifo_read #(.BURST_SIZE(256)) dma(
 .rst(rst),.mem_clk(mem_clk),.Sdr_init_done(!rst),
 .Sdr_init_ref_vld(1'b0),.Sdr_busy(1'b0),.Sdr_rd_en(response_valid[latency-1]),
 .App_wr_busy(1'b0),.O_rd_busy(busy),.I_rd_grant(grant),.O_rd_want(want),
 .App_rd_en(app_rd),.App_rd_addr(addr),.read_req(read_req),.read_req_ack(ack),
 .read_finish(finish),.read_addr_0(21'd0),.read_addr_1(21'd0),
 .read_addr_2(21'd0),.read_addr_3(21'd0),.read_addr_index(idx_a),
 .read_len(21'd307200),.fifo_aclr(aclr),.wrusedw({1'b0,wrusedw}));
rfifo_32_32_512 fifo(
 .rst(rst|aclr),.clkw(mem_clk),.clkr(video_clk),
 .we(response_valid[latency-1]),.di(response_data[latency-1]),
 .re(actual_re),.dout(dout),.valid(fifo_valid),.full_flag(full),
 .empty_flag(empty),.afull(),.aempty(),.wrusedw(wrusedw),.rdusedw(rdusedw));
// Fault injection is TESTBENCH ONLY. Production RTL is not edited.
assign actual_re=(read_shift==-1) ? delay.de_d[17] :
                 (read_shift==1) ? delay.de_d[19] : read_en;
video_delay delay(.video_clk(video_clk),.rst(rst),.read_en(read_en),
 .read_data(data_delay ? delayed_dout[31:8] : dout[31:8]),
 .hs(hs),.vs(vs),.de(de),.hs_r(dh),.vs_r(dv),.de_r(dd),.vout_data(raw_rgb));
video_transition_effects transition(
 .I_clk(video_clk),.I_rst(rst),.I_frame_vs(vs),.I_hs(dh),.I_vs(dv),.I_de(dd),
 .I_rgb_a(raw_rgb),.I_rgb_b(24'd0),.I_display_valid(frame_valid),
 .I_requested_idx(2'd0),.O_read_idx_a(idx_a),.O_read_idx_b(),
 .I_frame_read_req(1'b0),.I_force_warning(1'b0),.I_warning_ready(1'b0),
 .O_read_b_enable(),.O_display_idx(),.O_transition_active(),
 .O_transition_kind(),.O_transition_step(),.O_hs(th),.O_vs(tv),.O_de(td),.O_rgb(transition_rgb));
video_image_adjust adjust(video_clk,rst,th,tv,td,
 frame_valid ? transition_rgb : 24'd0,2'd3,2'd0,ah,av,ad,adjusted_rgb);
video_rgb_to_axis_640x480 axis(video_clk,rst,av,ad,adjusted_rgb,user,valid,last,axis_rgb);
video_alignment_monitor probe(
 .I_clk(video_clk),.I_rst(rst),.I_clear(1'b0),.I_enable(frame_valid),
 .I_source_vs(av),.I_source_de(ad),.I_source_rgb(adjusted_rgb),
 .I_axis_valid(valid),.I_axis_user(user),.I_axis_last(last),.I_axis_rgb(axis_rgb),
 .I_read_en(actual_re),.I_empty_a(empty),.I_fifo_valid(fifo_valid),
 .I_fifo_rgb(dout[31:8]),.I_raw_de(dd),.I_raw_rgb(raw_rgb),
 .O_flags(alignment_flags),.O_ready(alignment_ready));
always @(posedge mem_clk) begin
    mem_cycles<=mem_cycles+1;
    if(rst || aclr) response_valid<=0;
    else begin
        response_valid<={response_valid[14:0],app_rd};
        response_data[0]<=pattern(addr);
        for(j=1;j<16;j=j+1) response_data[j]<=response_data[j-1];
        if(response_valid[latency-1] && full) $fatal(1,"FIFO overflow");
    end
end
always @(posedge video_clk) begin
    delayed_dout<=dout;
    if(!rst) begin
        video_cycle=video_cycle+1;
        if(read_req && !req_prev) begin started=1; read_index=0; end
        req_prev=read_req;
        // Independent pre-edge pipeline check: sidebands and data must
        // correspond to the SAME source beat, not merely equal totals.
        exp_valid=ad;
        exp_rgb=adjusted_rgb;
        exp_user=ad && (axis_index==0);
        exp_last=ad && (axis_index%640==639);
        if(av != axis_vs_prev) axis_index=0;
        axis_vs_prev=av;
        if(actual_re && started) begin
            if(!re_prev) begin
                starts=starts+1;
                if(rdusedw<min_start) min_start=rdusedw;
                if(read_index==0) begin
                    first_read_cycle=video_cycle;
                    $display("READ_START frame=%0d cycle=%0d rdusedw=%0d empty=%b",frames,video_cycle,rdusedw,empty);
                end
            end
            if(rdusedw<min_used) min_used=rdusedw;
            if(empty) underflows=underflows+1;
            read_index=read_index+1;
        end
        re_prev=actual_re;
        // Capture pre-edge values at line heads/tails, including blank cycles.
        if(started && raw_index<1300 && (raw_index%640<8 || raw_index%640>635))
            $fdisplay(csv,"%0t,%0d,%0d,%0d,%b,%b,%0d,%b,%h,%b,%b,%h,%b,%b,%b,%h",
              $time,frames,video_cycle,raw_index,de,actual_re,rdusedw,empty,dout,
              fifo_valid,dd,raw_rgb,valid,user,last,axis_rgb);
        #1;
        if(dv != raw_vs_prev) raw_index=0;
        raw_vs_prev=dv;
        if(dd) begin
            if(started) begin
                if(raw_index==0) begin
                    first_raw_cycle=video_cycle;
                    $display("RAW_START frame=%0d cycle=%0d read_to_rgb_cycles=%0d rgb=%h",frames,video_cycle,first_raw_cycle-first_read_cycle,raw_rgb);
                    if(read_shift==0 && first_raw_cycle-first_read_cycle!=1)
                        $fatal(1,"Unexpected read/RGB latency");
                end
                if(raw_rgb !== (pattern(raw_index)>>8)) raw_errors=raw_errors+1;
                checked_pixels=checked_pixels+1;
            end
            raw_index=raw_index+1;
        end
        // Existing timing source leaves its second delay stage unreset.
        // Ignore reset pipeline fill only, long before any active pixels.
        if(video_cycle>64 && (valid !== exp_valid || axis_rgb !== exp_rgb ||
           user !== exp_user || last !== exp_last)) begin
            sof_errors=sof_errors+1;
            if(sof_errors<4) $display("AXIS_ERROR pixel=%0d valid=%b/%b user=%b/%b last=%b/%b",axis_index,valid,exp_valid,user,exp_user,last,exp_last);
        end
        if(valid) begin
            if(frame_valid && axis_rgb !== (pattern(axis_index)>>8)) axis_errors=axis_errors+1;
            axis_index=axis_index+1;
            if(axis_index==307200) begin
                if(started) frames=frames+1;
                if(frames>=frames_to_check) begin
                    if(sof_errors!=0) $fatal(1,"SOF/VALID/DATA/LAST errors=%0d",sof_errors);
                    if(fault_expected) begin
                        if(!alignment_flags[3]) $fatal(1,"Board monitor missed injected R fault");
                        if(raw_errors==0) $fatal(1,"Injected fault escaped pixel checker");
                        if(starve && underflows==0) $fatal(1,"Starvation escaped empty detector");
                        if(!starve && underflows!=0) $fatal(1,"Alignment injection unexpectedly underflowed");
                        $display("PASS INJECTED_FAULT shift=%0d delay=%0d starve=%0d raw_errors=%0d axis_errors=%0d empty_reads=%0d",read_shift,data_delay,starve,raw_errors,axis_errors,underflows);
                    end else begin
                        if(alignment_flags!==0 || (frames>1 && alignment_ready!==1))
                            $fatal(1,"Board monitor false flags=%b ready=%b",alignment_flags,alignment_ready);
                        if(raw_errors || axis_errors || underflows)
                            $fatal(1,"READ_CHAIN raw_errors=%0d axis_errors=%0d underflows=%0d",raw_errors,axis_errors,underflows);
                        $display("PASS READ_AXIS phase=%0d latency=%0d pause=%0d frames=%0d pixels=%0d line_start_min=%0d active_min=%0d SOF_errors=0",phase,latency,pause_cycles,frames,checked_pixels,min_start,min_used);
                    end
                    test_passed=1;
                    $fclose(csv); $finish;
                end
            end
        end
    end
end
// Dump bounded windows only. Entire frames are still checked by assertions.
initial begin
    if($value$plusargs("LATENCY=%d",latency)) begin end
    if($value$plusargs("PAUSE=%d",pause_cycles)) begin end
    if($value$plusargs("FRAMES=%d",frames_to_check)) begin end
    if($value$plusargs("SHIFT=%d",read_shift)) begin end
    if($value$plusargs("DATA_DELAY=%d",data_delay)) begin end
    if($value$plusargs("OUT=%s",outbase)) begin end
    starve=$test$plusargs("STARVE");
    fault_expected=starve || read_shift!=0 || data_delay!=0;
    if(latency<1 || latency>10) $fatal(1,"Use model latency 1..10");
    csv=$fopen({outbase,".csv"},"w");
    if(!csv) $fatal(1,"Cannot open CSV output");
    $fdisplay(csv,"time_ps,frame,cycle,raw_index,DE,read_en,rdusedw,empty,dout,fifo_valid,out_DE,out_RGB,axis_valid,axis_user,axis_last,axis_RGB");
    $dumpfile({outbase,".vcd"}); $dumpvars(1,tb_video_read_axis_stress); $dumpoff;
    repeat(8) @(negedge video_clk); rst=0;
    repeat(20) @(negedge video_clk); async_valid=1;
    wait(started);
    forever begin
        @(negedge video_clk);
        if(started && de && read_index<1400) begin
            $dumpon;
            repeat(850) @(negedge video_clk);
            $dumpoff;
        end
    end
end
initial begin #200000000; $fatal(1,"timeout"); end
endmodule
