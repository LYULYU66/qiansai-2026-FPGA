// Copy only verified artifacts/evidence. Text manifests are returned as an
// apply_patch payload; never overwrite a previous release or baseline.
const fs=require('fs'),path=require('path'),crypto=require('crypto');
const base=__dirname,root=path.resolve(base,'../..');
const rel='dual_board/image_link/board_test_20261006/dual_stars';
const out=path.join(root,rel),sim=path.join(base,'sim/dual_stars_20261006');
if(fs.existsSync(path.join(out,'manifest.json')))throw Error('Already published');
const hash=f=>crypto.createHash('sha256').update(fs.readFileSync(f)).digest('hex').toUpperCase();
const checks={stars:['PASS star control:','PASS dual stars pixels:','PASS control guard:','PASS CTL3 guard:'],
 selection:['PASS B third-image selection:'],uart:['PASS CTL3 UART control:'],
 boundary:['PASS player B boundary:','PASS B third-image source:'],preview:['PASS B third-image star preview:'],
 reader:['PASS two-song reader reverse=0','PASS two-song reader reverse=1'],
 features:['PASS dualsong control:','PASS dualsong timeline:'],
 audio:['PASS audio status:','PASS visual guard:','PASS remote compute:','PASS audio offload:']};
const regression=Object.entries(checks).map(([name,markers])=>{
 const file=path.join(sim,name+'.log'),txt=fs.readFileSync(file,'utf8');
 if(/\*\* (Fatal|Error)|Errors: [1-9]/.test(txt)||markers.some(p=>!txt.includes(p)))throw Error('Failed/missing '+name);
 return {name,passed:true,sha256:hash(file),markers};
});
// The accepted A dual-song and B second-image sources/bits must remain intact.
for(const name of ['dualsong_key3','b_hdmi_image2']){
 const dir=path.join(base,'board_test_20261006',name),m=JSON.parse(fs.readFileSync(path.join(dir,'manifest.json'),'utf8'));
 for(const s of m.sources)if(hash(path.join(root,s.file))!==s.sha256)throw Error('Baseline source changed: '+s.file);
 for(const a of m.artifacts)if(hash(path.join(dir,a.file))!==a.sha256)throw Error('Baseline bit changed: '+a.file);
}
const resources={},artifacts=[],sources=new Map();
fs.mkdirSync(path.join(out,'evidence'),{recursive:true});
function copy(source,relative){
 const dst=path.join(out,relative);fs.mkdirSync(path.dirname(dst),{recursive:true});fs.copyFileSync(source,dst);
}
for(const board of ['A','B']){
 const dir=path.join(base,'prj/dual_stars_'+board.toLowerCase()+'_20261006');
 const stem='MEDIA_'+board+'_DUAL_STARS_20261006',bit=path.join(dir,stem+'.bit');
 const area=fs.readFileSync(path.join(dir,stem+'_phy.area'),'utf8');
 const timing=fs.readFileSync(path.join(dir,stem+'_pr.timing'),'utf8');
 const logs=fs.readdirSync(dir).filter(f=>/^td_.*\.log$/.test(f)).map(f=>path.join(dir,f));
 logs.sort((a,b)=>fs.statSync(b).mtimeMs-fs.statSync(a).mtimeMs);
 if(!fs.readFileSync(logs[0],'utf8').includes('Generate bits file '+stem+'.bit.'))throw Error('Build incomplete '+board);
 const num=k=>Number(area.match(new RegExp('^\\s*#'+k+'\\s+(\\d+)','m'))[1]);
 const slack=timing.match(/SWNS: ([\-\d.]+)ns, STNS: [\-\d.]+ns\s+HWNS: ([\-\d.]+)ns/);
 const self=k=>Number(timing.slice(timing.indexOf('Path Group     :     '+k+' -> '+k)).match(/Max\s+: SWNS\s+([\-\d.]+)ns/)[1]);
 resources[board]={lut:num('lut'),lut_percent:Number((num('lut')/196).toFixed(2)),registers:num('reg'),
  bram9k:num('bram9k'),bram32k:num('bram32k'),dsp:num('dsp'),pll:num('pll'),
  setup_ns:Number(slack[1]),hold_ns:Number(slack[2]),udp_self_ns:self('udp_clk'),
  video_self_ns:self(board==='A'?'video_clk':'compute_clk')};
 artifacts.push({board,file:stem+'.bit',bytes:fs.statSync(bit).size,sha256:hash(bit),seed:board==='A'?4:3});
 copy(bit,stem+'.bit');copy(logs[0],'evidence/'+board+'_build.log');
 for(const suffix of ['.al','_phy.area','_gate.area','_pr.timing','_phy.ts'])copy(path.join(dir,stem+suffix),'evidence/'+stem+suffix);
 copy(path.join(dir,'build_stars.tcl'),'evidence/'+board+'_build_stars.tcl');
 for(const m of fs.readFileSync(path.join(dir,stem+'.al'),'utf8').matchAll(/<File Path="([^"]+)"/g)){
  const file=m[1];if(!fs.existsSync(file))throw Error('Missing source '+file);
  const relative=path.relative(root,file).replaceAll('\\','/');
  if(relative.startsWith('../')||path.isAbsolute(relative))throw Error('Outside workspace '+relative);
  sources.set(relative,{file:relative,sha256:hash(file)});
 }
}
for(const s of sources.values())copy(path.join(root,s.file),'source_snapshot/'+s.file);
for(const f of fs.readdirSync(path.join(base,'rtl/dual_stars_20261006')))
 copy(path.join(base,'rtl/dual_stars_20261006',f),'source_snapshot/dual_board/image_link/rtl/dual_stars_20261006/'+f);
