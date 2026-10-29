const fs=require('fs'),p=require('path'),base=__dirname,root=p.resolve(base,'../..');
const old=p.join(base,'prj/yilu_replace_b_20261006'),dest=p.join(base,'prj/yilu_replace_b_seed4_20261006');
const slash=s=>s.replaceAll('\\','/'),stem='MEDIA_B_YILU_REPLACE_20261006';
const jobs=[[stem+'.al',fs.readFileSync(p.join(old,stem+'.al'),'utf8').replaceAll(slash(old),slash(dest))],
 ['build_replace.tcl',fs.readFileSync(p.join(old,'build_replace.tcl'),'utf8').replace('set_param place seed 3','set_param place seed 4')]];
console.log('*** Begin Patch');for(const [f,s] of jobs){console.log('*** Add File: '+slash(p.relative(root,p.join(dest,f))));for(const l of s.trimEnd().split(/\r?\n/))console.log('+'+l);}console.log('*** End Patch');
