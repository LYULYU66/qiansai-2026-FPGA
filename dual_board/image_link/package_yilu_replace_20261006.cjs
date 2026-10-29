// Publish only complete builds and passing current tests; prior releases preserved.
const fs=require('fs'),p=require('path'),crypto=require('crypto');
const base=__dirname,root=p.resolve(base,'../..');
const seed4=process.argv.includes('--seed4');
const rel='dual_board/image_link/board_test_20261006/yilu_replace'+(seed4?'_s4':'');
const out=p.join(root,rel),sim=p.join(base,'sim/yilu_replace_20261006');
if(fs.existsSync(p.join(out,'manifest.json')))throw Error('Already published');
const hash=f=>crypto.createHash('sha256').update(fs.readFileSync(f)).digest('hex').toUpperCase();
const checks={cover:['PASS RGB565 cover:'],features:['PASS dualsong control:','PASS dualsong timeline:'],
 reader:['PASS two-song reader reverse=0','PASS two-song reader reverse=1'],
 boundary:['PASS player B boundary:','PASS B third-image source:'],
 audio:['PASS audio status:','PASS visual guard:','PASS remote compute:','PASS audio offload:'],
 stars:['PASS star control:','PASS dual stars pixels:','PASS control guard:','PASS CTL3 guard:'],
 selection:['PASS B third-image selection:'],uart:['PASS CTL3 UART control:']};
const regression=Object.entries(checks).map(([name,markers])=>{
 const file=p.join(sim,name+'.log'),txt=fs.readFileSync(file,'utf8');
 if(/\*\* (Fatal|Error)|Errors: [1-9]/.test(txt)||markers.some(s=>!txt.includes(s)))throw Error('Failed/missing '+name);
 return {name,passed:true,markers,sha256:hash(file),mtime:fs.statSync(file).mtime.toISOString()};
});
const oldDir=p.join(base,'board_test_20261006/dual_stars');
const old=JSON.parse(fs.readFileSync(p.join(oldDir,'manifest.json'),'utf8'));
for(const s of old.sources)if(hash(p.join(root,s.file))!==s.sha256)throw Error('Old source changed '+s.file);
for(const a of old.artifacts)if(hash(p.join(oldDir,a.file))!==a.sha256)throw Error('Old bit changed '+a.file);
const resources={},artifacts=[],sources=new Map();
fs.mkdirSync(out,{recursive:true});
function copy(source,dest){const dst=p.join(out,dest);fs.mkdirSync(p.dirname(dst),{recursive:true});fs.copyFileSync(source,dst);}
for(const board of ['A','B']){
 const dir=p.join(base,'prj/yilu_replace_'+board.toLowerCase()+(seed4&&board==='B'?'_seed4':'')+'_20261006');
 const stem='MEDIA_'+board+'_YILU_REPLACE_20261006';
 const logs=fs.readdirSync(dir).filter(f=>/^td_.*\.log$/.test(f)).map(f=>p.join(dir,f));
 logs.sort((a,b)=>fs.statSync(b).mtimeMs-fs.statSync(a).mtimeMs);
 const build=fs.readFileSync(logs[0],'utf8');
 if(!build.includes('Generate bits file '+stem+'.bit.'))throw Error('Build incomplete '+board);
 const area=fs.readFileSync(p.join(dir,stem+'_phy.area'),'utf8');
 const timing=fs.readFileSync(p.join(dir,stem+'_pr.timing'),'utf8');
 const num=k=>Number(area.match(new RegExp('^\\s*#'+k+'\\s+(\\d+)','m'))[1]);
 const slack=timing.match(/SWNS: ([\-\d.]+)ns, STNS: [\-\d.]+ns\s+HWNS: ([\-\d.]+)ns/);
 const self=k=>Number(timing.slice(timing.indexOf('Path Group     :     '+k+' -> '+k)).match(/Max\s+: SWNS\s+([\-\d.]+)ns/)[1]);
 resources[board]={lut:num('lut'),lut_percent:Number((num('lut')/196).toFixed(2)),registers:num('reg'),
  bram9k:num('bram9k'),bram32k:num('bram32k'),dsp:num('dsp'),pll:num('pll'),
  setup_ns:Number(slack[1]),hold_ns:Number(slack[2]),udp_self_ns:self('udp_clk'),
  video_self_ns:self(board==='A'?'video_clk':'compute_clk')};
 const bit=p.join(dir,stem+'.bit');
 artifacts.push({board,file:stem+'.bit',bytes:fs.statSync(bit).size,sha256:hash(bit)});copy(bit,stem+'.bit');
 copy(logs[0],'evidence/'+board+'_build.log');copy(p.join(dir,'build_replace.tcl'),'evidence/'+board+'_build.tcl');
 for(const suffix of ['.al','_phy.area','_gate.area','_pr.timing','_phy.ts'])copy(p.join(dir,stem+suffix),'evidence/'+stem+suffix);
 for(const m of fs.readFileSync(p.join(dir,stem+'.al'),'utf8').matchAll(/<File Path="([^"]+)"/g)){
  const file=m[1],relative=p.relative(root,file).replaceAll('\\','/');
  if(relative.startsWith('../')||p.isAbsolute(relative)||!fs.existsSync(file))throw Error('Bad source '+relative);
  sources.set(relative,{file:relative,sha256:hash(file)});
 }
}
for(const s of sources.values())copy(p.join(root,s.file),'source_snapshot/'+s.file);
for(const r of regression)copy(p.join(sim,r.name+'.log'),'evidence/'+r.name+'.log');
for(const f of fs.readdirSync(sim))if(/\.(v|vh|do|ps1)$/.test(f))copy(p.join(sim,f),'tests/'+f);
for(const f of fs.readdirSync(p.join(root,'assets/lyrics/yilu_replace_20261006')))
 copy(p.join(root,'assets/lyrics/yilu_replace_20261006',f),'assets/'+f);
