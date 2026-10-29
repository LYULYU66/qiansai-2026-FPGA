// A tiny lookaside replaces only the cover on song 2. Static home artwork
// remains cached in SDRAM; no atlas reload, extra frame store, or RGB delay.
module video_song_cover_overlay(
    input I_clk,I_rst,I_vs,I_de,I_home,I_music,I_song,
    input [23:0] I_rgb,
    output [23:0] O_rgb
);
reg [10:0] x,nx;
reg [9:0] y,ny;
reg de_d,vs_d,seen,nseen,song_frame;
wire frame_start=I_vs&&!vs_d;
always @(*) begin
    nx=x;ny=y;nseen=seen;
    if(frame_start)begin nx=0;ny=0;nseen=0;end
    else if(I_de)begin
        if(!de_d)begin
            nx=0;
            if(!seen)begin ny=0;nseen=1;end
            else if(y<479)ny=y+1'b1;
        end else if(x<639)nx=x+1'b1;
    end else nx=0;
end
wire home_hit=I_home&&nx>=184&&nx<224&&ny>=336&&ny<376;
wire music_hit=I_music&&nx>=160&&nx<224&&ny>=136&&ny<200;
wire hit=I_de&&song_frame&&(home_hit||music_hit);
wire [5:0] dx=nx-(I_music?11'd160:11'd184);
wire [5:0] dy=ny-(I_music?10'd136:10'd336);
wire [8:0] sx5={3'd0,dx}+{1'd0,dx,2'd0};
wire [8:0] sy5={3'd0,dy}+{1'd0,dy,2'd0};
wire [5:0] sx=I_music?sx5[8:3]:dx;
wire [5:0] sy=I_music?sy5[8:3]:dy;
wire [8:0] address={sy,3'd0}+{2'd0,sy,1'd0}+{5'd0,sx[5:2]};
wire [15:0] packed_pixels;
song2_cover_rom rom(.I_clk(I_clk),.I_addr(hit?address:9'd0),.O_word(packed_pixels));
reg hit_d;
reg [1:0] lane;
always @(posedge I_clk or posedge I_rst)begin
    if(I_rst)begin x<=0;y<=0;de_d<=0;vs_d<=0;seen<=0;song_frame<=0;hit_d<=0;lane<=0;end
    else begin
        x<=nx;y<=ny;seen<=nseen;de_d<=I_de;vs_d<=I_vs;
        if(frame_start)song_frame<=I_song;
        hit_d<=hit;lane<=sx[1:0];
    end
end
wire [3:0] index=(packed_pixels >> {lane,2'd0});
wire [23:0] color;
song2_cover_palette palette(index,color);
// Index 0 is white outside the circular crop, hiding the old cover underneath.
assign O_rgb=I_de&&hit_d?color:I_rgb;
endmodule
