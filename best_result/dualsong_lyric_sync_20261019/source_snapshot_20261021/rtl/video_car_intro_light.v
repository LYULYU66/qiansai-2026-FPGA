`timescale 1ns/1ps
// Low-resource car entrance for the dashboard page.
// The original car effect also rotated, faded and added a moving sheen. Those
// per-pixel effects consume a large amount of LUT/routing margin on this B
// build. This version keeps the recognizable indexed car sprite and its
// smooth bottom-to-dashboard entrance, while leaving the dashboard needles
// and A/B image transport plenty of headroom.
module video_car_intro_light (
    input  wire        I_clk,
    input  wire        I_rst,
    input  wire        I_enable,
    input  wire        I_vs,
    input  wire        I_de,
    input  wire [23:0] I_rgb,
    output wire [23:0] O_rgb,
    output reg         O_vs,
    output reg         O_de,
    // 20261021: raster position of the pixel now on O_rgb (valid with O_de),
    // shared with the dashboard subtitle that follows this overlay.
    output wire [10:0] O_x,
    output wire [9:0]  O_y
);
reg [10:0] x,nx;
reg [9:0]  y,ny;
reg seen,nseen,de_prev,vs_prev;
reg [6:0] age;
reg [7:0] hold_count;
wire frame_start=I_vs&&!vs_prev;
assign O_x=x;
assign O_y=y;

always @* begin
    nx=x;
    ny=y;
    nseen=seen;
    if(frame_start) begin
        nx=0;
        ny=0;
        nseen=0;
    end else if(I_de) begin
        if(!de_prev) begin
            nx=0;
            if(!seen) begin
                ny=0;
                nseen=1;
            end else if(y<479) ny=y+1'b1;
        end else if(x<639) nx=x+1'b1;
    end else begin
        nx=0;
    end
end

// The entrance lasts 56 frames (about 0.94 s at 59.5 Hz), then holds the car
// below the gauges for about two seconds before restarting. Do not clear the
// counters when I_enable drops: page/cache CDC activity can briefly deassert
// the page enable and must not create a visible animation glitch.
always @(posedge I_clk or posedge I_rst) begin
    if(I_rst) begin
        x<=0; y<=0; seen<=0; de_prev<=0; vs_prev<=0; age<=0; hold_count<=0;
    end else begin
        x<=nx;
        y<=ny;
        seen<=nseen;
        de_prev<=I_de;
        vs_prev<=I_vs;
        if(I_enable && frame_start) begin
            if(age<7'd56) begin
                age<=age+1'b1;
                hold_count<=0;
            end else if(hold_count==8'd119) begin
                age<=0;
                hold_count<=0;
            end else begin
                hold_count<=hold_count+1'b1;
            end
        end
    end
end

wire [9:0] rise=(age<7'd56) ? ({3'd0,age}<<1) : 10'd112;
wire [9:0] car_top=10'd480-rise;
wire [9:0] car_y=ny-car_top;
wire [9:0] car_x=nx-10'd192;
wire sprite_hit=I_enable && I_de && nx>=11'd192 && nx<11'd448 &&
                ny>=car_top && car_y<10'd96;
wire [14:0] sprite_addr={car_y[6:0],car_x[7:0]};
wire [3:0] sprite_index;
wire [23:0] sprite_rgb;
car_intro_rom u_sprite(
    .clk(I_clk),.enable(sprite_hit),.address(sprite_addr),
    .index(sprite_index),.rgb(sprite_rgb)
);

reg [23:0] bg_q;
reg hit_q,enable_q;
always @(posedge I_clk or posedge I_rst) begin
    if(I_rst) begin
        O_vs<=0;
        O_de<=0;
        bg_q<=0;
        hit_q<=0;
        enable_q<=0;
    end else begin
        O_vs<=I_vs;
        O_de<=I_de;
        bg_q<=I_rgb;
        hit_q<=sprite_hit;
        enable_q<=I_enable;
    end
end

// Palette index zero is transparent; all other indexed pixels are the car.
assign O_rgb=(O_de && enable_q && hit_q && sprite_index!=0) ? sprite_rgb : bg_q;
endmodule
