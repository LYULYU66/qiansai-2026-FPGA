// Paired engineering release. Binary/evidence copying is mechanical;
// manifest/notes are emitted for apply_patch, never shell-written text.
const fs=require('fs'),p=require('path'),crypto=require('crypto');
const base=__dirname,root=p.resolve(base,'../..');
const rel='dual_board/image_link/board_test_20261007/stars_opt',out=p.join(root,rel),sim=p.join(base,'sim/stars_opt_20261007');
if(fs.existsSync(p.join(out,'manifest.json')))throw Error('Already published');
const hash=f=>crypto.createHash('sha256').update(fs.readFileSync(f)).digest('hex').toUpperCase();
const baseline=p.join(base,'board_test_20261007/manual_dual');
const old=JSON.parse(fs.readFileSync(p.join(baseline,'manifest.json'),'utf8'));
for(const s of old.sources)if(hash(p.join(root,s.file))!==s.sha256)throw Error('Baseline source changed '+s.file);
for(const a of old.artifacts)if(hash(p.join(baseline,a.file))!==a.sha256)throw Error('Baseline bit changed '+a.file);
const cases={
 'stars_verified.log':[['PASS star motion:','PASS star control:','PASS dual stars pixels:'],3],
 'optimization.log':[['PASS shared snapshot PERIOD=1:','PASS shared snapshot PERIOD=3:','PASS shared snapshot PERIOD=97:','PASS compute equivalence:'],4],
 'audio.log':[['PASS audio status:','PASS visual guard:','PASS remote compute:','PASS audio offload:'],4],
 'boundary.log':[['PASS manual-dual B boundary:'],1],
 'preview.log':[['PASS B manual TF5/TF6 preview:'],1]
};
const regression=Object.entries(cases).map(([file,[markers,count]])=>{
 const f=p.join(sim,file),txt=fs.readFileSync(f,'utf8'),pass=txt.split(/\r?\n/).filter(l=>/^# PASS /.test(l));
 if(/\*\* (Fatal|Error)|Errors: [1-9]/.test(txt)||markers.some(s=>!txt.includes(s))||pass.length!==count)throw Error('Failed/incomplete '+file);
 return {file,passed:true,pass_count:count,pass_lines:pass,sha256:hash(f),mtime:fs.statSync(f).mtime.toISOString()};
});
const resources={},artifacts=[],sources=new Map(),evidence=[];
function copy(src,dest){const dst=p.join(out,dest);fs.mkdirSync(p.dirname(dst),{recursive:true});fs.copyFileSync(src,dst);evidence.push({file:dest,sha256:hash(dst)});}
for(const [board,folder,stem,seed] of [
 ['A','stars_opt_a_s4_20261007','MEDIA_A_STARS_OPT_S4_20261007',4],
 ['B','stars_opt_b_20261007','MEDIA_B_STARS_OPT_20261007',3]]){
 const dir=p.join(base,'prj',folder),published='MEDIA_'+board+'_STARS_OPT_20261007';
 const logs=fs.readdirSync(dir).filter(f=>/^td_.*\.log$/.test(f)).map(f=>p.join(dir,f)).sort((a,b)=>fs.statSync(b).mtimeMs-fs.statSync(a).mtimeMs);
 const txt=fs.readFileSync(logs[0],'utf8');
 if(!txt.includes('Generate bits file '+stem+'.bit.')||/RUN-\d+ ERROR|Incremental route failed/.test(txt))throw Error('Incomplete build '+board);
 const area=fs.readFileSync(p.join(dir,stem+'_phy.area'),'utf8'),timing=fs.readFileSync(p.join(dir,stem+'_pr.timing'),'utf8');
 if(!/Confidence\s*:\s*Routed/.test(timing))throw Error('Not routed');
 const num=k=>Number(area.match(new RegExp('^\\s*#'+k+'\\s+(\\d+)','m'))[1]);
 const slack=timing.match(/SWNS: ([\-\d.]+)ns, STNS: [\-\d.]+ns\s+HWNS: ([\-\d.]+)ns/);
 const self=k=>{const i=timing.indexOf('Path Group     :     '+k+' -> '+k);if(i<0)throw Error('Clock '+k);const t=timing.slice(i);return {setup_ns:Number(t.match(/Max\s+: SWNS\s+([\-\d.]+)ns/)[1]),hold_ns:Number(t.match(/Min\s+: HWNS\s+([\-\d.]+)ns/)[1])};};
 resources[board]={seed,lut:num('lut'),lut_percent:Number((num('lut')/196).toFixed(2)),registers:num('reg'),bram9k:num('bram9k'),bram32k:num('bram32k'),dsp:num('dsp'),pll:num('pll'),setup_ns:Number(slack[1]),hold_ns:Number(slack[2]),video:self(board==='A'?'video_clk':'compute_clk'),udp:self('udp_clk'),lut_delta:num('lut')-old.resources[board].lut,reg_delta:num('reg')-old.resources[board].registers};
 if(board==='B')resources[board].sd=self('sd_clk');
 for(const k of ['bram9k','bram32k','dsp','pll'])if(resources[board][k]!==old.resources[board][k])throw Error('Unexpected '+board+' '+k);
 const bit=p.join(dir,stem+'.bit');artifacts.push({board,file:published+'.bit',build_stem:stem,bytes:fs.statSync(bit).size,sha256:hash(bit)});copy(bit,published+'.bit');
 copy(logs[0],'evidence/'+board+'_build.log');copy(p.join(dir,'build_flow.tcl'),'evidence/'+board+'_build.tcl');
 for(const suffix of ['.al','_phy.area','_gate.area','_pr.timing','_phy.ts'])copy(p.join(dir,stem+suffix),'evidence/'+stem+suffix);
 for(const m of fs.readFileSync(p.join(dir,stem+'.al'),'utf8').matchAll(/<File Path="([^"]+)"/g)){
  const f=m[1],relative=p.relative(root,f).replaceAll('\\','/');
  if(relative.startsWith('../')||p.isAbsolute(relative)||!fs.existsSync(f))throw Error('Bad input '+relative);
  sources.set(relative,{file:relative,sha256:hash(f)});
 }
}
if(resources.B.lut>=old.resources.B.lut)throw Error('B resource optimization not achieved');
const added=[...sources.values()].filter(s=>!old.sources.some(o=>o.file===s.file));
if(added.length!==4||added.some(s=>!s.file.includes('rtl/stars_opt_20261007/')))throw Error('Unexpected RTL scope');
for(const s of sources.values())copy(p.join(root,s.file),'source_snapshot/'+s.file);
for(const r of regression)copy(p.join(sim,r.file),'evidence/'+r.file);
for(const f of fs.readdirSync(sim))if(/\.(v|sv|vh|do|cjs|py)$/.test(f))copy(p.join(sim,f),'tests/'+f);
for(const f of ['tb_audio_visual_guard.v','tb_audio_status_guard.v'])copy(p.join(base,'sim',f),'tests/shared/'+f);
for(const f of ['tb_b_boundary.v','b_hdmi_models.v'])copy(p.join(base,'sim/manual_dual_20261007',f),'tests/shared/'+f);
for(const f of ['audio_receipt_a_test.v','audio_receipt_b_test.v'])if(fs.existsSync(p.join(base,'sim/dualsong_20261005',f)))copy(p.join(base,'sim/dualsong_20261005',f),'tests/shared/'+f);
for(const f of ['stars60_dual_screen_12s.mp4','preview_00s.png','preview_04s.png','preview_08s.png'])copy(p.join(sim,'software_preview',f),f==='stars60_dual_screen_12s.mp4'?'software_preview.mp4':f);
const unchanged=[...sources.values()].filter(s=>old.sources.some(o=>o.file===s.file&&o.sha256===s.sha256));
const manifest={version:'stars_opt_20261007',created_at:new Date().toISOString(),hardware_verified:false,timing_closed:false,
 usage:'Paired A+B PROGRAM_SRAM engineering candidate only; no programming or TF writes',baseline:'dual_board/image_link/board_test_20261007/manual_dual',
 lights:{count:60,size_counts:{large:8,medium:12,small:40},speed_multiplier:4,world_size:[1280,480],viewports:{A:[0,639],B:[640,1279]},shared_pan_cycle_seconds:32.000016384,local_x_cycle_seconds:8.000004096,local_y_cycle_seconds:16.000008192,breathing_seconds:{large:2.000001024,other:4.000002048},amplitude_ranges:{large:[80,207],medium:[32,95],small:[12,43]},row_evaluator:'single eased unit,3 clocks per particle;7 viewport-needed lanes*6*3 +3 skips=129 blanking clocks;10x27bit distributed row RAM unchanged',protocol:'CTL4 format and timestamp unchanged; renderers on both boards apply4x geometry acceleration',audio_independent:true},
 resource_changes:{ring_pointer:'11-bit Gray/modulo occupancy pointers only;1024-word RAM,896-word occupancy bound and32-bit absolute playback/session counters unchanged',visual_packet:'share held296-bit coherent CDC snapshot; remove private264-bit shift-copy;ARM/release stages preserve atomic tag/payload/CRC; default standalone mode retained',functions_removed:[]},
 controls:old.controls,images:old.images,synchronization:old.synchronization,startup:old.startup,
 resources,artifacts,sources:[...sources.values()],unchanged_input_count:unchanged.length,changed_or_added_inputs:added,
 regression,total_pass_count:regression.reduce((s,r)=>s+r.pass_count,0),evidence,
 carried_baseline_regression:{count:old.total_pass_count,manifest:'../manual_dual/manifest.json',sha256:hash(p.join(baseline,'manifest.json')),scope:'six-image scanning/scaling/routing and CTL4 input files unchanged; previous regressions are carried evidence, not rerun this turn'},
 software_preview:'software_preview.mp4:12s/30fps integer-equation raster on the previously generated seamless left/right backgrounds;not hardware capture;no A status/time overlay or monitor effects',
 caveats:'Timing remains unclosed. A seed1/2 failed route; only successful seed4 released. A LUT grows for enhanced stars while B and combined LUT fall; several timing paths worsen despite other improvements. SDRAM/encrypted HDMI/PHY and decoded SD transport are modeled in tests; no hardware acceptance.'};
