// Independent B hardware candidate. No old sources/projects/logs/bit files
// are overwritten; clone test runners without changing any golden assertion.
const fs=require('fs'),path=require('path'),crypto=require('crypto');
const root=path.resolve(__dirname,'../../..'),base='dual_board/image_link/';
const read=f=>fs.readFileSync(path.join(root,f),'utf8');
const sha=f=>crypto.createHash('sha256').update(fs.readFileSync(path.join(root,f))).digest('hex').toUpperCase();
for(const file of ['phase11_baseline_20261005.json','phase10_validation_20261004.json'])
    for(const item of JSON.parse(read(base+file)).files)
        if((file.startsWith('phase11')||/\.(v|do)$/.test(item.file))&&sha(item.file)!==item.sha256)
            throw Error('Golden baseline changed: '+item.file);
for(const item of JSON.parse(read(base+'phase11_pipeline_validation_20261005.json')).source_manifest)
    if(sha(item.file)!==item.sha256)throw Error('Previous hardware candidate changed: '+item.file);
const replacements={
    '../../rtl/image_media_board_b.v':'../../rtl/hw_round4_20261005/image_media_board_b_hw.v',
    '../../rtl/image_tf_source.v':'../../rtl/hw_round4_20261005/image_tf_source_hw.v',
    '../../rtl/audio_visual_packet.v':'../../rtl/hw_round4_20261005/audio_visual_packet_hw.v',
    '../../rtl/hw_20261005/remote_audio_compute_hw.v':'../../rtl/hw_round4_20261005/remote_audio_compute_hw.v'
};
let xml=read(base+'prj/media_b/MEDIA_SOURCE_B_R2_HW_20261005.al')
    .replaceAll('MEDIA_SOURCE_B_R2_HW_20261005','MEDIA_SOURCE_B_R4_HW_20261005');
for(const [from,to]of Object.entries(replacements))xml=xml.replaceAll(from,to);
xml=xml.replace('</Verilog>','<File Path="../../rtl/hw_round4_20261005/player_domain_reset.v"><FileInfo><Attr Name="UsedInSyn" Val="true"/><Attr Name="UsedInP&amp;R" Val="true"/><Attr Name="BelongTo" Val="design_1"/><Attr Name="CompileOrder" Val="90"/></FileInfo></File>\n    </Verilog>');
fs.writeFileSync(path.join(root,base+'prj/media_b/MEDIA_SOURCE_B_R4_HW_20261005.al'),xml);
fs.writeFileSync(path.join(root,base+'prj/media_b/build_round4_b.tcl'),
    read(base+'prj/media_b/build_round2_b.tcl').replaceAll('MEDIA_SOURCE_B_R2_HW_20261005','MEDIA_SOURCE_B_R4_HW_20261005'));
const sim=path.join(root,base+'sim'),target=path.join(sim,'hw_round4_20261005');
fs.mkdirSync(target,{recursive:true});
for(const file of fs.readdirSync(path.join(sim,'hw_round2_20261005')).filter(f=>/^run_.*\.do$/.test(f))){
    let text=fs.readFileSync(path.join(sim,'hw_round2_20261005',file),'utf8')
        .replaceAll('hw_round2_20261005/','hw_round4_20261005/')
        // B keeps the previous, already verified ROM pipeline source.
        .replaceAll('../rtl/hw_round4_20261005/home_index_stream_hw.v','../rtl/hw_round2_20261005/home_index_stream_hw.v')
        .replaceAll('../rtl/image_tf_source.v','../rtl/hw_round4_20261005/image_tf_source_hw.v')
        .replaceAll('../rtl/audio_visual_packet.v','../rtl/hw_round4_20261005/audio_visual_packet_hw.v')
        .replaceAll('../rtl/hw_20261005/remote_audio_compute_hw.v','../rtl/hw_round4_20261005/remote_audio_compute_hw.v')
        .replaceAll('work_player_round2','work_player_round4').replaceAll('work_player_fixed_round2','work_player_fixed_round4');
    text='onerror {quit -code 1}\nif {![file exists work_player_round4]} {vlib work_player_round4}\n'+
        'vlog -sv -work work_player_round4 ../rtl/hw_round4_20261005/player_domain_reset.v\n'+text;
    fs.writeFileSync(path.join(target,file),text);
}
console.log('Prepared round-4 B domain reset/file-length candidate and isolated original test runners. No bitgen.');
