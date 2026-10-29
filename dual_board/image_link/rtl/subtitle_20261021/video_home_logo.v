`timescale 1ns/1ps
// A page 1 (home), 20261021: the user's logo (00_0.bmp, logo only) on a
// rounded, 7/8-opaque white badge directly below the BRI readout.
//   badge x 18..97, y 38..91 (80x54, corner radius 8)
//   logo  x 24..91, y 43..86 (68x44, 8-colour palette, one BRAM9K)
// Zero latency like the other A overlays: the ROM is addressed one pixel
// ahead (x+1 on the same line; the logo never touches x=0).
module video_home_logo (
    input  wire        I_clk,
    input  wire        I_rst,
    input  wire        I_enable,
    input  wire        I_vs,
    input  wire        I_de,
    input  wire [23:0] I_rgb,
    output wire [23:0] O_rgb
);
localparam [10:0] PX = 11'd18, LX = 11'd24;
localparam [9:0]  PY = 10'd38, LY = 10'd43;
localparam [10:0] PW = 11'd80, LW = 11'd68;
localparam [9:0]  PH = 10'd54, LH = 10'd44;

reg [10:0] x,nx;
reg [9:0]  y,ny;
reg seen,nseen,de_prev,vs_prev;
wire frame_start=I_vs&&!vs_prev;
always @* begin
    nx=x; ny=y; nseen=seen;
    if(frame_start) begin nx=0; ny=0; nseen=0; end
    else if(I_de) begin
        if(!de_prev) begin
            nx=0;
            if(!seen) begin ny=0; nseen=1; end
            else if(y<479) ny=y+1'b1;
        end else if(x<639) nx=x+1'b1;
    end else nx=0;
end
always @(posedge I_clk or posedge I_rst) begin
    if(I_rst) begin x<=0; y<=0; seen<=0; de_prev<=0; vs_prev<=0; end
    else begin x<=nx; y<=ny; seen<=nseen; de_prev<=I_de; vs_prev<=I_vs; end
end

// ---- logo ROM, addressed for the next pixel ----
wire [10:0] ax=nx+11'd1-LX;
wire [9:0]  ay=ny-LY;
wire logo_next=I_enable && nx+11'd1>=LX && nx+11'd1<LX+LW && ny>=LY && ny<LY+LH;
wire [14:0] col_x171={4'd0,ax}*15'd171;            // floor(col/3) for col<68
wire [4:0] word_in_row=col_x171[13:9];
wire [6:0] col3={word_in_row,1'b0}+{2'd0,word_in_row};
wire [1:0] lane=ax[6:0]-col3;
wire [9:0] row_base={ay[5:0],4'd0}+{1'b0,ay[5:0],3'd0}-{4'd0,ay[5:0]};   // *23
wire [8:0] logo_word;
home_logo_rom u_rom(.clk(I_clk),.ce(logo_next),.addr(row_base+{5'd0,word_in_row}),.q(logo_word));
reg logo_q;
reg [1:0] lane_q;
always @(posedge I_clk or posedge I_rst) begin
    if(I_rst) begin logo_q<=0; lane_q<=0; end
    else begin logo_q<=logo_next && I_de; lane_q<=lane; end
end
wire [2:0] logo_index=(lane_q==2'd0) ? logo_word[2:0] :
                      (lane_q==2'd1) ? logo_word[5:3] : logo_word[8:6];
wire [23:0] logo_rgb;
home_logo_palette u_palette(.index(logo_index),.rgb(logo_rgb));

// ---- badge (current pixel) ----
wire [10:0] bx=nx-PX;
wire [9:0]  by=ny-PY;
wire in_box=nx>=PX && nx<PX+PW && ny>=PY && ny<PY+PH;
// Distance (rows) from the nearer horizontal edge, and inset of the arc.
wire [9:0] edge_row=(by<10'd8) ? by : (PH-10'd1-by);
reg [2:0] inset;
always @* begin
    case(edge_row[2:0])
        3'd0: inset=3'd5; 3'd1: inset=3'd3; 3'd2: inset=3'd2;
        3'd3: inset=3'd1; 3'd4: inset=3'd1; default: inset=3'd0;
    endcase
    if(edge_row>=10'd8) inset=3'd0;
end
wire [10:0] edge_col=(bx<11'd8) ? bx : (PW-11'd1-bx);
wire in_badge=I_enable && I_de && in_box && edge_col>={8'd0,inset};
// bg/8 + 7/8 of the badge white (250,251,253): at most 250 per channel.
wire [23:0] badge_rgb={8'hDB+{3'b000,I_rgb[23:19]},
                       8'hDC+{3'b000,I_rgb[15:11]},
                       8'hDD+{3'b000,I_rgb[7:3]}};
assign O_rgb=!in_badge ? I_rgb :
             (logo_q && logo_index!=3'd0) ? logo_rgb : badge_rgb;
endmodule
