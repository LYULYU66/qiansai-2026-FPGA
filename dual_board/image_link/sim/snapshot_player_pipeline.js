// Reproducible evidence, not a claim of hardware success. Require completed
// fresh candidate regression logs; preserve phase-10/golden snapshots.
const fs=require('fs'),path=require('path'),crypto=require('crypto');
const root=path.resolve(__dirname,'../../..'),base='dual_board/image_link/';
const read=f=>fs.readFileSync(path.join(root,f),'utf8');
const sha=f=>crypto.createHash('sha256').update(fs.readFileSync(path.join(root,f))).digest('hex').toUpperCase();
const baseline=JSON.parse(read(base+'phase11_baseline_20261005.json'));
for(const item of baseline.files)if(sha(item.file)!==item.sha256)throw Error('Golden baseline changed: '+item.file);
for(const [f,h]of Object.entries({
    'rtl/audio_receipt.v':'4B08AB1BA3B2E8734C59D9B199EDE164D20AF0A0A5F569A65D437C3DE26AD4DC',
    'rtl/remote_audio_compute.v':'2CECCA2356611026FC82E030D45F56B597F823CC49E8BEFECD534FF1D3720020'
}))if(sha(base+f)!==h)throw Error('Golden audio changed: '+f);
function completedLog(relative,markers){
    const file=base+relative,text=read(file);
    if(/Errors: [1-9]|\*\* (Error|Fatal):/.test(text))throw Error('Simulation failed: '+file);
    if(!/# End time:[^\r\n]+\r?\n# Errors: 0, Warnings: \d+\s*(?:#\s*quit -code 0\s*)?$/.test(text))throw Error('Incomplete log: '+file);
    for(const marker of markers)if(!text.includes(marker))throw Error('Missing '+marker+' in '+file);
    return {file,sha256:sha(file),passed:markers,errors:0,warnings:(text.match(/\*\* Warning:/g)||[]).length};
}
const golden=JSON.parse(read(base+'phase10_validation_20261004.json'));
// Original assertions and RTL must be byte-identical, not merely have matching
// PASS labels. Only independent hardware override sources are modified.
for(const item of golden.files.filter(x=>/\.(v|do)$/.test(x.file)))
    if(sha(item.file)!==item.sha256)throw Error('Golden RTL/test changed: '+item.file);
const full=completedLog('sim/hw_20261005/modelsim_all.log',golden.passed);
const guard=completedLog('sim/hw_20261005/modelsim_guard.log',['PASS player pipeline guard:']);
const round3=completedLog('sim/hw_round3_20261005/modelsim_round3.log',[
    'PASS player frame reset:','PASS player frame credit:','PASS home atlas:',
    'PASS home pixels:','PASS tagged image:','PASS home pipeline:','PASS home source:'
]);
function area(relative){
    const text=read(base+relative),out={file:base+relative,sha256:sha(base+relative)};
    for(const [key,field]of Object.entries({lut:'lut',registers:'reg',bram9k:'bram',bram32k:'bram32k',dsp:'dsp',pll:'pll'})){
        const match=text.match(new RegExp('^#'+field+'\\s+(\\d+)','m'));
        if(!match)throw Error('Missing resource '+field+' in '+relative);out[key]=Number(match[1]);
    }
    out.lut_percent=Number((100*out.lut/19600).toFixed(2));return out;
}
function timing(relative){
    const file=base+relative,text=read(file),out={file,sha256:sha(file)};
    for(const [key,label]of Object.entries({setup_or_recovery_wns:'SWNS',hold_or_removal_wns:'HWNS'})){
        const m=text.match(new RegExp('\\b'+label+':\\s*([+-]?[\\d.]+)ns'));
        if(!m)throw Error('Missing '+label+' in '+file);out[key]=Number(m[1]);
    }
    out.confidence=text.match(/Confidence\s+:\s*(\w+)/)[1];
    out.sta_coverage_percent=Number(text.match(/STA coverage\s+:\s*([\d.]+)%/)[1]);
    out.closed=out.confidence==='Routed'&&out.setup_or_recovery_wns>=0&&out.hold_or_removal_wns>=0;
    out.path_groups=[];
    for(const group of text.split(/(?=Path Group\s+:)/).slice(1)){
        const name=group.match(/Path Group\s+:\s*([^\r\n]+)/)[1];
        const rows=[...group.matchAll(/Slack\s+:\s*([+-]?[\d.]+)ns\s+Begin Point\s+:\s*([^\r\n]+)\s+End Point\s+:\s*([^\r\n]+)\s+Check Type\s+:\s*(\w+)/g)]
            .map(m=>({slack:Number(m[1]),begin:m[2].split(' (')[0],end:m[3].split(' (')[0],type:m[4]}));
        for(const type of ['setup','hold','recovery','removal']){
            const paths=rows.filter(p=>p.type===type).sort((a,b)=>a.slack-b.slack).slice(0,2);
            if(paths.length)out.path_groups.push({name,type,worst_reported:paths});
        }
    }
    return out;
}
function physical(role,name,log){
    const prefix='prj/media_'+role+'/',text=read(base+prefix+log);
    // A failed route is useful evidence, never silently replaced with an old
    // successful report that happened to share the same project prefix.
    if(/\bERROR\b/.test(text))return {routing_completed:false,
        td_errors:text.split(/\r?\n/).filter(line=>/\bERROR\b/.test(line)),
        gate:area(prefix+name+'_gate.area'),placed:timing(prefix+name+'_place.timing'),
        routed:null,timing:null,td_log:{file:base+prefix+log,sha256:sha(base+prefix+log)}};
    for(const command of ['route','report_area','report_timing_summary'])
        if(!text.includes(command))throw Error('Missing TD stage '+command);
    return {routing_completed:true,routed:area(prefix+name+'_phy.area'),gate:area(prefix+name+'_gate.area'),
        timing:timing(prefix+name+'_pr.timing'),td_log:{file:base+prefix+log,sha256:sha(base+prefix+log)}};
}
const a=physical('a','MEDIA_IMAGE_A_R3_HW_20261005',process.argv[2]||'');
const b=physical('b','MEDIA_SOURCE_B_R2_HW_20261005','td_20261005_132323.log');
const sources=[
    'rtl/hw_20261005/audio_receipt_hw.v','rtl/hw_20261005/remote_audio_compute_hw.v',
    'rtl/hw_round2_20261005/home_index_stream_hw.v','rtl/hw_round3_20261005/top_dual_image_hw.v',
    'rtl/hw_round3_20261005/frame_read_write_hw.v','constraints/media_a.adc','constraints/media_a.sdc',
    'constraints/media_b.adc','constraints/media_b.sdc',
    'prj/media_a/MEDIA_IMAGE_A_R3_HW_20261005.al','prj/media_a/build_round3_a_seed3.tcl',
    'prj/media_b/MEDIA_SOURCE_B_R2_HW_20261005.al','prj/media_b/build_round2_b.tcl',
    'sim/tb_player_pipeline_guard.v','sim/tb_player_frame_reset.v','sim/tb_player_frame_credit.v',
    'sim/run_player_pipeline.ps1','sim/run_player_round3.ps1','sim/run_player_round3.do',
    'sim/hw_round2_20261005/run_home_modelsim.do'
].map(file=>({file:base+file,sha256:sha(base+file)}));
const result={stage:'formal-player physical pipeline audit',generatedAt:new Date().toISOString(),
    original_single_board_and_diagnostic_bits_unchanged:true,production_phase10_unchanged:true,
    hardware_verified:false,published_player_bits:[],modelsim:{audio_pipeline_full_40:full,
        audio_full_rate_guard:guard,memory_reset_and_home_pipeline:round3},board_a:a,board_b:b,
    source_manifest:sources,
    timing_closed:!!(a.timing&&b.timing&&a.timing.closed&&b.timing.closed),
    caveats:['No complete physical PHY/HDMI/SDRAM simulation or board-player verification.',
        'Only asynchronous PHY RX and audio clock groups are cut; related pixel/UDP/SDRAM clocks remain timed.',
        'External IO delay specification audit remains incomplete; coverage is not full constraint certification.',
        'Negative timing candidates are not automatically bit-generated.',
        '40 tests cover audio pipeline; 7 additional tests cover later memory/home changes, not a new full 40 on that exact top.']};
const output=path.join(root,base+'phase11_pipeline_validation_20261005.json');
fs.writeFileSync(output,JSON.stringify(result,null,2)+'\n');
console.log(JSON.stringify({file:output,a_lut:(a.routed||a.gate).lut,a_area_stage:a.routed?'routed':'gate only',
    a_routing_completed:a.routing_completed,b_lut:(b.routed||b.gate).lut,timing_closed:result.timing_closed,
    audio_tests:full.passed.length,additional_tests:guard.passed.length+round3.passed.length,player_bits:[]},null,2));
