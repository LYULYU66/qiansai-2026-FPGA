// Independent R5 source/project/test runners. Never overwrite a protected
// candidate or change original test assertions, clocks, IP or FIFO capacity.
const fs=require('fs'),path=require('path'),crypto=require('crypto');
const root=path.resolve(__dirname,'../../..'),base='dual_board/image_link/';
const read=f=>fs.readFileSync(path.join(root,f),'utf8');
const sha=f=>crypto.createHash('sha256').update(fs.readFileSync(path.join(root,f))).digest('hex').toUpperCase();
for(const f of ['phase11_baseline_20261005.json','phase10_validation_20261004.json'])
 for(const item of JSON.parse(read(base+f)).files)
  if((f.startsWith('phase11')||/\.(v|do)$/.test(item.file))&&sha(item.file)!==item.sha256)
   throw Error('Golden baseline changed: '+item.file);
const round4=JSON.parse(read(base+'phase12_domain_validation_20261005.json'));
for(const item of round4.source_manifest.concat(round4.baseline_manifests,[round4.documentation]))
 if(sha(item.file)!==item.sha256)throw Error('Protected R4 candidate changed: '+item.file);
const from='MEDIA_SOURCE_B_R4_HW_20261005',to='MEDIA_SOURCE_B_R5_HW_20261005';
const project=read(base+'prj/media_b/'+from+'.al').replaceAll(from,to)
 .replaceAll('../../rtl/image_packet_tx.v','../../rtl/hw_round5_20261005/image_packet_tx_hw.v');
fs.writeFileSync(path.join(root,base+'prj/media_b/'+to+'.al'),project);
fs.writeFileSync(path.join(root,base+'prj/media_b/build_round5_b.tcl'),
 read(base+'prj/media_b/build_round4_b.tcl').replaceAll(from,to));
const sim=path.join(root,base+'sim'),folder=path.join(sim,'hw_round5_20261005');
fs.mkdirSync(folder,{recursive:true});
for(const file of fs.readdirSync(path.join(sim,'hw_round4_20261005')).filter(f=>/^run_.*\.do$/.test(f))){
 let text=fs.readFileSync(path.join(sim,'hw_round4_20261005',file),'utf8')
  .replaceAll('hw_round4_20261005/','hw_round5_20261005/')
  .replaceAll('../rtl/hw_round5_20261005/','../rtl/hw_round4_20261005/')
  .replaceAll('../rtl/image_packet_tx.v','../rtl/hw_round5_20261005/image_packet_tx_hw.v')
  .replaceAll('work_player_round4','work_player_round5').replaceAll('work_player_fixed_round4','work_player_fixed_round5');
 fs.writeFileSync(path.join(folder,file),text);
}
let boundary=read(base+'sim/run_player_round4_boundary.do')
 .replaceAll('work_player_boundary4','work_player_boundary5')
 .replaceAll('hw_round4_20261005/','hw_round5_20261005/')
 .replaceAll('set hw4 ../rtl/hw_round4_20261005','set hw4 ../rtl/hw_round4_20261005')
 .replaceAll('../rtl/image_packet_tx.v','../rtl/hw_round5_20261005/image_packet_tx_hw.v');
fs.writeFileSync(path.join(folder,'run_boundary.do'),boundary);
// Rename only the golden module symbol; all golden behavior remains identical.
fs.writeFileSync(path.join(folder,'image_packet_tx_golden.v'),
 read(base+'rtl/image_packet_tx.v').replace('module image_packet_tx #(','module image_packet_tx_golden_r5 #('));
console.log('Prepared isolated R5 BRAM-output hold pipeline and unmodified golden regression assertions. No bitgen.');
