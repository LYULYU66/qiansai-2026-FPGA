const fs=require('fs'),path=require('path');
const dir=path.join(__dirname,'hw_round7_20261005');fs.mkdirSync(dir,{recursive:true});
const old=fs.readFileSync(path.join(__dirname,'../rtl/hw_round3_20261005/frame_read_write_hw.v'),'utf8');
fs.writeFileSync(path.join(dir,'frame_read_write_golden.v'),old.replace('module frame_read_write','module frame_read_write_golden_r7'));
console.log('Prepared unchanged R3 native writer as comparison oracle.');
