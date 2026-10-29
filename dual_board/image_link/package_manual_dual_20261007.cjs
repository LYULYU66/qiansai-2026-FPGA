// Mechanical binary/evidence copies; JSON/Markdown text is emitted for apply_patch.
const fs=require('fs'),p=require('path'),crypto=require('crypto');
const base=__dirname,root=p.resolve(base,'../..');
const rel='dual_board/image_link/board_test_20261007/manual_dual',out=p.join(root,rel);
const sim=p.join(base,'sim/manual_dual_20261007');
if(fs.existsSync(p.join(out,'manifest.json')))throw Error('Already published');
const hash=f=>crypto.createHash('sha256').update(fs.readFileSync(f)).digest('hex').toUpperCase();
const baseline=p.join(base,'board_test_20261006/firefly_video');
const old=JSON.parse(fs.readFileSync(p.join(baseline,'manifest.json'),'utf8'));
for(const s of old.sources)if(hash(p.join(root,s.file))!==s.sha256)throw Error('Baseline source changed: '+s.file);
for(const a of old.artifacts)if(hash(p.join(baseline,a.file))!==a.sha256)throw Error('Baseline bit changed: '+a.file);
const cases={
 'control.log':[['PASS page sync:','PASS control guard:','PASS CTL3 guard:','PASS remote display:'],4],
 'scan_final.log':[['PASS SIX_SCAN:','PASS SIX_PRELOAD:'],6],
 'routes_retry.log':[['PASS SOURCE_ROUTES:'],1],
 'preview.log':[['PASS B manual TF5/TF6 preview:'],1],
 'boundary.log':[['PASS manual-dual B boundary:'],1],
 'reader.log':[['PASS manual-dual two-song reader'],4],
 'audio.log':[['PASS audio status:','PASS visual guard:','PASS remote compute:','PASS audio offload:'],4],
 'features.log':[['PASS dualsong control:','PASS dualsong timeline:'],2],
 'cover.log':[['PASS RGB565 cover:'],1]
};
const regression=[];
for(const [file,[markers,count]] of Object.entries(cases)){
 const f=p.join(sim,file),txt=fs.readFileSync(f,'utf8');
 const passLines=txt.split(/\r?\n/).filter(l=>/^# PASS /.test(l));
 if(/\*\* (Fatal|Error)|Errors: [1-9]/.test(txt)||markers.some(s=>!txt.includes(s))||passLines.length!==count)throw Error('Failed/missing '+file+'\n'+passLines.join('\n'));
 regression.push({file,passed:true,pass_count:count,pass_lines:passLines,sha256:hash(f),mtime:fs.statSync(f).mtime.toISOString()});
}
const resources={},artifacts=[],sources=new Map(),evidence=[];
function copy(src,dest){const dst=p.join(out,dest);fs.mkdirSync(p.dirname(dst),{recursive:true});fs.copyFileSync(src,dst);evidence.push({file:dest,sha256:hash(dst)});}
for(const [board,seed] of [['A',1],['B',3]]){
 const dir=p.join(base,'prj/manual_dual_'+board.toLowerCase()+'_s'+seed+'_20261007');
 const stem='MEDIA_'+board+'_MANUAL_DUAL_S'+seed+'_20261007',published='MEDIA_'+board+'_MANUAL_DUAL_20261007';
 const logs=fs.readdirSync(dir).filter(f=>/^td_.*\.log$/.test(f)).map(f=>p.join(dir,f)).sort((a,b)=>fs.statSync(b).mtimeMs-fs.statSync(a).mtimeMs);
 const txt=fs.readFileSync(logs[0],'utf8');
 if(!txt.includes('Generate bits file '+stem+'.bit.')||/RUN-\d+ ERROR|Incremental route failed/.test(txt))throw Error('Incomplete build '+board);
 const area=fs.readFileSync(p.join(dir,stem+'_phy.area'),'utf8'),timing=fs.readFileSync(p.join(dir,stem+'_pr.timing'),'utf8');
 if(!/Confidence\s*:\s*Routed/.test(timing))throw Error('Not routed '+board);
 const num=k=>Number(area.match(new RegExp('^\\s*#'+k+'\\s+(\\d+)','m'))[1]);
 const slack=timing.match(/SWNS: ([\-\d.]+)ns, STNS: [\-\d.]+ns\s+HWNS: ([\-\d.]+)ns/);
 const self=k=>{const i=timing.indexOf('Path Group     :     '+k+' -> '+k);if(i<0)throw Error('Missing clock '+k);const t=timing.slice(i);return {setup_ns:Number(t.match(/Max\s+: SWNS\s+([\-\d.]+)ns/)[1]),hold_ns:Number(t.match(/Min\s+: HWNS\s+([\-\d.]+)ns/)[1])};};
 resources[board]={seed,lut:num('lut'),lut_percent:Number((num('lut')/196).toFixed(2)),registers:num('reg'),bram9k:num('bram9k'),bram32k:num('bram32k'),dsp:num('dsp'),pll:num('pll'),setup_ns:Number(slack[1]),hold_ns:Number(slack[2]),video:self(board==='A'?'video_clk':'compute_clk'),udp:self('udp_clk'),lut_delta:num('lut')-old.resources[board].lut};
 if(board==='B')resources[board].sd=self('sd_clk');
 for(const k of ['bram9k','bram32k','dsp','pll'])if(resources[board][k]!==old.resources[board][k])throw Error('Unexpected resource growth '+board+' '+k);
 const bit=p.join(dir,stem+'.bit');artifacts.push({board,file:published+'.bit',build_stem:stem,bytes:fs.statSync(bit).size,sha256:hash(bit)});copy(bit,published+'.bit');
 copy(logs[0],'evidence/'+board+'_build.log');copy(p.join(dir,'build_flow.tcl'),'evidence/'+board+'_build.tcl');
 for(const suffix of ['.al','_phy.area','_gate.area','_pr.timing','_phy.ts'])copy(p.join(dir,stem+suffix),'evidence/'+stem+suffix);
 for(const m of fs.readFileSync(p.join(dir,stem+'.al'),'utf8').matchAll(/<File Path="([^"]+)"/g)){
  const f=m[1],relative=p.relative(root,f).replaceAll('\\','/');
  if(relative.startsWith('../')||p.isAbsolute(relative)||!fs.existsSync(f))throw Error('Bad source '+relative);
  sources.set(relative,{file:relative,sha256:hash(f)});
 }
}
for(const s of sources.values())copy(p.join(root,s.file),'source_snapshot/'+s.file);
for(const r of regression)copy(p.join(sim,r.file),'evidence/'+r.file);
for(const f of fs.readdirSync(sim))if(/\.(v|sv|vh|do)$/.test(f))copy(p.join(sim,f),'tests/'+f);
// Shared unchanged tests are retained with their original workspace routes.
for(const f of ['tb_audio_offload.v','tb_remote_compute.v','tb_audio_visual_guard.v','tb_audio_status_guard.v','tb_control_guard.v','tb_remote_display.v'])copy(p.join(base,'sim',f),'tests/shared/'+f);
for(const sub of ['yilu_replace_20261006','dualsong_20261005','dual_stars_20261006'])for(const f of fs.readdirSync(p.join(base,'sim',sub)))if(/\.(v|sv|vh|do)$/.test(f))copy(p.join(base,'sim',sub,f),'tests/shared/'+sub+'/'+f);
const pcm=p.join(root,'best_result/yilu_replace_20261006/TF_CARD/MUSIC2.PCM');
if(hash(pcm)!==old.music2_sha256)throw Error('Existing PCM changed');
const shader='dual_board/image_link/rtl/firefly_video_20261006/video_dual_star_overlay.v';
if(hash(p.join(root,shader))!==old.sources.find(s=>s.file===shader).sha256)throw Error('Unexpected shader change');
const unchanged=[...sources.values()].filter(s=>old.sources.some(o=>o.file===s.file&&o.sha256===s.sha256));
const manifest={version:'manual_dual_20261007',created_at:new Date().toISOString(),hardware_verified:false,timing_closed:false,
 usage:'Paired A+B PROGRAM_SRAM engineering candidate only; no programming or TF writes performed',baseline:'dual_board/image_link/board_test_20261006/firefly_video',
 controls:{B:{KEY1:'reset',KEY2:'toggle TF image 5/6; cached target required',KEY3:'unused',KEY4:'unused',autoplay:false},A:'unchanged; remote B6 entry pauses autoplay, local hazard priority retained'},
 images:{A:[1,2,3,4],B:[5,6],order:'first six regular BMP entries in FAT root directory; NOT filename sorting',formats:'existing 24-bit uncompressed BMP reader/downscaler; recommend 640x480',tf_board:'B',local_cache_slots:4,local_cache_external_bytes:4915200},
 synchronization:{protocol:'CTL4, 14 bytes; reserved byte11 now visible-relax flag + 7-bit entry epoch',trigger:'B actually displays image6 at frame boundary',action:'A requests image3; defer until cached and no local hazard; pause autoplay',return_to_B5:'does not move A',duplicates:'do not override A manual page again',star_time:'unchanged B-owned shared animation timestamp; A left/B right; not electrical HDMI genlock'},
 startup:'A first four images still require link/session/ACK before B local images; PCM starts after first four commits and interleaves with images5/6',
 resources,artifacts,sources:[...sources.values()],unchanged_input_count:unchanged.length,regression,total_pass_count:regression.reduce((s,r)=>s+r.pass_count,0),evidence,
 music2_sha256:hash(pcm),
 test_limitations:'Native cache/FIFO/scaler/display and protocol exercised; SDRAM, encrypted HDMI/PHY and SD sector transport use explicit interface models. B integrated boundary test forces decoded TF outputs and network inputs. Existing isolated audio/features/cover suites compile unchanged sources; new boundary and reader tests exercise modified B integration. Physical timing/electrical acceptance not performed.',
 caveats:'Global and several self-domain setup/hold paths remain negative. A seed4/2/3 failed routing; only successful seed1 released. B seed3 selected over seed4 for better SD/video setup, not as timing-closed. Both boards must update CTL4 together.'};
