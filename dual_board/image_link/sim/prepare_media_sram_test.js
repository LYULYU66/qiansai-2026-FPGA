// Explicit engineering SRAM test, NOT a timing-closed production release.
// Clone only project/build names; production RTL, pin/clock constraints and
// earlier reports/bits are never overwritten. No board is programmed here.
const fs=require('fs'),path=require('path'),crypto=require('crypto');
const root=path.resolve(__dirname,'../../..'),base='dual_board/image_link/';
const read=f=>fs.readFileSync(path.join(root,f),'utf8');
const sha=f=>crypto.createHash('sha256').update(fs.readFileSync(path.join(root,f))).digest('hex').toUpperCase();
for(const name of ['phase12_domain_validation_20261005.json','phase13_crc_pipeline_validation_20261005.json']){
 const m=JSON.parse(read(base+name));
 for(const i of m.source_manifest.concat(m.baseline_manifests,[m.documentation]))
  if(sha(i.file)!==i.sha256)throw Error('Protected candidate changed: '+i.file);
}
for(const name of ['phase11_baseline_20261005.json','phase10_validation_20261004.json'])
 for(const i of JSON.parse(read(base+name)).files)
  if((name.startsWith('phase11')||/\.(v|do)$/.test(i.file))&&sha(i.file)!==i.sha256)
   throw Error('Original baseline changed: '+i.file);
const guard=read(base+'sim/hw_round6_20261005/modelsim_guard.log');
if(!guard.includes('PASS AAK2/AAK3 pipeline:') || /Errors: [1-9]|\*\* (Error|Fatal):/.test(guard))
 throw Error('New receipt candidate has not passed equivalence.');
const jobs=[
 {dir:'media_a',from:'MEDIA_IMAGE_A_R3_HW_20261005',to:'MEDIA_SRAM_TEST_A_MAIN_20261005',script:'build_round3_a_seed3.tcl'},
 {dir:'media_b',from:'MEDIA_SOURCE_B_R6_HW_20261005',to:'MEDIA_SRAM_TEST_B_TF_20261005',script:'build_round6_b.tcl'}
];
for(const j of jobs){
 const dir=base+'prj/'+j.dir+'/';
 fs.writeFileSync(path.join(root,dir+j.to+'.al'),read(dir+j.from+'.al').replaceAll(j.from,j.to));
 let tcl=read(dir+j.script).replaceAll(j.from,j.to)
  .replace('# Initial physical audit only: no automatic bitgen on negative timing.',
   '# EXPERIMENTAL SRAM TEST ONLY. Known negative timing; not approved for flash/stable release.');
 tcl+='\nputs "WARNING: Engineering test bit only; routed timing is NOT closed. PROGRAM_SRAM only."\nbitgen -bit '+j.to+'.bit\n';
 fs.writeFileSync(path.join(root,dir+'build_sram_test.tcl'),tcl);
}
console.log('Prepared paired, independently named engineering SRAM builds. No IP, clocks, pins or source functionality changed.');
