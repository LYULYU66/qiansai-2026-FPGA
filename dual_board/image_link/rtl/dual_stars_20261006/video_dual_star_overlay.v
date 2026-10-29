`timescale 1ns/1ps
// B is the animation time master. Q4 coordinates: 1/16 pixel per tick.
// The shared phase always moves in one direction, while its velocity ramps
// smoothly up and down. A receives this same phase in CTL3, so both screens
// show the same star field crossing the 1280-pixel canvas boundary.
// Never reset this clock on song/PCM/link-session changes or page selection.
module dual_star_motion_clock #(parameter integer TICK_CYCLES=976563)(
    input wire clk,rst,
    output reg [15:0] phase_q4
);
localparam COUNT_BITS=TICK_CYCLES>1 ? $clog2(TICK_CYCLES) : 1;
reg [COUNT_BITS-1:0] divider;
reg [6:0] speed_q4;
reg [3:0] fractional_step,ramp_div;
reg slowing;
wire tick=divider==TICK_CYCLES-1;
wire [7:0] distance_sum={1'b0,speed_q4}+{4'd0,fractional_step};
wire [3:0] step_q4=distance_sum[7:4];
wire [16:0] forward_position={1'b0,phase_q4}+{13'd0,step_q4};
always @(posedge clk or posedge rst) begin
    if(rst)begin
        divider<=0;phase_q4<=0;speed_q4<=0;
        fractional_step<=0;ramp_div<=0;slowing<=0;
    end else if(tick)begin
        divider<=0;
        fractional_step<=distance_sum[3:0];
        phase_q4<=forward_position>=17'd20480 ?
                  forward_position-17'd20480 : forward_position[15:0];
        // Change velocity every 12 ticks (~94 ms): slow -> fast -> slow.
        // There is no direction reversal, so the two displays remain visually
        // coherent while the star stream breathes in speed.
        if(ramp_div==4'd11)begin
            ramp_div<=0;
            if(!slowing)begin
                speed_q4<=speed_q4+1'b1;
                if(speed_q4==7'd63) slowing<=1;
            end else begin
                speed_q4<=speed_q4-1'b1;
                if(speed_q4==7'd1) slowing<=0;
            end
        end else ramp_div<=ramp_div+1'b1;
    end else divider<=divider+1'b1;
end
endmodule

// Shared 1280x480 star canvas. A views x0..639, B views x640..1279.
// Three stars in each of ten 128-pixel lanes, all translating to the RIGHT.
// The lane cache stores a large/medium/small size per star. Soft additive Q2
// halos and gentle twinkle keep the field attractive without audio,
// multiplier, DSP, BRAM, image ROM or added RGB/DE/VS pipeline latency.
module video_dual_star_overlay #(parameter integer VIEW_X=0)(
    input wire I_clk,I_rst,I_enable,I_vs,I_de,
    input wire [23:0] I_rgb,
    input wire [15:0] I_phase_q4,
    output wire [23:0] O_rgb
);
reg [9:0] x,nx;
reg [8:0] y,ny;
reg de_d,vs_d,seen,nseen;
reg [14:0] frame_phase;
reg [24:0] line_cache [0:9];
reg row_busy,row_ready;
reg [3:0] row_index;
reg [8:0] row_y;
wire frame_start=I_vs&&!vs_d;
wire line_end=!I_de&&de_d;
always @* begin
    nx=x;ny=y;nseen=seen;
    if(frame_start)begin nx=0;ny=0;nseen=0;end
    else if(I_de)begin
        if(!de_d)begin nx=0;
            if(!seen)begin ny=0;nseen=1;end
            else if(y<479)ny=y+1'b1;
        end else if(x<639)nx=x+1'b1;
    end else nx=0;
end
function [8:0] base_y;
    input [3:0] n;
    begin case(n)
        0:base_y=95;1:base_y=172;2:base_y=78;3:base_y=206;4:base_y=134;
        5:base_y=66;6:base_y=188;7:base_y=120;8:base_y=164;default:base_y=88;
    endcase end
endfunction
function [6:0] base_x;
    input [3:0] n;
    begin case(n)
        0:base_x=29;1:base_x=39;2:base_x=26;3:base_x=33;4:base_x=42;
        5:base_x=25;6:base_x=36;7:base_x=30;8:base_x=40;default:base_x=34;
    endcase end
endfunction
function [7:0] seed_phase;
    input [3:0] n;
    begin case(n)
        0:seed_phase=16;1:seed_phase=107;2:seed_phase=50;3:seed_phase=185;4:seed_phase=224;
        5:seed_phase=141;6:seed_phase=84;7:seed_phase=12;8:seed_phase=172;default:seed_phase=61;
    endcase end
endfunction
wire signed [9:0] d0=$signed({1'b0,row_y})-$signed({1'b0,base_y(row_index)});
wire signed [9:0] d1=d0-10'sd112;
wire signed [9:0] d2=d0-10'sd224;
wire [9:0] a0=d0[9] ? -d0 : d0;
wire [9:0] a1=d1[9] ? -d1 : d1;
wire [9:0] a2=d2[9] ? -d2 : d2;
wire [1:0] nearest=(a0<=a1 && a0<=a2) ? 2'd0 : (a1<=a2 ? 2'd1 : 2'd2);
wire [9:0] nearest_y=nearest==0 ? a0 : (nearest==1 ? a1 : a2);
wire [5:0] row_distance=(|nearest_y[9:6]) ? 6'd63 : nearest_y[5:0];
function [1:0] star_size;
    input [3:0] lane;input [1:0] point;
    begin case(lane)
        0,3,6,9:star_size=point==0?2'd2:(point==1?2'd0:2'd1);
        1,4,7:star_size=point==0?2'd1:(point==1?2'd2:2'd0);
        default:star_size=point;
    endcase end
endfunction
wire [1:0] size=star_size(row_index,nearest);
wire [6:0] point_x=nearest==0 ? base_x(row_index) :
                       (nearest==1 ? 7'd120-base_x(row_index) : base_x(row_index)+7'd25);
wire [7:0] pulse=frame_phase[10:3]+seed_phase(row_index)+{nearest,6'd0};
wire [6:0] triangle=pulse[7] ? ~pulse[6:0] : pulse[6:0];
wire hot_lane=row_index==0||row_index==3||row_index==6||row_index==9;
wire [7:0] amplitude=(size==2 ? 8'd152 : (size==1 ? 8'd112 : 8'd80))+
                     {2'd0,triangle[6:1]}+(hot_lane ? 8'd24 : 8'd0);
// No reset network on the small RAM. row_ready is the validity barrier.
always @(posedge I_clk)begin
    if(!I_rst && I_enable && !I_de && !frame_start && row_busy)
        line_cache[row_index]<={{point_x,2'd0},row_distance,amplitude,size};
end
always @(posedge I_clk or posedge I_rst)begin
    if(I_rst)begin
        x<=0;y<=0;de_d<=0;vs_d<=0;seen<=0;frame_phase<=0;
        row_busy<=0;row_ready<=0;row_index<=0;row_y<=0;
    end else begin
        x<=nx;y<=ny;seen<=nseen;de_d<=I_de;vs_d<=I_vs;
        if(frame_start)begin
            frame_phase<=I_phase_q4<20480 ? I_phase_q4[14:0] : 15'd0;
            row_busy<=I_enable;row_ready<=0;row_index<=0;row_y<=0;
        end else if(I_enable)begin
            if(!I_de && row_busy)begin
                if(row_index==9)begin row_busy<=0;row_ready<=1;end
                else row_index<=row_index+1'b1;
            end
            if(line_end)begin
                row_busy<=1;row_ready<=0;row_index<=0;
                row_y<=(!seen || y==479) ? 9'd0 : y+1'b1;
            end
        end else begin row_busy<=0;row_ready<=0;end
    end
end
// Inverse translation gives the star-space coordinate for this viewport.
// Inputs come from a REGISTERED RGB/DE producer. Compute the next coordinate
// before the edge: the light register then matches the producer's new pixel.
// During blanking precompute x=0 from the next row's already prepared cache,
// including the first valid pixel (which cannot be predicted from I_de alone).
// World width is exactly 1280 pixels; one conditional add replaces division.
localparam [14:0] VIEW_Q4=VIEW_X*16;
wire [9:0] look_x=I_de && nx<639 ? nx+1'b1 : 10'd0;
wire [14:0] world_x={1'b0,look_x,4'd0}+VIEW_Q4;
wire signed [15:0] shifted=$signed({1'b0,world_x})-$signed({1'b0,frame_phase});
wire [14:0] star_x=shifted[15] ? shifted+16'd20480 : shifted[14:0];
wire [3:0] render_index=star_x[14:11];
wire [24:0] entry=line_cache[render_index];
wire signed [9:0] dx=$signed({1'b0,star_x[10:2]})-$signed({1'b0,entry[24:16]});
wire [9:0] dx_abs=dx[9] ? -dx : dx;
// Power-of-two scaling gives the three star sizes without a multiplier.
wire [1:0] scale=entry[1:0];
wire [9:0] dx_scaled=scale==2 ? {2'd0,dx_abs[9:2]} :
                           (scale==1 ? {1'b0,dx_abs[9:1]} : dx_abs);
wire [7:0] dy_scaled=scale==2 ? {2'd0,entry[15:10]} :
                           (scale==1 ? {1'b0,entry[15:10],1'b0} :
                                       {entry[15:10],2'd0});
wire [5:0] dy_abs=dy_scaled[5:0];
wire [5:0] dmax=dx_scaled[5:0]>dy_abs ? dx_scaled[5:0] : dy_abs;
wire [5:0] dmin=dx_scaled[5:0]>dy_abs ? dy_abs : dx_scaled[5:0];
wire [6:0] radius={1'b0,dmax}+{2'b00,dmin[5:1]};
wire halo=!(|dx_scaled[9:6]) && !(|dy_scaled[7:6]) && radius<32;
wire [8:0] core_cost={radius[4:0],4'd0};
wire [7:0] halo_cost={radius[4:0],3'd0};
wire [7:0] strength=entry[9:2];
wire [7:0] core_light=({1'b0,strength}>core_cost) ? strength-core_cost[7:0] : 8'd0;
wire [7:0] halo_light=strength>halo_cost ? ((strength-halo_cost)>>2) : 8'd0;
wire [8:0] total={1'b0,core_light}+{1'b0,halo_light};
reg [7:0] light;
reg warm_core;
always @(posedge I_clk or posedge I_rst)begin
    if(I_rst)begin light<=0;warm_core<=0;end
    else if(I_enable && row_ready)begin
        light<=halo ? (total[8] ? 8'd255 : total[7:0]) : 8'd0;
        warm_core<=radius<=3;
    end else begin light<=0;warm_core<=0;end
end
wire [7:0] green=light-(light>>4);
wire [7:0] blue=warm_core ? light : light>>2;
wire [8:0] r={1'b0,I_rgb[23:16]}+{1'b0,light};
wire [8:0] g={1'b0,I_rgb[15:8]}+{1'b0,green};
wire [8:0] b={1'b0,I_rgb[7:0]}+{1'b0,blue};
assign O_rgb=I_enable && I_de && row_ready ?
    {r[8] ? 8'hff : r[7:0],g[8] ? 8'hff : g[7:0],b[8] ? 8'hff : b[7:0]} : I_rgb;
endmodule
