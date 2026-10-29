// Copy existing artifacts; emit new text files through apply_patch. Refuse to
// overwrite a published candidate or to package dirty baseline HDL inputs.
const fs=require('fs'),p=require('path'),crypto=require('crypto');
const base=__dirname,root=p.resolve(base,'../..');
const prior=p.join(base,'board_test_20261007/car_intro');
const rel='dual_board/image_link/board_test_20261008/startup_fix',out=p.join(root,rel);
const dir=p.join(base,'prj/startup_fix_b_20261008'),stem='MEDIA_B_STARTUP_FIX_20261008';
const sim=p.join(base,'sim/startup_fix_20261008');
if(fs.existsSync(out))throw Error('Candidate directory already exists');
const hash=f=>crypto.createHash('sha256').update(fs.readFileSync(f)).digest('hex').toUpperCase();
const old=JSON.parse(fs.readFileSync(p.join(prior,'manifest.json'),'utf8'));
for(const x of old.sources)if(hash(p.join(root,x.file))!==x.sha256)throw Error('Baseline input changed: '+x.file);
for(const x of old.artifacts)if(hash(p.join(prior,x.file))!==x.sha256)throw Error('Baseline artifact changed: '+x.file);
const cases={scheduler:['PASS flat scheduler B:','PASS flat scheduler A:'],boundary:['PASS manual-dual B boundary:'],restart:['PASS startup pipeline:']};
const regression=Object.entries(cases).map(([name,markers])=>{
 const file=name+'.log',f=p.join(sim,file),t=fs.readFileSync(f,'utf8');
 const passed=t.split(/\r?\n/).filter(l=>/^# PASS /.test(l));
 if(/\*\* (Fatal|Error)|Errors: [1-9]/.test(t)||passed.length!==markers.length||markers.some(x=>!t.includes(x))||!t.includes('End time:'))throw Error('Incomplete regression '+file);
 return {file,pass_count:passed.length,pass_lines:passed,sha256:hash(f),mtime:fs.statSync(f).mtime.toISOString()};
});
const logs=fs.readdirSync(dir).filter(f=>/^td_.*\.log$/.test(f)).map(f=>p.join(dir,f)).sort((a,b)=>fs.statSync(b).mtimeMs-fs.statSync(a).mtimeMs);
const build=fs.readFileSync(logs[0],'utf8');
if(!build.includes('Generate bits file '+stem+'.bit.')||/RUN-\d+ ERROR|Incremental route failed/.test(build))throw Error('Build incomplete');
const area=fs.readFileSync(p.join(dir,stem+'_phy.area'),'utf8'),timing=fs.readFileSync(p.join(dir,stem+'_pr.timing'),'utf8');
if(!/Confidence\s*:\s*Routed/.test(timing))throw Error('Not routed');
const num=k=>Number(area.match(new RegExp('^\\s*#'+k+'\\s+(\\d+)','m'))[1]);
const slack=timing.match(/SWNS: ([\-\d.]+)ns, STNS: [\-\d.]+ns\s+HWNS: ([\-\d.]+)ns/);
const self=k=>{const i=timing.indexOf('Path Group     :     '+k+' -> '+k);if(i<0)throw Error('No clock '+k);const t=timing.slice(i);return {setup_ns:Number(t.match(/Max\s+: SWNS\s+([\-\d.]+)ns/)[1]),hold_ns:Number(t.match(/Min\s+: HWNS\s+([\-\d.]+)ns/)[1])};};
const resources={A:{...old.resources.A,unchanged:true},B:{seed:3,lut:num('lut'),lut_percent:Number((num('lut')/196).toFixed(2)),registers:num('reg'),bram9k:num('bram9k'),bram32k:num('bram32k'),dsp:num('dsp'),pll:num('pll'),setup_ns:Number(slack[1]),hold_ns:Number(slack[2]),video:self('compute_clk'),udp:self('udp_clk'),sd:self('sd_clk'),lut_delta:num('lut')-old.resources.B.lut,reg_delta:num('reg')-old.resources.B.registers}};
for(const k of ['bram9k','bram32k','dsp','pll'])if(resources.B[k]!==old.resources.B[k])throw Error('Unexpected memory/DSP/PLL change');
const sources=new Map();
const axml=p.join(base,'prj/stars_opt_a_s4_20261007/MEDIA_A_STARS_OPT_S4_20261007.al');
for(const xml of [axml,p.join(dir,stem+'.al')])for(const m of fs.readFileSync(xml,'utf8').matchAll(/<File Path="([^"]+)"/g)){
 const path=m[1],file=p.relative(root,path).replaceAll('\\','/');if(file.startsWith('../')||p.isAbsolute(file))throw Error('Outside root '+file);
 sources.set(file,{file,sha256:hash(path)});
}
const added=[...sources.values()].filter(s=>!old.sources.some(o=>o.file===s.file));
if(added.length!==1||!added[0].file.endsWith('/rtl/startup_fix_20261008/media_udp_arbiter.v'))throw Error('Unexpected input scope');
const bit=p.join(dir,stem+'.bit');
for(const s of sources.values())if(fs.statSync(p.join(root,s.file)).mtimeMs>fs.statSync(bit).mtimeMs)throw Error('Source newer than bit: '+s.file);
const evidence=[],artifacts=[];
function copy(src,dst){const f=p.join(out,dst);fs.mkdirSync(p.dirname(f),{recursive:true});fs.copyFileSync(src,f);evidence.push({file:dst,sha256:hash(f)});}
const a=old.artifacts.find(x=>x.board==='A');copy(p.join(prior,a.file),a.file);artifacts.push({...a,unchanged:true});
copy(bit,stem+'.bit');artifacts.push({board:'B',file:stem+'.bit',bytes:fs.statSync(bit).size,sha256:hash(bit)});
for(const s of sources.values())copy(p.join(root,s.file),'source_snapshot/'+s.file);
copy(logs[0],'evidence/B_build.log');copy(p.join(dir,'build_flow.tcl'),'evidence/B_build.tcl');
for(const suffix of ['.al','_gate.area','_phy.area','_pr.timing','_phy.ts'])copy(p.join(dir,stem+suffix),'evidence/'+stem+suffix);
for(const r of regression)copy(p.join(sim,r.file),'evidence/'+r.file);
for(const f of fs.readdirSync(sim))if(/\.(v|do)$/.test(f))copy(p.join(sim,f),'tests/'+f);
for(const f of ['prepare_startup_fix_20261008.cjs','prepare_startup_tests_20261008.cjs','package_startup_fix_20261008.cjs'])copy(p.join(base,f),'build_helpers/'+f);
const total=regression.reduce((n,x)=>n+x.pass_count,0);
const manifest={version:'startup_fix_20261008',created_at:new Date().toISOString(),hardware_verified:false,timing_closed:false,
 baseline:'dual_board/image_link/board_test_20261007/car_intro',
 observed_failure:'User reports paired car_intro bits: A display number0, black screen and no sound; B loads local page after long startup.',
 diagnosis:{confirmed:['A number0 denotes no valid displayed frame','B skips stalled source images after no-progress timeout; local display does not prove A received first four images','car_intro B udp self setup -3.070ns; worst path crosses idle channel priority/length/ACK selection'],suspected:'B application packet corruption or stalls may lead to missing A image commits and PCM. Hardware root cause not yet confirmed.'},
 change:'B only: latch owner/length before UDP request and pipeline selected payload byte/valid before shared CRC/output. Preserve seven-clock source prime allowance and poison CRC on producer abort.',
 controls:old.controls,images:old.images,synchronization:old.synchronization,
 startup:'B loads remote images1..4 in order, advancing on complete or no-progress timeout (3s at100MHz); then local images5/6, with PCM enabled after remote preload attempts. No startup timeout shortened in this candidate.',
 resources,artifacts,sources:[...sources.values()],changed_or_added_inputs:added,functions_removed:[],regression,total_pass_count:total,evidence,
 carried_baseline_regression:{manifest:'../../board_test_20261007/car_intro/manifest.json',sha256:hash(p.join(prior,'manifest.json')),scope:'Unchanged car/star/FIFO/HDMI pixel tests carried by input hashes; not rerun this turn.'},
 caveats:'PROGRAM_SRAM candidate; timing remains unclosed. RTL simulation confirms protocol operation, not PHY/MAC/SDRAM electrical behavior or hardware startup fix. TF content, A bit, pins, PLLs, constraints and visible effects unchanged. No board programming performed.'};
