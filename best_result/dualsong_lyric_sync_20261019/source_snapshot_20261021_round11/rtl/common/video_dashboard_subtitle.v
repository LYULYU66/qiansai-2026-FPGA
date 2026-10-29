`timescale 1ns/1ps
// Dashboard (TF5) top band, 20261021.
//   Normal: "安路科技提醒您行车安全，祝您旅途愉快" scrolls right-to-left at
//           1 px/frame in a 32 px band (y 22..53) between two thin light-blue
//           rules that fade out towards the screen sides; text fades in/out
//           over the outer 32 px and has a white -> sky-blue vertical gradient.
//   Hazard: large bold "注意安全" (64 px, x 192..447, y 6..69) breathing
//           between deep and bright red at ~0.9 Hz, with red bars on the
//           band edges pulsing in step.
// B is LUT-bound, so every colour is precomputed: glyph ROM -> colour ROM
// (subtitle_colour_rom, all mixes over the band's near-black artwork) ->
// output.  Two clocks of latency; O_rgb/O_vs/O_de are the inputs delayed by
// two clocks.  I_x/I_y are the raster position of the pixel on I_rgb (from
// video_car_intro_light).  Two BRAM32K glyph ROMs + three BRAM9K colours.
module video_dashboard_subtitle #(
    parameter [9:0] SCROLL_INIT = 10'd384   // first character enters from the right
) (
    input  wire        I_clk,
    input  wire        I_rst,
    input  wire        I_enable,
    input  wire        I_hazard_async,
    input  wire        I_vs,
    input  wire        I_de,
    input  wire [10:0] I_x,
    input  wire [9:0]  I_y,
    input  wire [23:0] I_rgb,
    output reg  [23:0] O_rgb,
    output reg         O_vs,
    output reg         O_de
);
(* async_reg="true" *) reg [1:0] hazard_sync;
reg hazard_frame, vs_prev;
reg [9:0] scroll;
reg [5:0] pulse;
wire frame_start=I_vs&&!vs_prev;
always @(posedge I_clk or posedge I_rst) begin
    if(I_rst) begin
        vs_prev<=0; hazard_sync<=0; hazard_frame<=0;
        scroll<=SCROLL_INIT; pulse<=0;
    end else begin
        vs_prev<=I_vs;
        hazard_sync<={hazard_sync[0],I_hazard_async};
        if(frame_start) begin
            hazard_frame<=hazard_sync[1];
            scroll<=scroll+1'b1;
            pulse<=pulse+1'b1;
        end
    end
end
wire [4:0] breath=pulse[5] ? ~pulse[4:0] : pulse[4:0];       // 0..31..0

// ---- stage 0: glyph ROM address ----
// Every band lies in y<128 and the warning box is the 64-px columns 3..6.
wire band_rows=I_enable && I_de && I_y<10'd128;
wire [6:0] y7=I_y[6:0];
wire [3:0] seg=I_x[9:6];
wire [9:0] tick_col=I_x[9:0]+scroll;
wire [4:0] tick_row=I_y[4:0]-5'd22;                    // band y 22..53
wire [3:0] tick_glyph;
wire tick_valid;
subtitle_ticker_text u_text(.pos(tick_col[9:5]),.glyph(tick_glyph),.valid(tick_valid));
wire [7:0] warn_x=I_x[7:0]+8'd64;                      // I_x-192
wire [5:0] warn_row=I_y[5:0]-6'd6;                     // box y 6..69
wire tick_hit=band_rows && !hazard_frame && y7>=7'd22 && y7<7'd54 && tick_valid;
wire warn_hit=band_rows && hazard_frame && seg>=4'd3 && seg<=4'd6 &&
              y7>=7'd6 && y7<7'd70;
wire [15:0] tick_q,warn_q;
subtitle_ticker_rom u_tick_rom(.clk(I_clk),.ce(tick_hit),
    .addr({tick_glyph,tick_row,tick_col[4:3]}),.q(tick_q));
subtitle_warning_rom u_warn_rom(.clk(I_clk),.ce(warn_hit),
    .addr({warn_x[7:6],warn_row,warn_x[5:3]}),.q(warn_q));
// Rules (y 12 and 63): opacity 0,2,4,6,6,6,6,4,2,0 eighths per 64-px column.
reg [2:0] rule_w;
always @* begin
    case(seg)
        4'd1,4'd8: rule_w=3'd2;
        4'd2,4'd7: rule_w=3'd4;
        4'd3,4'd4,4'd5,4'd6: rule_w=3'd6;
        default: rule_w=3'd0;
    endcase
end
wire rule_hit=band_rows && !hazard_frame && rule_w!=3'd0 && (y7==7'd12 || y7==7'd63);
wire bar_hit=band_rows && hazard_frame && (y7<7'd3 || (y7>=7'd73 && y7<7'd76));
// Text fade over the outer 32 px: limit in eighths 0,2,4,6 / 8.
wire [3:0] edge_limit=(I_x[9:5]==5'd0)  ? {1'b0,I_x[4:3],1'b0} :
                      (I_x[9:5]==5'd19) ? {1'b0,~I_x[4:3],1'b0} : 4'd8;

// ---- stage 1: coverage -> colour ROM address ----
reg [23:0] bg1;
reg vs1,de1,tick1,warn1,rule1,bar1;
reg [2:0] lane1,rule_w1;
reg [4:0] row1;
reg [3:0] limit1;
always @(posedge I_clk or posedge I_rst) begin
    if(I_rst) begin
        bg1<=0; vs1<=0; de1<=0; tick1<=0; warn1<=0; rule1<=0; bar1<=0;
        lane1<=0; rule_w1<=0; row1<=0; limit1<=0;
    end else begin
        bg1<=I_rgb; vs1<=I_vs; de1<=I_de;
        tick1<=tick_hit; warn1<=warn_hit; rule1<=rule_hit && !tick_hit; bar1<=bar_hit;
        lane1<=hazard_frame ? warn_x[2:0] : tick_col[2:0];
        rule_w1<=rule_w; row1<=tick_row; limit1<=edge_limit;
    end
end
wire [15:0] glyph_word=warn1 ? warn_q : tick_q;
wire [1:0] level=glyph_word[{lane1,1'b0} +: 2];
// Coverage levels 1..3 -> 3/8, 6/8, 8/8.
wire [3:0] cov_w=(level==2'd3) ? 4'd8 : (level==2'd2) ? 4'd6 : (level==2'd1) ? 4'd3 : 4'd0;
wire [3:0] tick_w=(cov_w<limit1) ? cov_w : limit1;
reg [1:0] kind;
reg [4:0] sel;
reg [3:0] w;
always @* begin
    kind=2'd0; sel=row1; w=4'd0;
    if(warn1)      begin kind=2'd1; sel=breath; w=cov_w; end
    else if(bar1)  begin kind=2'd3; sel=breath; w=breath[4] ? 4'd6 : 4'd4; end
    else if(tick1) begin kind=2'd0; sel=row1;   w=tick_w; end
    else if(rule1) begin kind=2'd2; sel=5'd0;   w={1'b0,rule_w1}; end
end
wire [23:0] colour;
wire paint=w!=4'd0;
wire [2:0] w_index=w[2:0]-3'd1;                        // 1..8 -> 0..7
subtitle_colour_rom u_colour(.clk(I_clk),.ce(paint),.addr({kind,sel,w_index}),.q(colour));

// ---- stage 2: output ----
reg paint2;
reg [23:0] bg2;
always @(posedge I_clk or posedge I_rst) begin
    if(I_rst) begin paint2<=0; bg2<=0; O_vs<=0; O_de<=0; end
    else begin paint2<=paint; bg2<=bg1; O_vs<=vs1; O_de<=de1; end
end
always @* O_rgb=paint2 ? colour : bg2;
endmodule
