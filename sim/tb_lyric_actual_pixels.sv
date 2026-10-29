`timescale 1ns/1ps
module tb_lyric_actual_pixels;
parameter LOW_POWER=0;
parameter OUTPUT_DIR="sim/lyrics_20261001";
reg clk=0,rst=1,vs=0,de=0;
reg [23:0] rgb=0;
reg [1:0] page=1;
reg song_ok=1,transition=0;
reg [7:0] line=14,next_line=15;
reg [9:0] red_pixels_input=177;
wire [23:0] osd_rgb,visual_rgb,home_rgb,lyric_rgb,status_rgb,baseline_rgb;
reg [23:0] image[0:307199];
reg [1:0] reference_font[0:64371];
reg [29:0] reference_events[0:511];
reg [23:0] expected_rgb,ink;
reg [15:0] font_addr=0;
wire [1:0] font_cov;
reg [8:0] event_addr=0;
wire [29:0] event_data;
reg stream_enable=0,sample_read=0;
wire [7:0] timeline_line,timeline_next;
wire [4:0] timeline_sung;
wire [9:0] timeline_red;
reg [5:0] boundary_address=0;
wire [4:0] boundary_current,boundary_next;
integer absolute_time=0,completed_red=0;
wire [4:0] reference_length,reference_next_length;
wire [7:0] unused_char;
integer x,y,scenario,f,b0,b1,b2,preview,font_file,event_file,pixel_file,pixels=0,i,event_count=0;
integer cindex,col,row,gid,cov,glyph_pixels=0,red_pixels=0,white_pixels=0;
integer visible_line,visible_next,visible_sung,active_line,active_sung,text_y,len,left_edge,right_edge;
integer old_line=0,old_next=0,slide_expected=0,credit_row,stage,relative_x,cursor;
always #20 clk=~clk;
osd_alpha_overlay osd(.I_clk(clk),.I_rst(rst),.I_enable(page==1 || page==2),
    .I_vs(vs),.I_de(de),.I_rgb(rgb),.O_rgb(osd_rgb));
audio_visualizer_overlay visual(.I_clk(clk),.I_rst(rst),.I_enable(page==1 || page==2),
    .I_vs(vs),.I_de(de),.I_rgb(osd_rgb),.I_vu_left_level(7'd72),.I_vu_right_level(7'd85),
    .I_spectrum_levels({7'd25,7'd36,7'd55,7'd61,7'd70,7'd86,7'd105,7'd79,
                       7'd61,7'd44,7'd63,7'd85,7'd91,7'd67,7'd47,7'd74}),
    .I_wave_samples({7'sd0,7'sd10,7'sd24,7'sd30,7'sd25,7'sd8,-7'sd15,-7'sd30,
                    -7'sd28,-7'sd12,7'sd7,7'sd25,7'sd18,7'sd3,-7'sd13,-7'sd5}),
    .I_volume_level(4'd8),.I_hazard_front(1'b0),.I_hazard_left(1'b0),
    .I_hazard_right(1'b0),.O_rgb(visual_rgb));
video_home_overlay home(.I_clk(clk),.I_rst(rst),.I_enable((page==0 || page==1) && !transition),
    .I_music_page(page==1),.I_vs(vs),.I_de(de),.I_rgb(visual_rgb),.O_rgb(home_rgb));
video_lyric_overlay #(.LOW_POWER(LOW_POWER)) dut(.I_clk(clk),.I_rst(rst),.I_enable(page==1 && song_ok && !transition),
    .I_card_enable(page==1 && !transition),
    .I_vs(vs),.I_de(de),.I_rgb(home_rgb),.I_line(line),.I_next_line(next_line),
    .I_red_pixels(red_pixels_input),.O_rgb(lyric_rgb));
video_status_overlay status(.I_clk(clk),.I_rst(rst),.I_enable(1'b1),.I_vs(vs),.I_de(de),
    .I_rgb(lyric_rgb),.I_brightness_level(2'd3),.I_contrast_level(2'd0),
    .I_volume_level(4'd8),.O_rgb(status_rgb));
video_status_overlay baseline(.I_clk(clk),.I_rst(rst),.I_enable(1'b1),.I_vs(vs),.I_de(de),
    .I_rgb(home_rgb),.I_brightness_level(2'd3),.I_contrast_level(2'd0),
    .I_volume_level(4'd8),.O_rgb(baseline_rgb));
lyric_font_rom font_check(.I_clk(clk),.I_addr(font_addr),.O_cov(font_cov));
lyric_event_rom event_check(.I_clk(clk),.I_addr(event_addr),.O_event(event_data));
lyric_boundary_map boundary_check(boundary_address,boundary_current,boundary_next);
// A separate source-ROM instance keeps the oracle independent of DUT cache.
lyric_line_rom reference_lines(.I_clk(clk),.I_addr(11'd0),
    .I_line(8'(visible_line)),.I_next_line(8'(visible_next)),.O_char(unused_char),
    .O_length(reference_length),.O_next_length(reference_next_length));
audio_lyric_timeline timeline(.I_audio_clk(clk),.I_video_clk(clk),.I_rst(rst),
    .I_stream_enable(stream_enable),.I_song_matches(1'b1),
    .I_sample_read(sample_read),.O_line_video(timeline_line),
    .O_next_line_video(timeline_next),.O_sung_chars_video(timeline_sung),.O_red_pixels_video(timeline_red));
function [7:0] blend;
    input [7:0] background,foreground;
    input integer coverage;
    begin
        case(coverage)
            1: blend=(background>>1)+(background>>2)+(foreground>>2);
            2: blend=(background>>2)+(foreground>>1)+(foreground>>2)+(foreground&1);
            3: blend=foreground;
            default: blend=background;
        endcase
    end
endfunction
task tick; begin @(posedge clk); #1; end endtask
initial begin
    f=$fopen("best_result/CAR01.BMP","rb");
    if(!f) $fatal(1,"reference background not found");
    i=$fseek(f,54,0);
    for(y=479;y>=0;y=y-1) for(x=0;x<640;x=x+1) begin
        b0=$fgetc(f); b1=$fgetc(f); b2=$fgetc(f);
        image[y*640+x]={8'(b2),8'(b1),8'(b0)};
    end
    $fclose(f);
    repeat(4) tick; @(negedge clk); rst=0;
    font_file=$fopen({OUTPUT_DIR,"/font_cov.hex"},"w");
    for(i=0;i<64372;i=i+1) begin
        @(negedge clk); font_addr=i; tick;
        if(^font_cov===1'bx) $fatal(1,"undefined font address %0d",i);
        reference_font[i]=font_cov;
        $fwrite(font_file,"%h\n",font_cov);
    end
    $fclose(font_file);
    event_file=$fopen({OUTPUT_DIR,"/events.hex"},"w");
    for(i=0;i<512;i=i+1) begin
        @(negedge clk); event_addr=i; repeat(2) tick;
        if(^event_data===1'bx) $fatal(1,"undefined event address %0d",i);
        reference_events[i]=event_data;
        $fwrite(event_file,"%h\n",event_data);
        if(event_data[5:0]!=63) event_count=event_count+1;
    end
    $fclose(event_file);
    if(event_count<43 || event_count>=512) $fatal(1,"invalid karaoke event count %0d",event_count);
    @(negedge clk); stream_enable=1; repeat(40) tick;
    for(i=0;i<event_count;i=i+1) begin
        absolute_time=absolute_time+reference_events[i][29:6];
        @(negedge clk); timeline.sample_count=absolute_time;
        repeat(100) tick;
        if(reference_events[i][5:0]==32) begin
            if(timeline_line!==boundary_current || timeline_next!==boundary_next || timeline_red!==0)
                $fatal(1,"actual boundary %0d failed",boundary_address);
            boundary_address=boundary_address+1;completed_red=0;
        end else begin
            if(reference_events[i][5:0]<=20) completed_red=reference_events[i][5:0]*32;
            if(timeline_red!==completed_red) $fatal(1,"actual smooth event %0d failed",i);
        end
    end
    if(timeline_line!==23 || timeline_next!==24 || timeline_red!==0)
        $fatal(1,"outro must prepare song info, not preview first two lyrics");
    @(negedge clk); timeline.sample_count=24'd10043559; sample_read=1; tick;
    if(timeline.current_line!==23 || timeline.next_line!==24)
        $fatal(1,"exact EOF must remain in song-info mode without blank/verse flash");
    @(negedge clk); sample_read=0; repeat(40) tick;
    if(timeline.sample_count!==0 || timeline_line!==23 || timeline_next!==24 || timeline_red!==0)
        $fatal(1,"actual song EOF did not atomically clear and wrap");

    for(scenario=0;scenario<19;scenario=scenario+1) begin
        page=(scenario<3 || scenario>=6)?1:(scenario==3)?0:(scenario==4)?2:3;
        song_ok=(scenario!=1); transition=(scenario==2);
        line=(scenario==6 || scenario==7)?23:(scenario==8)?24:
             (scenario==9 || scenario==10)?25:
             (scenario==11 || scenario==12 || scenario==18)?1:
             (scenario==13 || scenario==14)?2:(scenario==15)?0:
             (scenario==16 || scenario==17)?23:14;
        next_line=(scenario==6 || scenario==7 || scenario==16 || scenario==17)?24:
                  (scenario==8)?25:(scenario==9 || scenario==10 || scenario==15)?0:
                  (scenario==11 || scenario==12 || scenario==18)?2:
                  (scenario==13 || scenario==14)?3:15;
        red_pixels_input=(scenario==7 || scenario==8)?81:(scenario==9)?97:
                         (scenario==10)?192:
                         (scenario>=6 && scenario<=11 || scenario>=15)?0:
                         (scenario==12)?320:(scenario==13)?17:(scenario==14)?20:177;
        visible_line=line; visible_next=next_line; visible_sung=red_pixels_input;
        if(visible_line!=old_line) begin
            if(visible_line==old_next && visible_line>0 && visible_line<26 && old_line>0 && old_line<26)
                slide_expected=36;
            else slide_expected=0;
        end else if(slide_expected>3)slide_expected=slide_expected-3;else slide_expected=0;
        old_line=visible_line;old_next=visible_next;
        @(negedge clk); vs=1; de=0; tick;
        @(negedge clk); vs=0; repeat(80) tick;
        if(scenario==0 || scenario==7 || scenario==11) begin
            if(scenario==0)preview=$fopen({OUTPUT_DIR,"/preview.ppm"},"w");
            else if(scenario==7)preview=$fopen({OUTPUT_DIR,"/intro.ppm"},"w");
            else preview=$fopen({OUTPUT_DIR,"/interlude.ppm"},"w");
            $fwrite(preview,"P3\n640 480\n255\n");
            if(scenario==0)pixel_file=$fopen({OUTPUT_DIR,"/actual_pixels.hex"},"w");
        end
        for(y=0;y<480;y=y+1) begin
            for(x=0;x<640;x=x+1) begin
                @(negedge clk); de=1; rgb=image[y*640+x];
                // Requests may change during active video, but both rows and
                // all red progress must remain the previous VS snapshot.
                if(scenario==0 && y==100 && x==13) begin
                    line=15; next_line=16; red_pixels_input=1;
                end
                tick;
                expected_rgb=baseline_rgb; cov=0; ink=24'hFFFFFF;
                active_line=0; active_sung=0; text_y=0; len=0;
                if(y>=232+slide_expected && y<256+slide_expected) begin
                    active_line=visible_line; active_sung=visible_sung;
                    text_y=232+slide_expected; len=reference_length;
                end else if(y>=268+slide_expected && y<292+slide_expected) begin
                    active_line=visible_next; active_sung=0;
                    text_y=268+slide_expected; len=reference_next_length;
                end
                if(y>=144 && y<168) begin
                    active_line=26;active_sung=0;text_y=144;len=4;ink=24'h1D3042;
                end
                left_edge=(active_line==26)?248:320-len*16; right_edge=left_edge+len*32;
                if(page==1 && (song_ok || active_line==26) && !transition && len>0 &&
                    x>=left_edge && x<right_edge &&y>=text_y+2&&y<text_y+24&&
                    y<304) begin
                    relative_x=x-left_edge;cindex=relative_x/32;col=relative_x%32-5;row=y-text_y-2;
                    if(col>=0 && col<22) begin
                        gid=reference_lines.rom[active_line*32+cindex];
                        cov=reference_font[gid*484+row*22+col];
                    end
                    if(active_sung>0 && visible_sung>0)begin
                        cursor=visible_sung+4;
                        if(relative_x+2<cursor)ink=24'hFF4040;
                        else if(relative_x+1<cursor)ink=24'hFF7070;
                        else if(relative_x<cursor)ink=24'hFFB8B8;
                    end
                    expected_rgb={blend(expected_rgb[23:16],ink[23:16],cov),
                                  blend(expected_rgb[15:8],ink[15:8],cov),
                                  blend(expected_rgb[7:0],ink[7:0],cov)};
                    if(cov) begin
                        glyph_pixels=glyph_pixels+1;
                        if(ink==24'hFF4040) red_pixels=red_pixels+1;
                        else white_pixels=white_pixels+1;
                    end
                end
                if(status_rgb!==expected_rgb)
                    $fatal(1,"dual lyric pixel scenario=%0d page=%0d x=%0d y=%0d cov=%0d got=%h expected=%h",
                        scenario,page,x,y,cov,status_rgb,expected_rgb);
                if(scenario==0 ||scenario==7 ||scenario==11) begin
                    $fwrite(preview,"%0d %0d %0d\n",status_rgb[23:16],status_rgb[15:8],status_rgb[7:0]);
                    if(scenario==0&&y>=232 && y<304) $fwrite(pixel_file,"%h\n",status_rgb);
                end
                if(y>=424 && y<452 && status_rgb!==baseline_rgb)
                    $fatal(1,"existing scrolling subtitle was changed");
                pixels=pixels+1;
            end
            @(negedge clk); de=0; repeat((scenario%3)+1) tick;
            if(status_rgb!==rgb) $fatal(1,"blanking changed");
        end
        if(scenario==0 ||scenario==7 ||scenario==11) $fclose(preview);
        if(scenario==0)$fclose(pixel_file);
    end
    if(red_pixels==0 || white_pixels==0) $fatal(1,"missing red/white glyph pixels");
    $display("PASS actual smooth lyrics: 64372 font pixels, 512 delta entries, %0d events, exact EOF, %0d composed pixels; 24px, compact credits, shared music card, interlude preview, feathered sweep, line-slide, VS atomic, scroll unchanged",event_count,pixels);
    $finish;
end
initial begin #300000000; $fatal(1,"actual smooth lyrics timeout"); end
endmodule
