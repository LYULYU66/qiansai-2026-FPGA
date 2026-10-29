`timescale 1ns/1ps
module tb_home_atlas;
reg clk=0;always #4 clk=~clk;
reg rst=1,start=0,consume=0,top=1;
reg [1:0] page=0;
wire ready;
wire [7:0] index;
reg [7:0] expected[0:614399];
home_index_stream dut(.clk(clk),.rst(rst),.start(start),.consume(consume),
    .frame_index(page),.top_down(top),.ready(ready),.index(index));
integer p,d,n,y,x,ticks;
task transfer;
    input integer page_number,direction;
    begin
        @(negedge clk);page=page_number;top=direction;start=1;consume=0;
        @(negedge clk);start=0;n=0;ticks=0;
        while(n<307200) begin
            consume=ready && (ticks%11!=0) && (ticks%23>2);
            if(consume) begin
                x=n%640;y=direction ? n/640 : 479-n/640;
                if(index !== (page_number<2 ? expected[page_number*307200+y*640+x] : 8'd0))
                    $fatal(1,"atlas mismatch p=%0d d=%0d x=%0d y=%0d got=%h",page_number,direction,x,y,index);
                n=n+1;
            end
            ticks=ticks+1;@(negedge clk);
        end
        consume=0;repeat(5) @(negedge clk);
    end
endtask
initial begin
    $readmemh("home_reference_indices.hex",expected);
    repeat(5) @(negedge clk);rst=0;
    for(p=0;p<2;p=p+1) for(d=0;d<2;d=d+1) transfer(p,d);
    transfer(2,1);transfer(3,0);
    // Restart/abort while halfway through a run cannot reuse old row/colour.
    start=1;page=0;top=1;@(negedge clk);start=0;
    repeat(200) begin consume=ready;@(negedge clk);end
    consume=0;rst=1;repeat(3) @(negedge clk);rst=0;
    transfer(1,0);
    $display("PASS home atlas: exact 152-colour UI, both BMP row directions, all pages, stalls and reset");$finish;
end
initial begin #100000000;$fatal(1,"atlas timeout");end
endmodule
