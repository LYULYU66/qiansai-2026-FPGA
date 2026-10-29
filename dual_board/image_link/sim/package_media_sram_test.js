// Fail closed on mismatched source/test evidence. Publishing an experimental
// file is NOT programming a board, approving Flash, or claiming timing closure.
const fs=require('fs'),path=require('path'),crypto=require('crypto');
const root=path.resolve(__dirname,'../../..'),base='dual_board/image_link/';
const abs=f=>path.resolve(root,f),read=f=>fs.readFileSync(abs(f),'utf8');
const sha=f=>crypto.createHash('sha256').update(fs.readFileSync(abs(f))).digest('hex').toUpperCase();
const item=file=>({file,sha256:sha(file)});
const protectedNames=['phase11_baseline_20261005.json','phase10_validation_20261004.json','phase11_pipeline_validation_20261005.json','phase12_domain_validation_20261005.json','phase13_crc_pipeline_validation_20261005.json'];
for(const name of protectedNames){
 const m=JSON.parse(read(base+name));
 const files=m.source_manifest ? m.source_manifest.concat(m.baseline_manifests||[],m.documentation?[m.documentation]:[]) : m.files.filter(i=>name.startsWith('phase11_baseline')||/\.(v|do)$/.test(i.file));
 for(const i of files)if(sha(i.file)!==i.sha256)throw Error('Protected original/candidate changed: '+i.file);
}
const previous=JSON.parse(read(base+'phase13_crc_pipeline_validation_20261005.json'));
for(const test of Object.values(previous.modelsim))if(sha(test.file)!==test.sha256)throw Error('Previous regression log changed: '+test.file);
function validateLog(relative,markers){
 const file=base+relative,t=read(file);
 if(/Errors: [1-9]|\*\* (Error|Fatal):/.test(t))throw Error('Simulation failed: '+file);
 if(!/# End time:[^\r\n]+\r?\n# Errors: 0, Warnings: \d+\s*(?:#\s*quit -code 0\s*)?$/.test(t))throw Error('Incomplete simulation: '+file);
 for(const marker of markers)if(!t.includes(marker))throw Error('Missing '+marker+' in '+file);
 return {...item(file),passed:markers,errors:0,warnings:(t.match(/\*\* Warning:/g)||[]).length};
}
const tests={
 receipt_equivalence:validateLog('sim/hw_round6_20261005/modelsim_guard.log',['PASS receipt pipeline equivalence ext=0','PASS receipt pipeline equivalence ext=1','PASS AAK2/AAK3 pipeline:']),
 b_top_and_home:validateLog('sim/hw_round6_20261005/modelsim_boundary.log',['PASS player B boundary:','PASS home source:']),
 audio:validateLog('sim/hw_round6_20261005/modelsim_audio.log',['PASS audio status','PASS visual guard','PASS remote compute','PASS audio offload','PASS audio guard','PASS media abort','PASS audio media'])
};
const original=read(base+'rtl/hw_20261005/audio_receipt_hw.v');
const expectedGolden=original.replaceAll('module audio_receipt_rx #','module audio_receipt_rx_golden_r6 #').replaceAll('module audio_receipt_tx #','module audio_receipt_tx_golden_r6 #').replaceAll('module audio_playback_progress (','module audio_playback_progress_golden_r6 (');
if(read(base+'sim/hw_round6_20261005/audio_receipt_golden.v')!==expectedGolden)throw Error('Golden receipt differs beyond module names.');
function area(file){
 const t=read(file),out={...item(file)};
 for(const [key,tag]of Object.entries({lut:'lut',registers:'reg',bram9k:'bram9k',bram32k:'bram32k',dsp:'dsp',pll:'pll'})){
  const m=t.match(new RegExp('^\\s*#'+tag+'\\s+(\\d+)','m'));if(!m)throw Error('Missing '+tag+' '+file);out[key]=Number(m[1]);
 }
 out.lut_percent=Number((100*out.lut/19600).toFixed(2));return out;
}
function timing(file){
 const t=read(file),out={...item(file),confidence:t.match(/Confidence\s+:\s*(\w+)/)[1],coverage_percent:Number(t.match(/STA coverage\s+:\s*([\d.]+)%/)[1]),setup_or_recovery_wns:Number(t.match(/\bSWNS:\s*([+-]?[\d.]+)ns/)[1]),hold_or_removal_wns:Number(t.match(/\bHWNS:\s*([+-]?[\d.]+)ns/)[1]),path_groups:[]};
 if(out.confidence!=='Routed')throw Error('Not routed: '+file);
 for(const group of t.split(/(?=Path Group\s+:)/).slice(1)){
  const name=group.match(/Path Group\s+:\s*([^\r\n]+)/)[1];
  const rows=[...group.matchAll(/Slack\s+:\s*([+-]?[\d.]+)ns\s+Begin Point\s+:\s*([^\r\n]+)\s+End Point\s+:\s*([^\r\n]+)\s+Check Type\s+:\s*(\w+)/g)].map(m=>({slack:Number(m[1]),begin:m[2].split(' (')[0],end:m[3].split(' (')[0],type:m[4]}));
  for(const type of ['setup','hold','recovery','removal']){
   const worst=rows.filter(p=>p.type===type).sort((a,b)=>a.slack-b.slack).slice(0,2);
   if(worst.length)out.path_groups.push({name,type,worst_reported:worst});
  }
 }
 out.closed=out.setup_or_recovery_wns>=0&&out.hold_or_removal_wns>=0;return out;
}
const jobs=[
 {role:'A main HDMI/SDRAM',dir:'media_a',prefix:'MEDIA_SRAM_TEST_A_MAIN_20261005',candidate:'MEDIA_IMAGE_A_R3_HW_20261005',td:'td_20261005_152523.log'},
 {role:'B TF/media/compute',dir:'media_b',prefix:'MEDIA_SRAM_TEST_B_TF_20261005',candidate:'MEDIA_SOURCE_B_R6_HW_20261005',td:'td_20261005_152618.log'}
];
const sources=new Set(),builds=[],folder=base+'board_test_20261005/';
for(const job of jobs){
 const dir=base+'prj/'+job.dir+'/',prefix=dir+job.prefix,project=prefix+'.al',t=read(project);
 if(t.replaceAll(job.prefix,job.candidate)!==read(dir+job.candidate+'.al'))throw Error('Test project changed source configuration.');
 const logFile=dir+job.td,log=read(logFile);
 if(/\bERROR\b/.test(log)||!log.includes('finish command "route"')||!log.includes('finish command "bitgen -bit '+job.prefix+'.bit"'))throw Error('Incomplete/failed TD: '+logFile);
 const a=area(prefix+'_phy.area'),tm=timing(prefix+'_pr.timing');
 const ca=area(dir+job.candidate+'_phy.area'),ct=timing(dir+job.candidate+'_pr.timing');
 for(const key of ['lut','registers','bram9k','bram32k','dsp','pll'])if(a[key]!==ca[key])throw Error('Test build area differs from candidate: '+key);
 for(const key of ['setup_or_recovery_wns','hold_or_removal_wns'])if(tm[key]!==ct[key])throw Error('Test build timing differs from candidate: '+key);
 const bit=prefix+'.bit',destination=folder+job.prefix+'.bit';
 if(fs.statSync(abs(bit)).size<100000)throw Error('Missing/short bit: '+bit);
 if(fs.existsSync(abs(destination))){if(sha(destination)!==sha(bit))throw Error('Refusing overwrite of different test bit.');}
 else fs.copyFileSync(abs(bit),abs(destination));
 if(sha(destination)!==sha(bit))throw Error('Copy verification failed.');
 for(const m of t.matchAll(/<File Path="([^"]+)"/g))sources.add(path.relative(root,path.resolve(abs(dir),m[1])).replaceAll('\\','/'));
 sources.add(project);sources.add(dir+'build_sram_test.tcl');
 builds.push({role:job.role,bit:{...item(destination),bytes:fs.statSync(abs(destination)).size},routed:a,timing:tm,td_log:item(logFile),critical_warnings:log.split(/\r?\n/).filter(l=>l.includes('CRITICAL-WARNING:')),candidate_project:item(dir+job.candidate+'.al')});
}
for(const f of ['sim/prepare_player_round6.js','sim/run_player_round6.ps1','sim/run_player_round6_guard.do','sim/run_player_round6_audio.do','sim/tb_audio_receipt_pipeline_equiv.v','sim/hw_round6_20261005/audio_receipt_golden.v','sim/hw_round6_20261005/run_boundary.do','sim/hw_round6_20261005/run_audio_modelsim.do','sim/hw_round6_20261005/run_offload_modelsim.do','sim/prepare_media_sram_test.js','sim/package_media_sram_test.js','prj/media_b/build_round6_b.tcl','prj/media_b/MEDIA_SOURCE_B_R6_HW_20261005.al','sim/home_reference_indices.hex','constraints/media_a.adc','constraints/media_a.sdc','constraints/media_b.adc','constraints/media_b.sdc'])sources.add(base+f);
const result={stage:'dual-board media engineering SRAM test with B receipt qualification pipeline',generatedAt:new Date().toISOString(),release_status:'EXPERIMENTAL_SRAM_ONLY_NOT_TIMING_CLOSED',hardware_verified:false,automatic_board_programming:false,flash_programming_approved:false,old_single_board_and_diagnostic_bits_unchanged:true,previous_candidates_unchanged:true,tests,previous_full_40_evidence:item(base+'phase13_crc_pipeline_validation_20261005.json'),test_counts:{previous_full_40_not_rerun_this_round:40,new_receipt_testbenches:1,equivalence_parameter_cases:2,new_receipt_packets:2400,b_top_boundary:1,repeated_home_source:1,repeated_audio_regressions:7,total_this_round_test_runs:10},builds,source_manifest:[...sources].sort().map(item),protected_manifests:protectedNames.map(f=>item(base+f)),documentation:[item(folder+'README.md'),item(base+'phase14_receipt_pipeline_notes_20261005.md')],limitations:['Both boards retain negative same-domain and cross-domain timing; not only special SDRAM IO paths.','No new false paths, clock groups, PLL, native IP, FIFO depth or protocol changes.','Prior full regression is R5 evidence; only the listed targeted R6 checks were freshly run.','Application-level and native FIFO simulation is not real TF/PHY/SDRAM/HDMI verification.','A SDRAM placement/local clock warnings remain; external IO timing specification audit is incomplete.','Use PROGRAM_SRAM with paired files, keep known rollback, do not treat board observations as timing signoff.']};
fs.writeFileSync(abs(folder+'manifest.json'),JSON.stringify(result,null,2)+'\n');
fs.writeFileSync(abs(base+'phase14_receipt_pipeline_validation_20261005.json'),JSON.stringify(result,null,2)+'\n');
console.log(JSON.stringify({release_status:result.release_status,hardware_verified:false,tests_this_round:10,boards:builds.map(b=>({role:b.role,bit:b.bit.file,lut:b.routed.lut,setup_or_recovery_wns:b.timing.setup_or_recovery_wns,hold_or_removal_wns:b.timing.hold_or_removal_wns})),protected_originals_unchanged:true},null,2));
