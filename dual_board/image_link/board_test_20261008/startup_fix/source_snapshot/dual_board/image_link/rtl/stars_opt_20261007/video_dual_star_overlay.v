`timescale 1ns/1ps
// Preserve the shared CTL4 timestamp. Both paired renderers accelerate geometry.
module dual_star_motion_clock #(parameter integer TICK_CYCLES=976563)(
 input wire clk,rst, output reg [15:0] phase_q4
);
localparam COUNT_BITS=TICK_CYCLES>1 ? $clog2(TICK_CYCLES) : 1;
reg [COUNT_BITS-1:0] divider;
always @(posedge clk or posedge rst)begin
 if(rst)begin divider<=0;phase_q4<=0;end
 else if(divider==TICK_CYCLES-1)begin
  divider<=0;phase_q4<=phase_q4==16383 ? 16'd0 : phase_q4+1'b1;
 end else divider<=divider+1'b1;
end
endmodule

// Sixty particles (8 large,12 medium,40 small) on the shared 1280x480 canvas.
// One eased-wave evaluator is reused over X/Y/breath on three blanking clocks.
// Each fixed viewport needs seven lanes: 7*6*3 +3 skipped lanes =129 clocks,
// within the 160-clock 640x480 horizontal blank. No new BRAM/DSP or RGB delay.
module video_dual_star_overlay #(parameter integer VIEW_X=0)(
 input wire I_clk,I_rst,I_enable,I_vs,I_de,
 input wire [23:0] I_rgb, input wire [15:0] I_phase_q4,
 output wire [23:0] O_rgb
);
reg [9:0] x,nx;
reg [8:0] y,ny;
reg de_d,vs_d,seen,nseen;
reg [14:0] frame_phase;
reg [11:0] pan_q4;
reg [26:0] line_cache[0:9];
reg row_busy,row_ready;
reg [3:0] row_index;
reg [2:0] row_point;
reg [1:0] eval_step;
reg [8:0] row_y,center_x;
reg [10:0] center_y,best_distance;
reg [26:0] best_entry;
wire frame_start=I_vs&&!vs_d;
wire line_end=!I_de&&de_d;
always @* begin
 nx=x;ny=y;nseen=seen;
 if(frame_start)begin nx=0;ny=0;nseen=0;end
 else if(I_de)begin
  if(!de_d)begin nx=0;if(!seen)begin ny=0;nseen=1;end else if(y<479)ny=y+1'b1;end
  else if(x<639)nx=x+1'b1;
 end else nx=0;
end
function [9:0] eased;
 input [11:0] phase;reg [10:0] t,triple;
 begin
  t=phase[11] ? ~phase[10:0] : phase[10:0];
  triple={2'd0,t[8:0]}+{1'b0,t[8:0],1'b0};
  case(t[10:9])
   0:eased={3'd0,t[8:2]};1:eased=10'd128+{1'b0,triple[10:2]};
   2:eased=10'd512+{1'b0,triple[10:2]};default:eased=10'd896+{3'd0,t[8:2]};
  endcase
 end
endfunction
function [6:0] base_x;
 input [3:0] n;
 begin case(n)
  0:base_x=43;1:base_x=53;2:base_x=40;3:base_x=47;4:base_x=56;
  5:base_x=39;6:base_x=50;7:base_x=44;8:base_x=54;default:base_x=48;
 endcase end
endfunction
function [6:0] base_y;
 input [3:0] n;
 begin case(n)
  0:base_y=55;1:base_y=92;2:base_y=38;3:base_y=76;4:base_y=64;
  5:base_y=26;6:base_y=88;7:base_y=50;8:base_y=104;default:base_y=68;
 endcase end
endfunction
function [7:0] seed_phase;
 input [3:0] n;
 begin case(n)
  0:seed_phase=16;1:seed_phase=107;2:seed_phase=50;3:seed_phase=185;4:seed_phase=224;
  5:seed_phase=141;6:seed_phase=84;7:seed_phase=12;8:seed_phase=172;default:seed_phase=61;
 endcase end
endfunction
function [11:0] point_phase;
 input [2:0] n;
 begin case(n)
  0:point_phase=0;1:point_phase=683;2:point_phase=1365;
  3:point_phase=2048;4:point_phase=2731;default:point_phase=3413;
 endcase end
endfunction
wire main_lane=row_index==0||row_index==3||row_index==6||row_index==9;
wire [1:0] size=main_lane && (row_point==0||row_point==3) ? 2'd2 :
               (!main_lane && (row_point==1||row_point==4) ? 2'd1 : 2'd0);
wire lane_needed=(VIEW_X==0) ? (row_index<5||row_index>=8) :
                 ((VIEW_X==640) ? row_index>=3 : 1'b1);
wire [13:0] fast_time={frame_phase[11:0],2'b00};
wire [7:0] seed=seed_phase(row_index);
wire [11:0] phase_x=fast_time[11:0]+{seed,4'd0}+{row_point,9'd0};
wire [11:0] phase_y=fast_time[12:1]+{(seed^8'h93),4'd0}+point_phase(row_point);
wire [11:0] phase_b=(size==2 ? {fast_time[9:0],2'd0} : {fast_time[10:0],1'b0})+
                     {seed,4'd0}+point_phase(row_point);
wire [11:0] eval_phase=eval_step==0 ? phase_x : (eval_step==1 ? phase_y : phase_b);
wire [9:0] ease_value=eased(eval_phase);
wire [6:0] point_x=(row_point==0||row_point==3) ? base_x(row_index) :
                  ((row_point==1||row_point==4) ? 7'd120-base_x(row_index) : base_x(row_index)+7'd25);
wire [8:0] point_y={2'd0,base_y(row_index)}+{row_point,6'd0};
wire [10:0] row_y_q2={row_y,2'd0};
wire [10:0] distance=row_y_q2>=center_y ? row_y_q2-center_y : center_y-row_y_q2;
wire [7:0] stored_dy=|distance[10:8] ? 8'd255 : distance[7:0];
wire [7:0] amplitude=size==2 ? 8'd80+{1'b0,ease_value[9:3]} :
                   (size==1 ? 8'd32+{2'd0,ease_value[9:4]} : 8'd12+{3'd0,ease_value[9:5]});
wire [26:0] candidate={center_x,stored_dy,amplitude,size};
wire choose_current=row_point==0||distance<best_distance;
wire [9:0] next_pan=eased(I_phase_q4<20480 ? I_phase_q4[11:0] : 12'd0);
always @(posedge I_clk)
 if(!I_rst&&I_enable&&!I_de&&!frame_start&&row_busy&&lane_needed&&eval_step==2&&row_point==5)
  line_cache[row_index]<=choose_current ? candidate : best_entry;
always @(posedge I_clk or posedge I_rst)begin
 if(I_rst)begin
  x<=0;y<=0;de_d<=0;vs_d<=0;seen<=0;frame_phase<=0;pan_q4<=0;
  row_busy<=0;row_ready<=0;row_index<=0;row_point<=0;eval_step<=0;row_y<=0;
  center_x<=0;center_y<=0;best_distance<=0;best_entry<=0;
 end else begin
  x<=nx;y<=ny;seen<=nseen;de_d<=I_de;vs_d<=I_vs;
  if(frame_start)begin
   frame_phase<=I_phase_q4<20480 ? I_phase_q4[14:0] : 15'd0;
   pan_q4<={2'd0,next_pan}+{1'b0,next_pan,1'b0};
   row_busy<=I_enable;row_ready<=0;row_index<=0;row_point<=0;eval_step<=0;row_y<=0;
  end else if(I_enable)begin
   if(!I_de&&row_busy)begin
    if(!lane_needed)begin
     row_index<=row_index+1'b1;row_point<=0;eval_step<=0;
    end else case(eval_step)
     0:begin center_x<={point_x-7'd16,2'd0}+{2'd0,ease_value[9:3]};eval_step<=1;end
     1:begin center_y<={point_y-9'd16,2'd0}+{4'd0,ease_value[9:3]};eval_step<=2;end
     2:begin
      if(choose_current)begin best_distance<=distance;best_entry<=candidate;end
      eval_step<=0;
      if(row_point==5)begin
       row_point<=0;
       if(row_index==9)begin row_busy<=0;row_ready<=1;end else row_index<=row_index+1'b1;
      end else row_point<=row_point+1'b1;
     end
    endcase
   end
   if(line_end)begin
    row_busy<=1;row_ready<=0;row_index<=0;row_point<=0;eval_step<=0;
    row_y<=(!seen||y==479) ? 9'd0 : y+1'b1;
   end
  end else begin row_busy<=0;row_ready<=0;end
 end
end
localparam [14:0] VIEW_Q4=VIEW_X*16;
wire [9:0] look_x=I_de&&nx<639 ? nx+1'b1 : 10'd0;
wire [14:0] world_x={1'b0,look_x,4'd0}+VIEW_Q4;
wire signed [15:0] shifted=$signed({1'b0,world_x})-$signed({4'd0,pan_q4});
wire [14:0] star_x=shifted[15] ? shifted+16'd20480 : shifted[14:0];
wire [3:0] render_index=star_x[14:11];
wire [26:0] entry=line_cache[render_index];
wire signed [9:0] dx=$signed({1'b0,star_x[10:2]})-$signed({1'b0,entry[26:18]});
wire [9:0] dx_abs=dx[9] ? -dx : dx;
wire [1:0] scale=entry[1:0];
wire [9:0] dx_scaled=scale==2 ? {2'd0,dx_abs[9:2]} : (scale==1 ? {1'b0,dx_abs[9:1]} : dx_abs);
wire [7:0] dy_scaled=scale==2 ? {2'd0,entry[17:12]} : (scale==1 ? {1'b0,entry[17:11]} : entry[17:10]);
wire [5:0] dy_abs=dy_scaled[5:0];
wire [5:0] dmax=dx_scaled[5:0]>dy_abs ? dx_scaled[5:0] : dy_abs;
wire [5:0] dmin=dx_scaled[5:0]>dy_abs ? dy_abs : dx_scaled[5:0];
wire [6:0] radius={1'b0,dmax}+{2'b00,dmin[5:1]};
wire halo=!(|dx_scaled[9:6])&&!(|dy_scaled[7:6])&&radius<32;
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
 else if(I_enable&&row_ready)begin light<=halo ? (total[8] ? 8'd255 : total[7:0]) : 8'd0;warm_core<=radius<=2;end
 else begin light<=0;warm_core<=0;end
end
wire [7:0] red=light-(light>>4),blue=warm_core ? light-(light>>2) : light>>4;
wire [8:0] r={1'b0,I_rgb[23:16]}+{1'b0,red},g={1'b0,I_rgb[15:8]}+{1'b0,light},b={1'b0,I_rgb[7:0]}+{1'b0,blue};
assign O_rgb=I_enable&&I_de&&row_ready ?
 {r[8] ? 8'hff : r[7:0],g[8] ? 8'hff : g[7:0],b[8] ? 8'hff : b[7:0]} : I_rgb;
endmodule
