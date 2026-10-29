// Publish only completed routed builds and fresh successful test evidence.
const fs=require('fs'),path=require('path'),crypto=require('crypto');
const root=path.resolve(__dirname,'../..');
const out=path.join(__dirname,'board_test_20261005/resource_opt_r10');
if(fs.existsSync(out) && fs.readdirSync(out).length) throw Error('Published evidence already exists; never overwrite.');
const sha=p=>crypto.createHash('sha256').update(fs.readFileSync(p)).digest('hex').toUpperCase();
const accepted=JSON.parse(fs.readFileSync(path.join(__dirname,'accepted_baseline_20261005_r7_r8/acceptance.json'),'utf8'));
for(const item of accepted.sources) if(sha(item.file)!==item.sha256) throw Error('Accepted source changed: '+item.file);
for(const item of accepted.boards) if(sha(item.bit)!==item.sha256) throw Error('Accepted bit changed: '+item.bit);
const simulations=[
 ['equivalence','sim/resource_round10_20261005/modelsim_equivalence.log',['PASS waveform equivalence:','PASS status equivalence:','PASS visualizer equivalence:']],
 ['integration','sim/resource_round10_20261005/modelsim_integrated.log',['PASS audio status:','PASS visual guard:','PASS remote compute:','PASS audio offload:','PASS audio guard:','PASS media abort:','PASS audio media:','PASS native home read:','PASS full 640x480 native FIFO writer:','PASS player B boundary:','PASS home source:','PASS home stage retry:']]
];
const tests=[];
for(const [kind,file,markers] of simulations) {
  const p=path.join(__dirname,file),text=fs.readFileSync(p,'utf8');
  if(/FAIL|\*\*\s+(?:Error|Fatal)|Errors:\s*[1-9]/.test(text)) throw Error('Failed regression: '+p);
  for(const marker of markers) if(!text.includes(marker)) throw Error('Missing PASS: '+marker);
  tests.push({kind,file:p,sha256:sha(p),checks:markers,warnings:'Legacy test fixtures have disabled/unconnected ports; inspect log. No errors.'});
}
function metrics(prj,name) {
  const area=fs.readFileSync(path.join(prj,name+'_phy.area'),'utf8');
  const timing=fs.readFileSync(path.join(prj,name+'_pr.timing'),'utf8');
  if(!timing.includes('Confidence          : Routed')) throw Error('Not a routed report');
  const take=field=>Number(area.match(new RegExp('^[ \\t]*#'+field+'[ \\t]+(\\d+)','m'))[1]);
  const clk=clock=>{
    const section=timing.match(new RegExp('Path Group\\s+:\\s+'+clock+' -> '+clock+'[\\s\\S]*?Statistics:([\\s\\S]*?)(?=Max Paths)'));
    return section ? Number(section[1].match(/Max\s+: SWNS\s+(-?[\d.]+)ns/)[1]) : null;
  };
  return {area:{lut:take('lut'),registers:take('reg'),bram9k:take('bram9k'),bram32k:take('bram32k'),dsp:take('dsp'),pll:take('pll')},
    timing:{global_setup_ns:Number(timing.match(/SWNS: (-?[\d.]+)ns/)[1]),global_hold_ns:Number(timing.match(/HWNS: (-?[\d.]+)ns/)[1]),udp_self_setup_ns:clk('udp_clk'),video_self_setup_ns:clk('video_clk'),sd_self_setup_ns:clk('sd_clk')}};
}
const selected=[
 ['A','prj/media_a_res10_seed4','MEDIA_SRAM_TEST_A_RESOPT_R10_S4_20261005',4,'MEDIA_SRAM_TEST_A_IMAGEFIX_R7_20261005'],
 ['B','prj/media_b','MEDIA_SRAM_TEST_B_RESOPT_R10_20261005',3,'MEDIA_SRAM_TEST_B_HOMESTAGE_R8_20261005']
];
const manifest={generated_at:new Date().toISOString(),hardware_verified:false,release_status:'EXPERIMENTAL_PROGRAM_SRAM_ONLY_NOT_TIMING_CLOSED',accepted_baseline:path.join(__dirname,'accepted_baseline_20261005_r7_r8'),accepted_files_unchanged:true,tests,boards:[],
 changes:['A: reuse completed BCD digits to determine resolution text length; bounded divide-by-12 replaces wide priority decoder.',
 'A: snapshot shift-bank data retains contents on reset; resettable busy/lane/valid guards preserve externally visible behavior.',
 'B: 105-bit serial trace construction replaces lane-addressed writes; fifteen new points precede atomic publication; temporary work data needs no clear.'],
 unchanged:['Network protocol, clocks, pins, HDMI IP, PLLs, SDRAM writer/read alignment, RAM/FIFO capacities, visual algorithms, lyrics/song timeline, UART commands and all page features.'],
 caveats:['No FPGA physical programming performed. Simulation does not establish timing closure or physical hardware reliability.',
 'A UDP self setup improves slightly; B UDP self setup is slightly worse than accepted R8. Both retain setup violations.',
 'Total LUT drops; total routed register count increases by nine. Dedicated RAM/DSP/PLL allocations are unchanged.',
 'This is a low-risk first round, not completion of all dual-board architectural efficiency opportunities.']};
