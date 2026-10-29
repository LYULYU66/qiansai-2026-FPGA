`timescale 1ns/1ps
// Capture the existing opaque UI, not the picture. Used for compression sizing
// and the later pixel-for-pixel remote-overlay regression.
module tb_home_capture;
reg clk=0; always #20 clk=~clk;
reg rst=1,vs=0,de=0,music=0;
wire [23:0] rgb;
localparam [23:0] SENTINEL=24'h010203;
video_home_overlay #(.EXTERNAL_CLOCK(1)) dut(
    .I_clk(clk),.I_rst(rst),.I_enable(1'b1),.I_vs(vs),.I_de(de),
    .I_music_page(music),.I_rgb(SENTINEL),.O_rgb(rgb));
integer out,p,x,y,len;
reg [23:0] last_color;
initial begin
    out=$fopen("home_reference_runs.csv","w");
    repeat(4) @(negedge clk); rst=0;
    for(p=0;p<2;p=p+1) begin
        music=p;vs=1;de=0;
        repeat(3) @(negedge clk);vs=0;
        repeat(3) @(negedge clk);
        for(y=0;y<480;y=y+1) begin
            len=0;last_color=0;
            for(x=0;x<640;x=x+1) begin
                de=1;@(posedge clk);#1;
                if(^rgb===1'bx) $fatal(1,"unknown UI p=%0d x=%0d y=%0d",p,x,y);
                if(len!=0 && rgb!=last_color) begin
                    $fwrite(out,"%0d,%0d,%0d,%06h\n",p,y,len,last_color);
                    len=0;
                end
                last_color=rgb;len=len+1;
                @(negedge clk);
            end
            $fwrite(out,"%0d,%0d,%0d,%06h\n",p,y,len,last_color);
            de=0;repeat(5) @(negedge clk);
        end
    end
    $fclose(out);$display("PASS home capture: 2 x 640x480 UI rasters");$finish;
end
initial begin #30000000; $fatal(1,"capture timeout"); end
endmodule
