// Audit the final scheduler candidate without overwriting earlier phases.
const fs=require('fs'),path=require('path'),crypto=require('crypto');
const root=path.resolve(__dirname,'../../../');
const prefix='dual_board/image_link/';
const read=f=>fs.readFileSync(path.join(root,f),'utf8');
const sha=f=>crypto.createHash('sha256').update(fs.readFileSync(path.join(root,f))).digest('hex').toUpperCase();
const previous=JSON.parse(read(prefix+'phase8_validation_20261004.json'));
const additions=['PASS flat scheduler A','PASS flat scheduler B','PASS flat audio offload','PASS flat media restart'];
const full=prefix+'sim/phase9_candidate_crc_modelsim_20261004.log';
const final=prefix+'sim/modelsim_netopt.log';
for(const [file,cases]of [[full,previous.passed.concat(additions)],[final,additions]]){
    const log=read(file);
    for(const marker of cases)if(!log.includes(marker))throw Error(file+': missing '+marker);
    if(/Errors: [1-9]|\*\* (Fatal|Error):/.test(log)||
       !/Errors: 0, Warnings: \d+\s*(?:#\s*quit -code 0\s*)?$/.test(log))throw Error('Failed/incomplete '+file);
}
const baseline=[['src/user_source/hdl_source/top_tf_hdmi_audio.v','561394111CB599D811AA3408B25C6AABCC420D32111BC03D3B3EE87AB2D8E0E8'],
    ['best_result/lab_ex5_i2s_v1.0_logic_round3_20261003.bit','94744392DEC4010D38261036AB360AB6E01BC4C718B34167E821302A15297C88']];
for(const [file,hash]of baseline)if(sha(file)!==hash)throw Error('Single board changed '+file);
function walk(dir){return fs.readdirSync(dir,{withFileTypes:true}).flatMap(e=>e.isDirectory()?walk(path.join(dir,e.name)):[path.join(dir,e.name)]);}
const oldDir=path.join(root,prefix,'backup_phase8_netopt/rtl');
const modified=walk(oldDir).map(f=>path.relative(oldDir,f).replaceAll('\\','/'))
    .filter(f=>sha(prefix+'rtl/'+f)!==sha(prefix+'backup_phase8_netopt/rtl/'+f)).sort();
const expected=['image_media_board_b.v','media_udp_arbiter.v','top_dual_image.v'];
if(JSON.stringify(modified)!==JSON.stringify(expected))throw Error('Unexpected production RTL changes: '+modified.join(','));
if(read(prefix+'rtl/media_udp_arbiter.v').split('endmodule')[0].replaceAll('\r','')!==
   read(prefix+'backup_phase8_netopt/rtl/media_udp_arbiter.v').split('endmodule')[0].replaceAll('\r',''))throw Error('Legacy arbiter changed');
for(const [dir,name]of [['media_a','MEDIA_IMAGE_A.al'],['media_b','MEDIA_SOURCE_B.al']])
    if(sha(prefix+'prj/'+dir+'/'+name)!==sha(prefix+'backup_phase8_netopt/'+name))throw Error('Project source list changed '+name);
function area(file){
    const stats={};
    for(const [key,name]of Object.entries({lut:'lut',reg:'registers',bram9k:'bram9k',bram32k:'bram32k',dsp:'dsp',pll:'pll'})){
        const match=read(file).match(new RegExp('^\\s*#'+key+'\\s+(\\d+)','m'));
        if(!match)throw Error('Missing resource '+key);stats[name]=Number(match[1]);
    }return stats;
}
const a=prefix+'prj/media_a/MEDIA_IMAGE_A_gate.area',b=prefix+'prj/media_b/MEDIA_SOURCE_B_gate.area';
const aStats=area(a),bStats=area(b);
if(aStats.lut!==15799 || bStats.lut!==13261)throw Error('Final candidate report differs');
for(const key of ['bram9k','bram32k','dsp','pll'])
    if(aStats[key]!==previous.board_a[key]||bStats[key]!==previous.board_b[key])throw Error('Hard resources changed '+key);
const buildLogs=['media_a','media_b'].map(dir=>{
    const folder=prefix+'prj/'+dir+'/';
    const name=fs.readdirSync(path.join(root,folder)).filter(f=>/^td_20261004_.*\.log$/.test(f)).sort().pop();
    if(!name)throw Error('No build log '+dir);
    const log=read(folder+name);
    if(/\bERROR\b/.test(log)||!log.includes('finish command "optimize_gate'))throw Error('Build failed '+name);
    return folder+name;
});
const copies=[[a,prefix+'prj/media_a/MEDIA_IMAGE_A_netopt_20261004_gate.area'],
    [b,prefix+'prj/media_b/MEDIA_SOURCE_B_netopt_20261004_gate.area'],
    [final,prefix+'sim/phase9_final_netopt_20261004.log']];
for(const [from,to]of copies)fs.copyFileSync(path.join(root,from),path.join(root,to));
const files=walk(path.join(root,prefix+'rtl')).filter(f=>/\.(v|json)$/.test(f))
    .concat(walk(path.join(root,prefix+'sim')).filter(f=>/(tb_.*\.v|run_.*\.(do|ps1)|snapshot_netopt_validation\.js)$/.test(path.basename(f))))
    .map(f=>path.relative(root,f).replaceAll('\\','/'));
files.push(a,b,full,final,...buildLogs,...copies.map(([,f])=>f),prefix+'phase9_network_scheduler_20261004.md',
    prefix+'prj/media_a/MEDIA_IMAGE_A.al',prefix+'prj/media_b/MEDIA_SOURCE_B.al',...baseline.map(([f])=>f));
const result={phase:9,date:'2026-10-04',generatedAt:new Date().toISOString(),modelsim:'Starter 10.5b',
    original_unchanged_cases_passed:previous.passed.length,full_regression_with_crc_expression_candidate_passed:34,
    final_candidate_targeted_cases_passed:4,final_candidate_full_regression_rerun:false,
    full_regression_warnings:(read(full).match(/\*\* Warning:/g)||[]).length,
    final_candidate_warnings:(read(final).match(/\*\* Warning:/g)||[]).length,simulation_errors:0,
    passed:previous.passed.concat(additions),
    validation_note:'The complete 34-case run used the equivalent explicit payload-CRC expression for the new scheduler. The final lower-LUT candidate was recompiled and independently passed all four new scheduler/media tests afterward. The legacy two-channel arbiter and its original 30 component tests were not changed.',
    board_a:aStats,board_b:bStats,resource_stage:'gate synthesis, not placed/routed',rom_initialization:'gate eram_init on',
    lut_saved:{a:previous.board_a.lut-aStats.lut,b:previous.board_b.lut-bStats.lut,total:previous.board_a.lut+previous.board_b.lut-aStats.lut-bStats.lut},
    total_lut:aStats.lut+bStats.lut,total_vs_one_board_percent:(aStats.lut+bStats.lut)/19600*100,
    protocols:['IMG4','AUD2','AAK3','VIZ2','CTL2','LNK1'],
    modified_production_rtl:modified,legacy_arbiter_unchanged:true,single_board_unchanged:true,project_lists_unchanged:true,
    arp_icmp_removed:false,encrypted_udp_mac_modified:false,physical_constraints_changed:false,
    player_bit_generated:false,placed_and_routed:false,timing_closed:false,hardware_validated:false,
    next_required_work:'A significant further reduction needs a separately validated fixed-peer IPv4/UDP endpoint replacing the opaque general UDP stack. Formal A/B pin/timing constraints and place/route remain incomplete.',
    files:[...new Set(files)].sort().map(file=>({file,sha256:sha(file)}))};
fs.writeFileSync(path.join(root,prefix+'phase9_validation_20261004.json'),JSON.stringify(result,null,2)+'\n');
console.log(JSON.stringify({full_cases:34,final_candidate_cases:4,warnings:result.final_candidate_warnings,
    board_a:aStats,board_b:bStats,lut_saved:result.lut_saved,single_board_unchanged:true},null,2));
