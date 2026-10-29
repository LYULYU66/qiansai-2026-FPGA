// Isolate latest dual-song/cover baseline; never modify previously released inputs.
const fs=require('fs'),p=require('path'),base=__dirname,root=p.resolve(base,'../..');
const slash=s=>s.replaceAll('\\','/');
const jobs=[['rtl/dual_star_flow_20261006/video_dual_star_overlay.v',fs.readFileSync(p.join(base,'rtl/dual_stars_20261006/video_dual_star_overlay.v'),'utf8')]];
for(const board of ['a','b']){
 const old=p.join(base,'prj/yilu_replace_'+board+(board==='b'?'_seed4':'')+'_20261006');
 const dest=p.join(base,'prj/star_flow_'+board+'_20261006');
 const oldName='MEDIA_'+board.toUpperCase()+'_YILU_REPLACE_20261006';
 const name='MEDIA_'+board.toUpperCase()+'_STAR_FLOW_20261006';
 let xml=fs.readFileSync(p.join(old,oldName+'.al'),'utf8').replaceAll(slash(old),slash(dest)).replaceAll(oldName,name)
  .replaceAll('/rtl/dual_stars_20261006/video_dual_star_overlay.v','/rtl/dual_star_flow_20261006/video_dual_star_overlay.v');
 jobs.push([slash(p.relative(base,p.join(dest,name+'.al'))),xml]);
 jobs.push([slash(p.relative(base,p.join(dest,'build_flow.tcl'))),fs.readFileSync(p.join(old,'build_replace.tcl'),'utf8').replaceAll(oldName,name)]);
}
console.log('*** Begin Patch');for(const [f,s] of jobs){if(fs.existsSync(p.join(base,f)))throw Error('Already exists '+f);
 console.log('*** Add File: dual_board/image_link/'+f);for(const l of s.trimEnd().split(/\r?\n/))console.log('+'+l);
}console.log('*** End Patch');
