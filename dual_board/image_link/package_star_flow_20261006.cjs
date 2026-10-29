// Publish a paired engineering candidate only after current exact-pixel tests/builds.
const fs=require('fs'),p=require('path'),crypto=require('crypto');
const base=__dirname,root=p.resolve(base,'../..');
const rel='dual_board/image_link/board_test_20261006/star_flow',out=p.join(root,rel);
const sim=p.join(base,'sim/dual_star_flow_20261006');
if(fs.existsSync(p.join(out,'manifest.json')))throw Error('Already published');
const hash=f=>crypto.createHash('sha256').update(fs.readFileSync(f)).digest('hex').toUpperCase();
const oldDir=p.join(base,'board_test_20261006/yilu_replace_s4');
const old=JSON.parse(fs.readFileSync(p.join(oldDir,'manifest.json'),'utf8'));
for(const s of old.sources)if(hash(p.join(root,s.file))!==s.sha256)throw Error('Old source changed '+s.file);
for(const a of old.artifacts)if(hash(p.join(oldDir,a.file))!==a.sha256)throw Error('Old bit changed '+a.file);
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
 const dir=p.join(base,'prj/star_flow_'+board.toLowerCase()+'_20261006'),stem='MEDIA_'+board+'_STAR_FLOW_20261006';
 const logs=fs.readdirSync(dir).filter(f=>/^td_.*\.log$/.test(f)).map(f=>p.join(dir,f));logs.sort((a,b)=>fs.statSync(b).mtimeMs-fs.statSync(a).mtimeMs);
 if(!fs.readFileSync(logs[0],'utf8').includes('Generate bits file '+stem+'.bit.'))throw Error('Incomplete build '+board);
 const area=fs.readFileSync(p.join(dir,stem+'_phy.area'),'utf8'),timing=fs.readFileSync(p.join(dir,stem+'_pr.timing'),'utf8');
 const num=k=>Number(area.match(new RegExp('^\\s*#'+k+'\\s+(\\d+)','m'))[1]);
 const slack=timing.match(/SWNS: ([\-\d.]+)ns, STNS: [\-\d.]+ns\s+HWNS: ([\-\d.]+)ns/);
 const self=k=>Number(timing.slice(timing.indexOf('Path Group     :     '+k+' -> '+k)).match(/Max\s+: SWNS\s+([\-\d.]+)ns/)[1]);
 resources[board]={lut:num('lut'),lut_percent:Number((num('lut')/196).toFixed(2)),registers:num('reg'),bram9k:num('bram9k'),bram32k:num('bram32k'),dsp:num('dsp'),pll:num('pll'),
  setup_ns:Number(slack[1]),hold_ns:Number(slack[2]),video_self_ns:self(board==='A'?'video_clk':'compute_clk'),udp_self_ns:self('udp_clk'),lut_delta:num('lut')-old.resources[board].lut};
 for(const k of ['bram9k','bram32k','dsp','pll'])if(resources[board][k]!==old.resources[board][k])throw Error('Unexpected resource growth '+board+' '+k);
 const bit=p.join(dir,stem+'.bit');artifacts.push({board,file:stem+'.bit',bytes:fs.statSync(bit).size,sha256:hash(bit)});copy(bit,stem+'.bit');
 copy(logs[0],'evidence/'+board+'_build.log');copy(p.join(dir,'build_flow.tcl'),'evidence/'+board+'_build.tcl');
 for(const suffix of ['.al','_phy.area','_gate.area','_pr.timing','_phy.ts'])copy(p.join(dir,stem+suffix),'evidence/'+stem+suffix);
 for(const m of fs.readFileSync(p.join(dir,stem+'.al'),'utf8').matchAll(/<File Path="([^"]+)"/g)){
  const f=m[1],relative=p.relative(root,f).replaceAll('\\','/');if(relative.startsWith('../')||p.isAbsolute(relative)||!fs.existsSync(f))throw Error('Bad source '+relative);
  sources.set(relative,{file:relative,sha256:hash(f)});
 }
}
const oldShader='dual_board/image_link/rtl/dual_stars_20261006/video_dual_star_overlay.v';
const newShader='dual_board/image_link/rtl/dual_star_flow_20261006/video_dual_star_overlay.v';
const oldInputs=old.sources.filter(s=>s.file!==oldShader);
const newInputs=[...sources.values()].filter(s=>s.file!==newShader);
if(JSON.stringify(oldInputs.map(s=>s.file).sort())!==JSON.stringify(newInputs.map(s=>s.file).sort()))throw Error('Changes beyond shader');
for(const s of sources.values())copy(p.join(root,s.file),'source_snapshot/'+s.file);
for(const r of regression)copy(p.join(sim,r.name+'.log'),'evidence/'+r.name+'.log');
for(const f of fs.readdirSync(sim))if(/\.(v|vh|do|ps1)$/.test(f))copy(p.join(sim,f),'tests/'+f);
// Expose the unchanged PCM dependency by link, do not create another TF copy.
const pcm=p.join(root,'best_result/yilu_replace_20261006/TF_CARD/MUSIC2.PCM');
if(hash(pcm)!==old.pcm.sha256.toUpperCase())throw Error('Existing song 2 PCM changed');
const manifest={version:'star_flow_20261006',created_at:new Date().toISOString(),hardware_verified:false,timing_closed:false,
 usage:'Paired A+B PROGRAM_SRAM engineering candidate; no automatic programming or TF writes',
 stars:{count:30,size_counts:{large:10,medium:10,small:10},approx_glow_diameters_px:{large:[38,60],medium:[14,26],small:[5,11]},
  color:'warm-white cores and broad gold halos, staggered per-point brightness; four lanes brighter',
  world_size:[1280,480],viewports:{A:[0,639],B:[640,1279]},position_fraction_bits:4,
  speed_px_s:[0,32],leg_seconds:12.000006144,distance_per_leg_px:192,cycle_seconds:24.000012288,
  direction:'right acceleration/deceleration, then left; repeated',master:'B existing 125MHz clock, base reset only',
  motion:'integer Q4-speed/fraction accumulator; 128Hz tick and 1/16-step speed ramp every 12 ticks; no multiplier/divider',
  protocol:'unchanged CTL3, 14 bytes, existing phase snapshot/sequence/CRC',audio_independent:true,
  synchronization:'phase synchronization, not electrical HDMI genlock; A holds on loss and resynchronizes on next valid packet'},
 resources,artifacts,sources:[...sources.values()],regression,
 unchanged_sources:oldInputs.length,baseline:'dual_board/image_link/board_test_20261006/yilu_replace_s4',
 carried_baseline_tests:'Baseline 17 tests were previously passed; not claimed rerun this turn. Only the shared star shader/master source replaced; all other inputs byte-identical.',
 tf:'No change to BMP/PCM; retain latest MUSIC2.PCM (14122496 stereo frames) and existing MUSIC.PCM',
 music2_pcm:'best_result/yilu_replace_20261006/TF_CARD/MUSIC2.PCM',music2_sha256:hash(pcm),
 caveats:'Current native cache/FIFO/DE/SOF/EOL shader tests use SDRAM and encrypted HDMI/PHY interface models; no physical acceptance; global timing remains open.',
 waveforms:['motion.wlf','star_control.wlf','star_pixels.wlf','preview.wlf'].map(f=>'dual_board/image_link/sim/dual_star_flow_20261006/'+f)};
