`timescale 1ns/1ps
// Original HDL, not a Three.js/GLSL port. Fixed-view 16x8 orthographic tiles.
// Eight tiny two-bank LUT RAMs; one serial height updater in vertical blanking.
// RGB/HS/VS/DE ALWAYS travel through the same THREE-clock pipeline, off-page too.
module video_sonic_topography (
 input wire I_clk,I_rst,I_enable,I_hs,I_vs,I_de,
 input wire [23:0] I_rgb,
 input wire [111:0] I_bands,
 input wire [3:0] I_volume,
 output reg [23:0] O_rgb,
 output reg O_hs,O_vs,O_de
);
reg [9:0] x,nx;
reg [8:0] y,ny;
reg seen,nseen,de_prev,vs_prev;
wire frame_start=I_vs&&!vs_prev;
always @* begin
 nx=x;ny=y;nseen=seen;
 if(frame_start)begin nx=0;ny=0;nseen=0;end
 else if(I_de)begin
  if(!de_prev)begin nx=0;if(!seen)begin ny=0;nseen=1;end else if(y<479)ny=y+1'b1;end
  else if(x<639)nx=x+1'b1;
 end else nx=0;
end
reg [3:0] volume_meta,volume_sync,volume_stable,volume_frame;
always @(posedge I_clk or posedge I_rst)begin
 if(I_rst)begin x<=0;y<=0;seen<=0;de_prev<=0;vs_prev<=0;volume_meta<=8;volume_sync<=8;volume_stable<=8;end
 else begin
  x<=nx;y<=ny;seen<=nseen;de_prev<=I_de;vs_prev<=I_vs;
  volume_meta<=I_volume;volume_sync<=volume_meta;
  if(volume_meta==volume_sync)volume_stable<=volume_sync;
 end
end
function [6:0] gain;
 input [6:0] a;input [3:0] v;
 begin case(v)
  0:gain=0;1:gain=a>>3;2:gain=a>>2;3:gain=(a>>2)+(a>>3);
  4:gain=a>>1;5:gain=(a>>1)+(a>>3);6:gain=(a>>1)+(a>>2);
  7:gain=a-(a>>3);default:gain=a;
 endcase end
endfunction
function [6:0] ease;
 input [6:0] a,b;reg [7:0] d;
 begin
  if(b>=a)begin d={1'b0,b}-{1'b0,a}+8'd1;ease=a+(d>>1);end
  else begin d={1'b0,a}-{1'b0,b}+8'd7;ease=a-(d>>3);end
 end
endfunction
function signed [4:0] wave;
 input [4:0] phase;
 begin case(phase[4:2])
  0:wave=0;1:wave=2;2:wave=3;3:wave=2;
  4:wave=0;5:wave=-2;6:wave=-3;default:wave=-2;
 endcase end
endfunction
function [4:0] height_for;
 input [6:0] a;input [2:0] row;input [3:0] col;
 input [4:0] phase;input ring;
 reg [5:0] base;
 reg signed [8:0] h;
 begin
  // Use half-scale input so ordinary mid-level music fills the stage;
  // height_for still clamps every tile to 24 pixels of stored depth.
  base={1'b0,a[6:1]};
  case(row)
   0,7:base=base>>2;
   1,6:base=base>>1;
   2,5:base=(base>>1)+(base>>2);
   default:base=base;
  endcase
  h=$signed({3'd0,base});
  if(a>=16)h=h+wave(phase+{1'b0,col}+{row,2'd0});
  if(ring&&a!=0)h=h+2;
  height_for=h<0?5'd0:h>24?5'd24:h[4:0];
 end
endfunction
// Visual beat proxy from the existing lowest FOUR detected bands. It is not
// a new sub-bass filter or a precise BPM detector; B's 47-byte VIZ2 is unchanged.
wire [6:0] low01=I_bands[6:0]>I_bands[13:7]?I_bands[6:0]:I_bands[13:7];
wire [6:0] low23=I_bands[20:14]>I_bands[27:21]?I_bands[20:14]:I_bands[27:21];
wire [6:0] low_raw=low01>low23?low01:low23;
wire [6:0] low_scaled=gain(low_raw,volume_stable);
reg [6:0] last_low;
wire kick=low_scaled>8 && {1'b0,low_scaled}>{1'b0,last_low}+8'd8;
reg [6:0] motion_phase;
reg [5:0] ring_age;
reg ring_active,ring_job_active;
reg [3:0] ring_job_radius;
reg [4:0] phase_job;
reg [1:0] state;
reg [3:0] band_index;
reg [6:0] job_index;
reg [111:0] target_snapshot;
reg [6:0] levels[0:15];
reg [15:0] level_valid;
reg display_bank,job_bank,height_valid;
wire [6:0] old_level=level_valid[band_index]?levels[band_index]:7'd0;
wire [6:0] target_level=target_snapshot[6:0]>96?7'd96:target_snapshot[6:0];
wire [6:0] new_level=ease(old_level,gain(target_level,volume_frame));
wire [3:0] left_index=job_index[3:0]==0?4'd0:job_index[3:0]-4'd1;
wire [3:0] right_index=job_index[3:0]==15?4'd15:job_index[3:0]+4'd1;
wire [8:0] spatial_sum={2'd0,levels[left_index]}+{1'd0,levels[job_index[3:0]],1'b0}+{2'd0,levels[right_index]};
wire [6:0] spatial_level=spatial_sum[8:2];
wire [3:0] dc=job_index[3:0]>=7?job_index[3:0]-4'd7:4'd7-job_index[3:0];
wire [2:0] dr=job_index[6:4]>=3?job_index[6:4]-3'd3:3'd3-job_index[6:4];
wire [4:0] radius={1'b0,dc}+{1'b0,dr,1'b0};
wire ring_cell=ring_job_active&&radius=={1'b0,ring_job_radius}&&volume_frame!=0;
wire [4:0] new_height=volume_frame==0?5'd0:height_for(spatial_level,job_index[6:4],job_index[3:0],phase_job,ring_cell);
wire height_write=!I_rst&&I_enable&&!I_de&&!frame_start&&state==2;
always @(posedge I_clk)begin
 if(!I_rst&&I_enable&&!I_de&&!frame_start&&state==1)levels[band_index]<=new_level;
end
always @(posedge I_clk or posedge I_rst)begin
 if(I_rst)begin
  volume_frame<=8;last_low<=0;motion_phase<=0;ring_age<=0;ring_active<=0;
  ring_job_active<=0;ring_job_radius<=0;phase_job<=0;state<=0;band_index<=0;
  job_index<=0;level_valid<=0;display_bank<=0;job_bank<=1;height_valid<=0;
 end else if(!I_enable)begin
  last_low<=0;motion_phase<=0;ring_age<=0;ring_active<=0;
  ring_job_active<=0;state<=0;level_valid<=0;height_valid<=0;
 end else if(frame_start)begin
  motion_phase<=motion_phase+1'b1;last_low<=low_scaled;
  volume_frame<=volume_stable;phase_job<=motion_phase[6:2];
  if(volume_stable==0)begin ring_active<=0;ring_age<=0;ring_job_active<=0;end
  else if(kick)begin ring_active<=1;ring_age<=0;ring_job_active<=1;end
  else begin
   if(ring_active)begin if(ring_age==31)ring_active<=0;else ring_age<=ring_age+1'b1;end
   ring_job_active<=ring_active&&ring_age<31;
  end
  ring_job_radius<=kick?4'd0:ring_age[4:1];
  state<=1;band_index<=0;job_index<=0;job_bank<=~display_bank;
 end else if(I_de)begin
  // Malformed/too-short blanking aborts the unpublished bank, never exposing
  // a partially updated height field. Normal update takes only144 clocks.
  if(state!=0)state<=0;
 end else case(state)
  1:begin
   level_valid[band_index]<=1;
   if(band_index==15)begin state<=2;job_index<=0;end else band_index<=band_index+1'b1;
  end
  2:begin
   if(job_index==127)begin state<=0;display_bank<=job_bank;height_valid<=1;end
   else job_index<=job_index+1'b1;
  end
  default:state<=0;
 endcase
end
always @(posedge I_clk)begin
 if(!I_rst&&I_enable&&frame_start)target_snapshot<=I_bands;
 else if(!I_rst&&state==1&&!I_de&&!frame_start)target_snapshot<={7'd0,target_snapshot[111:7]};
end
wire [7:0] row_hit;
wire [5:0] row_ink[0:7];
genvar r;
generate for(r=0;r<8;r=r+1)begin:g_row
 // Large fixed-view stage. Stored height remains 5 bits; multiplying by
 // four is wiring, with no additional RAM or DSP. Left/right VUs stay clear.
 localparam [9:0] LEFT=50+r*4;
 localparam [8:0] BASE_Y=244+r*20;
 reg [5:0] tiles[0:31];
 wire [9:0] off_x=nx-LEFT;
 wire [5:0] tile=height_valid?tiles[{display_bank,off_x[8:5]}]:6'd0;
 wire [8:0] delta_y=ny-(BASE_Y-{2'd0,tile[4:0],2'd0});
 reg [6:0] dy_q;
 reg [4:0] lx_q,h_q;
 reg valid_q,ring_q,checker_q;
 always @(posedge I_clk)begin
  if(height_write&&job_index[6:4]==r)tiles[{job_bank,job_index[3:0]}]<={ring_cell,new_height};
 end
 always @(posedge I_clk or posedge I_rst)begin
  if(I_rst)begin dy_q<=0;lx_q<=0;h_q<=0;valid_q<=0;ring_q<=0;checker_q<=0;end
  else begin
   dy_q<=delta_y[6:0];lx_q<=off_x[4:0];h_q<=tile[4:0];ring_q<=tile[5];
   checker_q<=off_x[5]^((r%2)!=0);
   valid_q<=I_enable&&I_de&&nx>=LEFT&&nx<LEFT+512&&ny>=96&&ny<416&&delta_y[8:7]==0;
  end
 end
 wire [2:0] shift=(4'd15-dy_q[3:0])>>2;
 wire top=dy_q<16;
 wire [6:0] bottom={h_q,2'd0}+7'd16;
 wire top_hit=top&&{1'b0,lx_q}>={3'd0,shift}&&{1'b0,lx_q}<{3'd0,shift}+6'd28;
 wire side_hit=!top&&lx_q<30;
 wire tile_edge=top&&(dy_q==0||lx_q=={2'd0,shift});
 wire [1:0] face=top?2'd0:(lx_q<28?2'd1:2'd2);
 wire [2:0] shade=h_q[4:2]>(checker_q?1:0)?h_q[4:2]-(checker_q?1:0):3'd0;
 assign row_hit[r]=valid_q&&dy_q<bottom&&(top_hit||side_hit);
 assign row_ink[r]={tile_edge||ring_q,face,shade};
end endgenerate
reg selected_hit;
reg [5:0] selected_ink;
integer i;
always @*begin
 selected_hit=0;selected_ink=0;
 // Front rows overwrite rear rows: bounded fixed-view occlusion, no Z-buffer.
 for(i=0;i<8;i=i+1)if(row_hit[i])begin selected_hit=1;selected_ink=row_ink[i];end
end
function [23:0] palette;
 input [5:0] ink;reg [23:0] c;
 begin
  case(ink[2:0])
   0:c=24'h102E4A;1:c=24'h075B80;2:c=24'h078EAD;3:c=24'h00B6C9;
   4:c=24'h14D2D5;5:c=24'h55F2E4;default:c=24'hB8FFF0;
  endcase
  if(ink[5])c=ink[2:0]==0?24'h0D6A88:24'hA4FFFF;
  else if(ink[4:3]==1)c={1'b0,c[23:17],1'b0,c[15:9],1'b0,c[7:1]};
  else if(ink[4:3]==2)c={2'b0,c[23:18],2'b0,c[15:10],2'b0,c[7:2]};
  palette=c;
 end
endfunction
function [7:0] blend;
 input [7:0] bg,fg;reg [9:0] sum;
 begin sum={2'd0,bg}+{1'd0,fg,1'b0}+{2'd0,fg}+10'd2;blend=sum[9:2];end
endfunction
reg [23:0] bg0,bg1;
reg hs0,vs0,de0,hs1,vs1,de1,hit1;
reg [5:0] ink1;
wire [23:0] color=palette(ink1);
always @(posedge I_clk or posedge I_rst)begin
 if(I_rst)begin bg0<=0;bg1<=0;hs0<=0;vs0<=0;de0<=0;hs1<=0;vs1<=0;de1<=0;hit1<=0;ink1<=0;O_rgb<=0;O_hs<=0;O_vs<=0;O_de<=0;end
 else begin
  bg0<=I_rgb;bg1<=bg0;hs0<=I_hs;vs0<=I_vs;de0<=I_de;
  hs1<=hs0;vs1<=vs0;de1<=de0;hit1<=selected_hit;ink1<=selected_ink;
  O_hs<=hs1;O_vs<=vs1;O_de<=de1;
  O_rgb<=hit1&&de1?{blend(bg1[23:16],color[23:16]),blend(bg1[15:8],color[15:8]),blend(bg1[7:0],color[7:0])}:bg1;
 end
end
endmodule
