// Validate the FINAL paired diagnostic bits; never certify real hardware here.
const fs=require('fs'),path=require('path'),crypto=require('crypto'),cp=require('child_process');
const root=path.resolve(__dirname,'../../../'),prefix='dual_board/fixed_udp_hw/';
const read=f=>fs.readFileSync(path.join(root,f),'utf8');
const sha=f=>crypto.createHash('sha256').update(fs.readFileSync(path.join(root,f))).digest('hex').toUpperCase();
const rel=f=>path.relative(root,f).replaceAll('\\','/');
const logFile=prefix+'sim/modelsim_hw.log',log=read(logFile);
const marker='PASS fixed UDP hardware tops: actual A/B checker and key source, two 1200-packet IMG4 RGB/tag frames, lost-ACK retry, 12-byte reverse ACK, LED meaning and reset';
if(!log.includes(marker) || /Errors: [1-9]|Warnings: [1-9]|\*\* (Error|Fatal|Warning):/.test(log) ||
   !/Errors: 0, Warnings: 0\s*(?:#\s*quit -code 0\s*)?$/.test(log))throw Error('Incomplete/failed hardware-top simulation');
const proof=cp.execFileSync(process.execPath,[path.join(__dirname,'check_ipv4_sum.js')],{encoding:'utf8'});
if(!proof.includes('PASS IPv4 checksum predicate: all 1048576 sums, 16 valid folded-FFFF values'))throw Error('Checksum proof failed');
const proofFile=prefix+'sim/ipv4_checksum_proof_20261005.log';
fs.writeFileSync(path.join(root,proofFile),proof);
const baseline=[['src/user_source/hdl_source/top_tf_hdmi_audio.v','561394111CB599D811AA3408B25C6AABCC420D32111BC03D3B3EE87AB2D8E0E8'],
    ['best_result/lab_ex5_i2s_v1.0_logic_round3_20261003.bit','94744392DEC4010D38261036AB360AB6E01BC4C718B34167E821302A15297C88']];
for(const [file,hash]of baseline)if(sha(file)!==hash)throw Error('Single-board baseline changed '+file);
const files=new Set([logFile,proofFile,prefix+'README.md',prefix+'sim/check_ipv4_sum.js',prefix+'sim/snapshot_hw_validation.js',
    prefix+'sim/tb_fixed_udp_hw.v',prefix+'sim/run_modelsim.do',prefix+'sim/run_modelsim.ps1',...baseline.map(([f])=>f)]);
const pins={clk_50:'R7',sys_rst_n:'A2','led[0]':'A4','led[1]':'A3','led[2]':'C10','led[3]':'B12',
    phy1_rgmii_rx_clk:'T14',phy1_rgmii_rx_ctl:'T13',
    'phy1_rgmii_rx_data[0]':'P6','phy1_rgmii_rx_data[1]':'M6','phy1_rgmii_rx_data[2]':'T9','phy1_rgmii_rx_data[3]':'N9',
    phy1_rgmii_tx_clk:'T12',phy1_rgmii_tx_ctl:'T7',
    'phy1_rgmii_tx_data[0]':'T4','phy1_rgmii_tx_data[1]':'T6','phy1_rgmii_tx_data[2]':'M7','phy1_rgmii_tx_data[3]':'T8'};
const escape=s=>s.replace(/[.*+?^${}()|[\]\\]/g,'\\$&');
function board(role,seed){
    const dir=prefix+'prj/board_'+role.toLowerCase()+'/',name='FIXED_UDP_HW_'+role;
    const project=dir+name+'.al',xml=read(project),adc=prefix+'constraints/board_'+role.toLowerCase()+'.adc';
    const expected=role==='B'?{...pins,key_send_n:'B2'}:pins;
    const areaFile=dir+name+'_phy.area',timingFile=dir+name+'_pr.timing',area=read(areaFile),timing=read(timingFile);
    const bit=dir+name+'_20261005.bit',build=dir+'build_bit.tcl';
    const lastLog=fs.readdirSync(path.join(root,dir)).filter(f=>/^td_\d{8}_\d{6}\.log$/.test(f)).sort().pop();
    if(!lastLog)throw Error('Missing build log '+role);
    const buildLog=dir+lastLog,buildText=read(buildLog);
    if(/\bERROR\b/.test(buildText)||!buildText.includes('finish command "bitgen -bit '+name+'_20261005.bit"'))throw Error('Bitgen failed '+role);
    if(!read(build).includes('set_param place seed '+seed+'\n'))throw Error('Unexpected placement seed '+role);
    if(!area.includes('fixed_peer_udp')||/udp_ip_protocol_stack\s*\|/.test(area))throw Error('Wrong UDP hierarchy '+role);
    const setup=Number(timing.match(/SWNS:\s*([+-]?[\d.]+)ns/)[1]);
    const hold=Number(timing.match(/HWNS:\s*([+-]?[\d.]+)ns/)[1]);
    if(setup<0||hold<0||!timing.includes('Confidence          : Routed'))throw Error('Final routed timing failed '+role);
    const count=key=>{const m=area.match(new RegExp('^\\s*#'+key+'\\s+(\\d+)','m'));if(!m)throw Error('Missing '+key);return Number(m[1]);};
    if(count('IO')!==Object.keys(expected).length)throw Error('Unexpected top IO count '+role);
    for(const [port,pin]of Object.entries(expected)){
        const io=new RegExp('^\\s*'+escape(port)+'\\s+(?:INPUT|OUTPUT)\\s+'+pin+'\\s+LVCMOS33\\s','m');
        const loc=new RegExp('set_pin_assignment\\s+\\{\\s*'+escape(port)+'\\s*\\}\\s+\\{[^}]*LOCATION\\s*=\\s*'+pin+';');
        if(!io.test(area)||!loc.test(read(adc)))throw Error('Wrong/unconstrained pin '+role+' '+port);
    }
    const bitStat=fs.statSync(path.join(root,bit));
    if(bitStat.size<100000)throw Error('Invalid bit size '+role);
    const sources=[...xml.matchAll(/<File Path="([^"]+)"/g)].map(m=>rel(path.resolve(path.join(root,dir),m[1])));
    for(const file of sources){
        if(file.startsWith('../')||!fs.existsSync(path.join(root,file)))throw Error('Missing/out-of-workspace project source '+file);
        files.add(file);
        if(/(?:image_link\/rtl\/(?:fixed_peer_udp|image_packet_rx|image_receipt)|fixed_udp_hw\/rtl\/[^/]+)\.v$/.test(file) &&
           fs.statSync(path.join(root,file)).mtimeMs>bitStat.mtimeMs)throw Error('Source changed after bit '+file);
    }
    const macSdc='dual_board/ethernet_smoke/prj/board_a/al_ip/TEMAC_CORE/TEMAC_CORE.sdc';
    for(const file of [project,adc,areaFile,timingFile,bit,build,buildLog,macSdc])files.add(file);
    return {bit,sha256:sha(bit),bytes:bitStat.size,modified:bitStat.mtime.toISOString(),placement_seed:seed,
        resources:{lut:count('lut'),registers:count('reg'),bram9k:count('bram9k'),bram32k:count('bram32k'),dsp:count('dsp'),pll:count('pll')},
        resource_stage:'placed and routed diagnostic, NOT multimedia player',setup_wns_ns:setup,hold_wns_ns:hold,
        sta_coverage_percent:Number(timing.match(/STA coverage\s*:\s*([\d.]+)%/)[1]),pin_map:expected,build_log:buildLog};
}
const a=board('A',7),b=board('B',1);
if(a.resources.lut!==2263||b.resources.lut!==1933)throw Error('Unexpected final diagnostic resource counts');
const phaseFile='dual_board/image_link/phase10_validation_20261004.json',phase=JSON.parse(read(phaseFile));
if(phase.cases_passed!==40||phase.simulation_errors!==0||phase.board_a.lut!==13453||phase.board_b.lut!==10932)throw Error('Formal regression/resource snapshot differs');
files.add(phaseFile);
const result={date:'2026-10-05',generatedAt:new Date().toISOString(),diagnostic_only:true,formal_player_bit:false,hardware_verified:false,
    boards:{a,b},modelsim:{errors:0,warnings:0,pass:marker,frames:2,pixels_per_frame:307200,packets_per_frame:1200,
        lost_reverse_ack_retry_verified:true,duplicate_pixels_not_republished:true,reset_and_key_led_verified:true,
        actual_hw_tops:true,test_transport_bridge:true,encrypted_mac_phy_wire_simulated:false,log:logFile},
    checksum_predicate_proof:{all_20_bit_sums:1048576,accepted_folded_ffff_values:16,log:proofFile},
    protocol:{forward:'IMG4',payload_bytes:1042,reverse:'IAK2',reverse_bytes:12,udp_port:20482,retry_ms:100},
    timing_scope:'Inherited smoke clock plus TEMAC IP constraints; no clock relaxation. External RGMII IO delay and full IO/CDC coverage are not fully audited. Positive reported slack does not certify physical wire timing.',
    production_tx_unchanged:true,diagnostic_pattern_source_not_tf_tx:true,single_board_baseline_unchanged:true,
    formal_player:{phase_validation:phaseFile,cases_passed:40,simulation_warnings:phase.simulation_warnings,resource_stage:'gate synthesis',
        a_lut:phase.board_a.lut,b_lut:phase.board_b.lut,bit_generated:false},
    instructions:prefix+'README.md',next:'User burns paired SRAM bits and verifies B K2 whole-frame/return-ACK LED results over cable before formal player pin/timing/P&R integration.',
    files:[...files].sort().map(file=>({file,sha256:sha(file)}))};
fs.writeFileSync(path.join(root,prefix+'validation_20261005.json'),JSON.stringify(result,null,2)+'\n');
console.log(JSON.stringify({diagnostic_only:true,hardware_verified:false,modelsim_errors:0,modelsim_warnings:0,
    a:{...a.resources,setup:a.setup_wns_ns,hold:a.hold_wns_ns,bit:a.bit,sha256:a.sha256},
    b:{...b.resources,setup:b.setup_wns_ns,hold:b.hold_wns_ns,bit:b.bit,sha256:b.sha256}},null,2));
