`timescale 1ns/1ps
// B owns a 128 Hz animation timestamp. Keep the CTL3 16-bit field and reset
// domain unchanged; the field now encodes time, not horizontal translation.
// 16384 ticks form one seamless 128-second orbit/breathing super-period.
module dual_star_motion_clock #(parameter integer TICK_CYCLES=976563)(
    input wire clk,rst,
    output reg [15:0] phase_q4
);
localparam COUNT_BITS=TICK_CYCLES>1 ? $clog2(TICK_CYCLES) : 1;
reg [COUNT_BITS-1:0] divider;
always @(posedge clk or posedge rst) begin
    if(rst)begin divider<=0;phase_q4<=0;end
    else if(divider==TICK_CYCLES-1)begin
        divider<=0;
        phase_q4<=phase_q4==16383 ? 16'd0 : phase_q4+1'b1;
    end else divider<=divider+1'b1;
end
endmodule

// Reference-video fireflies: four main lights, six medium and twenty tiny
// lights on one 1280x480 canvas. Independent eased X/Y drift and breathing.
// All geometry is time-derived, so packet loss holds a complete A snapshot
// and reconnection needs no particle-state replay. No audio dependency.
// Thirty blanking clocks reuse one particle evaluator to fill 10x27 bits of
// distributed row RAM. No BRAM, multiplier/divider or added RGB/DE latency.
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
reg [11:0] pan_q4;
reg [26:0] line_cache [0:9];
reg row_busy,row_ready;
reg [3:0] row_index;
reg [1:0] row_point;
reg [8:0] row_y;
reg [10:0] best_distance;
reg [26:0] best_entry;
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
// Four linear segments approximate an eased sine. Low-end slopes are small,
// middle slopes are 3x larger; no ROM, squaring or DSP is required.
function [9:0] eased;
    input [11:0] phase;
    reg [10:0] t,triple;
    begin
        t=phase[11] ? ~phase[10:0] : phase[10:0];
        triple={2'd0,t[8:0]}+{1'b0,t[8:0],1'b0};
        case(t[10:9])
          0:eased={3'd0,t[8:2]};
          1:eased=10'd128+{1'b0,triple[10:2]};
          2:eased=10'd512+{1'b0,triple[10:2]};
          default:eased=10'd896+{3'd0,t[8:2]};
        endcase
    end
endfunction
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
        0:base_x=43;1:base_x=53;2:base_x=40;3:base_x=47;4:base_x=56;
        5:base_x=39;6:base_x=50;7:base_x=44;8:base_x=54;default:base_x=48;
    endcase end
endfunction
function [7:0] seed_phase;
    input [3:0] n;
    begin case(n)
        0:seed_phase=16;1:seed_phase=107;2:seed_phase=50;3:seed_phase=185;4:seed_phase=224;
        5:seed_phase=141;6:seed_phase=84;7:seed_phase=12;8:seed_phase=172;default:seed_phase=61;
    endcase end
endfunction
wire main_lane=row_index==0||row_index==3||row_index==6||row_index==9;
wire [1:0] size=main_lane && row_point==0 ? 2'd2 :
                      (!main_lane && row_point==1 ? 2'd1 : 2'd0);
wire [7:0] seed=seed_phase(row_index);
wire [11:0] phase_x=frame_phase[11:0]+{seed,4'd0}+{row_point,10'd0};
wire [11:0] phase_y=frame_phase[12:1]+{(seed^8'h93),4'd0}+
                       (row_point==0 ? 12'd0 : (row_point==1 ? 12'd1365 : 12'd2730));
wire [11:0] phase_b=(size==2 ? {frame_phase[9:0],2'd0} : {frame_phase[10:0],1'b0})+
                       {seed,4'd0}+(row_point==0 ? 12'd0 : (row_point==1 ? 12'd1365 : 12'd2730));
wire [9:0] drift_x=eased(phase_x),drift_y=eased(phase_y),breath=eased(phase_b);
wire [6:0] point_x=row_point==0 ? base_x(row_index) :
                       (row_point==1 ? 7'd120-base_x(row_index) : base_x(row_index)+7'd25);
wire [8:0] point_y=base_y(row_index)+(row_point==0 ? 9'd0 : (row_point==1 ? 9'd112 : 9'd224));
wire [8:0] center_x_q2={point_x-7'd16,2'd0}+{2'd0,drift_x[9:3]};
wire [10:0] center_y_q2={point_y-9'd16,2'd0}+{4'd0,drift_y[9:3]};
wire [10:0] row_y_q2={row_y,2'd0};
wire [10:0] distance=row_y_q2>=center_y_q2 ? row_y_q2-center_y_q2 : center_y_q2-row_y_q2;
wire [7:0] stored_dy=|distance[10:8] ? 8'd255 : distance[7:0];
wire [7:0] amplitude=size==2 ? 8'd40+{1'b0,breath[9:3]} :
                            (size==1 ? 8'd18+{2'd0,breath[9:4]} : 8'd6+{3'd0,breath[9:5]});
wire [26:0] candidate={center_x_q2,stored_dy,amplitude,size};
wire choose_current=row_point==0 || distance<best_distance;
wire [9:0] next_pan=eased(I_phase_q4<20480 ? I_phase_q4[13:2] : 12'd0);
// No reset fanout on distributed RAM; row_ready protects every consumer.
always @(posedge I_clk) begin
    if(!I_rst && I_enable && !I_de && !frame_start && row_busy && row_point==2)
        line_cache[row_index]<=choose_current ? candidate : best_entry;
end
always @(posedge I_clk or posedge I_rst)begin
    if(I_rst)begin
        x<=0;y<=0;de_d<=0;vs_d<=0;seen<=0;frame_phase<=0;pan_q4<=0;
        row_busy<=0;row_ready<=0;row_index<=0;row_point<=0;row_y<=0;
        best_distance<=0;best_entry<=0;
    end else begin
        x<=nx;y<=ny;seen<=nseen;de_d<=I_de;vs_d<=I_vs;
        if(frame_start)begin
            frame_phase<=I_phase_q4<20480 ? I_phase_q4[14:0] : 15'd0;
            pan_q4<={2'd0,next_pan}+{1'b0,next_pan,1'b0};
            row_busy<=I_enable;row_ready<=0;row_index<=0;row_point<=0;row_y<=0;
        end else if(I_enable)begin
            if(!I_de && row_busy)begin
                if(choose_current)begin best_distance<=distance;best_entry<=candidate;end
                if(row_point==2)begin
                    row_point<=0;
                    if(row_index==9)begin row_busy<=0;row_ready<=1;end
                    else row_index<=row_index+1'b1;
                end else row_point<=row_point+1'b1;
            end
            if(line_end)begin
                row_busy<=1;row_ready<=0;row_index<=0;row_point<=0;
                row_y<=(!seen || y==479) ? 9'd0 : y+1'b1;
            end
        end else begin row_busy<=0;row_ready<=0;end
    end
end
// Gentle common pan across the screen seam, plus independent local drift.
// Full 128s cycle, eased 0..191.8px..0. Local X/Y periods are 32/64s.
// Common pan is frame-latched to keep easing off the active pixel path.
localparam [14:0] VIEW_Q4=VIEW_X*16;
wire [9:0] look_x=I_de && nx<639 ? nx+1'b1 : 10'd0;
wire [14:0] world_x={1'b0,look_x,4'd0}+VIEW_Q4;
wire signed [15:0] shifted=$signed({1'b0,world_x})-$signed({4'd0,pan_q4});
wire [14:0] star_x=shifted[15] ? shifted+16'd20480 : shifted[14:0];
wire [3:0] render_index=star_x[14:11];
wire [26:0] entry=line_cache[render_index];
wire signed [9:0] dx=$signed({1'b0,star_x[10:2]})-$signed({1'b0,entry[26:18]});
wire [9:0] dx_abs=dx[9] ? -dx : dx;
wire [1:0] scale=entry[1:0];
wire [9:0] dx_scaled=scale==2 ? {2'd0,dx_abs[9:2]} : (scale==1 ? {1'b0,dx_abs[9:1]} : dx_abs);
wire [7:0] dy_scaled=scale==2 ? {2'd0,entry[17:12]} :
                           (scale==1 ? {1'b0,entry[17:11]} : entry[17:10]);
wire [5:0] dy_abs=dy_scaled[5:0];
wire [5:0] dmax=dx_scaled[5:0]>dy_abs ? dx_scaled[5:0] : dy_abs;
wire [5:0] dmin=dx_scaled[5:0]>dy_abs ? dy_abs : dx_scaled[5:0];
wire [6:0] radius={1'b0,dmax}+{2'b00,dmin[5:1]};
wire halo=!(|dx_scaled[9:6]) && !(|dy_scaled[7:6]) && radius<32;
wire [8:0] core_cost={radius[4:0],4'd0};
wire [7:0] halo_cost={1'b0,radius[4:0],2'd0}+{2'd0,radius[4:0],1'b0};
wire [7:0] strength=entry[9:2];
wire [7:0] core_light=({1'b0,strength}>core_cost) ? strength-core_cost[7:0] : 8'd0;
wire [7:0] halo_light=strength>halo_cost ? ((strength-halo_cost)>>3) : 8'd0;
wire [8:0] total={1'b0,core_light}+{1'b0,halo_light};
reg [7:0] light;
reg warm_core;
always @(posedge I_clk or posedge I_rst)begin
    if(I_rst)begin light<=0;warm_core<=0;end
    else if(I_enable && row_ready)begin
        light<=halo ? (total[8] ? 8'd255 : total[7:0]) : 8'd0;
        warm_core<=radius<=2;
    end else begin light<=0;warm_core<=0;end
end
wire [7:0] red=light-(light>>4);
wire [7:0] blue=warm_core ? light-(light>>2) : light>>4;
wire [8:0] r={1'b0,I_rgb[23:16]}+{1'b0,red};
wire [8:0] g={1'b0,I_rgb[15:8]}+{1'b0,light};
wire [8:0] b={1'b0,I_rgb[7:0]}+{1'b0,blue};
assign O_rgb=I_enable && I_de && row_ready ?
    {r[8] ? 8'hff : r[7:0],g[8] ? 8'hff : g[7:0],b[8] ? 8'hff : b[7:0]} : I_rgb;
endmodule
