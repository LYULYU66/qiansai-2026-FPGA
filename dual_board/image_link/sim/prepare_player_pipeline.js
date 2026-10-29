// Hardware-only source selection and mechanically cloned DO scripts. Keep
// production/golden source, benches, logs and all earlier snapshots unchanged.
const fs=require('fs'),path=require('path'),crypto=require('crypto');
const root=path.resolve(__dirname,'../../../'),base='dual_board/image_link/';
const read=f=>fs.readFileSync(path.join(root,f),'utf8');
const sha=f=>crypto.createHash('sha256').update(fs.readFileSync(path.join(root,f))).digest('hex').toUpperCase();
const old={audio_receipt:'4B08AB1BA3B2E8734C59D9B199EDE164D20AF0A0A5F569A65D437C3DE26AD4DC',
    remote_audio_compute:'2CECCA2356611026FC82E030D45F56B597F823CC49E8BEFECD534FF1D3720020'};
for(const [name,hash]of Object.entries(old))if(sha(base+'rtl/'+name+'.v')!==hash)throw Error('Golden source changed '+name);
const baseline=JSON.parse(read(base+'phase11_baseline_20261005.json'));
for(const item of baseline.files)if(sha(item.file)!==item.sha256)throw Error('Baseline changed '+item.file);
for(const [role,name]of [['a','MEDIA_IMAGE_A'],['b','MEDIA_SOURCE_B']]){
    const file=base+'prj/media_'+role+'/'+name+'_HW_20261005.al';
    let xml=read(file);
    for(const src of Object.keys(old)){
        xml=xml.replaceAll('../../rtl/'+src+'.v','../../rtl/hw_20261005/'+src+'_hw.v');
        xml=xml.replaceAll('C:/FPGA2026/HX4S20_Contest_2026/7_lab_ex_2026_nosoft/qiansai/lab_ex4_tf/'+base+'rtl/'+src+'.v',
            '../../rtl/hw_20261005/'+src+'_hw.v');
    }
    fs.writeFileSync(path.join(root,file),xml);
}
const simDir=path.join(root,base+'sim'),target=path.join(simDir,'hw_20261005');
fs.mkdirSync(target,{recursive:true});
for(const file of fs.readdirSync(simDir).filter(f=>/^run_.*\.do$/.test(f))){
    let text=fs.readFileSync(path.join(simDir,file),'utf8');
    for(const src of Object.keys(old))text=text.replaceAll('../rtl/'+src+'.v','../rtl/hw_20261005/'+src+'_hw.v');
    text=text.replace(/\bdo (run_[\w]+\.do)/g,'do hw_20261005/$1');
    text=text.replaceAll('work_image_link','work_player_hw').replaceAll('work_fixed_udp','work_player_fixed_udp');
    text=text.replace(/(-wlf\s+)([^\s]+\.wlf)/g,'$1hw_20261005/$2');
    fs.writeFileSync(path.join(target,file),text);
}
console.log('Prepared hardware-only projects/DO overrides. Golden sources and test assertions unchanged.');