const notes=`# 双板六图手动联动（2026-10-07）

本版 B 屏只显示 TF 第 5、6 张，KEY2 一个按键在两张之间切换，没有自动轮播。KEY1 仍复位，B KEY3/KEY4 不分配功能；A 按键功能不变。

第 5 张显示原图，不叠加星光。第 6 张叠加已有萤火虫灯光；B 真正显示第 6 张后通过以太网通知 A 进入第 3 张并暂停 A 自动轮播。若 A 正处于拨码危险状态，先保留预警，结束后执行待处理休闲请求。A 后续手动切走不会被重复包拖回来；B 返回第 5 张不强制 A 返回其他页。A 使用已有切页逻辑，联动不是两路 HDMI 电气锁帧。

## 下载

分别给 A 下载 MEDIA_A_MANUAL_DUAL_20261007.bit，给 B 下载 MEDIA_B_MANUAL_DUAL_20261007.bit。两板必须一起更新，不能与旧 CTL3 版本混烧。请先 PROGRAM_SRAM 验证，不直接固化 FLASH。本次没有操作烧录器、没有写 TF 卡。

旧版双板文件完整保留在 ../../board_test_20261006/firefly_video/，异常时整对回退。

## TF 卡

卡仍只插 B，保留 MUSIC.PCM 和 MUSIC2.PCM。图片顺序：首页、音乐、A 休闲左图、预警、B 仪表图、B 休闲右图。使用 24 位无压缩 BMP，推荐都为 640×480，沿用现有高分辨率缩小能力；不支持低于输出大小、压缩或 32 位 BMP。

编号取 FAT 根目录前六个正常 BMP 条目的顺序，**不是文件名排序**。仅改名为 01～06 不保证顺序；删除后新增可能占旧空位，额外测试 BMP 也会挤掉目标图片。不支持的 BMP 仍可能占编号。先备份卡，再整理所需六张并按 1→6 逐个复制；不要把资源管理器的排序当硬件顺序。

拼接休闲图位于 ../../assets/relax_panorama_20261007/：relax_A_left_640x480.bmp 放第 3 位，relax_B_right_640x480.bmp 放第 6 位。仪表背景在 ../../assets/instrument_background_20261006/instrument_background_640x480.bmp，可自行放第 5 位；此版只读图，没有新增指针/汽车动画。

## 上板检查

网线直连，两板配套上电，TF 插 B。现有启动仍先把 1～4 张送 A 并等待确认，不是 B 脱离 A 独立启动；音频随后启动，5/6 与 PCM 交错读取。等第 5 张出现并完成第 6 张缓存后按 B KEY2：B 应进入第 6 张、A 进入第 3 张，两屏开始共享时间轴的灯光；再按一次 B 返回第 5 张，无星光且 A 不被强制切走。

目标页尚未缓存时按键忽略，需要稍后重新按；长按只切一次。验证 A 手动切图、KEY3 换歌、串口参数、歌词与拨码预警仍正常；危险优先于休闲请求。缓存更换只在完整帧写完并到帧边界时显示，失败中止保留旧图。

## 实际布局布线资源

| 资源 | A（seed1） | B（seed3） |
|---|---:|---:|
| LUT | ${resources.A.lut}（${resources.A.lut_percent}%） | ${resources.B.lut}（${resources.B.lut_percent}%） |
| 相比 firefly LUT 变化 | ${resources.A.lut_delta} | +${resources.B.lut_delta} |
| 寄存器 | ${resources.A.registers} | ${resources.B.registers} |
| BRAM9K / BRAM32K | ${resources.A.bram9k} / ${resources.A.bram32k} | ${resources.B.bram9k} / ${resources.B.bram32k} |
| DSP / PLL | ${resources.A.dsp} / ${resources.A.pll} | ${resources.B.dsp} / ${resources.B.pll} |
| 全局建立 / 保持 ns | ${resources.A.setup_ns} / ${resources.A.hold_ns} | ${resources.B.setup_ns} / ${resources.B.hold_ns} |
| 视频自身建立 / 保持 ns | ${resources.A.video.setup_ns} / ${resources.A.video.hold_ns} | ${resources.B.video.setup_ns} / ${resources.B.video.hold_ns} |
| UDP 自身建立 / 保持 ns | ${resources.A.udp.setup_ns} / ${resources.A.udp.hold_ns} | ${resources.B.udp.setup_ns} / ${resources.B.udp.hold_ns} |

B SD 自身建立/保持为 ${resources.B.sd.setup_ns}/${resources.B.sd.hold_ns}ns。**时序仍未闭合，尚未上板验收，不保证硬件稳定。** A 三个种子曾布线失败，本次仅发布成功的 seed1；B 选 seed3，显示/SD 建立优于 seed4，但并未消除负裕量。

六图共用已有 TF/BMP/缩放通路；仅前四张通过网络送 A，后两张本地写 B 外部 SDRAM。每张本地图各一显示槽、一备用槽，共 4.6875MiB 外部 SDRAM，不新增 FPGA 帧 BRAM、DSP 或 PLL，不改 SDRAM 仲裁、FIFO 深度、视频对齐链或 HDMI IP。

## 验证范围

本轮 ${regression.reduce((s,r)=>s+r.pass_count,0)} 项 ModelSim PASS，详见 manifest.json 和 evidence：六图 FAT 扫描/碎片簇/缩放/PCM 交错、四图兼容、A1～4 与 B5/6 路由隔离、CTL4 CRC/重复包/缺图等待/危险优先/复位与 epoch、B 四槽原生 FIFO 到 HDMI 的 5 次完整帧及 4300800 个 RGB/DE/SOF/EOL 像素、按键长按/短抖动、帧槽保护和中止保留、双曲 PCM/重连/UART 集成、音频/歌词/封面回归。

SDRAM、SD 扇区和加密 HDMI/PHY 用接口模型，不能替代真实电气/时序验证。原有星光算法文件散列未变，本轮验证新增页面开关与叠加，不冒称重新跑旧版全部回归或已经上板。全部 ${sources.size} 个项目输入有 source_snapshot 与 SHA256；旧版源码和 bit 散列已验证未变。

重跑新增测试：在 dual_board/image_link/sim 依次执行 manual_dual_20261007/run_control.do、run_scan.do、run_routes.do、run_preview.do、run_boundary.do、run_reader.do；补充回归用 yilu_replace_20261006/run_audio.do、run_features.do、run_cover.do。ModelSim 请串行执行，日志出现 Fatal/Errors 非零即失败，不能只凭进程退出码。

重建工程：prj/manual_dual_a_s1_20261007/build_flow.tcl 和 prj/manual_dual_b_s3_20261007/build_flow.tcl，使用 TD 命令行直接传脚本路径；evidence 保存了当次项目、构建日志、资源和时序报告。
`;
console.log('*** Begin Patch');
for(const [f,s] of [['manifest.json',JSON.stringify(manifest,null,2)],['使用说明.md',notes]]){
 console.log('*** Add File: '+rel+'/'+f);for(const l of s.split(/\r?\n/))console.log('+'+l);
}
console.log('*** End Patch');
