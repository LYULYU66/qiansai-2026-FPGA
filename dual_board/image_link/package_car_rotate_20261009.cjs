// Publish a separate candidate. Never overwrite the startup/car releases.
const fs=require('fs'),p=require('path'),crypto=require('crypto');
const base=__dirname,root=p.resolve(base,'../..');
const prior=p.join(base,'board_test_20261008/startup_fix');
const rel='dual_board/image_link/board_test_20261009/car_rotate',out=p.join(root,rel);
const sim=p.join(base,'sim/car_rotate_20261009');
const hash=f=>crypto.createHash('sha256').update(fs.readFileSync(f)).digest('hex').toUpperCase();
if(fs.existsSync(out))throw Error('Candidate already published');
const old=JSON.parse(fs.readFileSync(p.join(prior,'manifest.json'),'utf8'));
const review=JSON.parse(fs.readFileSync(p.join(prior,'review_validation.json'),'utf8'));
for(const s of old.sources)if(hash(p.join(root,s.file))!==s.sha256)throw Error('Baseline source changed: '+s.file);
for(const a of old.artifacts)if(hash(p.join(prior,a.file))!==a.sha256)throw Error('Baseline bit changed: '+a.file);
for(const e of [...old.evidence,...review.evidence])if(hash(p.join(prior,e.file))!==e.sha256)throw Error('Baseline evidence changed: '+e.file);
const cases={rotation:['PASS car rotation lifecycle:','PASS car rotation pixels:','PASS car rotation reset:'],intro:['PASS car sprite ROM:','PASS car pixels:','PASS car lifecycle:'],boundary:['PASS manual-dual B boundary:']};
const regression=Object.entries(cases).map(([name,markers])=>{
 const file=name+'.log',f=p.join(sim,file),t=fs.readFileSync(f,'utf8');
 const passed=t.split(/\r?\n/).filter(l=>/^# PASS /.test(l));
 if(/\*\* (Fatal|Error)|Errors: [1-9]/.test(t)||passed.length!==markers.length||markers.some(m=>!t.includes(m))||!t.includes('End time:'))throw Error('Incomplete test '+file);
 return {file,pass_count:passed.length,pass_lines:passed,sha256:hash(f),mtime:fs.statSync(f).mtime.toISOString()};
});
function inspect(seed){
 const dir=p.join(base,seed===3?'prj/car_rotate_b_20261009':'prj/car_rotate_b_s'+seed+'_20261009');
 const stem=seed===3?'MEDIA_B_CAR_ROTATE_20261009':'MEDIA_B_CAR_ROTATE_S'+seed+'_20261009';
 const bit=p.join(dir,stem+'.bit');
 const logs=fs.readdirSync(dir).filter(f=>/^td_.*\.log$/.test(f)).map(f=>p.join(dir,f)).sort((a,b)=>fs.statSync(b).mtimeMs-fs.statSync(a).mtimeMs);
 const log=logs[0],build=fs.readFileSync(log,'utf8');
 if(!build.includes('Generate bits file '+stem+'.bit.')||/RUN-\d+ ERROR|Incremental route failed/.test(build))throw Error('Incomplete TD seed '+seed);
 const area=fs.readFileSync(p.join(dir,stem+'_phy.area'),'utf8'),timing=fs.readFileSync(p.join(dir,stem+'_pr.timing'),'utf8');
 if(!/Confidence\s*:\s*Routed/.test(timing))throw Error('Not routed seed '+seed);
 const num=k=>Number(area.match(new RegExp('^\\s*#'+k+'\\s+(\\d+)','m'))[1]);
 const slack=timing.match(/SWNS: ([\-\d.]+)ns, STNS: [\-\d.]+ns\s+HWNS: ([\-\d.]+)ns/);
 const self=k=>{const i=timing.indexOf('Path Group     :     '+k+' -> '+k);if(i<0)throw Error('No clock '+k);const t=timing.slice(i);return {setup_ns:Number(t.match(/Max\s+: SWNS\s+([\-\d.]+)ns/)[1]),hold_ns:Number(t.match(/Min\s+: HWNS\s+([\-\d.]+)ns/)[1])};};
 return {seed,dir,stem,bit,log,resources:{seed,lut:num('lut'),lut_percent:Number((num('lut')/196).toFixed(2)),registers:num('reg'),bram9k:num('bram9k'),bram32k:num('bram32k'),dsp:num('dsp'),pll:num('pll'),setup_ns:Number(slack[1]),hold_ns:Number(slack[2]),video:self('compute_clk'),udp:self('udp_clk'),sd:self('sd_clk'),lut_delta:num('lut')-old.resources.B.lut,reg_delta:num('reg')-old.resources.B.registers}};
}
const seeds=[3,1,4].map(inspect);
// Keep video setup positive; prefer UDP setup, then SD setup. This is NOT timing closure.
const candidates=seeds.filter(x=>x.resources.video.setup_ns>0).sort((a,b)=>b.resources.udp.setup_ns-a.resources.udp.setup_ns||b.resources.sd.setup_ns-a.resources.sd.setup_ns);
if(!candidates.length)throw Error('No usable video seed');
const chosen=candidates[0],resources={A:{...old.resources.A,unchanged:true},B:chosen.resources};
for(const k of ['bram9k','bram32k','pll'])if(resources.B[k]!==old.resources.B[k])throw Error('Unexpected memory/PLL change');
if(resources.B.dsp!==old.resources.B.dsp+1)throw Error('Unexpected DSP count');
const sources=new Map();
const axml=p.join(base,'prj/stars_opt_a_s4_20261007/MEDIA_A_STARS_OPT_S4_20261007.al');
for(const xml of [axml,p.join(chosen.dir,chosen.stem+'.al')])for(const m of fs.readFileSync(xml,'utf8').matchAll(/<File Path="([^"]+)"/g)){
 const path=m[1],file=p.relative(root,path).replaceAll('\\','/');
 if(file.startsWith('../')||p.isAbsolute(file))throw Error('Outside source root '+file);
 sources.set(file,{file,sha256:hash(path)});
}
const added=[...sources.values()].filter(s=>!old.sources.some(o=>o.file===s.file));
const removed=old.sources.filter(s=>!sources.has(s.file));
if(added.length!==1||removed.length!==1||!added[0].file.endsWith('/rtl/car_rotate_20261009/video_car_intro.v')||!removed[0].file.endsWith('/rtl/car_intro_20261007/video_car_intro.v'))throw Error('Unexpected source scope');
for(const s of sources.values())if(fs.statSync(p.join(root,s.file)).mtimeMs>fs.statSync(chosen.bit).mtimeMs)throw Error('Source newer than bit '+s.file);
const evidence=[],artifacts=[];
function copy(src,dst){const target=p.join(out,dst);fs.mkdirSync(p.dirname(target),{recursive:true});fs.copyFileSync(src,target);evidence.push({file:dst,sha256:hash(target)});}
const a=old.artifacts.find(x=>x.board==='A');copy(p.join(prior,a.file),a.file);artifacts.push({...a,unchanged:true});
const bname='MEDIA_B_CAR_ROTATE_20261009.bit';copy(chosen.bit,bname);artifacts.push({board:'B',file:bname,build_stem:chosen.stem,seed:chosen.seed,bytes:fs.statSync(chosen.bit).size,sha256:hash(chosen.bit)});
for(const s of sources.values())copy(p.join(root,s.file),'source_snapshot/'+s.file);
for(const build of seeds){
 const dest='evidence/seed'+build.seed+'/';copy(build.log,dest+'B_build.log');copy(p.join(build.dir,'build_flow.tcl'),dest+'build_flow.tcl');
 for(const suffix of ['.al','_gate.area','_phy.area','_pr.timing','_phy.ts'])copy(p.join(build.dir,build.stem+suffix),dest+build.stem+suffix);
}
for(const r of regression)copy(p.join(sim,r.file),'evidence/'+r.file);
for(const f of fs.readdirSync(sim))if(/\.(v|do)$/.test(f))copy(p.join(sim,f),'tests/car_rotate_20261009/'+f);
for(const f of ['tb_car_intro.v','car_reference.vh','sprite_reference.vh'])copy(p.join(base,'sim/car_intro_20261007',f),'tests/car_intro_20261007/'+f);
for(const f of ['tb_b_boundary.v','b_hdmi_models.v'])copy(p.join(base,'sim/manual_dual_20261007',f),'tests/manual_dual_20261007/'+f);
for(const f of ['prepare_car_rotate_20261009.cjs','prepare_car_rotate_seeds_20261009.cjs','package_car_rotate_20261009.cjs'])copy(p.join(base,f),'build_helpers/'+f);
const total=regression.reduce((n,x)=>n+x.pass_count,0);
const manifest={version:'car_rotate_20261009',created_at:new Date().toISOString(),hardware_verified:false,timing_closed:false,baseline:'dual_board/image_link/board_test_20261008/startup_fix',
 change:'B only: periodic single-sprite projected width compression and horizontal mirror, with travelling highlight. Not a real multi-view 3D car.',
 animation:{page:5,frame_rate_hz:25000000/(800*525),intro_frames:144,first_wait_frames:298,first_wait_seconds:5.0064,first_rotation_after_page_entry_seconds:7.4256,period_frames:298,period_seconds:5.0064,active_frames:64,active_seconds:1.0752,angle_steps:32,frames_per_angle:2,return_to_original:true,reset_on_page_exit:true,extra_frame_memory:false},
 controls:old.controls,images:old.images,synchronization:old.synchronization,startup:old.startup,
 resources,seed_comparison:seeds.map(x=>({seed:x.seed,build_stem:x.stem,resources:x.resources})),selection:'Among seeds3/1/4 with positive video setup, selected best UDP self setup, then SD self setup. No constraint/pin/PLL/FIFO change; timing remains unclosed.',
 artifacts,sources:[...sources.values()],changed_or_added_inputs:added,removed_project_inputs:removed,functions_removed:[],regression,total_pass_count:total,evidence,
 carried_baseline_regression:{manifest:'../../board_test_20261008/startup_fix/manifest.json',sha256:hash(p.join(prior,'manifest.json')),review_sha256:hash(p.join(prior,'review_validation.json')),scope:'Unchanged startup packet scheduler, paired A/B UDP reboot, stars and cached-image tests carried by source hashes; original car and actual B top rerun this turn.'},
 caveats:'PROGRAM_SRAM engineering candidate only. Functional RTL simulation is not proof of real PHY/MAC/SDRAM stability. Startup-fix hardware outcome remains unconfirmed. A/TF content unchanged; no automatic programming, flash erase or TF writes.'};
