// Native 24px AA, progressive pixel sweep, two rows and gentle line advance.
// One font read per pixel, no additional RGB/DE/VS delay or frame buffer.
module video_lyric_overlay #(parameter LOW_POWER=0)(
    input I_clk,I_rst,I_enable,I_vs,I_de,
    input I_card_enable,
    input I_intro_enable,
    input I_home_enable,
    input [2:0] I_song,
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
// Character cache in LUT RAM (combinational read, same timing as the former
// registers). cache_loaded masks it to the old all-zero reset contents until
// one complete load has rewritten all 36 cells; drawing is blocked while a
// load is in progress, so stale cells are never visible.
// Cells hold physical 10-bit glyph ids (lyric_glyph_map applied on load).
reg [9:0] row_cache[0:63];
reg cache_loaded;
reg [7:0] cache_line,cache_next_line;
reg [2:0] cache_song;
wire cache_dirty=!cache_loaded || I_line!=cache_line || I_next_line!=cache_next_line || I_song!=cache_song;
wire [8:0] cached_char;
wire [9:0] physical_char;
wire [4:0] requested_length,requested_next_length;
wire [1:0] load_row=load_index[5:4];
// Song-head rows are ordinary rows of lyric_line_rom bank 6, emitted by the
// PCM timeline like lyrics, so they use the same lengths and red sweep.
// I_intro_enable remains in the interface for project compatibility only.
wire [7:0] song_credit_line={cache_song,5'd26};
wire [7:0] load_line=(load_row==0)?(LOW_POWER ? cache_line : line_frame):
    (load_row==1)?(LOW_POWER ? cache_next_line : next_line_frame):song_credit_line;
lyric_line_rom u_lines(.I_clk(I_clk),.I_addr({load_line,load_index[3:0]}),
    .I_line(I_line),.I_next_line(I_next_line),.O_char(cached_char),
    .O_length(requested_length),.O_next_length(requested_next_length));
// More than 512 glyphs are stored; one song reuses the top logical ids.
lyric_glyph_map u_glyph_map(.I_song(cache_song),.I_glyph(cached_char),.O_glyph(physical_char));
wire [4:0] frame_length=requested_length;
wire [4:0] next_frame_length=requested_next_length;
wire cache_write=!I_rst && !frame_start && load_busy && load_valid && load_index!=0;
always @(posedge I_clk)
    if(cache_write) row_cache[load_index-1'b1]<=physical_char;
always @(posedge I_clk or posedge I_rst) begin
    if(I_rst) begin
        pixel_x<=0; pixel_y<=0; de_d<=0; vs_d<=0; active_seen<=0;
        line_frame<=0; next_line_frame<=0; length_frame<=0; next_length_frame<=0;
        red_frame<=0; slide<=0;
        load_index<=0; load_busy<=0; load_valid<=0; cache_loaded<=0;
        cache_line<=0; cache_next_line<=0;
        cache_song<=0;
    end else begin
        pixel_x<=next_x; pixel_y<=next_y; active_seen<=next_seen;
        de_d<=I_de; vs_d<=I_vs;
        if(frame_start) begin
            line_frame<=I_line; next_line_frame<=I_next_line;
            length_frame<=frame_length; next_length_frame<=next_frame_length;
            red_frame<=I_red_pixels;
            // The previously previewed next line slides into the focus row.
            // 36px in twelve frames (~0.2s); new preview enters from below.
            if(I_line!=line_frame) begin
                // Bank 6 head rows hand over to bank-N lyrics, so compare
                // the complete {bank,id} instead of requiring one bank.
                if(I_line==next_line_frame && I_line[4:0]!=0 &&
                   line_frame[4:0]!=0) slide<=36;
                else slide<=0;
            end else if(slide>3) slide<=slide-3;
            else slide<=0;
            // Red sweep and line slide still update every frame. Characters
            // reload only on first display or a different current/next pair.
            if(!LOW_POWER || ((I_enable || I_card_enable || I_home_enable) && cache_dirty)) begin
                load_index<=0; load_busy<=1; load_valid<=0;
                if(LOW_POWER) cache_loaded<=0;
                cache_line<=I_line; cache_next_line<=I_next_line;
                cache_song<=I_song;
            end
        end else if(load_busy) begin
            // Cells 32..38 hold the music-card title (up to seven characters).
            if(load_index==39) begin load_busy<=0; load_valid<=0; cache_loaded<=1; end
            else begin load_index<=load_index+1'b1; load_valid<=1; end
        end
    end
end

wire [2:0] title_length;
lyric_title_length u_title_length(.I_song(cache_song),.O_length(title_length));
// Titles use the 24px lyric font on both cards (20261021):
//   music card (page 2): one line, 28px pitch, centred at x=332;
//   home card  (page 1): 26px pitch, centred at x=283 right of the cover;
//                        titles longer than four characters use two lines.
wire home_two=title_length>3'd4;
reg [1:0] selected_row;
reg [9:0] row_y;
reg [4:0] row_length;
reg [2:0] line_len, line_off;
always @(*) begin
    line_len=title_length; line_off=3'd0;
    if(I_home_enable && !home_two && next_y>=331 && next_y<355) begin
        selected_row=3; row_y=331; row_length={2'd0,title_length};
    end else if(I_home_enable && home_two && next_y>=318 && next_y<342) begin
        selected_row=3; row_y=318; row_length=5'd4; line_len=3'd4;
    end else if(I_home_enable && home_two && next_y>=344 && next_y<368) begin
        selected_row=3; row_y=344; row_length={2'd0,title_length-3'd4};
        line_len=title_length-3'd4; line_off=3'd4;
    end else if(I_card_enable && next_y>=144 && next_y<168) begin
        selected_row=2; row_y=144; row_length={2'd0,title_length};
    end else if(next_y>=NEXT_Y+slide) begin
        selected_row=1; row_y=NEXT_Y+slide; row_length=next_length_frame;
    end else begin selected_row=0; row_y=CURRENT_Y+slide; row_length=length_frame; end
end
// 32px pitch eliminates the old divide-by-three. Crop only the all-zero
// native-font margins x=0/23,y=0/1; all antialiased pixels are retained.
// Title cell/column are counters stepped with the pixel position, keeping
// the titles off the long subtract/compare chain of the glyph-address path.
// Their per-line parameters are registered (they only change between lines).
localparam [10:0] CARD_CENTER=332, HOME_CENTER=283;
wire [10:0] home_half={5'd0,line_len,3'd0}+{6'd0,line_len,2'd0}+{8'd0,line_len}; // 13*len
wire [10:0] card_half={4'd0,line_len,4'd0}-{6'd0,line_len,1'b0};                 // 14*len
reg [10:0] title_start_x;
reg [4:0] title_last;
reg [2:0] title_len_r, title_off_r;
reg [4:0] title_cell;
reg [2:0] title_char;
reg title_active;
reg [4:0] next_title_cell;
reg [2:0] next_title_char;
reg next_title_active;
wire pixel_advance=!frame_start && I_de && !line_start && pixel_x<639;
always @(*) begin
    next_title_cell=0; next_title_char=0; next_title_active=0;
    if(pixel_advance && pixel_x==title_start_x) begin
        next_title_active=1;
    end else if(pixel_advance && title_active) begin
        if(title_cell==title_last) begin
            next_title_char=title_char+1'b1;
            next_title_active=(title_char+1'b1<title_len_r);
        end else begin
            next_title_cell=title_cell+1'b1; next_title_char=title_char;
            next_title_active=1;
        end
    end
end
always @(posedge I_clk or posedge I_rst) begin
    if(I_rst) begin
        title_start_x<=0; title_last<=5'd27; title_len_r<=0; title_off_r<=0;
        title_cell<=0; title_char<=0; title_active<=0;
    end else begin
        // First title pixel is centre - pitch*len/2; matched one pixel early.
        title_start_x<=(selected_row==3 ? HOME_CENTER-home_half : CARD_CENTER-card_half)-11'd1;
        title_last<=selected_row==3 ? 5'd25 : 5'd27;
        title_len_r<=line_len; title_off_r<=line_off;
        title_cell<=next_title_cell; title_char<=next_title_char;
        title_active<=next_title_active;
    end
end
wire [4:0] title_margin=selected_row==3 ? 5'd2 : 5'd3;   // (pitch-22)/2
wire [10:0] text_left=11'd320-{2'd0,row_length,4'd0};
wire [10:0] text_right=text_left+{1'd0,row_length,5'd0};
wire [10:0] relative_x=next_x-text_left;
wire [2:0] title_index=title_off_r+next_title_char;
wire [4:0] character_index=selected_row[1] ? {2'd0,title_index} : relative_x[9:5];
wire [9:0] relative_y=next_y-row_y;
wire [4:0] glyph_col=selected_row[1] ? next_title_cell-title_margin : relative_x[4:0]-5'd5;
wire [4:0] glyph_row=relative_y-2;
// The titles need only seven cache entries, not a sixteen-cell row.
wire [5:0] cache_addr=selected_row[1] ? {3'b100,character_index[2:0]} :
    {1'b0,selected_row[0],character_index[3:0]};
wire [9:0] glyph_id=cache_loaded ? row_cache[cache_addr] : 10'd0;
wire title_hit=selected_row[1] &&
    (!LOW_POWER || (selected_row==3 ? I_home_enable : I_card_enable)) && !load_busy &&
    next_title_active && next_title_cell>=title_margin && next_title_cell<title_margin+5'd22 &&
    next_y>=row_y+2 && next_y<row_y+24;
 wire next_hit=title_hit || (!selected_row[1] && (!LOW_POWER || I_enable) &&
    !load_busy && row_length!=0 && next_x>=text_left &&
    next_x<text_right && character_index<row_length &&
    relative_x[4:0]>=5 && relative_x[4:0]<27 && next_y>=row_y+2 && next_y<row_y+24 && next_y<304);
 wire font_hit=next_hit;
 wire [9:0] font_glyph=glyph_id;
 wire [4:0] font_row=glyph_row;
 wire [4:0] font_col=glyph_col;
// The QQ Music logo replaces every song cover on the music card. Its pixels
// share the font ROM read port; the box never overlaps a glyph pixel.
localparam [10:0] ICON_X=160;
localparam [9:0] ICON_Y=136;
wire icon_next=I_card_enable && next_x>=ICON_X && next_x<ICON_X+64 &&
    next_y>=ICON_Y && next_y<ICON_Y+64;
wire [5:0] icon_x=next_x-ICON_X;
wire [5:0] icon_y=next_y-ICON_Y;
wire [1:0] coverage;
wire [3:0] icon_index;
lyric_font_packed_rom u_font(.I_clk(I_clk),
    .I_glyph(font_hit?font_glyph:10'd0),.I_row(font_hit?font_row:5'd0),
    .I_col(font_hit?font_col:5'd0),
    .I_icon(icon_next),.I_icon_pixel({icon_y,icon_x}),
    .O_cov(coverage),.O_icon_index(icon_index));
wire [23:0] icon_rgb;
lyric_icon_palette u_icon_palette(.I_index(icon_index),.O_rgb(icon_rgb));
reg icon_hit;
always @(posedge I_clk or posedge I_rst)
    if(I_rst) icon_hit<=0; else icon_hit<=icon_next;
 reg glyph_hit,title_tag;
reg [23:0] ink;
wire [10:0] cursor=(red_frame==0)?11'd0:{1'b0,red_frame}+11'd4;
// Current credit/lyric row shares the same pixel sweep and feather.
// The card title is dark ink and independent of the PCM-file match gate.
always @(posedge I_clk or posedge I_rst) begin
    if(I_rst) begin glyph_hit<=0; title_tag<=0; ink<=24'hFFFFFF; end
    else begin
        glyph_hit<=font_hit;
        title_tag<=selected_row[1];
        if(selected_row[1]) ink<=24'h1D3042;
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
// Credits and lyrics share the same antialiased glyph path. No backing
// rectangle is drawn, so the photograph remains visible around both rows.
wire [1:0] cov=I_de&&glyph_hit&&
    (title_tag?(I_card_enable||I_home_enable):I_enable)?coverage:2'd0;
// The old home-atlas title is replaced in place, without reloading its SDRAM
// cache. Only this 64x16 white card patch changes; unrelated art is untouched.
// Home card: clear the atlas title (240..303 x 338..353) and the small QQ
// logo (316..335 x 336..355), with a 3-4 px margin against any 1-px skew of
// the cached background; the centred 24px title is drawn over this white.
wire erase_home=I_home_enable && I_de && pixel_x>=232 && pixel_x<339 && pixel_y>=330 && pixel_y<362;
// Music card: the old 20px service logo (392..411 x 146..165) is removed,
// with a 3 px margin so no edge pixel survives a 1-px background skew.
wire erase_music=I_card_enable && I_de &&
    pixel_x>=389 && pixel_x<415 && pixel_y>=143 && pixel_y<169;
wire [23:0] background=(I_de && icon_hit) ? icon_rgb :
    (erase_home || erase_music) ? 24'hFFFFFF : I_rgb;
assign O_rgb={blend(background[23:16],ink[23:16],cov),
              blend(background[15:8],ink[15:8],cov),
              blend(background[7:0],ink[7:0],cov)};
endmodule