const notes=`# 双屏星空增强 / 平滑往返（2026-10-06）

## 效果

30 个星点分为 10 个大星、10 个中星和 10 个小星，发光直径大致为 38–60、14–26、5–11 像素（随亮度变化，非硬圆框）。大星具有暖白亮芯和更宽的金色柔光；大小、基础亮度、亮暗相位有差异，不做全屏同步闪烁。

B 为唯一运动主板，既有 125 MHz 时钟生成平滑速度斜坡：接近静止 → 约 32 像素/秒 → 减速至零，约 12 秒后向左做同样的加速/减速，再往右，约 24 秒往返一轮，每个单向段约移动 192 像素。换向发生在零速度附近，不突然反向。1280×480 星点世界保持 A 在左、B 在右，统一相位跨屏接续；不随音量、静音、音乐播放、KEY3 换歌或切页改变运动。

A 只在第三页显示星点，左上参数和时钟保留并在星空图层之上。B 仍固定显示 TF 第三张图片及星点；首页、歌词、音乐封面、字幕、频谱、波形、危险提示等沿用上一版。

## 下载与验收

分别用 PROGRAM_SRAM 给 A 下载 MEDIA_A_STAR_FLOW_20261006.bit，给 B 下载 MEDIA_B_STAR_FLOW_20261006.bit；两板都更新。未自动烧录，不建议先固化 FLASH。TF 卡文件不需要为本次星空升级修改，沿用上一版两曲 PCM 和四张 BMP；上一版替换 MP3 对应 MUSIC2.PCM 为 56489984 字节（14122496 立体声帧），在 best_result/yilu_replace_20261006/TF_CARD/MUSIC2.PCM。

网线直连，两屏 A 左 B 右摆放。完成缓存后，让 A 停留第三页（KEY2 切换，KEY4 关闭自动轮播），观察至少 30 秒：星点大小/亮度有层次，缓慢加速再减速，左右轮流运动，两屏接续；静音、换歌不改变动画。切回首页/音乐页/预警页，确认没有星点覆盖；B 仍显示第三图。

重新布局的 bit 尚未上板验收，全局时序仍有负裕量。两路 HDMI 是共享动画相位，不是电气锁相；独立帧边界与约 10 ms 网络发送周期可能带来很小的位置差。断网 A 保留有效相位，B 继续运动，重连时接续新相位。若不稳定，可回到 yilu_replace_s4 目录的 A/B 配套 bit；旧版源码、bit 和 PCM 均未改动。

## 资源（完整布局布线）

| 资源 | A | B |
|---|---:|---:|
| LUT | ${resources.A.lut}（${resources.A.lut_percent}%） | ${resources.B.lut}（${resources.B.lut_percent}%） |
| 相对上一版 LUT 变化 | ${resources.A.lut_delta} | ${resources.B.lut_delta} |
| 寄存器 | ${resources.A.registers} | ${resources.B.registers} |
| BRAM9K / BRAM32K | ${resources.A.bram9k} / ${resources.A.bram32k} | ${resources.B.bram9k} / ${resources.B.bram32k} |
| DSP / PLL | ${resources.A.dsp} / ${resources.A.pll} | ${resources.B.dsp} / ${resources.B.pll} |
| 全局建立 / 保持（ns） | ${resources.A.setup_ns} / ${resources.A.hold_ns} | ${resources.B.setup_ns} / ${resources.B.hold_ns} |
| 视频域自身建立（ns） | ${resources.A.video_self_ns} | ${resources.B.video_self_ns} |
| UDP 域自身建立（ns） | ${resources.A.udp_self_ns} | ${resources.B.udp_self_ns} |

未增加 BRAM、DSP、PLL、帧缓存或网络包大小，沿用 10×25 位小行缓存。仅替换一个共享的星点 RTL 源文件，其他 ${oldInputs.length} 个项目输入的哈希与上一版一致；没有改 TF、音频/歌词、UART、引脚、PLL、时钟约束、SDRAM 仲裁或 FIFO 深度。

## 验证证据

本次 ModelSim 六项 PASS：7680 个精确速度/位置 tick（五次零速换向、正反模边界、分数积分器、复位）；CTL3 丢包、CRC、静音独立运动和帧边界原子同步；两屏 4915200 个精确 RGB 对比（三档大小/亮度、四分之一像素、相位边界、跨屏边缘、其他页旁路）；兼容控制及 CTL3 协议守卫；B 本地 HDMI 路径 3 次完整 640×480 缓存，检查原生 FIFO、RGB/DE/SOF/EOL、刷新停顿、中止保留和帧槽保护。

SDRAM、加密 HDMI/PHY 接口仍使用仿真模型，不代表实板时序或电气验收。上一版 17 项功能测试是既有证据，不冒充本次重新执行；本次未修改其他源文件。日志、布局布线资源/时序报告、源码快照及散列见 evidence 和 manifest.json。

重跑：sim/dual_star_flow_20261006/run_stars.do 与 run_preview.do；构建：prj/star_flow_a_20261006/build_flow.tcl 和 prj/star_flow_b_20261006/build_flow.tcl。
`;
console.log('*** Begin Patch');for(const [f,s] of [['manifest.json',JSON.stringify(manifest,null,2)],['使用说明.md',notes]]){
 console.log('*** Add File: '+rel+'/'+f);for(const l of s.split(/\r?\n/))console.log('+'+l);
}console.log('*** End Patch');
