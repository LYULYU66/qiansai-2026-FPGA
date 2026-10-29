`timescale 1ns/1ps
// IMAGE3 song list: the row of the song that is playing turns red.
// Only light text pixels are recoloured (index, title, artist, duration);
// the dark list background maps onto itself, so no box is drawn. Row
// boxes are measured from IMAGE3.BMP (text rows y131/177/222/268/314/361).
module video_playlist_highlight (
    input  wire        I_clk,
    input  wire        I_rst,
    input  wire        I_enable,
    input  wire        I_vs,
    input  wire        I_de,
    input  wire        I_playing,
    input  wire [2:0]  I_song,
    input  wire [23:0] I_rgb,
    output wire [23:0] O_rgb
);
reg [10:0] x,nx;
reg [9:0] y,ny;
reg de_d,vs_d,seen,nseen;
reg playing_frame;
reg [2:0] song_frame;
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
// The selection changes only at frame start, never mid-picture.
always @(posedge I_clk or posedge I_rst) begin
    if(I_rst)begin x<=0;y<=0;de_d<=0;vs_d<=0;seen<=0;playing_frame<=0;song_frame<=0;end
    else begin
        x<=nx;y<=ny;seen<=nseen;de_d<=I_de;vs_d<=I_vs;
        if(frame_start)begin playing_frame<=I_playing;song_frame<=I_song;end
    end
end
reg [9:0] row_top,row_bottom;
always @(*) begin
    case(song_frame)
        3'd0: begin row_top=128; row_bottom=151; end
        3'd1: begin row_top=174; row_bottom=197; end
        3'd2: begin row_top=219; row_bottom=242; end
        3'd3: begin row_top=265; row_bottom=288; end
        3'd4: begin row_top=311; row_bottom=334; end
        default: begin row_top=358; row_bottom=380; end
    endcase
end
// x<546 keeps the favourite/more icons at the right edge unchanged.
wire hit=I_enable&&playing_frame&&song_frame<6&&I_de&&
    nx>=10&&nx<546&&ny>=row_top&&ny<row_bottom;
// White -> (255,73,93); background (11,13,40) -> (13,13,40); antialiased
// edges blend proportionally, using green as the text-coverage measure.
wire [7:0] r=I_rgb[23:16],g=I_rgb[15:8],b=I_rgb[7:0];
wire [7:0] red_r=(r>g)?r:g;
wire [7:0] red_g={2'd0,g[7:2]}+8'd10;
wire [7:0] red_b={2'd0,b[7:2]}+8'd30;
assign O_rgb=hit?{red_r,red_g,red_b}:I_rgb;
endmodule
