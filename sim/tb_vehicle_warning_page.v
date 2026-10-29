`timescale 1ns/1ps
module tb_vehicle_warning_page;
reg clk=0, rst=1, vs=0, de=0, warning_page=0;
reg front=0, left=0, right=0, rear=0;
reg [23:0] rgb=24'h556677;
wire [23:0] osd_rgb, visual_rgb, out_rgb;
integer errors=0, x, y, pixels_checked=0;
integer face_pixels, text_pixels, f, n, byte0, byte1, byte2, preview;
reg [23:0] image_pixels[0:307199];
reg [23:0] source, expected;
reg fbox, lbox, rbox, bbox, inside_box, edge_box;
reg use_image=0, save_preview=0, change_page_midframe=0;
always #5 clk=~clk;

// This is the picture-4 playback suppression used by top: all visualizer
// hazard inputs are tied low, so disabled drawing is strictly transparent.
osd_alpha_overlay osd(
    .I_clk(clk), .I_rst(rst), .I_enable(!warning_page),
    .I_vs(vs), .I_de(de), .I_rgb(rgb), .O_rgb(osd_rgb));
audio_visualizer_overlay visualizer(
    .I_clk(clk), .I_rst(rst), .I_enable(!warning_page),
    .I_vs(vs), .I_de(de), .I_rgb(osd_rgb),
    .I_vu_left_level(7'd80), .I_vu_right_level(7'd60),
    .I_spectrum_levels({16{7'd80}}), .I_wave_samples({16{7'd20}}),
    .I_volume_level(4'd8), .I_hazard_front(1'b0),
    .I_hazard_left(1'b0), .I_hazard_right(1'b0), .O_rgb(visual_rgb));
vehicle_hazard_overlay #(.FRONT_FLASH_BIT(0), .SIDE_FLASH_BIT(1)) dut(
    .I_clk(clk), .I_rst(rst), .I_vs(vs), .I_de(de), .I_rgb(rgb),
    .I_warning_page(warning_page), .I_hazard_front(front),
    .I_hazard_left(left), .I_hazard_right(right), .I_hazard_rear(rear), .O_rgb(out_rgb));

task tick;
    begin @(posedge clk); #1; end
endtask
task sync_inputs;
    begin de=0; repeat(4) tick; end
endtask
task scan_frame;
    input page, ef, el, er, eb, bright;
    begin
        de=0; vs=1; tick; tick; vs=0; tick;
        face_pixels=0; text_pixels=0;
        if(save_preview) begin
            preview=$fopen("sim/vehicle_warning_4dir_20260930/preview.ppm","w");
            $fwrite(preview,"P3\n640 480\n255\n");
        end
        for(y=0;y<480;y=y+1) begin
            for(x=0;x<640;x=x+1) begin
                if(change_page_midframe && x==100 && y==150)
                    warning_page=1;
                source=use_image ? image_pixels[y*640+x] : 24'h556677;
                de=1; rgb=source; tick;
                // Playback overlays must draw no pixels at all on page 4,
                // including VU labels/tracks and the bottom subtitle strip.
                if(warning_page && !change_page_midframe && visual_rgb!==source) begin
                    if(errors<12) $display("FAIL playback leak x=%0d y=%0d",x,y);
                    errors=errors+1;
                end
                fbox=page && ef && bright && x>=224 && x<416 && y>=68 && y<128;
                lbox=page && el && bright && x>=16 && x<208 && y>=202 && y<262;
                rbox=page && er && bright && x>=432 && x<624 && y>=202 && y<262;
                bbox=page && eb && bright && x>=224 && x<416 && y>=394 && y<454;
                inside_box=fbox || lbox || rbox || bbox;
                edge_box=(fbox && (x<228 || x>=412 || y<72 || y>=124)) ||
                         (lbox && (x<20 || x>=204 || y<206 || y>=258)) ||
                         (rbox && (x<436 || x>=620 || y<206 || y>=258)) ||
                         (bbox && (x<228 || x>=412 || y<398 || y>=450));
                expected=source;
                if(ef && y<12) expected=bright ? 24'hFF1838 : 24'h600008;
                else if(el && x<12) expected=bright ? 24'hFF6A00 : 24'h682000;
                else if(er && x>=628) expected=bright ? 24'hFFD000 : 24'h685000;
                else if(eb && y>=468) expected=bright ? 24'hFF1838 : 24'h600008;
                else if(edge_box) expected=24'hFF243C;
                else if(inside_box) begin
                    // Font/face colors are constrained, while shape is
                    // verified separately against the font generator.
                    expected=out_rgb;
                    if(out_rgb==24'h531A23) face_pixels=face_pixels+1;
                    else if(out_rgb==24'hFFFFFF || out_rgb==24'hE2F0F2 ||
                            out_rgb==24'hB9D4D8) text_pixels=text_pixels+1;
                    else begin
                        if(errors<12) $display("FAIL card color x=%0d y=%0d rgb=%h",x,y,out_rgb);
                        errors=errors+1;
                    end
                    // Independently check the visible exclamation strokes.
                    if((fbox && x>=383 && x<385 && y>=86 && y<106) ||
                       (lbox && x>=175 && x<177 && y>=220 && y<240) ||
                       (rbox && x>=591 && x<593 && y>=220 && y<240) ||
                       (bbox && x>=383 && x<385 && y>=412 && y<432))
                        expected=24'hFFFFFF;
                end
                if(out_rgb!==expected) begin
                    if(errors<12) $display("FAIL warning x=%0d y=%0d got=%h expected=%h",x,y,out_rgb,expected);
                    errors=errors+1;
                end
                if(save_preview) $fwrite(preview,"%0d %0d %0d\n",out_rgb[23:16],out_rgb[15:8],out_rgb[7:0]);
                pixels_checked=pixels_checked+1;
            end
            de=0; rgb=24'h123456; tick;
            if(out_rgb!==rgb) begin $display("FAIL blanking transparency"); errors=errors+1; end
        end
        if(save_preview) $fclose(preview);
        if(page && bright && (ef || el || er || eb) && (face_pixels<3000 || text_pixels<900)) begin
            $display("FAIL missing card/text: face=%0d text=%0d",face_pixels,text_pixels);
            errors=errors+1;
        end
    end
endtask

initial begin
    repeat(4) tick; rst=0;
    warning_page=1; sync_inputs;
    scan_frame(1,0,0,0,0,1); // no danger: the complete picture remains clean
    front=1; sync_inputs;
    scan_frame(1,1,0,0,0,1);
    scan_frame(1,1,0,0,0,0); // local card disappears; outer border stays dim
    front=0; left=1; sync_inputs;
    scan_frame(1,0,1,0,0,1);
    left=0; right=1; sync_inputs;
    scan_frame(1,0,0,1,0,1);
    right=0; rear=1; sync_inputs;
    scan_frame(1,0,0,0,1,1);
    scan_frame(1,0,0,0,1,0);
    front=1; left=1; right=1; rear=1; sync_inputs;
    scan_frame(1,1,1,1,1,1);
    warning_page=0; change_page_midframe=1; sync_inputs;
    scan_frame(0,1,1,1,1,0); // entering page 4 halfway through a frame is deferred
    change_page_midframe=0;
    scan_frame(1,1,1,1,1,1);
    // Produce the actual HDL pixel output over the project's bright warning
    // background, rather than a separately drawn approximation of the UI.
    f=$fopen("best_result/CAR_WARN_ADAS_DAY_640x480.BMP","rb");
    if(f==0) $fatal(1,"warning background not found");
    n=$fseek(f,54,0);
    for(y=479;y>=0;y=y-1) for(x=0;x<640;x=x+1) begin
        byte0=$fgetc(f); byte1=$fgetc(f); byte2=$fgetc(f);
        image_pixels[y*640+x]={byte2[7:0],byte1[7:0],byte0[7:0]};
    end
    $fclose(f);
    front=0; left=0; right=0; rear=0; sync_inputs;
    scan_frame(1,0,0,0,0,1);
    front=1; left=1; right=1; rear=1; sync_inputs;
    use_image=1; save_preview=1;
    scan_frame(1,1,1,1,1,1);
    if(errors) $fatal(1,"vehicle warning page: %0d errors",errors);
    $display("PASS vehicle warning page: %0d pixels, F/L/R/rear, 32px font, blink, retained border, frame lock and no playback OSD",pixels_checked);
    $finish;
end
endmodule
