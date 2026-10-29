// Native 24px AA, progressive pixel sweep, two rows and gentle line advance.
// One font read per pixel, no additional RGB/DE/VS delay or frame buffer.
module video_lyric_overlay(
    input I_clk,I_rst,I_enable,I_vs,I_de,
    input I_card_enable,
    input [23:0] I_rgb,
    input [7:0] I_line,I_next_line,
    input [9:0] I_red_pixels,
    output [23:0] O_rgb
);
localparam [9:0] CURRENT_Y=232,NEXT_Y=268;
reg [10:0] pixel_x,next_x;
reg [9:0] pixel_y,next_y;
reg de_d,vs_d,active_seen,next_seen;
wire frame_start=I_vs&&!vs_d;
wire line_start=I_de&&!de_d;
always @(*) begin
    next_x=pixel_x; next_y=pixel_y; next_seen=active_seen;
    if(frame_start) begin next_x=0; next_y=0; next_seen=0; end
    else if(I_de) begin
        if(line_start) begin
            next_x=0;
            if(!active_seen) begin next_y=0; next_seen=1; end
            else if(pixel_y<479) next_y=pixel_y+1'b1;
        end else if(pixel_x<639) next_x=pixel_x+1'b1;
    end else next_x=0;
end
reg [7:0] line_frame,next_line_frame;
reg [4:0] length_frame,next_length_frame;
reg [9:0] red_frame;
reg [5:0] slide;
reg [5:0] load_index;
reg load_busy,load_valid;
reg [7:0] row_cache[0:35];
wire [7:0] cached_char;
wire [4:0] requested_length,requested_next_length;
wire [1:0] load_row=load_index[5:4];
// Credits use the normal current/next pair; a third cache row shares the
// same font port for the music-card title. No second font or image ROM.
wire [7:0] load_line=(load_row==0)?line_frame:
    (load_row==1)?next_line_frame:8'd26;
lyric_line_rom u_lines(.I_clk(I_clk),.I_addr({load_line[5:0],1'b0,load_index[3:0]}),
    .I_line(I_line),.I_next_line(I_next_line),.O_char(cached_char),
    .O_length(requested_length),.O_next_length(requested_next_length));
integer n;
always @(posedge I_clk or posedge I_rst) begin
    if(I_rst) begin
        pixel_x<=0; pixel_y<=0; de_d<=0; vs_d<=0; active_seen<=0;
        line_frame<=0; next_line_frame<=0; length_frame<=0; next_length_frame<=0;
        red_frame<=0; slide<=0;
        load_index<=0; load_busy<=0; load_valid<=0;
        for(n=0;n<36;n=n+1) row_cache[n]<=0;
    end else begin
        pixel_x<=next_x; pixel_y<=next_y; active_seen<=next_seen;
        de_d<=I_de; vs_d<=I_vs;
        if(frame_start) begin
            line_frame<=I_line; next_line_frame<=I_next_line;
            length_frame<=requested_length; next_length_frame<=requested_next_length;
            red_frame<=I_red_pixels;
            // The previously previewed next line slides into the focus row.
            // 36px in twelve frames (~0.2s); new preview enters from below.
            if(I_line!=line_frame) begin
                if(I_line==next_line_frame && I_line!=0 && I_line<26 &&
                   line_frame!=0 && line_frame<26) slide<=36;
                else slide<=0;
            end else if(slide>3) slide<=slide-3;
            else slide<=0;
            load_index<=0; load_busy<=1; load_valid<=0;
        end else if(load_busy) begin
            if(load_valid && load_index>0) row_cache[load_index-1'b1]<=cached_char;
            if(load_index==36) begin load_busy<=0; load_valid<=0; end
            else begin load_index<=load_index+1'b1; load_valid<=1; end
        end
    end
end

reg [1:0] selected_row;
reg [9:0] row_y;
reg [4:0] row_length;
always @(*) begin
    if(next_y>=144 && next_y<168) begin
        selected_row=2; row_y=144; row_length=4;
    end else if(next_y>=NEXT_Y+slide) begin
        selected_row=1; row_y=NEXT_Y+slide; row_length=next_length_frame;
    end else begin selected_row=0; row_y=CURRENT_Y+slide; row_length=length_frame; end
end
// 32px pitch eliminates the old divide-by-three. Crop only the all-zero
// native-font margins x=0/23,y=0/1; all antialiased pixels are retained.
wire [10:0] text_left=(selected_row==2)?11'd248:
    11'd320-{2'd0,row_length,4'd0};
wire [10:0] text_right=text_left+{1'd0,row_length,5'd0};
wire [10:0] relative_x=next_x-text_left;
wire [4:0] character_index=relative_x[9:5];
wire [4:0] glyph_col=relative_x[4:0]-5'd5;
wire [4:0] glyph_row=next_y-row_y-2;
// The card title needs only four cache entries, not a sixteen-cell row.
wire [5:0] cache_addr=selected_row[1] ? {4'b1000,character_index[1:0]} :
    {1'b0,selected_row[0],character_index[3:0]};
wire [7:0] glyph_id=row_cache[cache_addr];
wire next_hit=!load_busy && row_length!=0 && next_x>=text_left &&
    next_x<text_right && character_index<row_length &&
    relative_x[4:0]>=5 && relative_x[4:0]<27 &&
    next_y>=row_y+2 && next_y<row_y+24 &&
    next_y<304;
wire [1:0] coverage;
lyric_font_packed_rom u_font(.I_clk(I_clk),
    .I_glyph(next_hit?glyph_id:8'd0),.I_row(next_hit?glyph_row:5'd0),
    .I_col(next_hit?glyph_col:5'd0),.O_cov(coverage));
reg glyph_hit,title_tag;
reg [23:0] ink;
wire [10:0] cursor=(red_frame==0)?11'd0:{1'b0,red_frame}+11'd4;
// Current credit/lyric row shares the same pixel sweep and feather.
// The card title is dark ink and independent of the PCM-file match gate.
always @(posedge I_clk or posedge I_rst) begin
    if(I_rst) begin glyph_hit<=0; title_tag<=0; ink<=24'hFFFFFF; end
    else begin
        glyph_hit<=next_hit;
        title_tag<=(selected_row==2);
        if(selected_row==2) ink<=24'h1D3042;
        else if(selected_row==0 && red_frame!=0 && relative_x<cursor) begin
            if(relative_x+2<cursor) ink<=24'hFF4040;
            else if(relative_x+1<cursor) ink<=24'hFF7070;
            else ink<=24'hFFB8B8;
        end else ink<=24'hFFFFFF;
    end
end
function [7:0] blend;
    input [7:0] bg,fg; input [1:0] cov;
    begin case(cov)
        1: blend=(bg>>1)+(bg>>2)+(fg>>2);
        2: blend=(bg>>2)+(fg>>1)+(fg>>2)+{7'd0,fg[0]};
        3: blend=fg;
        default: blend=bg;
    endcase end
endfunction
// Intro credits use exactly the lyric font, white/red ink and AA blending.
// No backing rectangle or status frame: all non-text pixels remain untouched.
wire [1:0] cov=I_de&&glyph_hit&&(title_tag?I_card_enable:I_enable)?coverage:2'd0;
assign O_rgb={blend(I_rgb[23:16],ink[23:16],cov),
              blend(I_rgb[15:8],ink[15:8],cov),
              blend(I_rgb[7:0],ink[7:0],cov)};
endmodule