const notes=`# 双板启动链路修复候选（2026-10-08）

针对 car_intro 版 A 数码管0、黑屏无声，B等待较长后才显示的现象。A 的0表示未进入有效画面；B读取前四张远端图片时会等待A的回执，连续3秒无读取/像素进展会跳到下一张，因此B最终显示本地第5张不能证明A收到了前四张。

原B布线报告的 UDP 自身最差建立裕量为 -3.070ns，其中关键路径从控制包状态经过通道选择/长度选择，到另一个发送模块。该路径存在实测静态时序风险，尚未通过板上观测确认它就是这次故障的唯一原因。

## 本轮改动

B发包器先锁存通道归属和长度，再发UDP请求；选出的字节/有效信号增加一拍寄存，把生产模块到多路选择、CRC的长组合路径隔开。保持包内容、通道优先级、七拍首字节等待规则、中途复位补齐错误CRC、最终字节与回执规则。只替换一个版本化HDL文件。汽车出场动画、双屏60星点、图像/PCM/歌词、串口和预警功能沿用，A bit不变。

## 下载方法

1. A保持 MEDIA_A_STARS_OPT_20261007.bit（目录中提供相同副本）；只给B下载 MEDIA_B_STARTUP_FIX_20261008.bit，先选择 PROGRAM_SRAM。
2. TF仍插B，网线接好。下载完成后，先按一下A的KEY1复位，再按一下B的KEY1复位；SRAM下载后不要断电，否则会丢失这次加载的程序。
3. 观察A数码管能否从0变成1并开始出图、出声，记录两屏各自的启动等待时间。随后测试A切图/切歌，B的KEY2切5/6以及B6带A3联动。
4. 如果A仍为0，保持A不变，仅给B换回 board_test_20261007/stars_opt/MEDIA_B_STARS_OPT_20261007.bit，再按同样顺序复位。这个对照可判断是否仍与新增汽车版的实现有关。旧版保留，但也不能视为本次上板已验证正常。

不需要修改TF卡内容。本次没有自动烧录。此候选的目的为针对时序风险进行硬件对照；不能将仿真通过写成黑屏已修复。

## 实际布局布线

| B板指标 | car_intro | 本候选 |
| --- | --- | --- |
| LUT | 15886 / 81.05% | ${resources.B.lut} / ${resources.B.lut_percent}% |
| 寄存器 | 10378 | ${resources.B.registers} |
| BRAM9K / BRAM32K | 43 / 12 | 43 / 12 |
| DSP / PLL | 3 / 3 | 3 / 3 |
| UDP自身建立 | -3.070ns | ${resources.B.udp.setup_ns}ns |
| 视频自身建立 | 5.248ns | ${resources.B.video.setup_ns}ns |
| SD自身建立 | -1.336ns | ${resources.B.sd.setup_ns}ns |

A仍为14640 LUT（74.69%）、9337寄存器。B全局建立/保持 ${resources.B.setup_ns}/${resources.B.hold_ns}ns，UDP自身保持${resources.B.udp.hold_ns}ns、视频自身保持${resources.B.video.hold_ns}ns。时序尚未闭合，板上稳定性待确认。

## 本轮验证

${total}项ModelSim PASS：调度器B的38包、A尺寸的30包覆盖优先级、延迟ACK、0~6拍首字节延迟、包中止补齐、CRC、防插包和复位；实际B顶层1024个PCM字、两曲会话、串口和四张图中止恢复；原A调度器与候选B经真实fixed_peer_udp RTL互联，四图每图16包，五次B复位，已显示缓存保护及PCM播放逐字核对。启动测试的帧尺寸和心跳时间作了缩短以便仿真，不覆盖真实PHY/MAC或SDRAM电气时序。完整汽车像素、星点和B预览链路代码未变，其上一版测试以源文件散列核对继承。

源文件、构建日志、资源和时序报告、测试日志均保存在本目录。项目为 prj/startup_fix_b_20261008/MEDIA_B_STARTUP_FIX_20261008.al，构建脚本 build_flow.tcl；仿真脚本在 sim/startup_fix_20261008/。原car_intro目录和${old.sources.length}个源码输入均已核对未被修改。
`;
console.log('*** Begin Patch');for(const [f,t] of [['manifest.json',JSON.stringify(manifest,null,2)],['使用说明.md',notes]]){console.log('*** Add File: '+rel+'/'+f);for(const l of t.split(/\r?\n/))console.log('+'+l);}console.log('*** End Patch');
