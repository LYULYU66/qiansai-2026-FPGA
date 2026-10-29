// Mechanically capture this phase's checked artifacts; never rewrite phase 5.
const fs=require('fs'),path=require('path'),crypto=require('crypto');
const root=path.resolve(__dirname,'../../../');
const phase=path.join(root,'dual_board/image_link');
const sha=file=>crypto.createHash('sha256').update(fs.readFileSync(path.join(root,file))).digest('hex').toUpperCase();
const logFile='dual_board/image_link/sim/modelsim_regression.log';
const log=fs.readFileSync(path.join(root,logFile),'utf8');
const controlLogFile='dual_board/image_link/sim/modelsim_control.log';
const controlLog=fs.readFileSync(path.join(root,controlLogFile),'utf8');
const required=['PASS image_packet_rx','PASS image link TX/RX','PASS image pixel CDC','PASS reliable image',
    'PASS image sink guard','PASS remote display','PASS audio guard','PASS media abort','PASS audio media',
    'PASS audio status','PASS visual guard','PASS remote compute','PASS audio offload',
    'PASS home atlas','PASS home pixels','PASS tagged image','PASS home pipeline','PASS home source',
    'PASS media control','PASS control guard','PASS resolution image','PASS resolution guard','PASS resolution display'];
for(const result of required)if(!log.includes(result))throw Error('Missing '+result);
if(/Errors: [1-9]|\*\* (Fatal|Error):/.test(log))throw Error('Regression contains errors');
for(const result of required.slice(-5))if(!controlLog.includes(result))throw Error('Missing latest '+result);
if(/Errors: [1-9]|\*\* (Fatal|Error):/.test(controlLog)||!controlLog.includes('fast invalidation and abort retention'))
    throw Error('Latest control/invalidation regression not passed');
const baseline=[['src/user_source/hdl_source/top_tf_hdmi_audio.v','561394111CB599D811AA3408B25C6AABCC420D32111BC03D3B3EE87AB2D8E0E8'],
    ['best_result/lab_ex5_i2s_v1.0_logic_round3_20261003.bit','94744392DEC4010D38261036AB360AB6E01BC4C718B34167E821302A15297C88']];
for(const [file,expected]of baseline)if(sha(file)!==expected)throw Error('Single-board baseline changed: '+file);
// Check the SD wrapper has no accidental implementation edits.
const original=fs.readFileSync(path.join(root,'src/user_source/hdl_source/SD/sd_card_bmp.v'),'utf8').replaceAll('\r\n','\n');
const remote=fs.readFileSync(path.join(phase,'rtl/sd_card_bmp_remote.v'),'utf8').replaceAll('\r\n','\n')
    .replace('// Isolated copy of the single-board wrapper: only expose live BMP metadata.\n// Its SD/FAT/PCM/resample implementation is otherwise unchanged.\n','')
    .replace('module sd_card_bmp_remote #(','module sd_card_bmp #(')
    .replace('    output [31:0]              live_source_resolution,\n','')
    .replace('assign live_source_resolution={source_width,source_height};\n','');
if(remote!==original)throw Error('Unexpected SD implementation difference');
function area(file){
    const text=fs.readFileSync(path.join(root,file),'utf8'),result={};
    for(const [key,name]of Object.entries({lut:'lut',reg:'registers',bram9k:'bram9k',bram32k:'bram32k',dsp:'dsp',pll:'pll'})){
        const found=text.match(new RegExp('^\\s*#'+key+'\\s+(\\d+)','m'));
        if(!found)throw Error('Missing area field '+key);result[name]=Number(found[1]);
    }return result;
}
const a='dual_board/image_link/prj/media_a/MEDIA_IMAGE_A_gate.area',b='dual_board/image_link/prj/media_b/MEDIA_SOURCE_B_gate.area';
const aLog=fs.readdirSync(path.join(phase,'prj/media_a')).filter(f=>/^td_20261004_.*\.log$/.test(f))
    .sort().map(f=>'dual_board/image_link/prj/media_a/'+f).pop();
