// Capture checked results, rather than a hand-written list of claimed passes.
const fs=require('fs'),path=require('path'),crypto=require('crypto');
const root=path.resolve(__dirname,'../../../');
const phase=path.join(root,'dual_board/image_link');
const sha=file=>crypto.createHash('sha256').update(fs.readFileSync(path.join(root,file))).digest('hex').toUpperCase();
const logFile='dual_board/image_link/sim/modelsim_regression.log';
const log=fs.readFileSync(path.join(root,logFile),'utf8');
const required=['PASS image_packet_rx','PASS image link TX/RX','PASS image pixel CDC','PASS reliable image',
    'PASS image sink guard','PASS remote display','PASS audio guard','PASS media abort','PASS audio media',
    'PASS audio status','PASS visual guard','PASS remote compute','PASS audio offload',
    'PASS home atlas','PASS home pixels','PASS tagged image','PASS home pipeline','PASS home source'];
for(const result of required) if(!log.includes(result)) throw Error('Missing '+result);
if(/Errors: [1-9]|\*\* (Fatal|Error):/.test(log)) throw Error('Regression contains errors');
const single=[['src/user_source/hdl_source/top_tf_hdmi_audio.v','561394111CB599D811AA3408B25C6AABCC420D32111BC03D3B3EE87AB2D8E0E8'],
    ['best_result/lab_ex5_i2s_v1.0_logic_round3_20261003.bit','94744392DEC4010D38261036AB360AB6E01BC4C718B34167E821302A15297C88']];
for(const [file,expected] of single) if(sha(file)!==expected) throw Error('Single-board baseline changed: '+file);
function area(file){
    const text=fs.readFileSync(path.join(root,file),'utf8'), result={};
    for(const [key,name] of Object.entries({lut:'lut',reg:'registers',bram9k:'bram9k',bram32k:'bram32k',dsp:'dsp',pll:'pll'})) {
        const found=text.match(new RegExp('^\\s*#'+key+'\\s+(\\d+)','m'));
        if(!found) throw Error('Missing area field '+key); result[name]=Number(found[1]);
    }
    return result;
}
const a='dual_board/image_link/prj/media_a/MEDIA_IMAGE_A_gate.area';
const b='dual_board/image_link/prj/media_b/MEDIA_SOURCE_B_gate.area';
for(const [source,target] of [[a,'prj/media_a/MEDIA_IMAGE_A_home_offload_20261004_gate.area'],
    [b,'prj/media_b/MEDIA_SOURCE_B_home_offload_20261004_gate.area']])
    fs.copyFileSync(path.join(root,source),path.join(phase,target));
function walk(dir){return fs.readdirSync(dir,{withFileTypes:true}).flatMap(e=>e.isDirectory()?walk(path.join(dir,e.name)):[path.join(dir,e.name)]);}
const files=walk(path.join(phase,'rtl')).filter(f=>/\.(v|json)$/.test(f))
    .concat(walk(path.join(phase,'sim')).filter(f=>/\/(tb_home_.*\.v|tb_image_reliable\.v|tb_audio_offload\.v|run_.*\.(do|ps1)|generate_home_atlas\.js)$/.test(f.replaceAll('\\','/'))))
    .map(f=>path.relative(root,f).replaceAll('\\','/'));
files.push(a,b,logFile,'dual_board/image_link/prj/media_a/MEDIA_IMAGE_A.al',
    'dual_board/image_link/prj/media_b/MEDIA_SOURCE_B.al',
    'dual_board/image_link/prj/media_a/td_20261004_161049.log',
    'dual_board/image_link/prj/media_b/td_20261004_155854.log',...single.map(([f])=>f));
const result={phase:5,date:'2026-10-04',generatedAt:new Date().toISOString(),
    modelsim:'Starter 10.5b',simulation_cases_passed:required.length,simulation_errors:0,
    simulation_warnings:(log.match(/\*\* Warning:/g)||[]).length,
    warning_note:'Original FIFO unused ports and unused tag ports in legacy UI_TAG=0 tests; no warning suppression.',
    passed:required,resource_stage:'gate synthesis, not placed/routed',rom_initialization:'gate eram_init on',
    board_a:area(a),board_b:area(b),atlas:JSON.parse(fs.readFileSync(path.join(phase,'rtl/home_assets/home_atlas_manifest.json'),'utf8')),
    player_bit_generated:false,placed_and_routed:false,timing_closed:false,hardware_validated:false,
    files:[...new Set(files)].sort().map(file=>({file,sha256:sha(file)}))};
fs.writeFileSync(path.join(phase,'phase5_validation_20261004.json'),JSON.stringify(result,null,2)+'\n');
console.log(JSON.stringify({cases:result.simulation_cases_passed,warnings:result.simulation_warnings,
    board_a:result.board_a,board_b:result.board_b,single_board_unchanged:true},null,2));
