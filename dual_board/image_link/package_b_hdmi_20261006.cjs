// Validate/copy binary artifacts and evidence. Return text as an apply_patch
// payload, so the caller uses the normal file-editing tool for manifests/notes.
const fs=require('fs'),path=require('path'),crypto=require('crypto');
const root=path.resolve(__dirname,'../..');
const rel='dual_board/image_link/board_test_20261006/b_hdmi_image2';
const out=path.join(root,rel),sim=path.join(__dirname,'sim/b_hdmi_20261006');
if(fs.existsSync(path.join(out,'manifest.json')))throw Error('Already published');
const hash=p=>crypto.createHash('sha256').update(fs.readFileSync(p)).digest('hex').toUpperCase();
const checks={preview:['PASS B HDMI preview:'],boundary:['PASS player B boundary:','PASS B preview source:'],
 reader:['PASS two-song reader reverse=0','PASS two-song reader reverse=1'],
 features:['PASS dualsong control:','PASS dualsong timeline:'],
 audio:['PASS audio status:','PASS visual guard:','PASS remote compute:','PASS audio offload:']};
const regression=Object.entries(checks).map(([name,markers])=>{
 const file=path.join(sim,name+'.log'),text=fs.readFileSync(file,'utf8');
 if(/\*\* (Fatal|Error)|Errors: [1-9]/.test(text)||markers.some(x=>!text.includes(x)))
  throw Error('Missing/failed regression '+name);
 return {name,sha256:hash(file),passed:true,checks:text.split(/\r?\n/).filter(x=>x.includes('# PASS '))};
});
const baselineDir=path.join(__dirname,'board_test_20261006/dualsong_key3');
const old=JSON.parse(fs.readFileSync(path.join(baselineDir,'manifest.json'),'utf8'));
for(const s of old.sources)if(hash(path.join(root,s.file))!==s.sha256)throw Error('Baseline source changed: '+s.file);
for(const bit of old.artifacts)if(hash(path.join(baselineDir,bit.file))!==bit.sha256)throw Error('Baseline bit changed');
const dir=path.join(__dirname,'prj/b_hdmi_20261006'),stem='MEDIA_B_HDMI_IMAGE2_20261006';
const bit=path.join(dir,stem+'.bit'),area=fs.readFileSync(path.join(dir,stem+'_phy.area'),'utf8');
const timing=fs.readFileSync(path.join(dir,stem+'_pr.timing'),'utf8');
const builds=fs.readdirSync(dir).filter(x=>/^td_.*\.log$/.test(x)).map(x=>path.join(dir,x));
builds.sort((a,b)=>fs.statSync(b).mtimeMs-fs.statSync(a).mtimeMs);
const build=builds[0],log=fs.readFileSync(build,'utf8');
if(/\bERROR:/.test(log)||!log.includes('Generate bits file '+stem+'.bit.'))throw Error('Build incomplete');
const num=n=>Number(area.match(new RegExp('^\\s*#'+n+'\\s+(\\d+)','m'))[1]);
const slack=timing.match(/SWNS: ([\-\d.]+)ns, STNS: [\-\d.]+ns\s+HWNS: ([\-\d.]+)ns/);
const self=n=>Number(timing.slice(timing.indexOf('Path Group     :     '+n+' -> '+n)).match(/Max\s+: SWNS\s+([\-\d.]+)ns/)[1]);
const resources={lut:num('lut'),lut_percent:(num('lut')/196).toFixed(2),registers:num('reg'),
 bram9k:num('bram9k'),bram32k:num('bram32k'),dsp:num('dsp'),pll:num('pll'),
 setup_ns:Number(slack[1]),hold_ns:Number(slack[2]),udp_self_ns:self('udp_clk'),
 sd_self_ns:self('sd_clk'),mem_self_ns:self('mem_clk'),video_self_ns:self('compute_clk')};
fs.mkdirSync(path.join(out,'evidence'),{recursive:true});
fs.mkdirSync(path.join(out,'source_snapshot'),{recursive:true});
fs.copyFileSync(bit,path.join(out,stem+'.bit'));
for(const suffix of ['.al','_phy.area','_pr.timing','_phy.ts'])
 fs.copyFileSync(path.join(dir,stem+suffix),path.join(out,'evidence',stem+suffix));
