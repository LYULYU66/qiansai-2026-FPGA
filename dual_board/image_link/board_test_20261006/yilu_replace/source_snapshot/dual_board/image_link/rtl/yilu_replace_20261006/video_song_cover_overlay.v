// Full-color lookaside only for song 2; no framebuffer or RGB/DE latency added.
module video_song_cover_overlay(
    input I_clk,I_rst,I_vs,I_de,I_home,I_music,I_song,
    input [23:0] I_rgb,output [23:0] O_rgb
);
reg [10:0] x,nx;
reg [9:0] y,ny;
reg de_d,vs_d,seen,nseen,song_frame;
wire frame_start=I_vs&&!vs_d;
always @* begin
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
// Registered RGB producer advances at this same edge. Prefetch its next pixel.
// Both ROIs start away from x=0, so no blanking/first-pixel read is required.
wire [10:0] look_x=I_de&&nx<639?nx+1'b1:11'd0;
wire home_hit=I_home&&look_x>=184&&look_x<224&&ny>=336&&ny<376;
wire music_hit=I_music&&look_x>=160&&look_x<224&&ny>=136&&ny<200;
wire hit=I_de&&song_frame&&(home_hit||music_hit);
wire [5:0] dx=look_x-(I_music?11'd160:11'd184);
wire [5:0] dy=ny-(I_music?10'd136:10'd336);
// Centered 64->40 sampling, implemented by a tiny constant map (not divider).
function [5:0] home_coord;
 input [5:0] p;
 begin case(p)
  0:home_coord=0;1:home_coord=2;2:home_coord=4;3:home_coord=5;
  4:home_coord=7;5:home_coord=8;6:home_coord=10;7:home_coord=12;
  8:home_coord=13;9:home_coord=15;10:home_coord=16;11:home_coord=18;
  12:home_coord=20;13:home_coord=21;14:home_coord=23;15:home_coord=24;
  16:home_coord=26;17:home_coord=28;18:home_coord=29;19:home_coord=31;
  20:home_coord=32;21:home_coord=34;22:home_coord=36;23:home_coord=37;
  24:home_coord=39;25:home_coord=40;26:home_coord=42;27:home_coord=44;
  28:home_coord=45;29:home_coord=47;30:home_coord=48;31:home_coord=50;
  32:home_coord=52;33:home_coord=53;34:home_coord=55;35:home_coord=56;
  36:home_coord=58;37:home_coord=60;38:home_coord=61;39:home_coord=63;
  default:home_coord=0;
 endcase end
endfunction
wire [5:0] sx=I_music?dx:home_coord(dx);
wire [5:0] sy=I_music?dy:home_coord(dy);
wire [15:0] pixel;
song2_cover_rom rom(.I_clk(I_clk),.I_ce(hit),.I_addr({sy,sx}),.O_word(pixel));
reg hit_d;
always @(posedge I_clk or posedge I_rst)begin
 if(I_rst)begin x<=0;y<=0;de_d<=0;vs_d<=0;seen<=0;song_frame<=0;hit_d<=0;end
 else begin
  x<=nx;y<=ny;seen<=nseen;de_d<=I_de;vs_d<=I_vs;
  if(frame_start)song_frame<=I_song;
  hit_d<=hit;
 end
end
wire [23:0] color={pixel[15:11],pixel[15:13],pixel[10:5],pixel[10:9],pixel[4:0],pixel[4:2]};
assign O_rgb=I_de&&hit_d?color:I_rgb;
endmodule
