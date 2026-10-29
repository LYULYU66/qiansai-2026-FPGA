// A: static home/music UI is already indexed by B, in SDRAM's spare byte.
// I_index precedes adjusted I_rgb/I_de by ONE pixel clock, just like the
// brightness LUT input. The synchronous palette introduces no new RGB delay.
// Do not blend the tag byte: UI is disabled throughout image transitions.
module video_remote_home_overlay(
    input wire I_clk,I_rst,I_enable,I_de,
    input wire [7:0] I_index,
    input wire [23:0] I_rgb,
    output wire [23:0] O_rgb
);
wire [23:0] palette_rgb;
reg opaque;
home_palette_rom palette(.clk(I_clk),.enable(1'b1),.index(I_index),.rgb(palette_rgb));
always @(posedge I_clk or posedge I_rst) begin
    if(I_rst) opaque<=0;
    else opaque<=I_index!=0;
end
assign O_rgb=(I_enable && I_de && opaque) ? palette_rgb : I_rgb;
endmodule

// Small control-only overlay for the two music cards.  The card art stays in
// the indexed SDRAM atlas, whose centre button is the pause bars (playing).
// While paused, the bars' box is cleared to the white card and a play
// triangle in the same blue is drawn instead: no ROM, RAM or frame buffer.
module video_pause_icon_overlay(
    input  wire       I_clk,
    input  wire       I_rst,
    input  wire       I_vs,
    input  wire       I_de,
    input  wire       I_home,
    input  wire       I_music,
    input  wire       I_paused,
    input  wire [23:0] I_rgb,
    output wire [23:0] O_rgb
);
reg [10:0] pixel_x;
reg [9:0]  pixel_y;
reg de_d, vs_d, active_seen;
reg [10:0] next_x;
reg [9:0]  next_y;
reg next_seen;
wire frame_start=I_vs && !vs_d;
wire line_start=I_de && !de_d;
always @* begin
    next_x=pixel_x; next_y=pixel_y; next_seen=active_seen;
    if(frame_start) begin
        next_x=0; next_y=0; next_seen=0;
    end else if(I_de) begin
        if(line_start) begin
            next_x=0;
            if(!active_seen) begin next_y=0; next_seen=1; end
            else if(pixel_y<10'd479) next_y=pixel_y+1'b1;
        end else if(pixel_x<11'd639) next_x=pixel_x+1'b1;
    end else next_x=0;
end
always @(posedge I_clk or posedge I_rst) begin
    if(I_rst) begin
        pixel_x<=0; pixel_y<=0; de_d<=0; vs_d<=0; active_seen<=0;
    end else begin
        pixel_x<=next_x; pixel_y<=next_y; de_d<=I_de; vs_d<=I_vs;
        active_seen<=next_seen;
    end
end
// Bars: x 328..337 (music) / 279..288 (home), rows 180..192 / 378..390.
// The triangle has the bars' 13-row height, 12 columns starting one pixel
// left of the bars so its visual centre sits on the button centre.
wire control_area=(I_music && pixel_y>=10'd180 && pixel_y<10'd193) ||
                  (I_home  && pixel_y>=10'd378 && pixel_y<10'd391);
wire [9:0]  center_y=I_music ? 10'd186 : 10'd384;
wire [3:0]  play_dy=(pixel_y>=center_y) ? pixel_y-center_y : center_y-pixel_y;
wire [10:0] play_x=pixel_x-(I_music ? 11'd327 : 11'd278);
wire button_box=play_x<11'd13;
wire play_tri=play_x<11'd12 && {7'd0,play_dy}<=((11'd12-play_x)>>1);
wire paused_box=I_paused && I_de && control_area && button_box;
assign O_rgb=!paused_box ? I_rgb : play_tri ? 24'h256BB1 : 24'hFFFFFF;
endmodule
