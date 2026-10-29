`timescale 1ps/1ps
module tb_pll_phase;
reg clk50=0; always #10000 clk50=~clk50;
reg rst=1;
wire lock, c0, c1, c2, c3, c4;
pll_gen u(.refclk(clk50),.reset(rst),.extlock(lock),.clk0_out(c0),.clk1_out(c1),.clk2_out(c2),.clk3_out(c3),.clk4_out(c4));
realtime t3, t5x; integer k;
initial begin
    #100000 rst=0; wait(lock); #500000;
    for(k=0;k<3;k=k+1) begin
        @(posedge c3) t3=$realtime;
        @(posedge `FIVEX) t5x=$realtime;
        $display("pixel rise -> next 5x rise: %0.0f ps", t5x-t3);
    end
    $finish;
end
endmodule
