// Follow-up A-only experiment: keep UDP FIFO credit on the original reset,
// and restrict the local memory reset to real memory-domain state.
const fs=require('fs'),path=require('path'),crypto=require('crypto');
const base=path.resolve(__dirname,'..');
const read=f=>fs.readFileSync(path.join(base,f),'utf8');
const root=path.resolve(base,'../..');
for(const item of JSON.parse(read('phase11_baseline_20261005.json')).files){
    const actual=crypto.createHash('sha256').update(fs.readFileSync(path.join(root,item.file))).digest('hex').toUpperCase();
    if(actual!==item.sha256)throw Error('Golden baseline changed: '+item.file);
}
let project=read('prj/media_a/MEDIA_IMAGE_A_R2_HW_20261005.al')
    .replaceAll('MEDIA_IMAGE_A_R2_HW_20261005','MEDIA_IMAGE_A_R3_HW_20261005')
    .replaceAll('rtl/hw_round2_20261005/top_dual_image_hw.v','rtl/hw_round3_20261005/top_dual_image_hw.v')
    .replaceAll('src/user_source/hdl_source/SD/frame_read_write.v','dual_board/image_link/rtl/hw_round3_20261005/frame_read_write_hw.v');
fs.writeFileSync(path.join(base,'prj/media_a/MEDIA_IMAGE_A_R3_HW_20261005.al'),project);
fs.writeFileSync(path.join(base,'prj/media_a/build_round3_a.tcl'),read('prj/media_a/build_round2_a.tcl')
    .replaceAll('MEDIA_IMAGE_A_R2_HW_20261005','MEDIA_IMAGE_A_R3_HW_20261005'));
fs.writeFileSync(path.join(base,'prj/media_a/build_round3_a_seed3.tcl'),read('prj/media_a/build_round2_a.tcl')
    .replaceAll('MEDIA_IMAGE_A_R2_HW_20261005','MEDIA_IMAGE_A_R3_HW_20261005')
    .replace('set_param place seed 7','set_param place seed 3'));
let sim=read('sim/run_player_round2.do')
    .replaceAll('../rtl/hw_round2_20261005/top_dual_image_hw.v','../rtl/hw_round3_20261005/top_dual_image_hw.v')
    .replaceAll('work_player_round2','work_player_round3')
    .replaceAll('hw_round2_20261005/frame_reset.wlf','hw_round3_20261005/frame_reset.wlf');
sim=sim.replace('do hw_round2_20261005/run_home_modelsim.do',
    'vlog -sv -work work_player_round3 ../rtl/hw_round3_20261005/frame_read_write_hw.v ../../../src/user_source/hdl_source/SD/frame_fifo_write.v ../../../src/user_source/hdl_source/IP/afifo_32_16_256.v ../../../src/user_source/hdl_source/IP/afifo_16_32_256.v tb_player_frame_credit.v\n'+
    'vsim -onfinish stop -wlf hw_round3_20261005/frame_credit.wlf work_player_round3.tb_player_frame_credit\nlog -r /*\nrun -all\nquit -sim\n'+
    'do hw_round2_20261005/run_home_modelsim.do');
fs.writeFileSync(path.join(base,'sim/run_player_round3.do'),sim);
console.log('Prepared A-only round-3 memory-state reset; B retains round-2 ROM pipeline.');
