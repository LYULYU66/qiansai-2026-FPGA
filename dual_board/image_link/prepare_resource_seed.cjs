// Keep every placement attempt in its own project/evidence directory.
const fs=require('fs'),path=require('path');
const [board,seed]=process.argv.slice(2);
if(!['a','b'].includes(board)||!/^\d+$/.test(seed||'')) throw Error('Usage: node prepare_resource_seed.cjs a|b seed');
const src=path.join(__dirname,'prj/media_'+board);
const dest=path.join(__dirname,'prj/media_'+board+'_res10_seed'+seed);
if(fs.existsSync(dest)) throw Error('Seed attempt already exists');
fs.mkdirSync(dest);
const oldName='MEDIA_SRAM_TEST_'+board.toUpperCase()+'_RESOPT_R10_20261005';
const newName='MEDIA_SRAM_TEST_'+board.toUpperCase()+'_RESOPT_R10_S'+seed+'_20261005';
let xml=fs.readFileSync(path.join(src,oldName+'.al'),'utf8').replaceAll(oldName,newName);
xml=xml.replace(src.replaceAll('\\','/'),dest.replaceAll('\\','/'));
fs.writeFileSync(path.join(dest,newName+'.al'),xml);
let tcl=fs.readFileSync(path.join(src,'build_resource_r10.tcl'),'utf8').replaceAll(oldName,newName);
tcl=tcl.replace(/set_param place seed \d+/,'set_param place seed '+seed);
fs.writeFileSync(path.join(dest,'build_resource_r10.tcl'),tcl);
console.log(dest);
