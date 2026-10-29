// Publish only paired, fully built and currently simulated engineering bits.
const fs=require('fs'),p=require('path'),crypto=require('crypto');
const base=__dirname,root=p.resolve(base,'../..');
const rel='dual_board/image_link/board_test_20261006/firefly_video',out=p.join(root,rel);
const sim=p.join(base,'sim/firefly_video_20261006');
if(fs.existsSync(p.join(out,'manifest.json')))throw Error('Already published');
const hash=f=>crypto.createHash('sha256').update(fs.readFileSync(f)).digest('hex').toUpperCase();
const oldDir=p.join(base,'board_test_20261006/star_flow');
const old=JSON.parse(fs.readFileSync(p.join(oldDir,'manifest.json'),'utf8'));
for(const s of old.sources)if(hash(p.join(root,s.file))!==s.sha256)throw Error('Baseline input changed '+s.file);
for(const a of old.artifacts)if(hash(p.join(oldDir,a.file))!==a.sha256)throw Error('Baseline bit changed '+a.file);
const checks={stars:['PASS star motion:','PASS star control:','PASS dual stars pixels:','PASS control guard:','PASS CTL3 guard:'],
 preview:['PASS B third-image star preview:']};
const regression=Object.entries(checks).map(([name,markers])=>{
 const file=p.join(sim,name+'.log'),txt=fs.readFileSync(file,'utf8');
 if(/\*\* (Fatal|Error)|Errors: [1-9]/.test(txt)||markers.some(s=>!txt.includes(s)))throw Error('Failed/missing '+name);
 return {name,passed:true,markers,sha256:hash(file),mtime:fs.statSync(file).mtime.toISOString()};
});
const resources={},artifacts=[],sources=new Map();
function copy(src,dest){const dst=p.join(out,dest);fs.mkdirSync(p.dirname(dst),{recursive:true});fs.copyFileSync(src,dst);}
for(const board of ['A','B']){
 const dir=p.join(base,'prj/firefly_video_'+board.toLowerCase()+'_20261006'),stem='MEDIA_'+board+'_FIREFLY_VIDEO_20261006';
 const logs=fs.readdirSync(dir).filter(f=>/^td_.*\.log$/.test(f)).map(f=>p.join(dir,f));logs.sort((a,b)=>fs.statSync(b).mtimeMs-fs.statSync(a).mtimeMs);
 if(!fs.readFileSync(logs[0],'utf8').includes('Generate bits file '+stem+'.bit.'))throw Error('Incomplete build '+board);
 const area=fs.readFileSync(p.join(dir,stem+'_phy.area'),'utf8'),timing=fs.readFileSync(p.join(dir,stem+'_pr.timing'),'utf8');
 const num=k=>Number(area.match(new RegExp('^\\s*#'+k+'\\s+(\\d+)','m'))[1]);
 const slack=timing.match(/SWNS: ([\-\d.]+)ns, STNS: [\-\d.]+ns\s+HWNS: ([\-\d.]+)ns/);
 const self=k=>Number(timing.slice(timing.indexOf('Path Group     :     '+k+' -> '+k)).match(/Max\s+: SWNS\s+([\-\d.]+)ns/)[1]);
 resources[board]={lut:num('lut'),lut_percent:Number((num('lut')/196).toFixed(2)),registers:num('reg'),bram9k:num('bram9k'),bram32k:num('bram32k'),dsp:num('dsp'),pll:num('pll'),
  setup_ns:Number(slack[1]),hold_ns:Number(slack[2]),video_self_ns:self(board==='A'?'video_clk':'compute_clk'),udp_self_ns:self('udp_clk'),lut_delta:num('lut')-old.resources[board].lut};
 if(board==='B')resources[board].sd_self_ns=self('sd_clk');
 for(const k of ['bram9k','bram32k','dsp','pll'])if(resources[board][k]!==old.resources[board][k])throw Error('Unexpected resource growth '+board+' '+k);
 const bit=p.join(dir,stem+'.bit');artifacts.push({board,file:stem+'.bit',bytes:fs.statSync(bit).size,sha256:hash(bit)});copy(bit,stem+'.bit');
 copy(logs[0],'evidence/'+board+'_build.log');copy(p.join(dir,'build_flow.tcl'),'evidence/'+board+'_build.tcl');
 for(const suffix of ['.al','_phy.area','_gate.area','_pr.timing','_phy.ts'])copy(p.join(dir,stem+suffix),'evidence/'+stem+suffix);
 for(const m of fs.readFileSync(p.join(dir,stem+'.al'),'utf8').matchAll(/<File Path="([^"]+)"/g)){
  const f=m[1],relative=p.relative(root,f).replaceAll('\\','/');
  if(relative.startsWith('../')||p.isAbsolute(relative)||!fs.existsSync(f))throw Error('Bad source '+relative);
  sources.set(relative,{file:relative,sha256:hash(f)});
 }
}
const oldShader='dual_board/image_link/rtl/dual_star_flow_20261006/video_dual_star_overlay.v';
const newShader='dual_board/image_link/rtl/firefly_video_20261006/video_dual_star_overlay.v';
const oldInputs=old.sources.filter(s=>s.file!==oldShader),newInputs=[...sources.values()].filter(s=>s.file!==newShader);
if(JSON.stringify(oldInputs.map(s=>s.file).sort())!==JSON.stringify(newInputs.map(s=>s.file).sort()))throw Error('Changes beyond shader');
for(const s of sources.values())copy(p.join(root,s.file),'source_snapshot/'+s.file);
for(const r of regression)copy(p.join(sim,r.name+'.log'),'evidence/'+r.name+'.log');
for(const f of fs.readdirSync(sim))if(/\.(v|vh|do|ps1|py)$/.test(f))copy(p.join(sim,f),'tests/'+f);
const pcm=p.join(root,'best_result/yilu_replace_20261006/TF_CARD/MUSIC2.PCM');
if(hash(pcm)!==old.music2_sha256)throw Error('Existing song 2 PCM changed');
const reference='C:/Users/28492/xwechat_files/wxid_5n1i5mtgjsdh22_d795/msg/video/2026-10/bd82a9a0a1164844b52b25463d7d977f.mp4';
copy(p.join(sim,'software_preview/firefly_dual_screen_12s.mp4'),'software_preview.mp4');
copy(p.join(sim,'software_preview/preview_00s.png'),'software_preview_00s.png');
copy(p.join(sim,'software_preview/preview_08s.png'),'software_preview_08s.png');
const manifest={version:'firefly_video_20261006',created_at:new Date().toISOString(),hardware_verified:false,timing_closed:false,
 usage:'Paired A+B PROGRAM_SRAM engineering candidate only; no automatic programming or TF writes',
 reference_video:{path:reference,sha256:hash(reference),duration_seconds:19.07,interpretation:'screen fireflies only; no external ambient lamp controller added'},
 lights:{count:30,size_counts:{large:4,medium:6,small:20},palette:'yellow-green halos with pale warm cores',
  world_size:[1280,480],viewports:{A:[0,639],B:[640,1279]},
  timeline_ticks:16384,tick_hz:125000000/976563,cycle_seconds:128.000065536,
  common_pan:{range_px:[0,191.8125],cycle_seconds:128.000065536},
  local_drift:{range_px:[-16,15.75],x_period_seconds:32.000016384,y_period_seconds:64.000032768},
  breathing:{main_period_seconds:8.000004096,other_period_seconds:16.000008192,independent_seed_per_point:true},
  master:'B 125MHz, base reset only; phase now an animation timestamp; never mix with previous star bit',
  row_cache:'10x27-bit distributed RAM; 30 blanking clocks evaluate all 30 lights with one shared evaluator',
  protocol:'existing CTL3 14-byte length, CRC, sequence and phase bounds unchanged; timestamp semantics updated on both boards',
  synchronization:'frame-atomic animation phase, not electrical HDMI genlock',audio_independent:true},
 resources,artifacts,sources:[...sources.values()],regression,
 unchanged_sources:oldInputs.length,baseline:'dual_board/image_link/board_test_20261006/star_flow',
 tf:'Unchanged latest two PCM and four BMP files; no new video/animation frames stored on TF',
 music2_pcm:'best_result/yilu_replace_20261006/TF_CARD/MUSIC2.PCM',music2_sha256:hash(pcm),
 caveats:'Global timing not closed; A video self setup only +0.163ns in seed4 (previous +4.383ns). B SD self negative. Native cache/FIFO tests model SDRAM and encrypted HDMI/PHY; no hardware acceptance.',
 software_preview:'software_preview.mp4: 12s/30fps equation raster preview on existing night hills repeated across two screens; excludes hardware status/time layers and monitor characteristics',
 carried_baseline_tests:'Prior functional regressions are carried evidence only, not rerun this turn; only shared star shader/time-source input changed.',
 waveforms:['motion.wlf','star_control.wlf','star_pixels.wlf','preview.wlf'].map(f=>'dual_board/image_link/sim/firefly_video_20261006/'+f)};
