const fs=require('fs'),p=require('path'),base=__dirname;
const olddir='prj/car_rotate_b_20261009',oldstem='MEDIA_B_CAR_ROTATE_20261009';
console.log('*** Begin Patch');
for(const seed of [1,4]){
 const dir='prj/car_rotate_b_s'+seed+'_20261009',stem='MEDIA_B_CAR_ROTATE_S'+seed+'_20261009';
 const xml=fs.readFileSync(p.join(base,olddir,oldstem+'.al'),'utf8').replaceAll(olddir,dir).replaceAll(oldstem,stem);
 const tcl=fs.readFileSync(p.join(base,olddir,'build_flow.tcl'),'utf8').replaceAll(oldstem,stem).replace('set_param place seed 3','set_param place seed '+seed);
 for(const [f,t] of [[stem+'.al',xml],['build_flow.tcl',tcl]]){
  if(fs.existsSync(p.join(base,dir,f)))throw Error('Exists '+f);
  console.log('*** Add File: dual_board/image_link/'+dir+'/'+f);
  for(const l of t.split(/\r?\n/))console.log('+'+l);
 }
}
console.log('*** End Patch');
