`timescale 1ps/1ps
// Measures B's Ethernet-PLL outputs as wired by clk_gen_rst_gen + transport.
module tb_pll_b;
reg clk50=0; always #10000 clk50=~clk50;
reg rst=1;
wire lock, c0, c1, c2, c3, c4;
pll_gen u(.refclk(clk50),.reset(rst),.extlock(lock),.clk0_out(c0),.clk1_out(c1),.clk2_out(c2),.clk3_out(c3),.clk4_out(c4));
realtime t0[0:4], t1[0:4]; integer n[0:4]; integer i;
task automatic measure(input integer k); begin end endtask
always @(posedge c0) if(lock) begin if(n[0]==0) t0[0]=$realtime; n[0]=n[0]+1; t1[0]=$realtime; end
always @(posedge c1) if(lock) begin if(n[1]==0) t0[1]=$realtime; n[1]=n[1]+1; t1[1]=$realtime; end
always @(posedge c2) if(lock) begin if(n[2]==0) t0[2]=$realtime; n[2]=n[2]+1; t1[2]=$realtime; end
always @(posedge c3) if(lock) begin if(n[3]==0) t0[3]=$realtime; n[3]=n[3]+1; t1[3]=$realtime; end
always @(posedge c4) if(lock) begin if(n[4]==0) t0[4]=$realtime; n[4]=n[4]+1; t1[4]=$realtime; end
initial begin
    for(i=0;i<5;i=i+1) n[i]=0;
    #100000 rst=0;
    wait(lock); #2000000;
    for(i=0;i<5;i=i+1)
        $display("clkc%0d: %0.3f MHz (%0d edges)", i, (n[i]-1)*1.0e6/(t1[i]-t0[i]), n[i]);
    $finish;
end
endmodule
