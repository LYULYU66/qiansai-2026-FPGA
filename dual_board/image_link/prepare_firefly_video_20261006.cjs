const fs=require('fs'),p=require('path');
const base=__dirname,slash=s=>s.replaceAll('\\','/'),jobs=[];
for(const board of ['a','b']){
 const old=p.join(base,'prj/star_flow_'+board+'_20261006');
 const dest=p.join(base,'prj/firefly_video_'+board+'_20261006');
 const oldName='MEDIA_'+board.toUpperCase()+'_STAR_FLOW_20261006';
 const name='MEDIA_'+board.toUpperCase()+'_FIREFLY_VIDEO_20261006';
 const xml=fs.readFileSync(p.join(old,oldName+'.al'),'utf8').replaceAll(slash(old),slash(dest)).replaceAll(oldName,name)
  .replaceAll('/rtl/dual_star_flow_20261006/video_dual_star_overlay.v','/rtl/firefly_video_20261006/video_dual_star_overlay.v');
 jobs.push([slash(p.relative(base,p.join(dest,name+'.al'))),xml]);
 jobs.push([slash(p.relative(base,p.join(dest,'build_flow.tcl'))),fs.readFileSync(p.join(old,'build_flow.tcl'),'utf8').replaceAll(oldName,name)]);
}
const src='sim/dual_star_flow_20261006',dst='sim/firefly_video_20261006';
for(const f of ['tb_dual_stars.v','tb_star_control.v','tb_b_hdmi_preview.v','run_stars.do','run_preview.do']){
 let s=fs.readFileSync(p.join(base,src,f),'utf8').replaceAll('dual_star_flow_20261006', 'firefly_video_20261006')
  .replaceAll('work_star_flow','work_firefly_video');
 if(f==='tb_star_control.v')s=s.replace('old_master==20479','old_master==16383')
  .replace('if(time_master.speed_q4>64)$fatal(1,"motion velocity out of range");','if(master>=16384 || wraps<1)$fatal(1,"animation timestamp out of range or wrap not covered");')
  .replace('eased bidirectional animation (modulus tested separately)','continuous animation timestamp, network-independent orbit/breathing');
 if(f==='tb_dual_stars.v')s=s.replace('1:ph=16;2:ph=10240;3:ph=20479','1:ph=1;2:ph=8192;3:ph=16383')
  .replace('lit_a<10000 || lit_b<10000','lit_a<3000 || lit_b<3000')
  .replace('3 sizes/brightness layers','independent XY drift, 3 sizes, staggered breathing');
 jobs.push([dst+'/'+f,s]);
}
console.log('*** Begin Patch');
for(const [f,s] of jobs){
 if(fs.existsSync(p.join(base,f)))throw Error('Already exists '+f);
 console.log('*** Add File: dual_board/image_link/'+f);
 for(const l of s.trimEnd().split(/\r?\n/))console.log('+'+l);
}
console.log('*** End Patch');
