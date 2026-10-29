// Generate independent project/runner copies; R3/R4/R5 evidence is immutable.
const fs=require('fs'),path=require('path'),crypto=require('crypto');
const root=path.resolve(__dirname,'../../..'),base='dual_board/image_link/';
const read=f=>fs.readFileSync(path.join(root,f),'utf8');
const sha=f=>crypto.createHash('sha256').update(fs.readFileSync(path.join(root,f))).digest('hex').toUpperCase();
for(const name of ['phase12_domain_validation_20261005.json','phase13_crc_pipeline_validation_20261005.json']){
 const m=JSON.parse(read(base+name));
 for(const i of m.source_manifest.concat(m.baseline_manifests,[m.documentation]))
  if(sha(i.file)!==i.sha256)throw Error('Protected evidence changed: '+i.file);
}
for(const name of ['phase11_baseline_20261005.json','phase10_validation_20261004.json'])
 for(const i of JSON.parse(read(base+name)).files)
  if((name.startsWith('phase11')||/\.(v|do)$/.test(i.file))&&sha(i.file)!==i.sha256)
   throw Error('Original baseline changed: '+i.file);
const from='MEDIA_SOURCE_B_R5_HW_20261005',to='MEDIA_SOURCE_B_R6_HW_20261005';
const project=read(base+'prj/media_b/'+from+'.al').replaceAll(from,to)
 .replaceAll('../../rtl/hw_20261005/audio_receipt_hw.v','../../rtl/hw_round6_20261005/audio_receipt_hw.v');
fs.writeFileSync(path.join(root,base+'prj/media_b/'+to+'.al'),project);
fs.writeFileSync(path.join(root,base+'prj/media_b/build_round6_b.tcl'),
 read(base+'prj/media_b/build_round5_b.tcl').replaceAll(from,to));
const folder=path.join(__dirname,'hw_round6_20261005');fs.mkdirSync(folder,{recursive:true});
fs.writeFileSync(path.join(folder,'audio_receipt_golden.v'),
 read(base+'rtl/hw_20261005/audio_receipt_hw.v').replaceAll('module audio_receipt_rx #','module audio_receipt_rx_golden_r6 #')
 .replaceAll('module audio_receipt_tx #','module audio_receipt_tx_golden_r6 #')
 .replaceAll('module audio_playback_progress (','module audio_playback_progress_golden_r6 ('));
fs.writeFileSync(path.join(folder,'run_boundary.do'),
 read(base+'sim/hw_round5_20261005/run_boundary.do')
 .replaceAll('work_player_boundary5','work_player_boundary6')
 .replaceAll('hw_round5_20261005/','hw_round6_20261005/')
 .replaceAll('../rtl/hw_round6_20261005/image_packet_tx_hw.v','../rtl/hw_round5_20261005/image_packet_tx_hw.v')
 .replaceAll('../rtl/hw_20261005/audio_receipt_hw.v','../rtl/hw_round6_20261005/audio_receipt_hw.v'));
for(const name of ['run_audio_modelsim.do','run_offload_modelsim.do'])
 fs.writeFileSync(path.join(folder,name),read(base+'sim/hw_round5_20261005/'+name)
  .replaceAll('work_player_round5','work_player_round6_audio')
  .replaceAll('hw_round5_20261005/','hw_round6_20261005/')
  .replaceAll('../rtl/hw_round6_20261005/image_packet_tx_hw.v','../rtl/hw_round5_20261005/image_packet_tx_hw.v')
  .replaceAll('../rtl/hw_20261005/audio_receipt_hw.v','../rtl/hw_round6_20261005/audio_receipt_hw.v'));
console.log('Prepared R6 receipt qualification pipeline; no constraints or native IP changed, no automatic bitgen.');
