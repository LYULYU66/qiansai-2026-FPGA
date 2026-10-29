// Versioned B-board change; previous published inputs remain immutable.
const fs=require('fs'),p=require('path'),base=__dirname,jobs=[];
const rd=f=>fs.readFileSync(p.join(base,f),'utf8');
const branch='rtl/car_rotate_20261009';
function rep(s,a,b){if(!s.includes(a))throw Error('Missing anchor: '+a);return s.replace(a,b);}
let s=rd('rtl/car_intro_20261007/video_car_intro.v');
s=rep(s,'reg [6:0] idle_phase;',`reg [6:0] idle_phase;
// 25MHz / (800*525) = 59.5238 frames/s: 298 VS periods = 5.0064s.
// One sprite is projected horizontally, then mirrored at the narrow edge.
// Two half-turns return to the original facing; this is a stylized turn,
// not a new multi-view 3D model. Counters only run at visible-page VS edges.
reg [8:0] rotate_timer;
reg rotate_seen;`);
s=rep(s,'age<=0;idle_phase<=0;end','age<=0;idle_phase<=0;rotate_timer<=0;rotate_seen<=0;end');
s=rep(s,"if(!I_enable)begin age<=0;idle_phase<=0;end\n  else if(frame_start)begin if(age<191)age<=age+1'b1;idle_phase<=idle_phase+1'b1;end",`if(!I_enable)begin age<=0;idle_phase<=0;rotate_timer<=0;rotate_seen<=0;end
  else if(frame_start)begin
   if(age<191)age<=age+1'b1;
   idle_phase<=idle_phase+1'b1;
   // First complete the existing introduction, then wait five seconds.
   if(age<144)begin rotate_timer<=0;rotate_seen<=0;end
   else if(rotate_timer==297)begin rotate_timer<=0;rotate_seen<=1;end
   else rotate_timer<=rotate_timer+1'b1;
  end`);
s=rep(s,'wire sprite_hit=I_enable&&I_de&&opacity!=0&&nx>=192&&nx<448&&ny>=car_top&&car_y<96;\nwire [14:0] sprite_addr={car_y[6:0],car_x[7:0]};',`wire rotating=rotate_seen && rotate_timer<64;
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
wire [14:0] sprite_addr={car_y[6:0],addressed_x};`);
s=rep(s,'reg [4:0] alpha_q;','reg [4:0] alpha_q;\nreg rotating_q;\nreg [5:0] turn_frame_q;');
s=rep(s,'pulse_q<=0;alpha_q<=0;end','pulse_q<=0;alpha_q<=0;rotating_q<=0;turn_frame_q<=0;end');
s=rep(s,'pulse_q<=idle_phase;alpha_q<=opacity;end','pulse_q<=idle_phase;alpha_q<=opacity;rotating_q<=rotating;turn_frame_q<=rotate_timer[5:0];end');
s=rep(s,"wire [9:0] sweep_x=10'd192+{2'd0,age_q[5:0],2'd0};","wire [5:0] sweep_frame=rotating_q ? turn_frame_q : age_q[5:0];\nwire [9:0] sweep_x=10'd192+{2'd0,sweep_frame,2'd0};");
s=rep(s,'wire [7:0] sheen=age_q>=64&&age_q<128&&sweep_dx<8 ?', 'wire [7:0] sheen=(rotating_q||(age_q>=64&&age_q<128))&&sweep_dx<8 ?');
jobs.push([branch+'/video_car_intro.v',s]);
const olddir='prj/startup_fix_b_20261008',dir='prj/car_rotate_b_20261009',oldstem='MEDIA_B_STARTUP_FIX_20261008',stem='MEDIA_B_CAR_ROTATE_20261009';
s=rd(olddir+'/'+oldstem+'.al').replaceAll(olddir,dir).replaceAll(oldstem,stem).replaceAll('/rtl/car_intro_20261007/video_car_intro.v','/'+branch+'/video_car_intro.v');
jobs.push([dir+'/'+stem+'.al',s]);jobs.push([dir+'/build_flow.tcl',rd(olddir+'/build_flow.tcl').replaceAll(oldstem,stem)]);
// Existing B application regression now uses the versioned rotation layer.
s=rd('sim/startup_fix_20261008/run_boundary.do').replaceAll('work_startup_fix_boundary','work_car_rotate_boundary').replaceAll('../rtl/car_intro_20261007/video_car_intro.v','../'+branch+'/video_car_intro.v').replaceAll('startup_fix_20261008/b_boundary.wlf','car_rotate_20261009/b_boundary.wlf');
jobs.push(['sim/car_rotate_20261009/run_boundary.do',s]);
s=rd('sim/car_intro_20261007/run_car.do').replaceAll('work_car_intro_unit','work_car_rotate_intro').replaceAll('../rtl/car_intro_20261007/video_car_intro.v','../'+branch+'/video_car_intro.v').replaceAll('car_intro_20261007/car.wlf','car_rotate_20261009/intro.wlf');
jobs.push(['sim/car_rotate_20261009/run_intro.do',s]);
console.log('*** Begin Patch');
for(const [f,t]of jobs){if(fs.existsSync(p.join(base,f)))throw Error('Exists '+f);console.log('*** Add File: dual_board/image_link/'+f);for(const l of t.split(/\r?\n/))console.log('+'+l);}
console.log('*** End Patch');