const comparison=seeds.map(s=>`| ${s.seed} | ${s.resources.lut} | ${s.resources.video.setup_ns} | ${s.resources.udp.setup_ns} | ${s.resources.sd.setup_ns} |`).join('\n');
const notes=`# B板汽车周期转向候选（2026-10-09）

只修改B的第5张仪表页汽车叠加层，保留前一版启动发包修复。现有单视角车图先收窄、镜像再展开，两次半转后回到原朝向，转向过程中有扫光；这属于低资源模拟转向，不是真实多视角3D旋转。未生成车头、车尾或额外多帧素材。

## 效果与操作

- 进入B第5张仪表页：先播放原出场淡入与上升，约2.42秒结束；再等待约5.01秒，首次转向约在入页7.43秒开始。
- 此后每约5.01秒启动一次，单次持续约1.08秒，共32角度、每角度2帧；完成后回到原朝向并保持。
- B的KEY2仍只手动切第5/6张，退出仪表页后动画计数归零；重新进入从出场开始。第6张及A第3张的星点联动不变。
- 所有新增计数只在有效仪表页的VS边沿推进；没有新增像素时钟、PLL、帧缓存或网口消息。

## 上板方法

1. A保持 MEDIA_A_STARS_OPT_20261007.bit，不需要重新下载。目录内提供相同副本，SHA256与前版一致。
2. 仅向B下载 MEDIA_B_CAR_ROTATE_20261009.bit，使用 PROGRAM_SRAM；本文件实际来自布局种子${chosen.seed}的 ${chosen.stem}。
3. TF保持插B、网线接好，先按A的KEY1复位，再按B的KEY1复位。下载SRAM后不要断电，以免丢失临时加载程序。
4. 先验收A出图/出声，再观察B仪表页出场和周期转向。至少观察3次转向，并测试B的KEY2切6→5；随后检查A切图、KEY3切歌、串口和预警。
5. 有问题仅给B退回 board_test_20261008/startup_fix/MEDIA_B_STARTUP_FIX_20261008.bit。该旧版完整保留，但之前A黑屏无声的启动修复仍未收到板上确认，不应宣称已修复。

TF图片及PCM无需变更，没有自动烧录或写TF卡。

## 实际布局布线资源

| 指标 | 启动修复B | 本候选B |
| --- | --- | --- |
| LUT | 15836（80.80%） | ${resources.B.lut}（${resources.B.lut_percent}%） |
| 寄存器 | 10393 | ${resources.B.registers} |
| BRAM9K / BRAM32K | 43 / 12 | ${resources.B.bram9k} / ${resources.B.bram32k} |
| DSP / PLL | 3 / 3 | ${resources.B.dsp} / ${resources.B.pll} |
| 视频自身建立 | +6.060ns | ${resources.B.video.setup_ns}ns |
| UDP自身建立 | -1.369ns | ${resources.B.udp.setup_ns}ns |
| SD自身建立 | -1.228ns | ${resources.B.sd.setup_ns}ns |

LUT相对启动修复版变化${resources.B.lut_delta}个、寄存器变化${resources.B.reg_delta}个，多1个DSP进行横向投影；LUT变化还受综合打包和布局影响，不能把该差值当作动画模块独立占用量。A仍为14640 LUT（74.69%）、9337寄存器、BRAM9K/32K=50/12、DSP/PLL=3/4。

本候选B全局建立/保持=${resources.B.setup_ns}/${resources.B.hold_ns}ns，UDP保持=${resources.B.udp.hold_ns}ns、SD保持=${resources.B.sd.hold_ns}ns、视频保持=${resources.B.video.hold_ns}ns。时序未闭合，只能作为板上对照候选，不能保证稳定启动。

相对启动修复版，UDP自身建立变化${Number((resources.B.udp.setup_ns-old.resources.B.udp.setup_ns).toFixed(3))}ns、SD自身建立变化${Number((resources.B.sd.setup_ns-old.resources.B.sd.setup_ns).toFixed(3))}ns（负值为恶化）；不能把“3个种子里较好”当作整体稳定性改善。

布局种子比较（ns，均为实际布线报告的自身路径）：

| 种子 | LUT | 视频建立 | UDP建立 | SD建立 |
| --- | --- | --- | --- | --- |
${comparison}

## 验证及边界

本轮ModelSim ${total}项PASS：周期/复位和188万级像素检查（独立cosine参考、全部32角度、边缘裁剪与镜像）、原车图ROM与338万级完整帧像素、原出场生命周期、实际B顶层1024个PCM字/两曲会话/串口及四图中止恢复。检查了输出RGB/DE/VS保持原有同一拍对齐，不覆盖仪表主体、消隐和关闭页透明旁路。日志存在原有未用端口连接警告，无Error/Fatal。

未改动的双板启动重连、发包器和星点测试通过源文件散列继承前版证据，不冒充本轮重跑。上述均是RTL仿真，不包含真实PHY、加密HDMI内部行为或SDRAM板级电气；没有上板验证。前版源码与bit已逐项核对未改动。

源码、3个布局种子的构建/资源/时序报告、回归日志和文件散列在本目录。新源码为 rtl/car_rotate_20261009/video_car_intro.v；选定工程为 ${p.relative(base,chosen.dir).replaceAll('\\','/')}/${chosen.stem}.al。
`;
console.log('*** Begin Patch');
for(const [f,t] of [['manifest.json',JSON.stringify(manifest,null,2)],['使用说明.md',notes]]){
 console.log('*** Add File: '+rel+'/'+f);for(const l of t.split(/\r?\n/))console.log('+'+l);
}
console.log('*** End Patch');
