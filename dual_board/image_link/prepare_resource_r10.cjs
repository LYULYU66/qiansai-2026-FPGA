// Derive an independent second round; never overwrite accepted/R9 evidence.
const fs=require('fs'),path=require('path');
const root=path.resolve(__dirname,'../..');
const rtl=path.join(__dirname,'rtl/resource_round10_20261005');
const sim=path.join(__dirname,'sim/resource_round10_20261005');
if(fs.existsSync(rtl)||fs.existsSync(sim)) throw Error('R10 already exists');
fs.mkdirSync(rtl);fs.mkdirSync(sim);
for(const file of ['audio_waveform_analyzer.v','video_status_overlay.v'])
  fs.copyFileSync(path.join(__dirname,'rtl/resource_round9_20261005',file),path.join(rtl,file));
fs.copyFileSync(path.join(root,'src/user_source/hdl_source/audio_visualizer_overlay.v'),path.join(rtl,'audio_visualizer_overlay.v'));
const visual=fs.readFileSync(path.join(root,'src/user_source/hdl_source/audio_visualizer_overlay.v'),'utf8');
fs.writeFileSync(path.join(sim,'golden_audio_visualizer_overlay.v'),visual.replace(/\baudio_visualizer_overlay\b/g,'audio_visualizer_overlay_golden'));
for(const file of ['golden_audio_waveform_analyzer.v','golden_video_status_overlay.v','tb_resource_equivalence.v','run_equivalence.do'])
  fs.copyFileSync(path.join(__dirname,'sim/resource_round9_20261005',file),path.join(sim,file));
for(const board of ['a','b']) {
  const prj=path.join(__dirname,'prj/media_'+board);
  const oldName='MEDIA_SRAM_TEST_'+board.toUpperCase()+'_RESOPT_R9_20261005';
  const name='MEDIA_SRAM_TEST_'+board.toUpperCase()+'_RESOPT_R10_20261005';
  let xml=fs.readFileSync(path.join(prj,oldName+'.al'),'utf8').replaceAll(oldName,name).replaceAll('resource_round9_20261005','resource_round10_20261005');
  if(board==='a') xml=xml.replace(/Path="[^"\r\n]*\/audio_visualizer_overlay\.v"/g,'Path="'+path.join(rtl,'audio_visualizer_overlay.v').replaceAll('\\','/')+'"');
  fs.writeFileSync(path.join(prj,name+'.al'),xml);
  fs.writeFileSync(path.join(prj,'build_resource_r10.tcl'),fs.readFileSync(path.join(prj,'build_resource_r9.tcl'),'utf8').replaceAll(oldName,name));
}
console.log('R10 isolated projects prepared.');
