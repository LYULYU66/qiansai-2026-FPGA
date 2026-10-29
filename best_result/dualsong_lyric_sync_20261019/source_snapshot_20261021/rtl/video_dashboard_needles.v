`timescale 1ns/1ps
// Red live needles for the TF5 instrument-cluster background.
// The background is static artwork; this small overlay supplies the two
// radial needles without touching the cached image or HDMI timing.
module gauge_needle_dynamic #(
    parameter integer CX=145,
    parameter integer CY=240
) (
    input  wire [10:0] x,
    input  wire [9:0]  y,
    input  wire [10:0] ex,
    input  wire [9:0]  ey,
    output reg         hit
);
integer wx,wy,cross,along,cross_abs;
always @* begin
    wx=x-CX;
    wy=y-CY;
    cross=wx*(ey-CY)-wy*(ex-CX);
    along=0;
    cross_abs=(cross<0)?-cross:cross;
    hit=(x>=((ex<CX)?ex:CX) && x<=((ex>CX)?ex:CX) &&
         y>=((ey<CY)?ey:CY) && y<=((ey>CY)?ey:CY) &&
         cross_abs<=3*(((ex<CX)?CX-ex:ex-CX) >
                       ((ey<CY)?CY-ey:ey-CY) ?
                       ((ex<CX)?CX-ex:ex-CX) :
                       ((ey<CY)?CY-ey:ey-CY)));
end
endmodule

module video_dashboard_needles #(
    parameter integer STEP_CYCLES=12_500_000,
    parameter integer DEBOUNCE_CYCLES=250_000
) (
    input  wire        I_clk,
    input  wire        I_rst,
    input  wire        I_enable,
    input  wire        I_vs,
    input  wire        I_de,
    input  wire        I_boost_key_n,
    input  wire [23:0] I_rgb,
    output wire [23:0] O_rgb
);
localparam integer STEP_BITS=(STEP_CYCLES>1)?$clog2(STEP_CYCLES):1;
localparam integer KEY_BITS=(DEBOUNCE_CYCLES>1)?$clog2(DEBOUNCE_CYCLES+1):1;

// Keep the button as a level: pressed = active-low key is held low.
reg key_meta,key_sync,key_stable;
reg [KEY_BITS-1:0] key_count;
always @(posedge I_clk or posedge I_rst) begin
    if(I_rst) begin
        key_meta<=1'b0; key_sync<=1'b0; key_stable<=1'b0; key_count<=0;
    end else begin
        key_meta<=~I_boost_key_n;
        key_sync<=key_meta;
        if(key_sync==key_stable) begin
            key_count<=0;
        end else if(key_count==DEBOUNCE_CYCLES-1) begin
            key_stable<=key_sync;
            key_count<=0;
        end else begin
            key_count<=key_count+1'b1;
        end
    end
end

// Use a small triangle sweep in the normal state so the needles only drift
// a few pixels around their nominal position.  The boost state still uses the
// full 4/5 and 100/120 excursion, but moves through a midpoint for a cleaner
// visual transition.
reg [STEP_BITS-1:0] step_count;
reg [1:0] sweep_step;
always @(posedge I_clk or posedge I_rst) begin
    if(I_rst) begin step_count<=0; sweep_step<=0; end
    else if(step_count==STEP_CYCLES-1) begin
        step_count<=0;
        case (sweep_step)
            2'd0:    sweep_step<=2'd1;
            2'd1:    sweep_step<=2'd2;
            default: sweep_step<=2'd1;
        endcase
    end else step_count<=step_count+1'b1;
end

// Raster position. next_x/next_y is the pixel represented by the current
// I_de/I_rgb pair, matching the existing video overlays in this project.
reg [10:0] pixel_x,next_x;
reg [9:0]  pixel_y,next_y;
reg de_d,vs_d,active_seen,next_seen;
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
            else if(pixel_y<479) next_y=pixel_y+1'b1;
        end else if(pixel_x<639) next_x=pixel_x+1'b1;
    end else next_x=0;
end
always @(posedge I_clk or posedge I_rst) begin
    if(I_rst) begin
        pixel_x<=0; pixel_y<=0; de_d<=0; vs_d<=0; active_seen<=0;
    end else begin
        pixel_x<=next_x; pixel_y<=next_y;
        de_d<=I_de; vs_d<=I_vs; active_seen<=next_seen;
    end
end

// Endpoints are calibrated to the final 640x480 artwork. The 270-degree
// sweep maps the requested displayed values to their dial angles. Only one
// dynamic segment is evaluated per gauge, keeping the network light.
reg [10:0] rpm_ex,spd_ex;
reg [9:0]  rpm_ey,spd_ey;
always @* begin
    if(key_stable) begin
        case (sweep_step)
            2'd0: begin
                rpm_ex=11'd145; rpm_ey=10'd140;
                spd_ex=11'd495; spd_ey=10'd140;
            end
            2'd1: begin
                rpm_ex=11'd172; rpm_ey=10'd148;
                spd_ex=11'd518; spd_ey=10'd145;
            end
            default: begin
                rpm_ex=11'd200; rpm_ey=10'd157;
                spd_ex=11'd540; spd_ey=10'd151;
            end
        endcase
    end else begin
        // Normal state: approximately +/-3 degrees around the low-speed
        // and 50 km/h marks, rather than the former wide 1/2 and 40/60 sweep.
        case (sweep_step)
            2'd0: begin
                rpm_ex=11'd47; rpm_ey=10'd235;
                spd_ex=11'd403; spd_ey=10'd208;
            end
            2'd1: begin
                rpm_ex=11'd48; rpm_ey=10'd230;
                spd_ex=11'd405; spd_ey=10'd203;
            end
            default: begin
                rpm_ex=11'd49; rpm_ey=10'd225;
                spd_ex=11'd407; spd_ey=10'd198;
            end
        endcase
    end
end
wire rpm_line,spd_line;
gauge_needle_dynamic #(.CX(145),.CY(240)) u_rpm_needle (
    .x(next_x),.y(next_y),.ex(rpm_ex),.ey(rpm_ey),.hit(rpm_line));
gauge_needle_dynamic #(.CX(495),.CY(240)) u_spd_needle (
    .x(next_x),.y(next_y),.ex(spd_ex),.ey(spd_ey),.hit(spd_line));
wire rpm_hub=(next_x>=141 && next_x<=149 && next_y>=236 && next_y<=244);
wire spd_hub=(next_x>=491 && next_x<=499 && next_y>=236 && next_y<=244);
wire needle_on=I_enable && I_de && (rpm_line || spd_line || rpm_hub || spd_hub);
assign O_rgb=needle_on ? 24'hF01828 : I_rgb;
endmodule
