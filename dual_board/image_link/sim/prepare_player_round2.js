// Mechanically derived projects/scripts; production and round-1 sources stay
// immutable while their long regressions run. This is NOT a golden rebuild.
const fs=require('fs'),path=require('path'),crypto=require('crypto');
const root=path.resolve(__dirname,'../../..'),base='dual_board/image_link/';
const read=f=>fs.readFileSync(path.join(root,f),'utf8');
const baseline=JSON.parse(read(base+'phase11_baseline_20261005.json'));
for(const item of baseline.files){
    const actual=crypto.createHash('sha256').update(fs.readFileSync(path.join(root,item.file))).digest('hex').toUpperCase();
    if(actual!==item.sha256)throw Error('Golden baseline changed: '+item.file);
}
for(const [role,name]of [['a','MEDIA_IMAGE_A'],['b','MEDIA_SOURCE_B']]){
    let project=read(base+'prj/media_'+role+'/'+name+'_HW_20261005.al');
    project=project.replace('<Name>'+name+'_HW_20261005</Name>','<Name>'+name+'_R2_HW_20261005</Name>');
    if(role==='a')project=project.replaceAll(base+'rtl/top_dual_image.v',base+'rtl/hw_round2_20261005/top_dual_image_hw.v');
    else project=project.replaceAll('../../rtl/home_index_stream.v','../../rtl/hw_round2_20261005/home_index_stream_hw.v')
        .replaceAll(base+'rtl/home_index_stream.v',base+'rtl/hw_round2_20261005/home_index_stream_hw.v');
    fs.writeFileSync(path.join(root,base+'prj/media_'+role+'/'+name+'_R2_HW_20261005.al'),project);
    let tcl=read(base+'prj/media_'+role+'/build_hw_'+role+'.tcl');
    tcl=tcl.replaceAll(name+'_HW_20261005',name+'_R2_HW_20261005');
    fs.writeFileSync(path.join(root,base+'prj/media_'+role+'/build_round2_'+role+'.tcl'),tcl);
}
const sim=path.join(root,base+'sim'),target=path.join(sim,'hw_round2_20261005');
fs.mkdirSync(target,{recursive:true});
for(const file of fs.readdirSync(path.join(sim,'hw_20261005')).filter(f=>/^run_.*\.do$/.test(f))){
    let content=fs.readFileSync(path.join(sim,'hw_20261005',file),'utf8');
    content=content.replaceAll('../rtl/home_index_stream.v','../rtl/hw_round2_20261005/home_index_stream_hw.v');
    content=content.replaceAll('hw_20261005/','hw_round2_20261005/')
        .replaceAll('../rtl/hw_round2_20261005/audio_receipt_hw.v','../rtl/hw_20261005/audio_receipt_hw.v')
        .replaceAll('../rtl/hw_round2_20261005/remote_audio_compute_hw.v','../rtl/hw_20261005/remote_audio_compute_hw.v')
        .replaceAll('work_player_hw','work_player_round2').replaceAll('work_player_fixed_udp','work_player_fixed_round2');
    fs.writeFileSync(path.join(target,file),content);
}
console.log('Prepared isolated round-2 A memory-reset / B ROM-read pipeline candidates. No bitgen.');
