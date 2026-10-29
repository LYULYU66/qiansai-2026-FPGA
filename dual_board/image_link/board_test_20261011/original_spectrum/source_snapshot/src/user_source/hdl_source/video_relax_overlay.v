// Music-responsive fireflies for picture 3. Sixteen lights share eight moving
// anchors; the secondary light uses the same scan-line glow datapath.
// Eight anchors share the same
// update and glow datapaths; point state and scan-line cache use tiny LUT RAMs.
// No multiplier, DSP, BRAM, source-image ROM, or RGB/timing latency is added.
// Particle positions are Q4; the glow is evaluated at quarter-pixel precision.
// Horizontal blanking prepares all eight line entries (VGA provides 160 clocks).
module video_relax_overlay #(parameter LOW_POWER=0)(
    input wire I_clk, I_rst, I_enable, I_vs, I_de,
    input wire [23:0] I_rgb,
    input wire I_audio_active,
    input wire [6:0] I_vu_left, I_vu_right,
    input wire [111:0] I_spectrum_levels,
    output wire [23:0] O_rgb
);
localparam TARGET=0, POSITION=1, STORE=2;
reg [50:0] points [0:7];
reg [22:0] line_cache [0:7];
reg init_busy, initialized, update_busy, row_busy, row_ready;
reg [2:0] init_index, update_index, row_index;
reg [1:0] update_state;
reg [55:0] band_snapshot;
reg [6:0] vu_frame;
reg [7:0] next_phase;
reg [10:0] next_energy, next_point_x;
reg [12:0] next_point_y;
reg [7:0] next_amplitude;
reg vs_d, de_d, active_seen;
reg [9:0] pixel_x;
reg [8:0] pixel_y, row_y;
reg [6:0] tile_x;
reg [2:0] tile_index;
wire frame_start=I_vs && !vs_d;
wire line_start=I_de && !de_d;
wire line_end=!I_de && de_d;
wire work_enable=!LOW_POWER || I_enable;

function [6:0] base_x;
    input [2:0] n;
    begin case(n)
        0:base_x=34; 1:base_x=42; 2:base_x=38; 3:base_x=51;
        4:base_x=31; 5:base_x=49; 6:base_x=40; default:base_x=24;
    endcase end
endfunction
function [8:0] base_y;
    input [2:0] n;
    begin case(n)
        0:base_y=130; 1:base_y=235; 2:base_y=166; 3:base_y=90;
        4:base_y=277; 5:base_y=202; 6:base_y=145; default:base_y=250;
    endcase end
endfunction
function [7:0] seed_phase;
    input [2:0] n;
    begin case(n)
        0:seed_phase=16; 1:seed_phase=107; 2:seed_phase=50; 3:seed_phase=185;
        4:seed_phase=224; 5:seed_phase=141; 6:seed_phase=84; default:seed_phase=12;
    endcase end
endfunction
function [6:0] triangle;
    input [7:0] p;
    begin triangle=p[7] ? ~p[6:0] : p[6:0]; end
endfunction

// Bits: amplitude[50:43], phase[42:35], y Q4[34:22], x Q4[21:11],
// energy Q4[10:0]. One asynchronous state-read port is shared by both engines.
wire [2:0] point_addr=update_busy ? update_index : row_index;
wire [50:0] point_q=points[point_addr];
wire [6:0] raw_target=(band_snapshot[6:0]>(vu_frame>>1)) ?
                          band_snapshot[6:0] : (vu_frame>>1);
