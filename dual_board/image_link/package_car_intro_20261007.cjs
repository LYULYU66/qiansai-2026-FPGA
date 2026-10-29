// Publish only fully checked versioned inputs. Old releases are never modified.
const fs=require('fs'),p=require('path'),crypto=require('crypto');
const base=__dirname,root=p.resolve(base,'../..'),prior=p.join(base,'board_test_20261007/stars_opt');
const rel='dual_board/image_link/board_test_20261007/car_intro',out=p.join(root,rel),sim=p.join(base,'sim/car_intro_20261007');
if(fs.existsSync(p.join(out,'manifest.json')))throw Error('Already published');
const hash=f=>crypto.createHash('sha256').update(fs.readFileSync(f)).digest('hex').toUpperCase();
const old=JSON.parse(fs.readFileSync(p.join(prior,'manifest.json'),'utf8'));
for(const x of old.sources)if(hash(p.join(root,x.file))!==x.sha256)throw Error('Changed baseline input:'+x.file);
for(const x of old.artifacts)if(hash(p.join(prior,x.file))!==x.sha256)throw Error('Changed baseline bit:'+x.file);
const cases={car:['PASS car sprite ROM:','PASS car pixels:','PASS car lifecycle:'],boundary:['PASS manual-dual B boundary:'],preview:['PASS B manual TF5/TF6 preview:']};
const regression=Object.entries(cases).map(([name,markers])=>{
 const file=name+'.log',f=p.join(sim,file),t=fs.readFileSync(f,'utf8');
 const passed=t.split(/\r?\n/).filter(l=>/^# PASS /.test(l));
 if(/\*\* (Fatal|Error)|Errors: [1-9]/.test(t)||passed.length!==markers.length||markers.some(x=>!t.includes(x)))throw Error('Failed/incomplete '+file);
 return {file,pass_count:passed.length,pass_lines:passed,sha256:hash(f),mtime:fs.statSync(f).mtime.toISOString()};
});
const dir=p.join(base,'prj/car_intro_b_20261007'),stem='MEDIA_B_CAR_INTRO_20261007';
const logs=fs.readdirSync(dir).filter(f=>/^td_.*\.log$/.test(f)).map(f=>p.join(dir,f)).sort((a,b)=>fs.statSync(b).mtimeMs-fs.statSync(a).mtimeMs);
const build=fs.readFileSync(logs[0],'utf8');
if(!build.includes('Generate bits file '+stem+'.bit.')||/RUN-\d+ ERROR|Incremental route failed/.test(build))throw Error('Build incomplete');
const area=fs.readFileSync(p.join(dir,stem+'_phy.area'),'utf8'),timing=fs.readFileSync(p.join(dir,stem+'_pr.timing'),'utf8');
if(!/Confidence\s*:\s*Routed/.test(timing))throw Error('Not routed');
const num=k=>Number(area.match(new RegExp('^\\s*#'+k+'\\s+(\\d+)','m'))[1]);
const slack=timing.match(/SWNS: ([\-\d.]+)ns, STNS: [\-\d.]+ns\s+HWNS: ([\-\d.]+)ns/);
const self=k=>{const i=timing.indexOf('Path Group     :     '+k+' -> '+k);if(i<0)throw Error('No clock '+k);const s=timing.slice(i);return {setup_ns:Number(s.match(/Max\s+: SWNS\s+([\-\d.]+)ns/)[1]),hold_ns:Number(s.match(/Min\s+: HWNS\s+([\-\d.]+)ns/)[1])};};
const resources={A:{...old.resources.A,lut_delta:0,reg_delta:0,unchanged:true},B:{seed:3,lut:num('lut'),lut_percent:Number((num('lut')/196).toFixed(2)),registers:num('reg'),bram9k:num('bram9k'),bram32k:num('bram32k'),dsp:num('dsp'),pll:num('pll'),setup_ns:Number(slack[1]),hold_ns:Number(slack[2]),video:self('compute_clk'),udp:self('udp_clk'),sd:self('sd_clk'),lut_delta:num('lut')-old.resources.B.lut,reg_delta:num('reg')-old.resources.B.registers}};
if(resources.B.bram32k!==old.resources.B.bram32k+3||resources.B.bram9k!==old.resources.B.bram9k||resources.B.dsp!==old.resources.B.dsp||resources.B.pll!==old.resources.B.pll)throw Error('Unexpected memory/DSP/PLL change');
const evidence=[],artifacts=[],sources=new Map();
function copy(src,dst){const f=p.join(out,dst);fs.mkdirSync(p.dirname(f),{recursive:true});fs.copyFileSync(src,f);evidence.push({file:dst,sha256:hash(f)});}
const a=old.artifacts.find(x=>x.board==='A');copy(p.join(prior,a.file),a.file);artifacts.push({...a,unchanged:true});
const bit=p.join(dir,stem+'.bit');copy(bit,stem+'.bit');artifacts.push({board:'B',file:stem+'.bit',bytes:fs.statSync(bit).size,sha256:hash(bit)});
const axml=p.join(base,'prj/stars_opt_a_s4_20261007/MEDIA_A_STARS_OPT_S4_20261007.al');
for(const xml of [axml,p.join(dir,stem+'.al')])for(const m of fs.readFileSync(xml,'utf8').matchAll(/<File Path="([^"]+)"/g)){
 const path=m[1],file=p.relative(root,path).replaceAll('\\','/');if(file.startsWith('../')||p.isAbsolute(file))throw Error('Outside root '+file);
 sources.set(file,{file,sha256:hash(path)});
}
const added=[...sources.values()].filter(s=>!old.sources.some(o=>o.file===s.file));
if(added.length!==3||added.some(s=>!s.file.includes('rtl/car_intro_20261007/')))throw Error('Unexpected changed input scope');
for(const s of sources.values())copy(p.join(root,s.file),'source_snapshot/'+s.file);
copy(logs[0],'evidence/B_build.log');copy(p.join(dir,'build_flow.tcl'),'evidence/B_build.tcl');
for(const suffix of ['.al','_gate.area','_phy.area','_pr.timing','_phy.ts'])copy(p.join(dir,stem+suffix),'evidence/'+stem+suffix);
for(const r of regression)copy(p.join(sim,r.file),'evidence/'+r.file);
for(const f of fs.readdirSync(sim))if(/\.(v|vh|do|py)$/.test(f))copy(p.join(sim,f),'tests/'+f);
copy(p.join(base,'sim/stars_opt_20261007/star_reference.vh'),'tests/shared/star_reference.vh');
for(const f of ['tb_b_boundary.v','b_hdmi_models.v'])copy(p.join(base,'sim/manual_dual_20261007',f),'tests/shared/'+f);
for(const f of fs.readdirSync(p.join(base,'assets/car_intro_20261007')))copy(p.join(base,'assets/car_intro_20261007',f),'assets/'+f);
for(const f of ['car_intro_5s.mp4','preview_036.png','preview_060.png','preview_099.png'])copy(p.join(sim,'software_preview',f),f==='car_intro_5s.mp4'?'software_preview.mp4':f);
const total=regression.reduce((n,x)=>n+x.pass_count,0);
const manifest={version:'car_intro_20261007',created_at:new Date().toISOString(),hardware_verified:false,timing_closed:false,baseline:'dual_board/image_link/board_test_20261007/stars_opt',
 feature:{screen:'B only',tf_image_ordinal:5,sprite_size:[256,96],sprite_placement:{x:192,final_y:368,initial_lift_px:12},palette:16,bits_per_pixel:4,transparent_index:0,native_bram32k:3,sequence:'16 frames platform ignition;128 frame fade and12px rise;64 frame sprite-clipped sweep during age64..127;then hold car and gently pulse platform',nominal_fade_end_seconds:144/(25e6/(800*525)),restart:'actual visible TF5 re-entry; not background bank refresh',video_latency_clocks:1,signal_alignment:'RGB,DE and VS delayed together; axis/HDMI/FIFO timing core and PLL unchanged'},
 controls:old.controls,images:old.images,synchronization:old.synchronization,startup:old.startup,resources,artifacts,sources:[...sources.values()],changed_or_added_inputs:added,functions_removed:[],regression,total_pass_count:total,evidence,
 carried_baseline_regression:{count:old.total_pass_count,manifest:'../stars_opt/manifest.json',sha256:hash(p.join(prior,'manifest.json')),scope:'TF/scaling/network/audio/lyrics/control/star RTL unchanged; carried previous regression evidence, not rerun here'},
 caveats:'PROGRAM_SRAM engineering candidate only. Timing remains unclosed, not board-accepted. Native SDRAM/HDMI test uses SDRAM/encrypted HDMI/PHY interface models; not electrical verification. Car intentionally16 colours/binary transparency to conserve memory. No TF writes/programming performed. Software preview uses repository instrument background, not a readback of current TF file.'};
