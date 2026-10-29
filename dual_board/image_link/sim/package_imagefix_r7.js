const fs=require('fs'),path=require('path'),crypto=require('crypto');
const base=path.resolve(__dirname,'..'),dir=path.join(base,'prj/media_a');
const name='MEDIA_SRAM_TEST_A_IMAGEFIX_R7_20261005';
const hash=p=>crypto.createHash('sha256').update(fs.readFileSync(p)).digest('hex').toUpperCase();
for(const [file,marker] of [['modelsim_writer_window.log','PASS image writer reset-window regression'],['modelsim_writer_full.log','PASS full 640x480 native FIFO writer']]){
 const log=fs.readFileSync(path.join(__dirname,'hw_round7_20261005',file),'utf8');
 if(!log.includes(marker)||!log.includes('Errors: 0')||log.includes('** Fatal:'))throw Error('Simulation not passed: '+file);
}
const log=fs.readFileSync(path.join(dir,'td_20261005_171004.log'),'utf8');
if(/ERROR|Error:/.test(log)||!log.includes(name+'.bit'))throw Error('Build not ready or contains error');
const out=path.join(base,'board_test_20261005',name+'.bit');
const source=path.join(dir,name+'.bit');
if(fs.existsSync(out)&&hash(out)!==hash(source))throw Error('Refusing overwrite');
fs.copyFileSync(source,out);
const files=[source,path.join(base,'rtl/hw_round7_20261005/frame_read_write_hw.v'),path.join(dir,name+'_phy.area'),path.join(dir,name+'_pr.timing')];
fs.writeFileSync(path.join(base,'board_test_20261005','imagefix_r7_manifest.json'),JSON.stringify({
 generated_at:new Date().toISOString(),hardware_verified:false,program_mode:'PROGRAM_SRAM only',
 previous_hardware_result:'Original A/B SRAM media test: audio works, A display black and page digit remains zero.',
 fix:'Gate producer credit through FIFO reset and three write clocks of reset release; explicitly zero-extend FIFO count input ports.',
 unchanged:'B bit, HDMI core, PLL, SDRAM controller, FIFO depth and protocol unchanged.',
 tests:['Old failure reproduced at 3 clock phases: 3 reset-window pixels lost and only 768/1024 SDRAM writes, cache invalid.','Fixed 5 clock phases, each 3 complete 1024-word frames checked.','Full 640x480 frame: all 307200 RGB/tag words and addresses checked, cache committed.'],
 bit:out,sha256:hash(out),files:files.map(p=>({path:p,sha256:hash(p)}))
},null,2));
console.log(out);console.log('SHA256 '+hash(out));