fs.copyFileSync(build,path.join(out,'evidence/B_build.log'));
for(const {name} of regression)fs.copyFileSync(path.join(sim,name+'.log'),path.join(out,'evidence',name+'.log'));
const project=fs.readFileSync(path.join(dir,stem+'.al'),'utf8');
const sources=[...project.matchAll(/<File Path="([^"]+)"/g)].map(m=>m[1]).filter(f=>fs.existsSync(f)).map(file=>({file:path.relative(root,file).replaceAll('\\','/'),sha256:hash(file)}));
for(const s of sources){
 if(s.file.startsWith('../') || path.isAbsolute(s.file))throw Error('Unexpected source outside workspace');
 const snapshot=path.join(out,'source_snapshot',s.file);
 fs.mkdirSync(path.dirname(snapshot),{recursive:true});
 fs.copyFileSync(path.join(root,s.file),snapshot);
}
const branch=path.join(__dirname,'rtl/b_hdmi_20261006');
for(const f of fs.readdirSync(branch)){
 const relative='dual_board/image_link/rtl/b_hdmi_20261006/'+f;
 if(!sources.some(s=>s.file===relative)){
  const snapshot=path.join(out,'source_snapshot',relative);
  fs.mkdirSync(path.dirname(snapshot),{recursive:true});fs.copyFileSync(path.join(branch,f),snapshot);
 }
}
const baseline=old.resources.B;
const manifest={version:'b_hdmi_image2_20261006',created_at:new Date().toISOString(),hardware_verified:false,timing_closed:false,
 usage:'PROGRAM_SRAM candidate only, no FLASH programming performed',
 image_selection:'Second successfully scanned BMP (zero-based index 1), raw RGB before home/UI tags; output 640x480',
 dependency:'Initial image preload currently requires A/B Ethernet link and A frame receipts. B retains cached picture across media/link restarts; no standalone B-only TF boot mode.',
 audio:'Local HDMI sample/ACR valid inputs permanently zero; existing network audio/visualization/lyrics remain active for A',
 resources,delta_vs_dualsong:{lut:resources.lut-baseline.lut,registers:resources.registers-baseline.registers,bram9k:resources.bram9k-baseline.bram9k,bram32k:resources.bram32k-baseline.bram32k,dsp:resources.dsp-baseline.dsp,pll:resources.pll-baseline.pll},
 artifacts:[{board:'B',file:stem+'.bit',bytes:fs.statSync(bit).size,sha256:hash(bit),seed:3}],
 unchanged_A:old.artifacts.find(x=>x.board==='A'),baseline_B:old.artifacts.find(x=>x.board==='B'),
 sources,regression,
 simulation_limits:'SDRAM device/controller and HDMI encrypted core/PHY are test-only interface models; native FIFOs, frame FSMs, source/packets and RGB/DE/SOF/EOL are actual RTL. Does not establish electrical correctness or timing closure.',
 waveform_files:['dual_board/image_link/sim/b_hdmi_20261006/preview.wlf','dual_board/image_link/sim/b_hdmi_20261006/b_boundary.wlf','dual_board/image_link/sim/b_hdmi_20261006/source.wlf']};
