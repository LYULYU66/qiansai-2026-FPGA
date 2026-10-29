// Generated validation artifacts only. Do not overwrite earlier phase records.
const fs=require('fs'),path=require('path'),crypto=require('crypto');
const root=path.resolve(__dirname,'../../../'),phase=path.join(root,'dual_board/image_link');
const sha=f=>crypto.createHash('sha256').update(fs.readFileSync(path.join(root,f))).digest('hex').toUpperCase();
const read=f=>fs.readFileSync(path.join(root,f),'utf8');
const required=['PASS image_packet_rx','PASS image link TX/RX','PASS image pixel CDC','PASS reliable image',
    'PASS image sink guard','PASS remote display','PASS audio guard','PASS media abort','PASS audio media',
    'PASS audio status','PASS visual guard','PASS remote compute','PASS audio offload',
    'PASS home atlas','PASS home pixels','PASS tagged image','PASS home pipeline','PASS home source',
    'PASS media control','PASS control guard','PASS resolution image','PASS resolution guard','PASS resolution display',
    'PASS link session','PASS media generation','PASS cache recovery','PASS audio session reset'];
const full='dual_board/image_link/sim/modelsim_regression.log',link='dual_board/image_link/sim/modelsim_link.log';
for(const [file,cases]of [[full,required],[link,required.slice(-4)]]){
    const log=read(file);
    for(const expected of cases)if(!log.includes(expected))throw Error(file+': missing '+expected);
    // Nested do files may exit without echoing their final quit command.
    // Require every case plus a clean final simulator completion summary.
    if(/Errors: [1-9]|\*\* (Fatal|Error):/.test(log)||
       !/Errors: 0, Warnings: \d+\s*(?:#\s*quit -code 0\s*)?$/.test(log))
        throw Error('Failed/incomplete simulation '+file);
}
const baseline=[['src/user_source/hdl_source/top_tf_hdmi_audio.v','561394111CB599D811AA3408B25C6AABCC420D32111BC03D3B3EE87AB2D8E0E8'],
    ['best_result/lab_ex5_i2s_v1.0_logic_round3_20261003.bit','94744392DEC4010D38261036AB360AB6E01BC4C718B34167E821302A15297C88']];
for(const [file,hash]of baseline)if(sha(file)!==hash)throw Error('Single-board baseline changed '+file);
function area(file){
    const result={};
    for(const [key,name]of Object.entries({lut:'lut',reg:'registers',bram9k:'bram9k',bram32k:'bram32k',dsp:'dsp',pll:'pll'})){
        const found=read(file).match(new RegExp('^\\s*#'+key+'\\s+(\\d+)','m'));
        if(!found)throw Error('Missing '+key);result[name]=Number(found[1]);
    }return result;
}
const a='dual_board/image_link/prj/media_a/MEDIA_IMAGE_A_gate.area',b='dual_board/image_link/prj/media_b/MEDIA_SOURCE_B_gate.area';
const buildLogs=['media_a','media_b'].map(dir=>{
    const prefix='dual_board/image_link/prj/'+dir+'/';
    const file=fs.readdirSync(path.join(root,prefix)).filter(f=>/^td_20261004_.*\.log$/.test(f)).sort().pop();
    if(!file)throw Error('No build log '+dir);
    const log=read(prefix+file);
    if(/\bERROR\b/.test(log)||!log.includes('finish command "optimize_gate'))throw Error('Synthesis failed '+file);
    return prefix+file;
});
const copies=[[a,'prj/media_a/MEDIA_IMAGE_A_session_recovery_20261004_gate.area'],
    [b,'prj/media_b/MEDIA_SOURCE_B_session_recovery_20261004_gate.area'],
    [full,'sim/phase7_modelsim_20261004.log'],[link,'sim/phase7_link_20261004.log']];
for(const [source,target]of copies)fs.copyFileSync(path.join(root,source),path.join(phase,target));
function walk(dir){return fs.readdirSync(dir,{withFileTypes:true}).flatMap(e=>e.isDirectory()?walk(path.join(dir,e.name)):[path.join(dir,e.name)]);}
const files=walk(path.join(phase,'rtl')).filter(f=>/\.(v|json)$/.test(f))
    .concat(walk(path.join(phase,'sim')).filter(f=>/\/(tb_.*\.v|run_.*\.(do|ps1)|snapshot_link_validation\.js)$/.test(f.replaceAll('\\','/'))))
    .map(f=>path.relative(root,f).replaceAll('\\','/'));
files.push(a,b,full,link,...buildLogs,...copies.map(([,t])=>'dual_board/image_link/'+t),
    'dual_board/image_link/prj/media_a/MEDIA_IMAGE_A.al','dual_board/image_link/prj/media_b/MEDIA_SOURCE_B.al',
    'dual_board/image_link/README.md','dual_board/image_link/phase7_session_recovery_20261004.md',...baseline.map(([f])=>f));
const previous=JSON.parse(read('dual_board/image_link/phase6_validation_20261004.json'));
const aArea=area(a),bArea=area(b);
const result={phase:7,date:'2026-10-04',generatedAt:new Date().toISOString(),modelsim:'Starter 10.5b',
    simulation_cases_passed:required.length,latest_link_cases_passed:4,simulation_errors:0,
    simulation_warnings:(read(full).match(/\*\* Warning:/g)||[]).length,
    latest_link_warnings:(read(link).match(/\*\* Warning:/g)||[]).length,passed:required,
    resource_stage:'gate synthesis, not placed/routed',rom_initialization:'gate eram_init on',
    board_a:aArea,board_b:bArea,delta_lut_vs_phase6:{a:aArea.lut-previous.board_a.lut,b:bArea.lut-previous.board_b.lut},
    protocols:['IMG4','AUD2','AAK3','VIZ2','CTL2','LNK1'],single_board_unchanged:true,
    handshake_recovery_simulated:true,stale_media_generation_rejected:true,committed_cache_survives_lease_change:true,
    complete_independent_B_media_restart:false,
    next_required_work:'Verify/reuse identical protected images without writing active SDRAM; different-content recovery also needs safe handling.',
    session_persistence:'Volatile 16-bit lease; not security authentication or replay protection across both cold resets/wrap.',
    player_bit_generated:false,placed_and_routed:false,timing_closed:false,hardware_validated:false,
    files:[...new Set(files)].sort().map(file=>({file,sha256:sha(file)}))};
fs.writeFileSync(path.join(phase,'phase7_validation_20261004.json'),JSON.stringify(result,null,2)+'\n');
console.log(JSON.stringify({cases:result.simulation_cases_passed,warnings:result.simulation_warnings,link_warnings:result.latest_link_warnings,
    board_a:aArea,board_b:bArea,delta:result.delta_lut_vs_phase6,single_board_unchanged:true,complete_media_restart:false},null,2));
