const fs=require('fs'),p=require('path'),base=__dirname;
const board=(process.argv[2]||'A').toUpperCase(),seed=Number(process.argv[3]);
if(!['A','B'].includes(board)||!Number.isInteger(seed)||seed<1||seed>9)throw Error('board / seed');
const orig='prj/stars_opt_'+board.toLowerCase()+'_20261007',dest='prj/stars_opt_'+board.toLowerCase()+'_s'+seed+'_20261007';
const old='MEDIA_'+board+'_STARS_OPT_20261007',name='MEDIA_'+board+'_STARS_OPT_S'+seed+'_20261007';
const read=f=>fs.readFileSync(p.join(base,orig,f),'utf8');
const jobs=[[dest+'/'+name+'.al',read(old+'.al').replaceAll(orig,dest).replaceAll(old,name)],
 [dest+'/build_flow.tcl',read('build_flow.tcl').replaceAll(old,name).replace(/set_param place seed \d+/,'set_param place seed '+seed)]];
console.log('*** Begin Patch');
for(const [f,data] of jobs){if(fs.existsSync(p.join(base,f)))throw Error('Exists '+f);console.log('*** Add File: dual_board/image_link/'+f);for(const l of data.trimEnd().split(/\r?\n/))console.log('+'+l);}
console.log('*** End Patch');
