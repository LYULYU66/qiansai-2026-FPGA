// Freeze only the completely validated final fixed-peer candidate. Earlier
// phase logs/reports remain untouched. Run after ModelSim Suite All finishes.
const fs=require('fs'),path=require('path'),crypto=require('crypto');
const root=path.resolve(__dirname,'../../../');
const prefix='dual_board/image_link/';
const read=f=>fs.readFileSync(path.join(root,f),'utf8');
const sha=f=>crypto.createHash('sha256').update(fs.readFileSync(path.join(root,f))).digest('hex').toUpperCase();
const previous=JSON.parse(read(prefix+'phase9_validation_20261004.json'));
const additions=['PASS fixed UDP unit','PASS fixed UDP pair',
    'PASS fixed UDP native FIFO padded','PASS fixed UDP native FIFO stripped',
    'PASS fixed UDP audio offload','PASS fixed UDP media restart'];
const passed=previous.passed.concat(additions);
const logFile=prefix+'sim/modelsim_regression.log',log=read(logFile);
for(const marker of passed)if(!log.includes(marker))throw Error('Missing '+marker);
if(passed.length!==40 || /Errors: [1-9]|\*\* (Fatal|Error):/.test(log) ||
   !/Errors: 0, Warnings: \d+\s*(?:#\s*quit -code 0\s*)?$/.test(log))
    throw Error('Incomplete/failed final 40-case regression');
const baseline=[['src/user_source/hdl_source/top_tf_hdmi_audio.v','561394111CB599D811AA3408B25C6AABCC420D32111BC03D3B3EE87AB2D8E0E8'],
    ['best_result/lab_ex5_i2s_v1.0_logic_round3_20261003.bit','94744392DEC4010D38261036AB360AB6E01BC4C718B34167E821302A15297C88']];
for(const [file,hash]of baseline)if(sha(file)!==hash)throw Error('Single-board baseline changed '+file);
function walk(dir){return fs.readdirSync(dir,{withFileTypes:true}).flatMap(e=>e.isDirectory()?walk(path.join(dir,e.name)):[path.join(dir,e.name)]);}
const oldDir=path.join(root,prefix+'backup_phase9_fixed_udp/rtl');
const oldFiles=walk(oldDir).map(f=>path.relative(oldDir,f).replaceAll('\\','/'));
const newFiles=walk(path.join(root,prefix+'rtl')).map(f=>path.relative(path.join(root,prefix+'rtl'),f).replaceAll('\\','/'));
const modified=oldFiles.filter(f=>sha(prefix+'rtl/'+f)!==sha(prefix+'backup_phase9_fixed_udp/rtl/'+f)).sort();
const added=newFiles.filter(f=>!oldFiles.includes(f)).sort();
if(JSON.stringify(modified)!==JSON.stringify(['dual_board_eth_transport.v','image_media_board_b.v','top_dual_image.v']) ||
   JSON.stringify(added)!==JSON.stringify(['fixed_peer_udp.v']))throw Error('Unexpected production changes '+modified+' / '+added);
for(const [dir,name]of [['media_a','MEDIA_IMAGE_A.al'],['media_b','MEDIA_SOURCE_B.al']]){
    const current=read(prefix+'prj/'+dir+'/'+name).replaceAll('\r','');
    const old=read(prefix+'backup_phase9_fixed_udp/'+name).replaceAll('\r','');
    const cleaned=current.replace(/^.*<File Path="\.\.\/\.\.\/rtl\/fixed_peer_udp\.v">.*<\/File>\n/m,'');
    if(cleaned!==old)throw Error('Unexpected project change '+name);
}
function area(file){
    const stats={};
    for(const [key,name]of Object.entries({lut:'lut',reg:'registers',bram9k:'bram9k',bram32k:'bram32k',dsp:'dsp',pll:'pll'})){
        const match=read(file).match(new RegExp('^\\s*#'+key+'\\s+(\\d+)','m'));
        if(!match)throw Error('Missing resource '+key);stats[name]=Number(match[1]);
    }return stats;
}
const a=prefix+'prj/media_a/MEDIA_IMAGE_A_gate.area',b=prefix+'prj/media_b/MEDIA_SOURCE_B_gate.area';
const aStats=area(a),bStats=area(b);
if(aStats.lut!==13453 || bStats.lut!==10932)throw Error('Reports differ from final measured candidate');
for(const key of ['bram32k','dsp','pll'])
    if(aStats[key]!==previous.board_a[key]||bStats[key]!==previous.board_b[key])throw Error('Unexpected hard resource change '+key);
if(aStats.bram9k!==previous.board_a.bram9k+1 || bStats.bram9k!==previous.board_b.bram9k+1)
    throw Error('Unexpected packet RAM cost');
for(const file of [a,b]){
    const text=read(file);
    if(!text.includes('fixed_peer_udp') || text.includes('|udp_ip_protocol_stack'))throw Error('Endpoint hierarchy differs '+file);
    if(/udp_ip_protocol_stack\s*\|/.test(text))throw Error('Legacy stack was not trimmed '+file);
}
const buildLogs=['media_a','media_b'].map(dir=>{
    const folder=prefix+'prj/'+dir+'/';
    const name=fs.readdirSync(path.join(root,folder)).filter(f=>/^td_\d{8}_\d{6}\.log$/.test(f)).sort().pop();
    if(!name)throw Error('No build log '+dir);
    const log=read(folder+name);
    if(/\bERROR\b/.test(log)||!log.includes('finish command "optimize_gate'))throw Error('Build failed '+name);
    return folder+name;
});
const copies=[[a,prefix+'prj/media_a/MEDIA_IMAGE_A_fixed_udp_20261004_gate.area'],
    [b,prefix+'prj/media_b/MEDIA_SOURCE_B_fixed_udp_20261004_gate.area'],
    [logFile,prefix+'sim/phase10_final_modelsim_20261004.log']];
for(const [from,to]of copies)fs.copyFileSync(path.join(root,from),path.join(root,to));
const files=walk(path.join(root,prefix+'rtl')).filter(f=>/\.(v|json)$/.test(f))
    .concat(walk(path.join(root,prefix+'sim')).filter(f=>/(tb_.*\.v|fixed_udp_.*\.v|run_.*\.(do|ps1)|snapshot_fixed_udp_validation\.js)$/.test(path.basename(f))))
    .map(f=>path.relative(root,f).replaceAll('\\','/'));
files.push(a,b,logFile,...buildLogs,...copies.map(([,f])=>f),prefix+'phase10_fixed_udp_20261004.md',prefix+'README.md',
    prefix+'prj/media_a/MEDIA_IMAGE_A.al',prefix+'prj/media_b/MEDIA_SOURCE_B.al',...baseline.map(([f])=>f),
    'dual_board/ethernet_smoke/source_code/rtl/udp_ip_protocol_stack_merge.enc.v',
    'dual_board/ethernet_smoke/source_code/rtl/tx_client_fifo.v',
    'dual_board/ethernet_smoke/source_code/rtl/rx_client_fifo.v',
    'dual_board/ethernet_smoke/source_code/rtl/temac_block.v');
const result={phase:10,date:'2026-10-05',generatedAt:new Date().toISOString(),modelsim:'Starter 10.5b',
    final_candidate_full_regression_rerun:true,cases_passed:40,new_cases:6,passed,
    simulation_errors:0,simulation_warnings:(log.match(/\*\* Warning:/g)||[]).length,
    warning_note:'Existing optional legacy test ports/native PCM RAM outputs and unsized constants in unchanged native MAC FIFO RTL; fixed UDP unit/pair has zero warnings. No encrypted TEMAC/PHY or physical timing simulation.',
    board_a:aStats,board_b:bStats,resource_stage:'gate synthesis, not placed/routed',rom_initialization:'gate eram_init on',
    lut_saved:{a:previous.board_a.lut-aStats.lut,b:previous.board_b.lut-bStats.lut,total:previous.board_a.lut+previous.board_b.lut-aStats.lut-bStats.lut},
    registers_saved:{a:previous.board_a.registers-aStats.registers,b:previous.board_b.registers-bStats.registers},
    total_lut:aStats.lut+bStats.lut,total_vs_one_board_percent:(aStats.lut+bStats.lut)/19600*100,
    protocols:['IMG4','AUD2','AAK3','VIZ2','CTL2','LNK1'],
    fixed_peers:{a:{ip:'192.168.10.11',mac:'02:00:00:00:00:0b',max_tx:18,max_rx:1042},
        b:{ip:'192.168.10.12',mac:'02:00:00:00:00:0c',max_tx:1042,max_rx:18},udp_port:20482},
    udp_checksum_policy:'Transmit IPv4 UDP checksum zero; explicitly reject nonzero UDP checksum. Validate IPv4 header checksum and existing application CRCs.',
    ethernet_padding_policy:'Transmit minimum 60 bytes excluding FCS; receive exact unpadded or exact minimum-padded frame. Intermediate or excess tails rejected.',
    modified_production_rtl:modified,added_production_rtl:added,single_board_unchanged:true,
    formal_project_only_added_fixed_udp_source:true,encrypted_udp_mac_modified:false,physical_constraints_changed:false,
    arp_icmp_removed_from_formal_players:true,legacy_smoke_udp_default_retained:true,
    player_bit_generated:false,placed_and_routed:false,timing_closed:false,hardware_validated:false,
    test_limitations:'Decoded media/component fixtures, independent packet oracle and actual native FIFO RTL with test-only synchronous dual-port RAM/MAC relay. No real TF/FAT source in integrated playback, encrypted TEMAC, FCS, wire/PHY, real SDRAM/HDMI, continuous line-rate FIFO overflow, or lossless peer cold-reset authentication validation.',
    next_required_work:'Complete isolated formal A/B pin/timing constraints, then place/route and timing checks; generate paired player bits only afterward; actual cable/static image/PCM/hazard/UART/visual/lyrics/restart checks still required.',
    files:[...new Set(files)].sort().map(file=>({file,sha256:sha(file)}))};
fs.writeFileSync(path.join(root,prefix+'phase10_validation_20261004.json'),JSON.stringify(result,null,2)+'\n');
console.log(JSON.stringify({cases:40,warnings:result.simulation_warnings,board_a:aStats,board_b:bStats,
    lut_saved:result.lut_saved,total_lut:result.total_lut,single_board_unchanged:true},null,2));