for(const t of regression)copy(path.join(sim,t.name+'.log'),'evidence/'+t.name+'.log');
for(const f of fs.readdirSync(sim))if(/\.(v|vh|do|ps1)$/.test(f))copy(path.join(sim,f),'tests/'+f);
const manifest={version:'dual_stars_20261006',created_at:new Date().toISOString(),hardware_verified:false,timing_closed:false,
 usage:'Paired A+B PROGRAM_SRAM engineering candidate; no programming performed',
 display:'A page 3 (index 2); B permanently displays TF page 3 (index 2). A left/B right of shared 1280x480 star canvas.',
 motion:{direction:'right',pixels_per_second:125000000/976563/16,world_width:1280,world_height:480,
  stars:30,position_fraction_bits:4,render_fraction_bits:2,master:'B independent 125MHz counter',
  audio_independent:true,packet:'CTL3 14 bytes, settings + Q4 phase + sequence + CRC, nominal 10ms resend',
  frame_atomic:true,synchronization:'Shared animation phase, NOT electrical HDMI frame/genlock. Frame/transport delays may produce small phase differences; A holds on network loss and recovers from next valid state.'},
 resources,artifacts,sources:[...sources.values()],regression,
 limits:'Native FIFOs/capture/HDMI pixel pipeline/source/packets tested with actual RTL. SDRAM and encrypted HDMI/PHY interfaces use test models. Not a timing/electrical or hardware acceptance.',
 preserved:'Original released dual-song and B second-image source and bit hashes verified unchanged.',
 dependencies:'TF remains on B; first cached image loading still requires A online and returning image receipts. B local HDMI is silent; A original audio/features retained.',
 waveforms:['star_control.wlf','star_pixels.wlf','uart.wlf','selection.wlf','b_boundary.wlf','source.wlf','preview.wlf'].map(f=>'dual_board/image_link/sim/dual_stars_20261006/'+f)};