const notes=`# 视频风格双屏休闲灯光（2026-10-06）

## 本版效果

根据用户提供的 19 秒视频，将原先大范围整排往返星点改成萤火虫式漂浮：30 个光点中 4 个主光点、6 个中光点、20 个细小辅光点，黄绿色柔光与淡暖色亮芯。各光点的横向、纵向漂浮和明暗呼吸错开；主光点约 8 秒呼吸一轮，其余约 16 秒，并非所有光点同时闪烁。

B 为唯一时间源，约 128Hz 更新，128 秒整体循环。局部 X/Y 漂浮周期为 32/64 秒，位移约 ±16 像素；共同横移约 0–192 像素–0，128 秒一轮，保留跨屏空间接续。所有运动用轻量分段缓动，不依赖音乐、音量、静音、KEY3 换歌或页面切换。不新增视频里的实体氛围灯控制器；实现的是两路 HDMI 屏内灯光。

A 仍只在第三页显示，参数和原有时钟保持在灯光层上方；B 仍固定第三张 TF 图片。首页、歌词、歌曲封面、串口、音频、预警等输入源码未变。本版没有加入刚制作的仪表背景，仪表功能尚未实现。

## 下载与验证

分别通过 PROGRAM_SRAM 下载 MEDIA_A_FIREFLY_VIDEO_20261006.bit 和 MEDIA_B_FIREFLY_VIDEO_20261006.bit。必须两板一起更新：CTL3 的格式和 CRC 不变，但相位字段解释已改为动画时间戳，不要混烧旧星点版。

TF 文件无需修改，沿用最新两首 PCM 和原有四张 BMP。MUSIC2.PCM 应为上一版新录音的 56489984 字节版本；本次未写 TF、未修改音频。网线直连、A 屏在左 B 屏在右，A 停留第三页并关闭自动轮播，观察至少 30 秒：少量主光点与柔和小光点，独立呼吸、慢速二维漂浮，无整排扫动；再测试静音、换歌、切页及预警，确认原功能保持。

software_preview.mp4 是 12 秒/30fps 的软件方程预览，不是上板录屏。使用已有山丘背景在两屏重复，不含硬件状态/时间图层，仅用于看灯光形态。

## 完整布局布线资源

| 资源 | A | B |
|---|---:|---:|
| LUT | ${resources.A.lut}（${resources.A.lut_percent}%） | ${resources.B.lut}（${resources.B.lut_percent}%） |
| 相比 star_flow LUT 变化 | +${resources.A.lut_delta} | +${resources.B.lut_delta} |
| 寄存器 | ${resources.A.registers} | ${resources.B.registers} |
| BRAM9K / BRAM32K | ${resources.A.bram9k} / ${resources.A.bram32k} | ${resources.B.bram9k} / ${resources.B.bram32k} |
| DSP / PLL | ${resources.A.dsp} / ${resources.A.pll} | ${resources.B.dsp} / ${resources.B.pll} |
| 全局建立 / 保持 ns | ${resources.A.setup_ns} / ${resources.A.hold_ns} | ${resources.B.setup_ns} / ${resources.B.hold_ns} |
| 视频域自身建立 ns | ${resources.A.video_self_ns} | ${resources.B.video_self_ns} |
| UDP 域自身建立 ns | ${resources.A.udp_self_ns} | ${resources.B.udp_self_ns} |

没有新增 BRAM、DSP、PLL、帧缓存或网络包大小；小行缓存仅从 10×25 位增加到 10×27 位，通过空白期复用计算避免 30 套并行绘制器。

**时序并未闭合，尚未上板验证。A 视频自身建立裕量从旧版 +4.383ns 降到本版 +${resources.A.video_self_ns}ns，余量很小，不能据此保证稳定。B SD 域自身建立为 ${resources.B.sd_self_ns}ns。** 布局变化会影响未改动逻辑的路径；没有修改引脚、约束、PLL、SDRAM 仲裁或 FIFO 深度。仅供 SRAM 工程验证，不建议直接固化 FLASH。如不稳定，烧回 star_flow 目录的配套两板 bit；旧版完整保留。

## 本次验证

六项 ModelSim PASS：32770 个准确动画 tick，两个 16384-tick 循环及分频为 1/3 的边界；CTL3 原子同步、CRC 错包、丢包保留/恢复、静音与 PCM 独立性；两屏 4915200 个 RGB 精确比对，覆盖二维漂浮、大小亮度、帧内相位变化不撕裂、其他页旁路及 36 个跨屏接缝像素；原控制/CTL3 守卫；B 原生缓存到 HDMI 的 3 次完整帧、BMP 正负高度、FIFO 信用、刷新停顿、中止保留、帧槽保护、DE/SOF/EOL 对齐。

SDRAM 与加密 HDMI/PHY 仍为接口仿真模型，不能替代物理时序/电气验收。之前全功能回归没有冒称本轮重跑；除一个共享灯光源码外，其余 ${oldInputs.length} 个项目输入散列与 star_flow 相同。证据见 evidence、source_snapshot 与 manifest.json。

重跑：sim/firefly_video_20261006/run_stars.do 和 run_preview.do；重建：prj/firefly_video_a_20261006/build_flow.tcl、prj/firefly_video_b_20261006/build_flow.tcl。
`;
console.log('*** Begin Patch');
for(const [f,s] of [['manifest.json',JSON.stringify(manifest,null,2)],['使用说明.md',notes]]){
 console.log('*** Add File: '+rel+'/'+f);for(const l of s.split(/\r?\n/))console.log('+'+l);
}
console.log('*** End Patch');
