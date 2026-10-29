// Mechanically clone existing gate projects; never edit their baseline inputs.
const fs=require('fs'),path=require('path'),crypto=require('crypto');
const root=path.resolve(__dirname,'../../../'),prefix='dual_board/image_link/';
const read=f=>fs.readFileSync(path.join(root,f),'utf8');
const sha=f=>crypto.createHash('sha256').update(fs.readFileSync(path.join(root,f))).digest('hex').toUpperCase();
const sources=[prefix+'prj/media_a/MEDIA_IMAGE_A.al',prefix+'prj/media_b/MEDIA_SOURCE_B.al',prefix+'rtl/top_dual_image.v',
    prefix+'rtl/image_media_board_b.v',prefix+'phase10_validation_20261004.json',
    'src/user_source/constraints_source/pin.adc','src/user_source/constraints_source/timing.sdc',
    'src/user_source/hdl_source/top_tf_hdmi_audio.v','best_result/lab_ex5_i2s_v1.0_logic_round3_20261003.bit',
    'dual_board/fixed_udp_hw/prj/board_a/FIXED_UDP_HW_A_20261005.bit',
    'dual_board/fixed_udp_hw/prj/board_b/FIXED_UDP_HW_B_20261005.bit'];
const baselineFile=prefix+'phase11_baseline_20261005.json';
if(fs.existsSync(path.join(root,baselineFile))){
    const baseline=JSON.parse(read(baselineFile));
    for(const item of baseline.files)if(sha(item.file)!==item.sha256)throw Error('Baseline changed '+item.file);
}else fs.writeFileSync(path.join(root,baselineFile),JSON.stringify({date:'2026-10-05',files:sources.map(file=>({file,sha256:sha(file)}))},null,2)+'\n');
for(const [role,name]of [['a','MEDIA_IMAGE_A'],['b','MEDIA_SOURCE_B']]){
    const dir=prefix+'prj/media_'+role+'/',newName=name+'_HW_20261005';
    let xml=read(dir+name+'.al').replace('<Name>'+name+'</Name>','<Name>'+newName+'</Name>');
    if(role==='a')xml=xml.replace('C:/FPGA2026/HX4S20_Contest_2026/7_lab_ex_2026_nosoft/qiansai/lab_ex4_tf/src/user_source/constraints_source/pin.adc','../../constraints/media_a.adc')
        .replace('C:/FPGA2026/HX4S20_Contest_2026/7_lab_ex_2026_nosoft/qiansai/lab_ex4_tf/src/user_source/constraints_source/timing.sdc','../../constraints/media_a.sdc');
    else xml=xml.replace('../../constraints/board_b.adc','../../constraints/media_b.adc')
        .replace('../../../ethernet_smoke/source_code/constraints/smoke.sdc','../../constraints/media_b.sdc');
    if(!xml.includes('../../constraints/media_'+role+'.adc')||!xml.includes('../../constraints/media_'+role+'.sdc'))throw Error('Constraint clone failed '+role);
    fs.writeFileSync(path.join(root,dir+newName+'.al'),xml);
    console.log('Prepared '+dir+newName+'.al (baseline unmodified)');
}