const bLog='dual_board/image_link/prj/media_b/td_20261004_164345.log';
for(const file of [aLog,bLog]){
    const text=fs.readFileSync(path.join(root,file),'utf8');
    if(/\bERROR\b/.test(text)||!text.includes('finish command "optimize_gate'))throw Error('Synthesis failed: '+file);
}
const copies=[[a,'prj/media_a/MEDIA_IMAGE_A_control_resolution_20261004_gate.area'],
    [b,'prj/media_b/MEDIA_SOURCE_B_control_resolution_20261004_gate.area'],
    [logFile,'sim/phase6_modelsim_20261004.log'],[controlLogFile,'sim/phase6_control_20261004.log']];
for(const [source,target]of copies)fs.copyFileSync(path.join(root,source),path.join(phase,target));
function walk(dir){return fs.readdirSync(dir,{withFileTypes:true}).flatMap(e=>e.isDirectory()?walk(path.join(dir,e.name)):[path.join(dir,e.name)]);}
const files=walk(path.join(phase,'rtl')).filter(f=>/\.(v|json)$/.test(f))
    .concat(walk(path.join(phase,'sim')).filter(f=>/\/(tb_.*\.v|run_.*\.(do|ps1)|snapshot_control_validation\.js)$/.test(f.replaceAll('\\','/'))))
    .map(f=>path.relative(root,f).replaceAll('\\','/'));
files.push(a,b,aLog,bLog,logFile,controlLogFile,...copies.map(([,t])=>'dual_board/image_link/'+t),
    'dual_board/image_link/prj/media_a/MEDIA_IMAGE_A.al','dual_board/image_link/prj/media_b/MEDIA_SOURCE_B.al',
    'dual_board/image_link/prj/media_a/build_gate.tcl','dual_board/image_link/prj/media_b/build_gate.tcl',
    'dual_board/image_link/constraints/board_b.adc','src/user_source/hdl_source/SD/sd_card_bmp.v',...baseline.map(([f])=>f));
const previous=JSON.parse(fs.readFileSync(path.join(phase,'phase5_validation_20261004.json'),'utf8'));
const aArea=area(a),bArea=area(b);
const result={phase:6,date:'2026-10-04',generatedAt:new Date().toISOString(),modelsim:'Starter 10.5b',
    simulation_cases_passed:required.length,latest_control_cases_passed:5,simulation_errors:0,
    simulation_warnings:(log.match(/\*\* Warning:/g)||[]).length,latest_control_warnings:(controlLog.match(/\*\* Warning:/g)||[]).length,
    warning_note:'Original FIFO unused ports and legacy UI_TAG/RESOLUTION=0 tests with unused new ports; no warning suppression.',
    passed:required,resource_stage:'gate synthesis, not placed/routed',rom_initialization:'gate eram_init on',
    board_a:aArea,board_b:bArea,delta_lut_vs_phase5:{a:aArea.lut-previous.board_a.lut,b:bArea.lut-previous.board_b.lut},
    control_reply_semantics:'OK and STATUS acknowledge/report B desired settings, not an A execution ACK',
    protocols:['IMG4','AUD2','AAK3','VIZ2','CTL2'],single_board_unchanged:true,sd_wrapper_implementation_unchanged:true,
    player_bit_generated:false,placed_and_routed:false,timing_closed:false,hardware_validated:false,
    files:[...new Set(files)].sort().map(file=>({file,sha256:sha(file)}))};
fs.writeFileSync(path.join(phase,'phase6_validation_20261004.json'),JSON.stringify(result,null,2)+'\n');
console.log(JSON.stringify({cases:required.length,warnings:result.simulation_warnings,board_a:aArea,board_b:bArea,
    delta:result.delta_lut_vs_phase5,single_board_unchanged:true,sd_wrapper_implementation_unchanged:true},null,2));