const notes=`# 双屏同步星点（2026-10-06）

两块板都要更新，本目录 A、B bit 需配套使用。旧双曲版和 B 第二图 HDMI 版本的源码与 bit 均已校验未改动。

## 显示效果

A 的第三页显示原背景、左上参数和原时钟，并用新星点替换旧音乐响应星点；其他页面不增加星点。B 固定读取既有 TF 扫描列表的第三张图（编号 3，内部索引 2），只显示这张图和星点，不增加卡片/歌词/音频。

两屏按 A 在左、B 在右摆放，组成横向星河。1280×480 虚拟画布中共有 30 个暖黄色软光星点，统一从左向右约 8 像素/秒，轻柔呼吸闪烁，不随音乐、音量、静音、切歌变化。位置采用 1/16 像素步进，软光按 1/4 像素计算，每帧锁定位置，跨屏边界继续运动，约 160 秒完成一次循环。

B 用原有 125 MHz 时钟计算唯一运动相位，每约 10 ms 利用既有参数包发送给 A；没有增加通信通道、音频数据量、PLL、DSP、BRAM 或图片素材。同步是动画相位同步，不是两路 HDMI 的电气锁相；由于独立视频帧边界和网络延迟，允许很小的位置差异。断网时 A 保留最后有效相位，B 继续运动，重连后 A 接续最新相位。

## 下载与验证

1. 先选 PROGRAM_SRAM，分别将 MEDIA_A_DUAL_STARS_20261006.bit 下载至 A，将 MEDIA_B_DUAL_STARS_20261006.bit 下载至 B；不要混用旧版，以免参数包格式不匹配。未代你执行烧录，不建议先固化 FLASH。
2. TF 卡仍插 B，原四张 BMP、MUSIC.PCM、MUSIC2.PCM 均无需更改；两板网线保持连接，两屏各接自己板子的 HDMI 输出口。
3. 两板上电并完成图片缓存后，B 显示第三张；A 默认手动模式，从第一页按 KEY2 两次到第三页。若已经开启自动轮播，用 KEY4 关闭轮播后停留第三页。两屏按 A 左、B 右摆放、显示区域尽量等高，观察星点缓慢向右、在 A 右边与 B 左边接续。
4. 静音、调音量或 KEY3 换歌，星点速度/方向不改变。A 切回其他页、触发危险进入第四页，不应显示星点；B 仍显示第三张。复测 A 图片切换、串口亮度/对比度/音量、双曲音频、第二页歌词/频谱、危险报警。
5. 当前沿用已验证的双板预加载流程，首次 B 图片显示依赖 A 返回图像确认；不提供 B 独立读卡启动。缓存完成后链路重启不主动清掉 B 画面。B 复位/断电后重新预加载。

## 资源（完整布局布线）

| 资源 | A 主板 | B 副板 |
|---|---:|---:|
| LUT | ${resources.A.lut}（${resources.A.lut_percent}%） | ${resources.B.lut}（${resources.B.lut_percent}%） |
| 寄存器 | ${resources.A.registers} | ${resources.B.registers} |
| BRAM9K | ${resources.A.bram9k}/64 | ${resources.B.bram9k}/64 |
| BRAM32K | ${resources.A.bram32k}/16 | ${resources.B.bram32k}/16 |
| DSP | ${resources.A.dsp}/29 | ${resources.B.dsp}/29 |
| PLL | ${resources.A.pll}/4 | ${resources.B.pll}/4 |

A 比双曲版少 ${14763-resources.A.lut} 个 LUT；B 比第三图静态 HDMI 中间版本增加 ${resources.B.lut-14036} 个 LUT。相对已上板的 B 第二图版，总增量还包含图片选择改动造成的综合/布局差异。BRAM、DSP、PLL 数量不增加。星点用仅 10×25 bit 的分布式行缓存，共用一套光晕运算；隐藏的 A 第三页停止星点行计算，第三页不再请求音乐频谱计算，歌词时间线和 PCM 播放不受影响。

与此前 A 双曲版 14763 LUT + B 第二图显示版 13986 LUT 的组合比较，两板 LUT 合计净增加 ${resources.A.lut+resources.B.lut-14763-13986} 个，实现新增双屏同步星点；这是两份完整布局布线报告之间的差值，不是把模块综合估算相加。

## 仿真与限制

8 组 ModelSim 共 17 个 PASS：491 万逐像素对照（两屏、跨屏、分数位、回绕、帧内原子更新、隐藏时原图透传）；真实参数包 CRC、非法长度/相位/音量、旧包顺序和重启恢复；实际串口命令与参数 CDC；第三图选择与原始 RGB 分流；实际 B 顶层 PCM/切歌/串口/链路恢复；原生异步 FIFO、SDRAM 帧 FSM 和 HDMI 输入像素/DE/SOF/EOL 的三个完整第三图帧；双曲 TF/FAT、歌词时间线、音频计算/频谱波形及网络重试回归。具体 PASS 和波形路径见 manifest.json，完整日志保留在 evidence。

仿真不包含真实 SDRAM 电气模型和加密 HDMI 内部，使用的是接口模型，不能替代上板验证。新 bit 尚未在你的两块板上验收，时序仍未闭合：A 建立 ${resources.A.setup_ns} ns、保持 ${resources.A.hold_ns} ns；B 建立 ${resources.B.setup_ns} ns、保持 ${resources.B.hold_ns} ns。视频同域分别为 ${resources.A.video_self_ns} / ${resources.B.video_self_ns} ns，UDP 同域分别为 ${resources.A.udp_self_ns} / ${resources.B.udp_self_ns} ns。没有修改 PLL/SDRAM 仲裁/约束来掩盖这些负裕量。

如异常，A 回退 ../dualsong_key3/MEDIA_A_DUALSONG_KEY3_20261006.bit，B 回退 ../b_hdmi_image2/MEDIA_B_HDMI_IMAGE2_20261006.bit（恢复已确认的第二张图显示）。重新构建项目为 prj/dual_stars_a_20261006、prj/dual_stars_b_20261006 各自的 build_stars.tcl；回归脚本为 sim/dual_stars_20261006/run_regression.ps1。
`;
const add=(f,t)=>'*** Add File: '+f+'\n'+t.trimEnd().split('\n').map(l=>'+'+l).join('\n')+'\n';
process.stdout.write('*** Begin Patch\n'+add(rel+'/manifest.json',JSON.stringify(manifest,null,2))+add(rel+'/使用说明.md',notes)+'*** End Patch\n');