wire [6:0] limited_target=raw_target>7'd96 ? 7'd96 : raw_target;
wire signed [11:0] energy_delta=$signed({1'b0,limited_target,4'd0})-
                               $signed({1'b0,point_q[10:0]});
wire signed [11:0] energy_step=energy_delta>=0 ?
                              (energy_delta >>> 2) : (energy_delta >>> 4);
wire signed [11:0] eased_energy=$signed({1'b0,point_q[10:0]})+energy_step;
wire [6:0] orbit_x=triangle(next_phase);
wire [6:0] orbit_y=triangle(next_phase+8'd96);
wire signed [12:0] target_x=$signed({2'b00,base_x(update_index),4'd0})+
                            $signed({4'd0,orbit_x,2'b0})-13'sd256;
wire signed [13:0] target_y=$signed({1'b0,base_y(update_index),4'd0})+
                            $signed({4'd0,orbit_y,3'b0})-14'sd512-
                            $signed({6'd0,next_energy[10:4],1'b0});
wire signed [12:0] x_delta=target_x-$signed({2'b00,point_q[21:11]});
wire signed [13:0] y_delta=target_y-$signed({1'b0,point_q[34:22]});
wire signed [12:0] eased_x=$signed({2'b00,point_q[21:11]})+(x_delta >>> 3);
wire signed [13:0] eased_y=$signed({1'b0,point_q[34:22]})+(y_delta >>> 3);
wire [8:0] amplitude_sum=9'd20+{4'd0,orbit_x[6:2]}+
                         {1'b0,next_energy[10:4],1'b0};
wire dominant=(update_index==0 || update_index==2 || update_index==5);

wire signed [11:0] row_delta=$signed({1'b0,row_y,2'd0})-
                             $signed({1'b0,point_q[34:24]});
wire [11:0] row_abs=row_delta[11] ? -row_delta : row_delta;
// A second, dimmer star is 112 pixels below the anchor, with mirrored local X.
// Their halos never overlap in a row: choose the nearer one during blanking,
// retaining just one cache entry and one renderer per 80-pixel tile.
wire signed [11:0] second_delta=row_delta-12'sd448;
wire [11:0] second_abs=second_delta[11] ? -second_delta : second_delta;
wire second_nearer=second_abs<row_abs;
wire [11:0] nearest_abs=second_nearer ? second_abs : row_abs;
wire [5:0] row_distance=(|nearest_abs[11:6]) ? 6'd63 : nearest_abs[5:0];
wire [8:0] row_point_x=second_nearer ? 9'd316-point_q[21:13] : point_q[21:13];
wire [7:0] row_amplitude=second_nearer ?
    point_q[50:43]-(point_q[50:43]>>2) : point_q[50:43];
wire point_store=work_enable && !I_rst && !I_de && !frame_start &&
                 (init_busy || (update_busy && update_state==STORE));
wire [2:0] write_index=init_busy ? init_index : update_index;
wire [50:0] initial_point={8'd18,seed_phase(init_index),base_y(init_index),4'd0,
                           base_x(init_index),4'd0,11'd0};
always @(posedge I_clk) begin
    if(point_store)
        points[write_index]<=init_busy ? initial_point :
            {next_amplitude,next_phase,next_point_y,next_point_x,next_energy};
    if(work_enable && !I_rst && !I_de && !frame_start && !init_busy && !update_busy && row_busy)
        line_cache[row_index]<={row_point_x,row_distance,row_amplitude};
end

always @(posedge I_clk or posedge I_rst) begin
    if(I_rst) begin
        init_busy<=1; initialized<=0; init_index<=0;
        update_busy<=0; update_index<=0; update_state<=TARGET;
        row_busy<=0; row_ready<=0; row_index<=0; row_y<=0;
        band_snapshot<=0; vu_frame<=0;
        next_phase<=0; next_energy<=0; next_point_x<=0; next_point_y<=0; next_amplitude<=0;
        vs_d<=0; de_d<=0; active_seen<=0;
        pixel_x<=0; pixel_y<=0; tile_x<=0; tile_index<=0;
    end else begin
        vs_d<=I_vs; de_d<=I_de;
        if(frame_start) begin
            pixel_x<=0; pixel_y<=0; tile_x<=0; tile_index<=0; active_seen<=0;
            row_ready<=0; row_busy<=0; row_y<=0; row_index<=0;
            if(initialized && work_enable) begin
                update_busy<=1; update_index<=0; update_state<=TARGET;
                vu_frame<=I_audio_active ?
                    (I_vu_left>I_vu_right ? I_vu_left : I_vu_right) : 7'd0;
                // Eight fixed lanes avoid a large per-point 16:1 band selector.
                band_snapshot<=I_audio_active ?
                    {I_spectrum_levels[104:98],I_spectrum_levels[90:84],
                     I_spectrum_levels[76:70],I_spectrum_levels[62:56],
                     I_spectrum_levels[48:42],I_spectrum_levels[34:28],
                     I_spectrum_levels[20:14],I_spectrum_levels[6:0]} : 56'd0;
            end
        end else begin
            if(I_de) begin
                if(line_start) begin
                    pixel_x<=0; tile_x<=0; tile_index<=0;
                    if(!active_seen) begin pixel_y<=0; active_seen<=1; end
                    else if(pixel_y<479) pixel_y<=pixel_y+1'b1;
                end else if(pixel_x<639) begin
                    pixel_x<=pixel_x+1'b1;
                    if(tile_x==79) begin tile_x<=0; tile_index<=tile_index+1'b1; end
                    else tile_x<=tile_x+1'b1;
                end
            end else begin pixel_x<=0; tile_x<=0; tile_index<=0; end

            // RAMs have no reset network. Eight initialization writes establish
            // validity; later state changes happen only in vertical blanking.
            if(work_enable && !I_de && init_busy) begin
                if(init_index==7) begin
                    init_busy<=0; initialized<=1;
                    row_busy<=1; row_index<=0; row_y<=0;
                end else init_index<=init_index+1'b1;
            end else if(work_enable && !I_de && update_busy) begin
                case(update_state)
                    TARGET: begin
                        next_phase<=point_q[42:35]+(vu_frame>=48 ? 8'd2 : 8'd1);
                        next_energy<=eased_energy[10:0]; update_state<=POSITION;
                    end
                    POSITION: begin
                        next_point_x<=eased_x[10:0]; next_point_y<=eased_y[12:0];
                        next_amplitude<=dominant ? amplitude_sum[7:0] : amplitude_sum[8:1];
                        update_state<=STORE;
                    end
                    STORE: begin
                        band_snapshot<={7'd0,band_snapshot[55:7]};
                        if(update_index==7) begin
                            update_busy<=0; row_busy<=1; row_index<=0; row_y<=0;
                        end else begin update_index<=update_index+1'b1; update_state<=TARGET; end
                    end
                    default:update_state<=TARGET;
                endcase
            end else if(work_enable && !I_de && row_busy) begin
                if(row_index==7) begin row_ready<=1; row_busy<=0; end
                else row_index<=row_index+1'b1;
            end
            if(line_end && work_enable) begin
                row_ready<=0; row_busy<=1; row_index<=0;
                row_y<=(!active_seen || pixel_y==479) ? 9'd0 : pixel_y+1'b1;
            end
            // Cancel an unfinished hidden-page row/position pass. Point
            // state remains intact; the next frame rebuilds all row entries.
            if(!work_enable) begin update_busy<=0;row_busy<=0;row_ready<=0;end
        end
    end
end

// Look ahead exactly one raster position, as the existing synchronous font
// overlays do. The registered light and the coordinate counters then describe
// the same pixel. RGB/VS/DE pass through without an additional pipeline stage.
reg [6:0] render_x;
reg [2:0] render_index;
always @(*) begin
    render_x=tile_x; render_index=tile_index;
    if(frame_start || !I_de || line_start) begin render_x=0; render_index=0; end
    else if(pixel_x<639) begin
        if(tile_x==79) begin render_x=0; render_index=tile_index+1'b1; end
        else render_x=tile_x+1'b1;
    end
end
wire [22:0] render_point=line_cache[render_index];
wire signed [9:0] dx=$signed({1'b0,render_x,2'd0})-
                     $signed({1'b0,render_point[22:14]});
wire [9:0] dx_abs=dx[9] ? -dx : dx;
wire [5:0] dy_abs=render_point[13:8];
wire [5:0] dmax=dx_abs[5:0]>dy_abs ? dx_abs[5:0] : dy_abs;
wire [5:0] dmin=dx_abs[5:0]>dy_abs ? dy_abs : dx_abs[5:0];
wire [6:0] radius={1'b0,dmax}+{2'b00,dmin[5:1]};
wire in_halo=!(|dx_abs[9:6]) && radius<32;
// Two nested smooth cones approximate a Gaussian glow with only shifts and
// subtracts. Additive, saturating warm light preserves the photograph outside
// the small halo. Fractional centers prevent whole-pixel position snapping.
wire [8:0] core_cost={radius[4:0],4'd0};
wire [7:0] halo_cost={radius[4:0],3'd0};
wire [7:0] core_light=({1'b0,render_point[7:0]}>core_cost) ?
                       render_point[7:0]-core_cost[7:0] : 8'd0;
wire [7:0] halo_light=(render_point[7:0]>halo_cost) ?
                       ((render_point[7:0]-halo_cost)>>2) : 8'd0;
wire [8:0] total_light={1'b0,core_light}+{1'b0,halo_light};
reg [7:0] light;
reg warm_core;
always @(posedge I_clk or posedge I_rst) begin
    if(I_rst) begin light<=0; warm_core<=0; end
    else if(!LOW_POWER || (work_enable && I_de)) begin
        light<=in_halo ? (total_light[8] ? 8'd255 : total_light[7:0]) : 8'd0;
        warm_core<=radius<=2;
    end
end
wire [7:0] green_light=light-(light>>3);
wire [7:0] blue_light=warm_core ? (light>>1) : (light>>3);
wire [8:0] r_sum={1'b0,I_rgb[23:16]}+{1'b0,light};
wire [8:0] g_sum={1'b0,I_rgb[15:8]}+{1'b0,green_light};
wire [8:0] b_sum={1'b0,I_rgb[7:0]}+{1'b0,blue_light};
assign O_rgb=(I_enable && I_de && initialized && row_ready) ?
    {r_sum[8] ? 8'hFF : r_sum[7:0],g_sum[8] ? 8'hFF : g_sum[7:0],
     b_sum[8] ? 8'hFF : b_sum[7:0]} : I_rgb;
endmodule

// Production page gating is tested independently of the HDMI/SDRAM PHY.
// Pages 1/2/4 keep their previous rules; page 3 bypasses every playback overlay
// before the common top-left status and final safety layer are drawn.
module video_playback_overlay_select (
    input wire I_valid, I_transition_active, I_pcm_available,
    input wire [1:0] I_picture_idx,
    input wire [23:0] I_regular_rgb, I_relax_rgb,
    output wire O_home, O_music, O_warning_selected, O_warning_draw,
    output wire O_relax_selected, O_relax_draw, O_osd, O_visualizer,
    output wire [23:0] O_rgb
);
assign O_home=I_valid && I_picture_idx==0 && !I_transition_active;
assign O_music=I_valid && I_picture_idx==1 && !I_transition_active;
assign O_warning_selected=I_valid && I_picture_idx==3;
assign O_warning_draw=O_warning_selected && !I_transition_active;
assign O_relax_selected=I_valid && I_picture_idx==2;
assign O_relax_draw=O_relax_selected && !I_transition_active;
assign O_osd=I_valid && !O_home && !O_warning_selected && !O_relax_selected;
assign O_visualizer=O_osd && I_pcm_available;
assign O_rgb=O_relax_selected ? I_relax_rgb : I_regular_rgb;
endmodule
