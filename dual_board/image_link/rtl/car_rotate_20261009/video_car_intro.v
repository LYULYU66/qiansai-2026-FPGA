`timescale 1ns/1ps
// One 256x96 indexed sprite, not a video/frame buffer. 25MHz pixel domain.
// All RGB/DE/VS signals acquire the same one-clock ROM latency.
module video_car_intro (
 input wire I_clk,I_rst,I_enable,I_vs,I_de,
 input wire [23:0] I_rgb,
 output wire [23:0] O_rgb,output reg O_vs,O_de
);
reg [9:0] x,nx;
reg [8:0] y,ny;
reg seen,nseen,de_prev,vs_prev;
reg [7:0] age;
reg [6:0] idle_phase;
// 25MHz / (800*525) = 59.5238 frames/s: 298 VS periods = 5.0064s.
// One sprite is projected horizontally, then mirrored at the narrow edge.
// Two half-turns return to the original facing; this is a stylized turn,
// not a new multi-view 3D model. Counters only run at visible-page VS edges.
reg [8:0] rotate_timer;
reg rotate_seen;
wire frame_start=I_vs&&!vs_prev;
always @* begin
 nx=x;ny=y;nseen=seen;
 if(frame_start)begin nx=0;ny=0;nseen=0;end
 else if(I_de)begin
  if(!de_prev)begin nx=0;if(!seen)begin ny=0;nseen=1;end else if(y<479)ny=y+1'b1;end
  else if(x<639)nx=x+1'b1;
 end else nx=0;
end
// Entering the visible instrument page restarts. A background bank refresh
// does not. Disabled/relax frames never advance or show the animation.
always @(posedge I_clk or posedge I_rst)begin
 if(I_rst)begin x<=0;y<=0;seen<=0;de_prev<=0;vs_prev<=0;age<=0;idle_phase<=0;rotate_timer<=0;rotate_seen<=0;end
 else begin
  x<=nx;y<=ny;seen<=nseen;de_prev<=I_de;vs_prev<=I_vs;
  if(!I_enable)begin age<=0;idle_phase<=0;rotate_timer<=0;rotate_seen<=0;end
  else if(frame_start)begin
   if(age<191)age<=age+1'b1;
   idle_phase<=idle_phase+1'b1;
   // First complete the existing introduction, then wait five seconds.
   if(age<144)begin rotate_timer<=0;rotate_seen<=0;end
   else if(rotate_timer==297)begin rotate_timer<=0;rotate_seen<=1;end
   else rotate_timer<=rotate_timer+1'b1;
  end
 end
end
// 16 frames of platform ignition, then a 128-frame fade and gentle 12px rise.
// Subtract before shifting: the fade must not wrap when age crosses128.
wire [7:0] fade_age=age-8'd16;
wire [4:0] opacity=age<16 ? 5'd0 : age>=144 ? 5'd16 : fade_age[7:3];
wire [3:0] lift=opacity>=12 ? 4'd0 : 4'd12-opacity[3:0];
wire [8:0] car_top=9'd368+lift;
wire [8:0] car_y=ny-car_top;
wire [9:0] car_x=nx-10'd192;
wire rotating=rotate_seen && rotate_timer<64;
wire [4:0] turn_step=rotate_timer[5:1]; // 32 angle steps, two frames per step.
wire [3:0] cosine_step=turn_step[3] ? (4'd0-turn_step[3:0]) : {1'b0,turn_step[2:0]};
function [12:0] inverse_width;
 input [3:0] step;
 begin case(step)
  0:inverse_width=13'd256; 1:inverse_width=13'd261;
  2:inverse_width=13'd277; 3:inverse_width=13'd308;
  4:inverse_width=13'd362; 5:inverse_width=13'd461;
  6:inverse_width=13'd669; 7:inverse_width=13'd1312;
  default:inverse_width=13'd4096; // keep a visible 16px edge, never vanish.
 endcase end
endfunction
wire [12:0] width_gain=rotating ? inverse_width(cosine_step) : 13'd256;
wire signed [8:0] centered_x=$signed({1'b0,car_x[7:0]})-9'sd128;
// One small signed multiply uses available arithmetic hardware rather than
// a per-pixel divider or an angle-by-pixel ROM. No additional image memory.
wire signed [22:0] expanded_x=centered_x*$signed({1'b0,width_gain});
wire signed [14:0] source_x=(expanded_x>>>8)+15'sd128;
wire mirror=rotating && turn_step>=8 && turn_step<24;
wire [7:0] addressed_x=mirror ? ~source_x[7:0] : source_x[7:0];
wire sprite_hit=I_enable&&I_de&&opacity!=0&&nx>=192&&nx<448&&ny>=car_top&&car_y<96&&source_x>=0&&source_x<=255;
wire [14:0] sprite_addr={car_y[6:0],addressed_x};
wire [3:0] sprite_index;
wire [23:0] sprite_rgb;
car_intro_rom u_sprite(.clk(I_clk),.enable(sprite_hit),.address(sprite_addr),.index(sprite_index),.rgb(sprite_rgb));
reg [23:0] bg;
reg enable_q,hit_q;
reg [9:0] px;
reg [8:0] py;
reg [7:0] age_q;
reg [6:0] pulse_q;
reg [4:0] alpha_q;
reg rotating_q;
reg [5:0] turn_frame_q;
always @(posedge I_clk or posedge I_rst)begin
 if(I_rst)begin O_vs<=0;O_de<=0;bg<=0;enable_q<=0;hit_q<=0;px<=0;py<=0;age_q<=0;pulse_q<=0;alpha_q<=0;rotating_q<=0;turn_frame_q<=0;end
 else begin O_vs<=I_vs;O_de<=I_de;bg<=I_rgb;enable_q<=I_enable;hit_q<=sprite_hit;px<=nx;py<=ny;age_q<=age;pulse_q<=idle_phase;alpha_q<=opacity;rotating_q<=rotating;turn_frame_q<=rotate_timer[5:0];end
end
function [7:0] add_sat;
 input [7:0] a,b;reg [8:0] t;
 begin t={1'b0,a}+{1'b0,b};add_sat=t[8]?8'd255:t[7:0];end
endfunction
// Explicit shift/add interpolation: no multiplier or DSP required.
function [7:0] mix;
 input [7:0] a,b;input [4:0] alpha;
 reg [12:0] ma,mb,total;
 reg [4:0] inv;
 begin
  inv=5'd16-alpha;
  ma=(alpha[0]?{5'd0,b}:13'd0)+(alpha[1]?{4'd0,b,1'b0}:13'd0)+
     (alpha[2]?{3'd0,b,2'd0}:13'd0)+(alpha[3]?{2'd0,b,3'd0}:13'd0)+(alpha[4]?{1'b0,b,4'd0}:13'd0);
  mb=(inv[0]?{5'd0,a}:13'd0)+(inv[1]?{4'd0,a,1'b0}:13'd0)+
     (inv[2]?{3'd0,a,2'd0}:13'd0)+(inv[3]?{2'd0,a,3'd0}:13'd0)+(inv[4]?{1'b0,a,4'd0}:13'd0);
  total=ma+mb+13'd8;mix=total[11:4];
 end
endfunction
wire [9:0] dx=px>=320 ? px-10'd320 : 10'd320-px;
wire [8:0] dy=py>=457 ? py-9'd457 : 9'd457-py;
wire [10:0] yscale={dy[6:0],4'd0};
wire [10:0] high=dx>=yscale ? {1'b0,dx} : yscale;
wire [10:0] low=dx>=yscale ? yscale : {1'b0,dx};
wire [11:0] radius={1'b0,high}+{2'd0,low[10:1]};
wire [8:0] reach=age_q<16 ? {1'b0,age_q[3:0],3'd0}+9'd8 : 9'd128;
wire platform=enable_q&&O_de&&px>=176&&px<464&&py>=443&&py<473&&radius<=reach;
wire [5:0] breath=pulse_q[6] ? ~pulse_q[5:0] : pulse_q[5:0];
wire [7:0] ground_light=radius+12'd6>=reach ? 8'd92 : radius+12'd16>=reach ? 8'd48 : 8'd12+{4'd0,breath[5:2]};
wire [23:0] ground_rgb=platform ? {add_sat(bg[23:16],ground_light>>3),add_sat(bg[15:8],ground_light>>1),add_sat(bg[7:0],ground_light)} : bg;
// A travelling highlight is clipped to opaque car pixels, not the background.
wire [5:0] sweep_frame=rotating_q ? turn_frame_q : age_q[5:0];
wire [9:0] sweep_x=10'd192+{2'd0,sweep_frame,2'd0};
wire [9:0] sweep_dx=px>=sweep_x ? px-sweep_x : sweep_x-px;
wire [7:0] sheen=(rotating_q||(age_q>=64&&age_q<128))&&sweep_dx<8 ? (sweep_dx<2?8'd72:sweep_dx<4?8'd40:8'd16) : 8'd0;
wire [23:0] polished={add_sat(sprite_rgb[23:16],sheen>>1),add_sat(sprite_rgb[15:8],sheen),add_sat(sprite_rgb[7:0],sheen)};
assign O_rgb=O_de&&enable_q&&hit_q&&sprite_index!=0 ?
 {mix(ground_rgb[23:16],polished[23:16],alpha_q),mix(ground_rgb[15:8],polished[15:8],alpha_q),mix(ground_rgb[7:0],polished[7:0],alpha_q)} : ground_rgb;
endmodule

