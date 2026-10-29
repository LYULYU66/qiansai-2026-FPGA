`timescale 1ns/1ps
// Use the actual reset helper defined in the A hardware top, plus the real
// frame_fifo_read. A short asynchronous pulse must reset without a clock;
// release may only occur on the second subsequent memory edge.
module tb_player_frame_reset;
reg clk=0,request=1,read_req=0;
always #5 clk=~clk;
wire rst,app_en,ack,finish;
wire [20:0] addr;
player_frame_reset dut(.clk(clk),.request(request),.rst(rst));
frame_fifo_read #(.BURST_SIZE(16)) reader (
    .rst(rst),.mem_clk(clk),.Sdr_init_done(1'b1),.Sdr_init_ref_vld(1'b0),
    .Sdr_busy(1'b0),.Sdr_rd_en(1'b0),.App_wr_busy(1'b0),.O_rd_busy(),
    .I_rd_grant(1'b1),.O_rd_want(),.App_rd_en(app_en),.App_rd_addr(addr),
    .read_req(read_req),.read_req_ack(ack),.read_finish(finish),
    .read_addr_0(21'd100),.read_addr_1(21'd200),.read_addr_2(21'd300),.read_addr_3(21'd400),
    .read_addr_index(2'd0),.read_len(21'd16),.fifo_aclr(),.wrusedw(10'd0));
integer edges=0,assertions=0,reads=0,n;
always @(posedge clk)begin
    if(request)edges=0;else edges=edges+1;
    #0.01;
    if(rst!== (request || edges<2))$fatal(1,"reset release not exactly second edge");
    if(rst && (app_en!==0 || ack!==0 || reader.state!==0))$fatal(1,"reader state not reset");
    if(!rst && app_en)begin
        if(addr!==100+reads)$fatal(1,"burst address/order after reset");
        reads=reads+1;
    end
end
always @(posedge request)begin
    edges=0;
    #0.01;
    if(rst!==1 || app_en!==0)$fatal(1,"reset assertion depends on memory clock");
    assertions=assertions+1;
end
task burst;
    begin
        reads=0;
        @(negedge clk);read_req=1;
        wait(ack);@(negedge clk);read_req=0;
        wait(finish);@(negedge clk);
        if(reads!=16)$fatal(1,"expected full burst after release");
    end
endtask
initial begin
    #1;request=0;wait(!rst);burst;
    // Exercise assertion at every 0.25 ns offset, including near both clock
    // edges. The pulse is shorter than one memory period, then clocks release.
    for(n=0;n<40;n=n+1)begin
        @(negedge clk);#(0.25*n+0.05);request=1;#0.20;request=0;
        wait(!rst);burst;
    end
    $display("PASS player frame reset: asynchronous short pulses, 40 phases, exact two-edge release and ordered reader bursts");$finish;
end
initial begin #100000;$fatal(1,"reset test timeout");end
endmodule
