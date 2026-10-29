// One clock for every screen, driven by the existing 25 MHz pixel clock.
// This is an elapsed wall-clock display, not a battery-backed/calendar RTC.
// Power-up/reset always starts at 09:00:00; page changes never reset it.
module video_unified_clock #(
    parameter integer CLK_FREQ_HZ=25000000,
    parameter [23:0] START_BCD=24'h090000
)(
    input wire I_clk,I_rst,I_vs,
    output reg [23:0] O_time_bcd,
    output reg [15:0] O_frame_hhmm
);
localparam DIV_BITS=(CLK_FREQ_HZ<2)?1:$clog2(CLK_FREQ_HZ);
reg [DIV_BITS-1:0] second_count;
reg vs_d;
function [7:0] bcd_next;
    input [7:0] value;
    begin bcd_next=value[3:0]==9 ? {value[7:4]+4'd1,4'd0} : value+8'd1; end
endfunction
always @(posedge I_clk or posedge I_rst) begin
    if(I_rst) begin
        second_count<=0;O_time_bcd<=START_BCD;
        O_frame_hhmm<=START_BCD[23:8];vs_d<=0;
    end else begin
        vs_d<=I_vs;
        // One shared frame snapshot makes all digits/pages atomic, even at
        // 09:59 -> 10:00 or when switching pages on the one-second edge.
        if(I_vs && !vs_d) O_frame_hhmm<=O_time_bcd[23:8];
        if(second_count==CLK_FREQ_HZ-1) begin
            second_count<=0;
            if(O_time_bcd[7:0]==8'h59) begin
                O_time_bcd[7:0]<=0;
                if(O_time_bcd[15:8]==8'h59) begin
                    O_time_bcd[15:8]<=0;
                    O_time_bcd[23:16]<=O_time_bcd[23:16]==8'h23 ? 8'h00 : bcd_next(O_time_bcd[23:16]);
                end else O_time_bcd[15:8]<=bcd_next(O_time_bcd[15:8]);
            end else O_time_bcd[7:0]<=bcd_next(O_time_bcd[7:0]);
        end else second_count<=second_count+1'b1;
    end
end
endmodule

// Native antialiased 16x24 digits. One small synchronous row ROM is shared
// by the stacked clock on page3 and compact HH:MM clocks on other pages.
// Like existing font overlays, lookahead aligns coverage with current RGB
// without adding any delay to RGB/DE/VS.
module video_clock_overlay #(parameter LOW_POWER=0)(
    input wire I_clk,I_rst,I_enable,I_vs,I_de,
    input wire [1:0] I_picture_idx,
    input wire [15:0] I_frame_hhmm,
    input wire [23:0] I_rgb,
    output wire [23:0] O_rgb
);
reg [9:0] x,nx;
reg [8:0] y,ny;
reg de_d,vs_d,seen,nseen;
wire fs=I_vs && !vs_d;
always @(*) begin
    nx=x;ny=y;nseen=seen;
    if(fs) begin nx=0;ny=0;nseen=0;end
    else if(I_de) begin
        if(!de_d)begin nx=0;if(!seen)begin ny=0;nseen=1;end else if(y<479)ny=y+1'b1;end
        else if(x<639)nx=x+1'b1;
    end else nx=0;
end
always @(posedge I_clk or posedge I_rst) begin
    if(I_rst)begin x<=0;y<=0;de_d<=0;vs_d<=0;seen<=0;end
    else begin x<=nx;y<=ny;seen<=nseen;de_d<=I_de;vs_d<=I_vs;end
end
reg hit_next,colon_next;
reg [3:0] digit_next;
reg [4:0] row_next;
reg [3:0] col_next;
reg [6:0] local_x;
reg [2:0] glyph_cell;
always @(*) begin
    hit_next=0;colon_next=0;digit_next=0;row_next=0;col_next=0;local_x=0;glyph_cell=0;
    if(I_picture_idx==2) begin
        // Right-aligned, two rows: hours above minutes, no box or colon.
        if(nx>=544 && nx<576 && ((ny>=152 && ny<176)||(ny>=180 && ny<204))) begin
            hit_next=1;col_next=nx[3:0];
            if(ny<176)begin row_next=ny-152;digit_next=nx[4] ? I_frame_hhmm[11:8]:I_frame_hhmm[15:12];end
            else begin row_next=ny-180;digit_next=nx[4] ? I_frame_hhmm[3:0]:I_frame_hhmm[7:4];end
        end
    end else begin
        // Homepage replaces its fixed 09:00; music/warning clock sits above
        // all lyric and hazard cards, below the common parameter line.
        if(nx>=544 && nx<624 &&
           ((I_picture_idx==0 && ny>=82 && ny<106)||
            (I_picture_idx!=0 && ny>=38 && ny<62))) begin
            local_x=nx-544;glyph_cell=local_x[6:4];col_next=local_x[3:0];
            row_next=I_picture_idx==0 ? ny-82 : ny-38;hit_next=1;
            case(glyph_cell)
                0:digit_next=I_frame_hhmm[15:12];
                1:digit_next=I_frame_hhmm[11:8];
                2:begin colon_next=1;digit_next=0;end
                3:digit_next=I_frame_hhmm[7:4];
                default:digit_next=I_frame_hhmm[3:0];
            endcase
        end
    end
end
wire [7:0] row_address={digit_next,4'd0}+{digit_next,3'd0}+row_next;
wire [15:0] row_coverage;
video_clock_digit_rom #(.LOW_POWER(LOW_POWER)) font(.I_clk(I_clk),
    .I_read_enable(I_enable && I_de && hit_next && !colon_next),
    .I_address({row_address,col_next[3]}),.O_row(row_coverage));
reg hit,colon;
reg [4:0] row;
reg [3:0] col;
always @(posedge I_clk or posedge I_rst)begin
    if(I_rst)begin hit<=0;colon<=0;row<=0;col<=0;end
    else begin hit<=hit_next;colon<=colon_next;row<=row_next;col<=col_next;end
end
wire colon_on=(col>=7 && col<10)&&((row>=7 && row<10)||(row>=15 && row<18));
wire [1:0] coverage=colon ? (colon_on?2'd3:2'd0) : row_coverage[(7-col[2:0])*2+:2];
// A small white/grayscale antialias palette matches the existing clock style.
// Zero coverage preserves the photograph; no RGB arithmetic/DSP or rectangle.
wire [23:0] ink_color=coverage==3 ? 24'hFFFFFF : coverage==2 ? 24'hE1E1E1 : 24'hAAAAAA;
assign O_rgb=(I_enable && I_de && hit && coverage!=0) ? ink_color:I_rgb;
endmodule