const notes=`# 双屏星点增强与 B 板资源优化（2026-10-07）

全景星点从 30 增至 60：8 个大光点、12 个中光点、40 个小光点，仍为黄绿色柔光与淡暖色亮芯。加强亮度，移动/呼吸约快 4 倍：共同往返横移约 32 秒一轮，局部 X/Y 漂移约 8/16 秒一轮，大光点/其他光点呼吸约 2/4 秒一轮，速度有缓动而非匀速。明暗与大小各不相同，不随音乐/音量变化。

B KEY2 仍只在 TF 第 5、6 张间手动切换；第 5 张无星点，第 6 张有星点并通知 A 切到第 3 张，危险预警优先。A/B 共享 B 时间轴及 1280×480 坐标，两路 HDMI 不作电气锁帧。本版不改 TF 文件或图片顺序，不改音乐、歌词数据、串口命令、拨码预警、显示对齐链、SDRAM 仲裁、FIFO 深度、PLL 或 HDMI IP。

## 下载与上板

两板必须配套更新：MEDIA_A_STARS_OPT_20261007.bit 给 A，MEDIA_B_STARS_OPT_20261007.bit 给 B。先 PROGRAM_SRAM 测试，不直接固化 FLASH；本次未烧录、未写 TF。回退用 ../manual_dual/ 的配套两板文件，不混搭新旧速度的渲染器。

TF 卡仍只插 B，根目录编号仍是 BMP 目录条目顺序而非文件名排序，沿用六图和 MUSIC.PCM/MUSIC2.PCM。等第 5/6 张缓存完成后按 B KEY2，观察至少 12 秒：A 第 3 张和 B 第 6 张有更多大小光点、明显漂移、错开的呼吸亮度；再返回 B 第 5 张应无星点。检查 A 手动选页、KEY3 换歌、串口音量/亮度/对比度、歌词及危险抢占，确认声音无卡顿、画面无新增撕裂。

software_preview.mp4 是 12 秒/30fps 的软件方程预览，不是上板录屏。用已生成的拼接背景，A 左 B 右；未叠加 A 的参数和时间图层。如果 TF 背景不同，实际观感会不同。

## 实际布局布线资源（非综合估算）

| 资源 | A 旧→新 | B 旧→新 |
|---|---:|---:|
| LUT | ${old.resources.A.lut}→${resources.A.lut}（${resources.A.lut_percent}%） | ${old.resources.B.lut}→${resources.B.lut}（${resources.B.lut_percent}%） |
| LUT 变化 | +${resources.A.lut_delta} | ${resources.B.lut_delta} |
| 寄存器 | ${old.resources.A.registers}→${resources.A.registers} | ${old.resources.B.registers}→${resources.B.registers} |
| BRAM9K / BRAM32K | ${resources.A.bram9k} / ${resources.A.bram32k}，不变 | ${resources.B.bram9k} / ${resources.B.bram32k}，不变 |
| DSP / PLL | ${resources.A.dsp} / ${resources.A.pll}，不变 | ${resources.B.dsp} / ${resources.B.pll}，不变 |
| 全局建立 / 保持 ns | ${resources.A.setup_ns} / ${resources.A.hold_ns} | ${resources.B.setup_ns} / ${resources.B.hold_ns} |
| 视频自身建立 / 保持 ns | ${resources.A.video.setup_ns} / ${resources.A.video.hold_ns} | ${resources.B.video.setup_ns} / ${resources.B.video.hold_ns} |
| UDP 自身建立 / 保持 ns | ${resources.A.udp.setup_ns} / ${resources.A.udp.hold_ns} | ${resources.B.udp.setup_ns} / ${resources.B.udp.hold_ns} |

B 实际省 ${-resources.B.lut_delta} LUT、${-resources.B.reg_delta} 寄存器；A 因星点增强增加 ${resources.A.lut_delta} LUT，两板合计 LUT 减少 ${-(resources.A.lut_delta+resources.B.lut_delta)} 个。没有删除现有功能。B 优化的是环形音频历史缓存的跨域指针及可视化发包的重复临时缓存；完整播放计数、采样数据、分析精度和歌词仍保留。星点不新增 60 套并行绘制器，而是在 160 拍行消隐中用 129 拍复用计算，行 RAM 位数仍为 10×27。

**时序仍未闭合，未上板验收。** B SD 自身建立/保持为 ${resources.B.sd.setup_ns}/${resources.B.sd.hold_ns}ns；与旧版相比，有路径改善，也有路径恶化，不能把 LUT 减少当成稳定性的保证。A 选成功的 seed4；seed1/2 布线失败，未发布失败结果。B 选 seed3。

## 本轮验证

${regression.reduce((s,r)=>s+r.pass_count,0)} 项 ModelSim PASS：6144000 次双屏 RGB 比对、95 个亮接缝样本、160 拍真实行消隐预算、速度周期/帧原子性/非休闲页旁路；三个 1/3/97 周期配置共 480 个精确 VIZ2 包，在源持续变化、等待网络和复位时保持头部/数据/CRC 一致；优化前后 3148351 个计算时钟逐拍对比，12202 个样本，覆盖 11 位环形回绕、32 位播放回绕、背压、音量、会话与不合法反馈；原音频及可视化守卫、实际 48k 播放反馈链路、B 集成 UART/双曲/重连；B 原生 FIFO 到 HDMI 的四槽缓存、5 个完整输入帧和 4300800 个像素、中止保留/防覆盖/KEY2 切页。

SDRAM、SD 扇区和加密 HDMI/PHY 用接口模型，不能替代硬件时序与电气验证。六图扫描/缩放/路由、CTL4 页面协议等输入未改，沿用上一版 ${old.total_pass_count} 项回归证据，不冒称本轮重跑。正式改动仅四个版本化文件，旧版 ${old.sources.length} 个输入散列及两块 bit 均验证未变。

源码、项目、构建日志、资源和时序报告在 source_snapshot / evidence / manifest.json；可重跑 sim/stars_opt_20261007/run_stars.do、run_optimization.do、run_audio.do、run_boundary.do、run_preview.do（ModelSim 串行）。重建 A 用 prj/stars_opt_a_s4_20261007/build_flow.tcl，B 用 prj/stars_opt_b_20261007/build_flow.tcl。
`;
console.log('*** Begin Patch');
for(const [f,s] of [['manifest.json',JSON.stringify(manifest,null,2)],['使用说明.md',notes]]){console.log('*** Add File: '+rel+'/'+f);for(const l of s.split(/\r?\n/))console.log('+'+l);}
console.log('*** End Patch');