const notes=`# B 板第二张原图 HDMI 输出（2026-10-06）

只更新 B 板：MEDIA_B_HDMI_IMAGE2_20261006.bit。A 板继续使用双曲 KEY3 版本，不用重新生成或下载 A；原始源码和两个旧 bit 保持不变。

## 上板

1. TD 先选 PROGRAM_SRAM，将本文件夹 B bit 下载到 B 板；不建议立即固化 FLASH。
2. TF 卡仍插 B 板，原四张 BMP、MUSIC.PCM/MUSIC2.PCM 均无需改动或复制第二份。
3. 两板原网口连接保持，A 主屏接 A 的 HDMI 输出；新增屏幕接 B 的 HDMI 输出口（不是 HDMI 输入口）。
4. 上电完成原来的图片预加载后，B 屏固定显示 TF 扫描列表的第二张图片。这里的第二张是既有读卡顺序的编号 2，不是强行按 Windows 文件名重新排序。
5. B 屏输出 640×480 的原图，没有首页卡片、参数、歌词、频谱、波形、字幕、预警或转场，也不播放 HDMI 音频。A 的切图、双曲 KEY3、串口、预警和音视频功能保持。
6. 当前复用双板预加载流程，首次显示依赖 A 在线并返回图片确认；B 单独上电、不连 A 时尚不能独立加载此图。加载成功后，网线重连/媒体重启不会主动清掉 B 已缓存画面。B 复位/断电后仍须重新预加载。

## 资源设计

复用一套 TF/FAT/BMP 缩放结果，在加 UI 标签之前分出第二张图的 RGB；只增加本地帧缓存和显示通路。双槽位放在 B 原有 8 MiB SDRAM 中，占 2,457,600 字节（约 2.34 MiB），不是把两帧放进 BRAM。写新图用非显示槽位，必须等全部 307,200 像素写完且 SDRAM 控制器尾部结束后才提交；视频帧边界切换，旧槽位真正退出显示后才允许复用。未完成和中止的重读不会暴露半帧。内存读侧仅保留一路帧流，第二路转场读 FIFO 的存储被综合删除。

复用现有 PLL 的 100 MHz 存储、100 MHz 移相、25 MHz 像素与 125 MHz 串行输出，PLL 数量不增加。HDMI 音频/ACR 输入恒为 0，没有新音频播放器或分析器；也没有复制任何界面字库和图标 ROM。

完整布局布线资源：

| B 板资源 | 原双曲版 | 本版 |
|---|---:|---:|
| LUT | ${baseline.lut}（${baseline.lut_percent}%） | ${resources.lut}（${resources.lut_percent}%） |
| 寄存器 | ${baseline.registers} | ${resources.registers} |
| BRAM9K | ${baseline.bram9k}/64 | ${resources.bram9k}/64 |
| BRAM32K | ${baseline.bram32k}/16 | ${resources.bram32k}/16 |
| DSP / PLL | ${baseline.dsp} / ${baseline.pll} | ${resources.dsp} / ${resources.pll} |

## 验证与风险

5 组 ModelSim 日志共 11 个 PASS：新增显示的 3 个完整 640×480 帧，正/负 BMP 高度方向，原始 RGB、DE、首像素 SOF、行尾 EOL、原生异步 FIFO 复位窗口/背压、刷新暂停、部分重读中止、快速重读槽位保护；真实源模块分流 307,200 个原始像素并仍传出 614,400 个正确网络 RGB/UI 像素；实际 B 顶层的双曲会话、UART、音频与重连中止；原 TF 双目录顺序/碎片 FAT/两曲切换和缺文件回退、歌词时间线、48 kHz 播放反馈、频谱波形和丢包重试等回归。波形在 sim/b_hdmi_20261006，日志在本目录 evidence。

仿真使用原生 FIFO 与实际缓存/视频/网络 RTL，但 SDRAM 控制器及设备、加密 HDMI 核与物理 PHY 使用接口模型，不等于实际 TMDS/SDRAM 电气验证。未在你的板子上验证，仍需先上板测试。

时序仍未闭合：全局建立 ${resources.setup_ns} ns、保持 ${resources.hold_ns} ns；SD 同域 ${resources.sd_self_ns} ns、UDP 同域 ${resources.udp_self_ns} ns。新增内存同域 ${resources.mem_self_ns} ns、视频同域 ${resources.video_self_ns} ns 为正，但不能据此忽略全局/跨时钟负裕量。已知 SDRAM 加密 IP 未驱动端口警告与旧 A 工程相同，完整日志保留。没有用放宽频率或大范围 false-path 掩盖问题。

验证建议：B 先显示第二张原图，A 连续切图、换歌、串口调音量；确认 B 始终保持该图且无声音，A 原功能正常。再拔插网线验证 B 保留已加载画面，重新加载成功后无半帧。若异常，B 回退 MEDIA_B_DUALSONG_KEY3_20261006.bit；A 不改，两个旧 bit 均保留在 ../dualsong_key3/。
`;
const add=(file,text)=>'*** Add File: '+file+'\n'+text.trimEnd().split('\n').map(x=>'+'+x).join('\n')+'\n';
process.stdout.write('*** Begin Patch\n'+add(rel+'/manifest.json',JSON.stringify(manifest,null,2))+add(rel+'/使用说明.md',notes)+'*** End Patch\n');