fs.mkdirSync(out,{recursive:true});
for(const [board,project,name,seed,oldName] of selected) {
  const prj=path.join(__dirname,project),baselinePrj=path.join(__dirname,'prj/media_'+board.toLowerCase());
  const bit=path.join(prj,name+'.bit');
  const logs=fs.readdirSync(prj).filter(x=>/^td.*\.log$/.test(x)).sort();
  const log=path.join(prj,logs[logs.length-1]);
  if(!fs.readFileSync(log,'utf8').includes('Generate bits file '+name+'.bit.')) throw Error('Bitgen not completed: '+name);
  const item={board,name,seed,project:path.join(prj,name+'.al'),build:path.join(prj,'build_resource_r10.tcl'),build_log:{file:log,sha256:sha(log)},baseline:metrics(baselinePrj,oldName),candidate:metrics(prj,name),files:[],source_manifest:[]};
  for(const ext of ['.bit','.al','_phy.area','_pr.timing','_phy.ts']) {
    const p=path.join(prj,name+ext),dest=path.join(out,name+ext);
    fs.copyFileSync(p,dest);item.files.push({file:dest,sha256:sha(dest)});
  }
  const xml=fs.readFileSync(item.project,'utf8');
  for(const m of xml.matchAll(/<File Path="([^"]+)"/g)) {
    const p=path.resolve(prj,m[1]);
    if(fs.existsSync(p))item.source_manifest.push({file:p,sha256:sha(p)});
  }
  manifest.boards.push(item);
}
const sum=(mode,field)=>manifest.boards.reduce((n,b)=>n+b[mode].area[field],0);
manifest.totals={baseline_lut:sum('baseline','lut'),candidate_lut:sum('candidate','lut'),lut_saved:sum('baseline','lut')-sum('candidate','lut'),baseline_registers:sum('baseline','registers'),candidate_registers:sum('candidate','registers')};
fs.writeFileSync(path.join(out,'manifest.json'),JSON.stringify(manifest,null,2)+'\n');
for(const t of tests)fs.copyFileSync(t.file,path.join(out,t.kind+'_modelsim.log'));
for(const file of ['audio_waveform_analyzer.v','video_status_overlay.v','audio_visualizer_overlay.v']) {
  fs.mkdirSync(path.join(out,'source'),{recursive:true});
  fs.copyFileSync(path.join(__dirname,'rtl/resource_round10_20261005',file),path.join(out,'source',file));
}
const rows=manifest.boards.map(b=>`| ${b.board} | ${b.baseline.area.lut} | ${b.candidate.area.lut}（${(b.candidate.area.lut/196).toFixed(2)}%） | ${b.baseline.area.lut-b.candidate.area.lut} | ${b.baseline.area.registers} → ${b.candidate.area.registers} |`).join('\n');
const boardFiles=manifest.boards.map(b=>`- ${b.board==='A'?'A 主板':'B TF/计算副板'}：\`${b.name}.bit\`，布局种子 ${b.seed}。`).join('\n');
fs.writeFileSync(path.join(out,'优化说明.md'),`# 双板资源优化 R10：首轮低风险优化\n\n已生成独立 SRAM 测试 bit，旧 A R7＋B R8 已验收版本未覆盖。新版本尚未上板验收，也没有自动下载。\n\n## 完整布局布线结果\n\n| 板 | 验收版 LUT | 候选 LUT | 减少 LUT | 寄存器 |\n|---|---:|---:|---:|---:|\n${rows}\n\n两板总 LUT：${manifest.totals.baseline_lut} → ${manifest.totals.candidate_lut}，减少 **${manifest.totals.lut_saved}**（${(100*manifest.totals.lut_saved/manifest.totals.baseline_lut).toFixed(2)}%）。总寄存器增加 9 个，不能称为所有资源都下降。\n\nA 的 BRAM9K/BRAM32K/DSP/PLL 仍为 50/7/3/4；B 仍为 28/9/3/3。没有削减 FIFO、音频历史、图片缓存或字模质量，也没有把负担简单搬到另一块板。\n\n## 具体修改\n\n1. A 分辨率位数直接由已完成的 BCD 结果计算，移除重复宽比较器；字符位置改用四级有界减法，保留原来的截断和字模位置。\n2. A 频谱/波形的临时快照不再逐位清零，使用原有忙、有效和图层标记隔离未初始化数据。外部颜色与更新时刻保持一致；不把该项单独宣称为确定的 LUT 节省。\n3. B 波形按采样顺序进入 105 位移位缓存，代替 16 路分片写译码。第 16 个点与前 15 点一起发布，滤波、触发、左右声道及显示幅度不变。有效控制复位后，完整重写才能发布。\n\nA 继续负责最终 HDMI 音视频、转场、显示和本地危险预警；B 继续负责 TF/BMP 缩放、PCM、音频计算、歌词时间轴和电脑串口。协议、引脚、约束、PLL、HDMI IP、SDRAM 控制和此前花屏修复均未改动。\n\n## 验证与限制\n\n- 3 项新旧逐拍等价检查：波形 800,008 拍，参数文字 4,509,940 拍，最终可视化 6,918,688 拍。覆盖全部 16 位宽高、2048 个定位输入、144 种参数组合、18 个完整 VGA 帧、音量 0–8、中途复位和重新开始。\n- 12 项新运行的集成回归通过，包括实际 48kHz 播放进度反馈、远程计算、原生 FIFO、图片完整写入/读取、UART、重连和图片首末包 ACK 丢失重传。\n- 原有 40 项历史回归并非本轮全部重跑。此次证据为上述 15 项；旧日志保留。部分旧测试夹具对禁用功能端口未连线有警告，日志无错误。\n- **时序仍未闭合**：A 全局建立 −5.699 ns（不变），保持从 −0.052 改善为 +0.003 ns；B 全局建立 −3.487 → −3.448 ns，保持 −1.540 ns（不变）。A UDP 同域建立 −1.230 → −1.156 ns；B −0.525 → −0.737 ns，略有变差。资源优化不代表所有时序改善，不能声称全局闭合。\n- A 种子 1 虽更省 49 个 LUT，但视频建立为负，因此选择视频建立为正、全局保持无负值的种子 4。B 种子 2/4 比当前种子 3 的资源与建立时间更差，未选用。A R9 种子 3 与 A R10 种子 2 布线失败，未发布失败 bit。\n\n## 上板方式\n\n${boardFiles}\n\n先用 **PROGRAM_SRAM** 测试，不建议 PROGRAM_FLASH 固化。B 插原 TF 卡，A 接 HDMI，连接两板网线，接线和卡内文件无需改变。建议一次只替换一块板：先 B 新版＋A 验收版，再替换 A，方便定位。\n\n检查首页所有图标、四张图切换与转场、音乐不断流、音量 0–8 的频谱/波形、歌词/前奏/循环、亮度/对比度/分辨率、时间、休闲星点、四方向拨码抢占与报警、重启/网线断连恢复。异常时立即回退已验收的 A R7＋B R8。新布局不能仅凭行为仿真保证实板完全正常。\n\n## 回退与复现\n\n已验收 bit、工程配置、资源/时序和 115 个项目源文件保存在 \`dual_board/image_link/accepted_baseline_20261005_r7_r8/\`，验收信息独立记录，未改写旧 manifest。源文件和旧 bit 哈希已重新核对。\n\n候选源码位于 \`dual_board/image_link/rtl/resource_round10_20261005/\`。重新构建：在 \`prj/media_a_res10_seed4\` 或 \`prj/media_b\` 下运行 \`td_commands_prompt.exe build_resource_r10.tcl\`；等价仿真在 \`sim/resource_round10_20261005\` 运行 \`vsim -c -do run_equivalence.do\`；集成仿真在 \`sim\` 运行 \`vsim -c -do resource_round10_20261005/run_integrated.do\`。本目录 \`manifest.json\` 保存完整源/产物哈希、时序、回归和项目路径。\n\n## “1+1大于2”的下一轮\n\n本轮是资源总量真实下降的第一步，尚不是大幅架构优化。后续优先评估 B 的重复可视化快照/发送缓存合并，以及 A 的渲染准备运算与 B 的音频计算复用；必须保持播放样本序号和帧边界同步，并证明两板总资源下降。A 安全抢占/缓存预警画面/报警音继续本地可用。涉及 CDC 与包发送时序的缓存合并属于中等风险，不与这一轮已验证改动混在同一个未经回归的 bit 中。\n`);
console.log(JSON.stringify({published:out,totals:manifest.totals,boards:manifest.boards.map(b=>({board:b.board,area:b.candidate.area,timing:b.candidate.timing,bit:b.files[0]}))},null,2));