const pcm=p.join(root,'best_result/yilu_replace_20261006/TF_CARD/MUSIC2.PCM');
const pcmData=JSON.parse(fs.readFileSync(p.join(root,'best_result/yilu_replace_20261006/pcm_manifest.json'),'utf8'));
if(hash(pcm)!==pcmData.sha256.toUpperCase())throw Error('PCM changed');
copy(pcm,'TF_CARD/MUSIC2.PCM');
for(const f of ['pcm_manifest.json','asset_audit.json','cover_rgb565_preview.png'])copy(p.join(root,'best_result/yilu_replace_20261006',f),f);
const manifest={version:'yilu_replace_20261006'+(seed4?'_s4':''),created_at:new Date().toISOString(),hardware_verified:false,timing_closed:false,
 layout_seed:{A:4,B:seed4?4:3},
 seed_tradeoff:seed4?'B seed 4 favors 25MHz video/compute (+7.859ns vs -0.212ns) and LUT (-31); UDP (-1.691 vs -1.300ns) and global hold (-1.796 vs -1.638ns) worsen; NOT globally timing closed.':'B seed 3 has negative 25MHz self slack; engineering candidate only.',
 usage:'Paired A+B engineering candidate, PROGRAM_SRAM only, no automatic programming or TF overwrite',
 changes:['Full replacement song 2 PCM (48k s16le stereo)',
  '34 user-supplied lyric rows newly aligned to replacement recording; 360 timed events; unchanged font and Gaobai bank',
  '64x64 RGB565 antialiased circular supplied photograph, 549 distinct colors; 64 music/40 home native display',
  'Cover lookahead corrected and tested against registered source, no RGB/DE latency'],
 preserved:'Baseline 122 source and 2 bit hashes verified unchanged. Third TF picture on B and audio-independent shared stars unchanged.',
 resources,artifacts,sources:[...sources.values()],regression,pcm:pcmData,
 caveats:'Forced WORD timestamps with subdivided character spans are estimates, not verified syllables; needs audition. Existing negative routed timing persists. No physical hardware acceptance.',
 waveforms:['cover.wlf','timeline.wlf','control.wlf','b_boundary.wlf','source.wlf'].map(f=>'dual_board/image_link/sim/yilu_replace_20261006/'+f)};
