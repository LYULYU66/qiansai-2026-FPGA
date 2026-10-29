// Require fresh, complete simulation and routed reports. Never update the
// phase-10/11 golden manifests or publish a negative-timing player bit.
const fs=require('fs'),path=require('path'),crypto=require('crypto');
const root=path.resolve(__dirname,'../../..'),base='dual_board/image_link/';
const read=f=>fs.readFileSync(path.join(root,f),'utf8');
const sha=f=>crypto.createHash('sha256').update(fs.readFileSync(path.join(root,f))).digest('hex').toUpperCase();
const protected11=JSON.parse(read(base+'phase11_baseline_20261005.json'));
const golden10=JSON.parse(read(base+'phase10_validation_20261004.json'));
const previous11=JSON.parse(read(base+'phase11_pipeline_validation_20261005.json'));
const previous12=JSON.parse(read(base+'phase12_domain_validation_20261005.json'));
for(const item of protected11.files.concat(golden10.files.filter(x=>/\.(v|do)$/.test(x.file)),previous11.source_manifest,
 previous12.source_manifest,previous12.baseline_manifests,[previous12.documentation]))
    if(sha(item.file)!==item.sha256)throw Error('Protected baseline changed: '+item.file);
function log(relative,markers){
    const file=base+relative,text=read(file);
    if(/Errors: [1-9]|\*\* (Error|Fatal):/.test(text))throw Error('Simulation failed: '+file);
    if(!/# End time:[^\r\n]+\r?\n# Errors: 0, Warnings: \d+\s*(?:#\s*quit -code 0\s*)?$/.test(text))throw Error('Incomplete log: '+file);
    for(const marker of markers)if(!text.includes(marker))throw Error('Missing '+marker+' in '+file);
    return {file,sha256:sha(file),passed:markers,errors:0,warnings:(text.match(/\*\* Warning:/g)||[]).length};
}
const full=log('sim/hw_round5_20261005/modelsim_all.log',golden10.passed);
const guard=log('sim/hw_round5_20261005/modelsim_guard.log',['PASS image TX pipeline equivalence:']);
const boundary=log('sim/hw_round5_20261005/modelsim_boundary.log',['PASS player B boundary:','PASS home source:']);
const equivalenceGolden=base+'sim/hw_round5_20261005/image_packet_tx_golden.v';
if(read(equivalenceGolden)!==read(base+'rtl/image_packet_tx.v').replace('module image_packet_tx #(','module image_packet_tx_golden_r5 #('))
 throw Error('Comparison oracle differs from original beyond the module name.');
function area(relative){
 const file=base+relative,text=read(file),out={file,sha256:sha(file)};
 for(const [key,field]of Object.entries({lut:'lut',registers:'reg',bram9k:'bram',bram32k:'bram32k',dsp:'dsp',pll:'pll'})){
  const m=text.match(new RegExp('^#'+field+'\\s+(\\d+)','m'));
  if(!m)throw Error('Missing '+field+' in '+file);out[key]=Number(m[1]);
 }
 out.lut_percent=Number((100*out.lut/19600).toFixed(2));return out;
}
const prefix='prj/media_b/MEDIA_SOURCE_B_R5_HW_20261005';
const tdLog=base+'prj/media_b/'+(process.argv[2]||'td_20261005_144410.log');
const tdText=read(tdLog);
if(/\bERROR\b/.test(tdText) || !tdText.includes('finish command "route"') || !tdText.includes('report_timing_status'))
 throw Error('TD route incomplete or failed: '+tdLog);
const timingFile=base+prefix+'_pr.timing',timingText=read(timingFile);
const timing={file:timingFile,sha256:sha(timingFile),
 confidence:timingText.match(/Confidence\s+:\s*(\w+)/)[1],
 sta_coverage_percent:Number(timingText.match(/STA coverage\s+:\s*([\d.]+)%/)[1]),
 setup_or_recovery_wns:Number(timingText.match(/\bSWNS:\s*([+-]?[\d.]+)ns/)[1]),
 hold_or_removal_wns:Number(timingText.match(/\bHWNS:\s*([+-]?[\d.]+)ns/)[1]),path_groups:[]};
if(timing.confidence!=='Routed')throw Error('Not a final routed timing report.');
for(const group of timingText.split(/(?=Path Group\s+:)/).slice(1)){
 const name=group.match(/Path Group\s+:\s*([^\r\n]+)/)[1];
 const rows=[...group.matchAll(/Slack\s+:\s*([+-]?[\d.]+)ns\s+Begin Point\s+:\s*([^\r\n]+)\s+End Point\s+:\s*([^\r\n]+)\s+Check Type\s+:\s*(\w+)/g)]
  .map(m=>({slack:Number(m[1]),begin:m[2].split(' (')[0],end:m[3].split(' (')[0],type:m[4]}));
 for(const type of ['setup','hold','recovery','removal']){
  const worst=rows.filter(p=>p.type===type).sort((a,b)=>a.slack-b.slack).slice(0,2);
  if(worst.length)timing.path_groups.push({name,type,worst_reported:worst});
 }
}
timing.closed=timing.setup_or_recovery_wns>=0 && timing.hold_or_removal_wns>=0;
const project=base+'prj/media_b/MEDIA_SOURCE_B_R5_HW_20261005.al';
const sourcePaths=[...read(project).matchAll(/<File Path="([^"]+)"/g)]
 .map(m=>path.relative(root,path.resolve(root,base+'prj/media_b',m[1])).replaceAll('\\','/'));
const extra=['sim/prepare_player_round5.js','sim/run_player_round5.ps1','sim/snapshot_player_round5.js',
 'sim/tb_image_tx_pipeline_equiv.v','sim/tb_player_b_boundary.v','sim/home_reference_indices.hex',
 'sim/run_player_round5_guard.do','sim/hw_round5_20261005/image_packet_tx_golden.v',
 'prj/media_b/build_round5_b.tcl',
 ...fs.readdirSync(path.join(root,base+'sim/hw_round5_20261005')).filter(f=>/^run_.*\.do$/.test(f)).map(f=>'sim/hw_round5_20261005/'+f)]
 .map(f=>base+f);
const sources=[...new Set([project,...sourcePaths,...extra])].map(file=>({file,sha256:sha(file)}));
const routed=area(prefix+'_phy.area'),gate=area(prefix+'_gate.area');
for(const field of ['bram9k','bram32k','dsp','pll'])
 if(routed[field]!==previous12.board_b.routed[field])throw Error('Hard-resource increase: '+field);
const worstUdp=(value)=>value.path_groups.find(g=>g.name==='udp_clk -> udp_clk'&&g.type==='setup').worst_reported[0].slack;
const cases=[...read(guard.file).matchAll(/TX pipeline case (\d+): (\d+) compared cycles, (\d+) CRC-verified packets, (\d+) complete frames/g)]
 .map(m=>({case:Number(m[1]),cycles:Number(m[2]),packets:Number(m[3]),frames:Number(m[4])}));
if(cases.length!==6)throw Error('Missing equivalence parameter case.');
const result={stage:'formal-player B image BRAM-to-CRC hold pipeline round 5',generatedAt:new Date().toISOString(),
 original_single_board_and_diagnostic_bits_unchanged:true,production_phase10_and_previous_candidate_unchanged:true,
 hardware_verified:false,published_player_bits:[],modelsim:{full_40:full,tx_cycle_equivalence:guard,b_top_and_home_source:boundary},
 release_status:'experimental_candidate_not_promoted_global_timing_worse',
 equivalence_cases:cases,
 test_counts:{original_regression:40,additional_unique_checks:2,new_testbenches:1,reused_top_boundary:1,repeated_home_source:1,total_test_runs:43},
 board_a:{unchanged:true,evidence_file:base+'phase11_pipeline_validation_20261005.json',routed:previous11.board_a.routed,timing:previous11.board_a.timing},
 board_b:{routing_completed:true,routed,gate,timing,td_log:{file:tdLog,sha256:sha(tdLog)},
  delta_from_previous_routed:{lut:routed.lut-previous12.board_b.routed.lut,registers:routed.registers-previous12.board_b.routed.registers},
  udp_intra_clock_setup:{previous:worstUdp(previous12.board_b.timing),current:worstUdp(timing)},
  global_setup_or_recovery_worse:timing.setup_or_recovery_wns<previous12.board_b.timing.setup_or_recovery_wns},
 source_manifest:sources,
 baseline_manifests:['phase11_baseline_20261005.json','phase10_validation_20261004.json','phase11_pipeline_validation_20261005.json','phase12_domain_validation_20261005.json']
  .map(f=>({file:base+f,sha256:sha(base+f)})),
 documentation:{file:base+'phase13_crc_pipeline_notes_20261005.md',sha256:sha(base+'phase13_crc_pipeline_notes_20261005.md')},
 timing_closed:previous11.board_a.timing.closed&&timing.closed,
 caveats:['No new clock-group/false-path exception, PLL/IP/FIFO depth or media protocol change.',
  '40 original component/integration regression assertions are unchanged, not a complete PHY/TF/HDMI physical simulation.',
  'B top boundary rerun substitutes decoded SD outputs and PLL/network pin transport; actual app FIFOs, CRC/packet scheduling, receipts, UART and compute are exercised.',
  'UDP intra-clock setup improves, but global recovery timing is worse; retain R4 as an independent reference, not a released new bit.',
  'Endpoint-specific STA constraints/Gray crossing and mapped reset topology still need audit.',
  'Routed timing remains negative; current sources are a validation candidate, not a released player bit.',
  'A is the previous round-3 hardware candidate and its physical build was not rerun in this round.']};
const out=path.join(root,base+'phase13_crc_pipeline_validation_20261005.json');
fs.writeFileSync(out,JSON.stringify(result,null,2)+'\n');
console.log(JSON.stringify({file:out,tests:full.passed.length,additional_test_runs:guard.passed.length+boundary.passed.length,additional_unique_checks:2,new_testbenches:1,
 b_routed_lut:routed.lut,b_lut_delta:result.board_b.delta_from_previous_routed.lut,
 setup_or_recovery_wns:timing.setup_or_recovery_wns,hold_or_removal_wns:timing.hold_or_removal_wns,
 timing_closed:result.timing_closed,published_player_bits:[]},null,2));
