`timescale 1ns/1ps
module tb_image_pixel_cdc;
    reg wr_clk=0, rd_clk=0, rst=1;
    always #5 wr_clk=~wr_clk;
    always #4 rd_clk=~rd_clk;
    wire ready, valid, overflow;
    wire [23:0] rgb;
    reg [23:0] sent=0;
    integer received=0, cycles=0;
    wire rd_ready=(cycles%13!=0) && (cycles%13!=1);
    image_pixel_cdc #(.ADDR_BITS(7)) dut (
        .rst(rst),.wr_clk(wr_clk),.wr_valid(ready && sent<4096),
        .wr_rgb(sent),.wr_ready(ready),.overflow(overflow),
        .rd_clk(rd_clk),.rd_ready(rd_ready),.rd_valid(valid),.rd_rgb(rgb)
    );
    always @(posedge wr_clk) if(!rst && ready && sent<4096) sent<=sent+1'b1;
    always @(posedge rd_clk) if(!rst) begin
        cycles=cycles+1;
        if(valid && rd_ready) begin
            if(rgb!==received[23:0]) $fatal(1,"CDC pixel mismatch %0d %h",received,rgb);
            received=received+1;
        end
        if(overflow) $fatal(1,"FIFO overflow");
    end
    initial begin
        repeat(5) @(negedge wr_clk); rst=0;
        repeat(16000) @(negedge wr_clk);
        if(received!=4096) $fatal(1,"CDC missing pixels %0d",received);
        $display("PASS image pixel CDC: 100/125 MHz, 4096 pixels, wraparound and backpressure");
        $finish;
    end
endmodule
