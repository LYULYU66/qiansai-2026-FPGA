`timescale 1ns/1ps
module tb_home_pixels;
reg clk=0;always #20 clk=~clk;
reg rst=1,vs=0,de=0,en=1,music=0;
reg [7:0] index=0;
reg [23:0] background=0;
wire [23:0] reference,remote;
reg [7:0] expected[0:614399];
video_home_overlay #(.EXTERNAL_CLOCK(1)) original(
    .I_clk(clk),.I_rst(rst),.I_enable(en),.I_vs(vs),.I_de(de),
    .I_music_page(music),.I_rgb(background),.O_rgb(reference));
video_remote_home_overlay dut(.I_clk(clk),.I_rst(rst),.I_enable(en),
    .I_de(de),.I_index(index),.I_rgb(background),.O_rgb(remote));
integer p,y,x,pass;
initial begin
    $readmemh("home_reference_indices.hex",expected);
    repeat(4) @(negedge clk);rst=0;
    for(pass=0;pass<2;pass=pass+1) for(p=0;p<2;p=p+1) begin
        music=p;vs=1;de=0;repeat(3) @(negedge clk);vs=0;repeat(3) @(negedge clk);
        for(y=0;y<480;y=y+1) begin
            for(x=0;x<640;x=x+1) begin
                de=1;index=expected[p*307200+y*640+x];
                // Photograph after arbitrary brightness/contrast changes.
                // UI colours must stay exact and transparent pixels must pass.
                background={x[7:0],y[7:0],(x[7:0]^y[7:0]^8'h37)};
                en=pass==0 || (x%17!=0);
                @(posedge clk);#1;
                if(remote!==reference) $fatal(1,"UI pixel mismatch p=%0d x=%0d y=%0d en=%b got=%h ref=%h",p,x,y,en,remote,reference);
                @(negedge clk);
            end
            de=0;repeat(5) @(negedge clk);
            if(remote!==background) $fatal(1,"blanking must pass background");
        end
    end
    $display("PASS home pixels: 1228800 exact original/home/music pixels, transparent backgrounds, UI disable");$finish;
end
initial begin #60000000;$fatal(1,"home pixels timeout");end
endmodule
