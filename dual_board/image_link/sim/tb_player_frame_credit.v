`timescale 1ns/1ps
// Real native FIFOs and frame controllers. FIFO credit is UDP/write-clock
// state: it must retain the old expression, never depend on the new mem reset.
module tb_player_frame_credit;
reg mem_clk=0,wr_clk=0,rd_clk=0,rst=1,abort=0,read_req=0;
always #5 mem_clk=~mem_clk;
always #4 wr_clk=~wr_clk;
always #20 rd_clk=~rd_clk;
wire mem_reset,ready,ack,app_en;
player_frame_reset resetter(.clk(mem_clk),.request(rst),.rst(mem_reset));
frame_read_write #(.BURST_SIZE(16)) dut(
    .rst(rst),.mem_reset(mem_reset),.mem_clk(mem_clk),.Sdr_init_done(1'b1),
    .Sdr_init_ref_vld(1'b0),.Sdr_busy(1'b0),.App_rd_en(app_en),.App_rd_addr(),
    .Sdr_rd_en(1'b0),.Sdr_rd_dout(32'd0),.read_clk(rd_clk),.read_req(read_req),
    .read_req_ack(ack),.read_finish(),.read_b_enable(1'b0),
    .read_addr_0(21'd0),.read_addr_1(21'd307200),.read_addr_2(21'd614400),.read_addr_3(21'd921600),
    .read_addr_index(2'd0),.read_addr_index_b(2'd0),.read_len(21'd16),
    .read_en(1'b0),.read_data(),.read_data_b(),.App_wr_en(),.App_wr_addr(),.App_wr_din(),.App_wr_dm(),
    .write_clk(wr_clk),.write_abort(abort),.write_req(1'b0),.write_req_ack(),.write_finish(),
    .write_addr_0(21'd0),.write_addr_1(21'd307200),.write_addr_2(21'd614400),.write_addr_3(21'd921600),
    .write_addr_index(2'd0),.write_len(21'd16),.write_top_down(1'b1),.write_en(1'b0),.write_data(32'd0),
    .read_empty_a(),.read_empty_b(),.read_valid_a(),.write_pixel_ready(ready));
integer n,credit_while_mem_reset=0;
always @(posedge wr_clk)begin
    #0.01;
    if(ready !== ((dut.write_usedw<480) && !abort && !rst))$fatal(1,"UDP credit/reset expression changed");
    if(!rst && mem_reset && ready)credit_while_mem_reset=credit_while_mem_reset+1;
end
always @(posedge mem_clk)begin
    #0.01;
    if(mem_reset && (app_en!==0 || dut.rd_owner!==0 || dut.frame_fifo_read_a.state!==0 || dut.frame_fifo_read_b.state!==0))
        $fatal(1,"memory reset did not reach only memory state");
end
initial begin
    // Only clock-model RAM contents are uninitialised; no read data consumed.
    repeat(20)@(negedge wr_clk);rst=0;
    wait(!mem_reset);@(negedge rd_clk);read_req=1;wait(ack);@(negedge rd_clk);read_req=0;
    repeat(100)@(negedge mem_clk);
    for(n=0;n<20;n=n+1)begin
        @(negedge wr_clk);rst=1;repeat(4)@(negedge wr_clk);#0.1;rst=0;
        wait(!mem_reset);repeat(3)@(negedge wr_clk);
    end
    abort=1;repeat(10)@(negedge wr_clk);abort=0;repeat(10)@(negedge wr_clk);
    if(credit_while_mem_reset==0)$fatal(1,"memory-only reset case not covered");
    $display("PASS player frame credit: native FIFOs, local memory reset, unchanged UDP credit, read request and write abort");$finish;
end
initial begin #100000;$fatal(1,"frame credit timeout");end
endmodule