const notes=`# B 板仪表页汽车出场动画（2026-10-07）

仅在 B 板 TF 第 5 张仪表页显示。两个圆盘下面的中央区域放一辆银白色汽车：蓝色能量底光展开，汽车约 2.4 秒渐显并上浮 12 像素，中段有青蓝光带从左向右扫过车身；完成后保留汽车与柔和呼吸底光。无文字、无状态框，不遮住工程内仪表背景的圆盘区域。KEY2 返回第 6 张时动画消失，仍显示双屏60星点；再回第 5 张重播。背景缓存刷新不重播。

## 下载

B 用 MEDIA_B_CAR_INTRO_20261007.bit；A 保持上一版 MEDIA_A_STARS_OPT_20261007.bit（此目录附同一份，散列不变）。不需要修改 TF 文件、编号、音乐或歌词，也不增加板间网络数据。先 PROGRAM_SRAM，不直接固化。回退用 ../stars_opt/ 的 B bit；A 不动。本次没有实际烧录或写 TF。

## 美术与资源取舍

使用 imagegen 技能和内置 image_gen 制作单张透明车图，再离线转成256×96、16色索引。素材及最终提示词在 assets/生成说明.md，高清母版 assets/car_master.png，实际硬件色表预览 assets/car_indexed256x96.png。不是多帧视频，没有实时图像旋转/缩放或3D渲染；上浮、透明渐显、扫光和底光由 FPGA 实时计算。

三块 BRAM32K 保存24576个4bit像素，不新增帧缓存、DSP或PLL。ROM仅在仪表页有效车图范围内打开读使能；动画计数只在帧边界更新，不使用大位宽MHz计时器。因ROM同步读，一拍 RGB/DE/VS 一起延后，不能只延迟RGB。

实际布局布线 B：LUT ${old.resources.B.lut}→${resources.B.lut}（${resources.B.lut_percent}%），增加${resources.B.lut_delta}；寄存器 ${old.resources.B.registers}→${resources.B.registers}；BRAM9K ${resources.B.bram9k}不变，BRAM32K ${old.resources.B.bram32k}→${resources.B.bram32k}；DSP ${resources.B.dsp}、PLL ${resources.B.pll}不变。A 源码和 bit 不变。这是新增动画的资源成本，不能把本次说成进一步降低 LUT。

**尚未上板，时序仍未闭合。** B 全局建立/保持 ${resources.B.setup_ns}/${resources.B.hold_ns}ns；视频自身 ${resources.B.video.setup_ns}/${resources.B.video.hold_ns}ns，UDP自身 ${resources.B.udp.setup_ns}/${resources.B.udp.hold_ns}ns，SD自身 ${resources.B.sd.setup_ns}/${resources.B.sd.hold_ns}ns。位宽和表格式节约内存不等于保证板上稳定。

## 验证与演示

本轮${total}项 ModelSim PASS：25276次原生BRAM索引/字序/色表检查，700次使能保持；3379200次独立整数参考完整帧 RGB/DE/VS 比对，覆盖0/15/16/24/64/96/128/143/144/191帧、淡入跨128不回绕、扫光、上浮、底光、离页旁路和圆盘不遮挡；帧计数/饱和/手动重播/复位；实际B顶层1024个PCM字、两曲/串口/网络中止；原生FIFO到HDMI四槽缓存、五次完整640×480输入、4300800次RGB/SOF/EOL检查，手动切页/中止/防覆盖/休闲星点正常。SDRAM和加密HDMI/PHY用接口模型，不能替代电气和硬件时序验收。

旧版${old.sources.length}个输入和两块bit散列均核对未变，本轮只新增/替换三个版本化 HDL 输入。上一版${old.total_pass_count}项音频、星点、缓存等证据保留，不冒称全部重跑。

software_preview.mp4 是软件预览，不是板上录屏，使用工程内 instrument_background_640x480.png。若当前 TF 第5图布局不同，汽车位置需要按实际背景再次校准。

上板检查：等待 B 第5图加载后观看至少3秒；KEY2切到第6图应无汽车且A到第3图，两个屏幕60星点继续同步；返回第5图应重新出场。检查音频无新增卡顿、切歌/歌词/串口/预警保持正常。资源/时序/日志在 evidence，源码冻结副本在 source_snapshot，散列在 manifest.json。

重建：prj/car_intro_b_20261007/build_flow.tcl。回归按 sim/car_intro_20261007/run_car.do、run_boundary.do、run_preview.do 串行运行。最终提示词和打包参数保存在 assets/生成说明.md、packing.json。
`;
console.log('*** Begin Patch');for(const [f,t] of [['manifest.json',JSON.stringify(manifest,null,2)],['使用说明.md',notes]]){console.log('*** Add File: '+rel+'/'+f);for(const l of t.split(/\r?\n/))console.log('+'+l);}console.log('*** End Patch');