const notes=`# 一路向北新录音、歌词校准及全彩封面（2026-10-06）

## 文件与下载

- A：MEDIA_A_YILU_REPLACE_20261006.bit；B：MEDIA_B_YILU_REPLACE_20261006.bit。两块板配套更新，用 PROGRAM_SRAM 先验证，不代你烧录，不建议直接固化。
- 将 TF_CARD/MUSIC2.PCM 复制到 **B 板 TF 卡根目录**，替换原 MUSIC2.PCM；建议先在电脑保留旧文件。MUSIC.PCM（告白气球）和四张 BMP 不变。未自动写入 TF 卡。
- 新文件为 ${pcmData.bytes} 字节，${pcmData.sample_frames} 个立体声采样帧，约 4 分 54 秒；48 kHz、16-bit signed little-endian、双声道交织、无文件头，不要另加 WAV 文件头或改采样格式。补齐末尾 73 个静音采样帧（1.52 ms）以对齐 512 字节扇区。
- 此版歌词/歌名/封面选择与新文件长度匹配；不要只换 PCM 而继续用旧歌词 bit，也不要用新 bit 配旧 MUSIC2.PCM。

## 封面与歌词

保留用户提供的同一张电影截图，居中方形裁切，圆形透明区域用原卡片白底代替并抗锯齿处理。40×40、15 色升级为 64×64、RGB565（16-bit，实际 549 种颜色），音乐页不再把 40 像素强行放大到 64 像素。首页仍维持 40×40，布局、歌名和控制图标位置不变。新增资源采用 BRAM 存储而非 LUT 查色，没有新增 DSP、帧缓存或 PLL；这仍是 640×480 页面中的小封面，不是提升整屏分辨率。

根据新 MP3 的实际声音重新生成 34 行用户提供歌词的时间轴及逐字红色进度，仍显示本句+下句，不添加边框，前奏/曲间预备、歌曲信息和 EOF 重启保留。告白气球的 373 个事件和两首歌的字模/字符 ROM 经逐字节对比未变。校准采用本地模型对已提供文字做词级音频对齐，字级跨度在词内划分；属于估计，不能用仿真证明每个字与歌声完全吻合，需要上板试听。

## 资源（完整布局布线）

| 资源 | A | B |
|---|---:|---:|
| LUT | ${resources.A.lut}（${resources.A.lut_percent}%） | ${resources.B.lut}（${resources.B.lut_percent}%） |
| 寄存器 | ${resources.A.registers} | ${resources.B.registers} |
| BRAM9K | ${resources.A.bram9k}/64 | ${resources.B.bram9k}/64 |
| BRAM32K | ${resources.A.bram32k}/16 | ${resources.B.bram32k}/16 |
| DSP / PLL | ${resources.A.dsp} / ${resources.A.pll} | ${resources.B.dsp} / ${resources.B.pll} |
| 全局建立 / 保持裕量（ns） | ${resources.A.setup_ns} / ${resources.A.hold_ns} | ${resources.B.setup_ns} / ${resources.B.hold_ns} |
| 视频域自身建立裕量（ns） | ${resources.A.video_self_ns} | ${resources.B.video_self_ns} |
| UDP 域自身建立裕量（ns） | ${resources.A.udp_self_ns} | ${resources.B.udp_self_ns} |

封面由 1 块 BRAM9K 换成 2 块 BRAM32K，A 的 BRAM32K 为 12/16。没有改时钟、PLL 或约束，但重新布局会改变各路径裕量，具体见表。时序仍未闭合，bit 生成成功不代表板上稳定；未宣称硬件验收。请先做 SRAM 实测再决定使用，不直接固化。
${seed4?'\n种子 4 的取舍：B 的 25 MHz 视频/计算域从 -0.212 ns 改善到 +7.859 ns，LUT 减少 31；但 UDP 自身建立裕量由 -1.300 ns 变为 -1.691 ns，全局保持由 -1.638 ns 变为 -1.796 ns，并非所有路径都更好。本候选优先避免新版视频/计算域的建立违例，仍须上板验证网络音频及显示。原种子 3 候选保留。\n':''}

## 验证与验收

ModelSim 当前八组 17 项 PASS：封面 1843200 个整帧像素（9792 个封面像素）、733 个两曲歌词事件与时间戳、KEY3 消抖/切歌、双曲 TF 文件扫描、B 完整边界/新歌曲类型、音频回读/频谱波形计算/网络吞吐，以及原双屏星点、第三图选择、串口。原本的 SDRAM/加密 HDMI/PHY 仿真接口仍为模型，不是电气验收。完整新 PCM 已与新 MP3 原格式转换输出逐字节核对。

上板先测 A KEY3 从告白气球切到一路向北；首页和第二页确认新圆形封面及歌名正确、第一次人声和副歌的逐字红色进度、歌曲结尾回到歌曲信息，再切回告白气球。复测图片、预警、音量/亮度/对比度、A/B 第三图同步星点。发现问题可回到原 dual_stars 目录两板 bit 和原 MUSIC2.PCM，旧发布全部保留。

源码/日志/资源/时序报告与音频散列在 manifest.json 和 evidence 中；重跑仿真用 sim/yilu_replace_20261006/run_regression.ps1，构建在 prj/yilu_replace_a_20261006 与 prj/yilu_replace_b${seed4?'_seed4':''}_20261006 的 build_replace.tcl。布局种子 A=4，B=${seed4?4:3}。${seed4?'B 的 HDL 与种子 3 候选逐字节一致，仅改变布局种子；原种子 3 候选仍保留在 yilu_replace 目录。':''}
`;
console.log('*** Begin Patch');
for(const [file,text] of [['manifest.json',JSON.stringify(manifest,null,2)],['使用说明.md',notes]]){
 console.log('*** Add File: '+rel+'/'+file);for(const line of text.split(/\r?\n/))console.log('+'+line);
}console.log('*** End Patch');
