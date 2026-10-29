// Mechanical isolation/backup only. Run once before editing the R9 sources.
const fs = require('fs');
const path = require('path');
const crypto = require('crypto');
const root = path.resolve(__dirname, '../..');
const link = __dirname;
const baseline = path.join(link, 'accepted_baseline_20261005_r7_r8');
if (fs.existsSync(baseline)) throw Error('Baseline already exists; do not overwrite.');
fs.mkdirSync(baseline);
const hash = p => crypto.createHash('sha256').update(fs.readFileSync(p)).digest('hex').toUpperCase();
const boards = [
  ['a', 'MEDIA_SRAM_TEST_A_IMAGEFIX_R7_20261005', '2F687129FD0FD90F03A7E121B87FC71DD96D7F819EF9EA267678CF12CC4E6E85'],
  ['b', 'MEDIA_SRAM_TEST_B_HOMESTAGE_R8_20261005', '49396EED177D2B465A951F516479A5285BDA9FF4B9B1316224A94A236CC6F626']
];
const ledger = {generated_at:new Date().toISOString(), acceptance:'User reports all current functions accepted on hardware; this does not establish timing closure.', boards:[], sources:[]};
const copied = new Set();
function copySource(p) {
  const rel = path.relative(root,p);
  if (rel.startsWith('..') || !fs.existsSync(p) || copied.has(p)) return;
  copied.add(p);
  const dest = path.join(baseline,'sources',rel);
  fs.mkdirSync(path.dirname(dest),{recursive:true}); fs.copyFileSync(p,dest);
  ledger.sources.push({file:p,backup:dest,sha256:hash(p)});
}
for(const [board,name,expected] of boards) {
  const prj = path.join(link,'prj','media_'+board);
  const bit = path.join(link,'board_test_20261005',name+'.bit');
  if(hash(bit)!==expected) throw Error('Accepted bit hash mismatch: '+bit);
  const dest = path.join(baseline,board); fs.mkdirSync(dest);
  fs.copyFileSync(bit,path.join(dest,name+'.bit'));
  for(const ext of ['.al','_phy.area','_pr.timing','_phy.ts']) {
    const p=path.join(prj,name+ext); if(fs.existsSync(p)) fs.copyFileSync(p,path.join(dest,name+ext));
  }
  const xml=fs.readFileSync(path.join(prj,name+'.al'),'utf8');
  for(const m of xml.matchAll(/<File Path="([^"]+)"/g)) copySource(path.resolve(prj,m[1]));
  ledger.boards.push({board,name,bit,sha256:expected});
}
for(const name of ['imagefix_r7_manifest.json','home_stage_r8_manifest.json','IMAGEFIX_R7.md','HOMESTAGE_R8.md']) {
  const p=path.join(link,'board_test_20261005',name); fs.copyFileSync(p,path.join(baseline,name));
}
fs.writeFileSync(path.join(baseline,'acceptance.json'),JSON.stringify(ledger,null,2)+'\n');
const rtl = path.join(link,'rtl','resource_round9_20261005');
const sim = path.join(link,'sim','resource_round9_20261005');
fs.mkdirSync(rtl); fs.mkdirSync(sim);
for(const [file,module] of [['audio_waveform_analyzer.v','audio_waveform_analyzer'],['video_status_overlay.v','video_status_overlay']]) {
  const input=fs.readFileSync(path.join(root,'src/user_source/hdl_source',file),'utf8');
  fs.writeFileSync(path.join(rtl,file),input);
  let golden=input.replace(new RegExp('\\b'+module+'\\b','g'),module+'_golden');
  if(file==='video_status_overlay.v') golden=golden.replace(/\bvideo_status_font_rom\b/g,'video_status_font_rom_golden');
  fs.writeFileSync(path.join(sim,'golden_'+file),golden);
}
for(const [board,oldName] of boards) {
  const prj=path.join(link,'prj','media_'+board), name='MEDIA_SRAM_TEST_'+board.toUpperCase()+'_RESOPT_R9_20261005';
  let xml=fs.readFileSync(path.join(prj,oldName+'.al'),'utf8').replaceAll(oldName,name);
  const file=board==='a'?'video_status_overlay.v':'audio_waveform_analyzer.v';
  const replacement=path.join(rtl,file).replaceAll('\\','/');
  xml=xml.replace(new RegExp('Path="[^"\\r\\n]*[/\\\\]'+file.replace('.', '\\.')+'"','g'),'Path="'+replacement+'"');
  fs.writeFileSync(path.join(prj,name+'.al'),xml);
  const oldBuild=board==='a'?'build_imagefix_r7.tcl':'build_home_stage_r8.tcl';
  const build=fs.readFileSync(path.join(prj,oldBuild),'utf8').replaceAll(oldName,name);
  fs.writeFileSync(path.join(prj,'build_resource_r9.tcl'),build);
}
console.log('Frozen accepted bits and '+ledger.sources.length+' project sources; isolated R9 projects prepared.');
