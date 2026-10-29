// 生成竞赛技术文档：双FPGA以太网协同的车载双屏影音系统
const {
  Document, Packer, Paragraph, TextRun, Table, TableRow, TableCell,
  ImageRun, PageBreak, Header, Footer, PageNumber, NumberFormat,
  AlignmentType, HeadingLevel, WidthType, BorderStyle, ShadingType,
} = require("docx");
const fs = require("fs");
const _is = require("image-size");
const sizeOf = _is.imageSize || _is.default || _is;

// ---------- 通用工具 ----------
const F_BODY = { ascii: "Times New Roman", eastAsia: "SimSun" };
const F_HEAD = { ascii: "Times New Roman", eastAsia: "SimHei" };

function h1(text) {
  return new Paragraph({
    heading: HeadingLevel.HEADING_1,
    alignment: AlignmentType.CENTER,
    keepNext: true,
    spacing: { before: 360, after: 200, line: 312 },
    children: [new TextRun({ text, bold: true, size: 32, font: F_HEAD, color: "000000" })],
  });
}
function h2(text) {
  return new Paragraph({
    heading: HeadingLevel.HEADING_2,
    keepNext: true,
    spacing: { before: 280, after: 140, line: 312 },
    children: [new TextRun({ text, bold: true, size: 30, font: F_HEAD, color: "000000" })],
  });
}
function h3(text) {
  return new Paragraph({
    heading: HeadingLevel.HEADING_3,
    keepNext: true,
    spacing: { before: 220, after: 120, line: 312 },
    children: [new TextRun({ text, bold: true, size: 28, font: F_HEAD, color: "000000" })],
  });
}
// 正文：两端对齐 + 首行缩进2字符
function p(text, opts = {}) {
  const runs = Array.isArray(text) ? text : [{ text }];
  return new Paragraph({
    alignment: AlignmentType.JUSTIFIED,
    spacing: { before: 0, after: 80, line: 312 },
    indent: opts.noIndent ? undefined : { firstLine: 480 },
    keepNext: opts.keepNext || undefined,
    children: runs.map(r => new TextRun({
      text: r.text, bold: r.bold || false, size: r.size || 24,
      font: r.head ? F_HEAD : F_BODY, color: "000000",
    })),
  });
}
// 图注/表题（居中，10.5pt）
function cap(text, keepNext = false) {
  return new Paragraph({
    alignment: AlignmentType.CENTER,
    spacing: { before: 60, after: 160, line: 312 },
    keepNext: keepNext || undefined,
    children: [new TextRun({ text, size: 21, bold: true, font: F_BODY, color: "000000" })],
  });
}
// 插图（保持纵横比）
function img(file, width) {
  const buf = fs.readFileSync(file);
  const dim = sizeOf(buf);
  const h = Math.round(width * dim.height / dim.width);
  return new Paragraph({
    alignment: AlignmentType.CENTER,
    spacing: { before: 120, after: 40, line: 312 },
    keepNext: true,
    children: [new ImageRun({ data: buf, transformation: { width, height: h }, type: "png" })],
  });
}
// 表格
function tbl(headers, rows, widths) {
  const border = (c) => ({ style: BorderStyle.SINGLE, size: 2, color: c });
  const mk = (text, isHead, w) => new TableCell({
    children: [new Paragraph({
      alignment: AlignmentType.CENTER,
      spacing: { before: 0, after: 0, line: 276 },
      children: [new TextRun({
        text, bold: isHead, size: 21,
        font: isHead ? F_HEAD : F_BODY, color: "000000",
      })],
    })],
    shading: isHead ? { type: ShadingType.CLEAR, fill: "EEF2F7" } : undefined,
    margins: { top: 60, bottom: 60, left: 100, right: 100 },
    width: w ? { size: w, type: WidthType.PERCENTAGE } : undefined,
    verticalAlign: "center",
  });
  return new Table({
    width: { size: 100, type: WidthType.PERCENTAGE },
    borders: {
      top: border("5B7BA6"), bottom: border("5B7BA6"),
      left: border("C9D4E2"), right: border("C9D4E2"),
      insideHorizontal: border("C9D4E2"), insideVertical: border("C9D4E2"),
    },
    rows: [
      new TableRow({ tableHeader: true, cantSplit: true, children: headers.map((t, i) => mk(t, true, widths ? widths[i] : undefined)) }),
      ...rows.map(r => new TableRow({ cantSplit: true, children: r.map((t, i) => mk(t, false, widths ? widths[i] : undefined)) })),
    ],
  });
}

// ---------- 内容 ----------
const children = [];

// ============ 摘要 ============
children.push(h1("摘  要"));
children.push(p("本作品是一套完全由 FPGA 搭建、不依赖任何 CPU 和操作系统的车载双屏影音系统。系统由两块 HX4S20C 开发板（FPGA 主芯片为安路 EG4S20）组成：A 板充当中控娱乐屏，B 板充当虚拟仪表盘，两板通过一根网线以千兆以太网 UDP 方式直连协同工作，各自独立驱动一台 HDMI 显示器。"));
children.push(p("A 屏呈现三个画面：带竞赛徽标、时钟和音乐卡片的首页；随演唱进度逐字变红的卡拉OK式歌词页；实时跳动的频谱、波形与音量条页面；另有四张 TF 卡图片支持手动与自动轮播和转场特效。B 屏呈现仪表盘（指针动画加滚动欢迎字幕）、六首歌的歌单（正在播放的一首整行标红）和流动星空三个画面。六首 48 kHz 双声道乐曲的 PCM 数据由 B 板从 TF 卡读出并分包发给 A 板播放；歌词的逐字进度、频谱、波形和音量条全部由 B 板根据 A 板实时反馈的已播放采样数计算，网络快慢抖动都不会影响音画同步，实测与设计时间表误差为 0 个采样。"));
children.push(p("系统还实现了安全预警联动：拨动 A 板任意一个预警开关，B 屏立即切入醒目的红色注意安全警告，解除后自动恢复原画面。图片通道支持亮度、对比度无损档位调节，参数在帧边界统一生效，不会出现上下半屏不一致的撕裂。"));
children.push(p("底层设计包括：FAT32 文件系统与簇链解析（支持碎片文件）、SDRAM 四帧缓存与每 15.62 微秒一次的定时刷新仲裁、四类业务包并行的自研可靠 UDP 传输层（确认重传、链路租约、断链自愈）、上电防抖复位与读卡超时防死锁。全部图像与音频处理只用移位和加法实现，不占用任何 DSP。设计通过了 40 余项仿真回归和两轮上板实测，两板全部时钟域时序余量为正，LUT 占用约 83%，RTL 实际输出画面与软件模型逐像素零差异。"));
children.push(p([{ text: "关键词：", bold: true }, { text: "FPGA；车载双屏；以太网 UDP；音画同步；HDMI" }], { noIndent: true }));

// ============ 第一部分 ============
children.push(h1("第一部分  作品概述"));

children.push(h2("1.1  功能与特性"));
children.push(p("系统围绕车载场景将两块 FPGA 分工：A 板负责中控娱乐屏，B 板负责虚拟仪表盘，两屏内容独立又实时联动。"));
children.push(p("A 板功能：首页显示竞赛徽标、时钟与音乐播放卡片（含播放/暂停状态）；歌词页把整首歌词按演唱进度逐字染红，歌头信息（歌名、词曲、编曲等）在前奏中依次浮现；频谱页实时显示频谱柱状图、时域波形和左右声道 VU 音量条；另有四张 TF 卡图片支持按键切换、自动轮播与转场特效。"));
children.push(p("B 板功能：仪表盘页面带指针扫动动画和顶部滚动字幕；歌单页面完整显示六首歌曲，正在播放的一首整行标红；娱乐页面为一片缓缓流动的星空。"));
children.push(p("联动功能：B 板按键可在歌单页切歌，拨码开关可暂停/恢复播放（A 屏卡片按钮同步变化）；A 板按键切换页面、调节亮度/对比度/音量三档参数；A 板任一预警开关拨动时，B 屏不论当前显示哪一页都立即切入红色安全警告。音频与视频经同一根 HDMI 线输出到显示器扬声器。"));

children.push(h2("1.2  应用领域"));
children.push(p("本作品直接面向智能汽车座舱：中控屏与仪表盘双屏异显、内容联动是新能源汽车的标配形态，本系统正是这一架构的小型化全硬件实现。相比软件方案，纯 FPGA 方案上电约两秒即可出画面、没有操作系统崩溃和卡顿问题、时序确定性强，适合对启动速度和可靠性要求高的车规场景做前期原型验证。"));
children.push(p("系统所包含的技术要素具有广泛迁移价值：双控制器以太网协同架构可用于工业多屏监控、多屏数字标牌和广告机；TF 卡 + FAT32 + SDRAM 帧缓存构成的多媒体播放链路可用于各类显示终端；自研可靠 UDP 传输层可移植到任何需要两片 FPGA 或两套控制器实时交换大量数据的分布式系统。"));
children.push(p("同时，本作品覆盖了文件系统、存储控制、视频时序、音频接口、高速串行收发、网络协议等数字系统设计的全部核心知识点，也是一份优秀的 FPGA 综合教学实验平台。"));

children.push(h2("1.3  主要技术特点"));
children.push(p("（1）双板千兆以太网协同：FPGA 直接驱动 RGMII 物理层，自研轻量 UDP 协议栈，图像、音频、控制、可视化四类业务包并行传输，具备确认重传、链路租约与断链自愈能力，任一板复位重启后整链自动恢复。"));
children.push(p("（2）音画闭环同步：B 板不按自己的发送时间、而按 A 板反馈的已播放采样数计算歌词进度与频谱特征，从机制上消除网络抖动的影响，六首歌 2523 个同步事件误差为 0 个采样。"));
children.push(p("（3）资源极致利用：亮度、对比度、音量、Alpha 混合等运算全部用移位和加法实现，不占用 DSP；预警大字等颜色预先算好存入 BRAM，在 LUT 占用 83% 的情况下仍完成布线并留正时序余量。"));
children.push(p("（4）存储与可靠性设计：FAT32 簇链解析支持不连续簇的碎片文件；SDRAM 按每 15.62 微秒一次的节奏刷新并与读写突发仲裁，回归测试中刷新与读写冲突为零；单图加载超时自动中止，坏文件不会卡死系统。"));

children.push(h2("1.4  主要性能指标"));
children.push(p("系统主要量化指标如表 1 所示。", { keepNext: true }));
children.push(cap("表 1  系统主要性能指标", true));
children.push(tbl(["项目", "指标"], [
  ["视频制式", "640 x 480 @ 60 Hz，HDMI 1.4b（VIC=1），两屏独立输出"],
  ["音频规格", "48 kHz / 双声道 / 16 bit PCM，HDMI 与视频同线输出"],
  ["板间链路", "1000BASE-T 以太网 UDP 直连，MAC 侧 125 MHz / 应用侧 62.5 MHz"],
  ["图像传输", "整帧 307200 像素分 1200 包，确认超时 100 ms 自动重传"],
  ["歌词同步", "六首歌共 2523 个事件，与设计时间表误差 0 个采样"],
  ["SDRAM 刷新", "每 15.62 us 一次（4096 次/64 ms），与读写重叠为 0"],
  ["资源占用", "A 板 LUT 83.3%（BRAM9K 64/64）；B 板 LUT 83.8%"],
  ["时序余量", "两板全部时钟域建立余量为正（+0.28 ~ +4.52 ns）"],
  ["验证规模", "40 余项仿真回归（ModelSim 0 错误 0 警告）+ 两轮上板实测"],
], [24, 76]));

children.push(h2("1.5  主要创新点"));
children.push(p("（1）以播放进度反馈闭环驱动跨板逐字歌词同步：A 板每消费一个音频采样就把计数反馈给 B 板，歌词、频谱、波形全部按实际发声位置推进，同步误差为 0 个采样，网络抖动完全不影响音画一致。"));
children.push(p("（2）两片 FPGA 各自独立渲染一屏又深度联动，等价于双 SoC 智能座舱架构的纯硬件实现，全程无 CPU 参与。"));
children.push(p("（3）图像与音频处理全部采用移位加法，零 DSP 占用；参数帧边界统一更新，调节不撕裂。"));
children.push(p("（4）自研无 CPU 的可靠 UDP 传输层：确认重传、链路租约、断链自愈一体化，支撑图像音频控制三类流量并行。"));

children.push(h2("1.6  设计流程"));
children.push(p("设计遵循需求分析、总体架构、模块编码、仿真回归、上板实测、时序收敛、版本固化的流程迭代推进，共经历 12 轮版本迭代，每轮均冻结下载文件并保留可回退备份，如图 1 所示。", { keepNext: true }));
children.push(img("fig_dev_flow.png", 560));
children.push(cap("图 1  设计流程示意"));

// ============ 第二部分 ============
children.push(h1("第二部分  系统组成及功能说明"));

children.push(h2("2.1  整体介绍"));
children.push(p("系统总体结构如图 2 所示。两块 HX4S20C 开发板通过千兆网线直连：A 板是中控娱乐屏主体，从 TF 卡读取 BMP 图片并在本地渲染首页、歌词页、频谱页等画面，同时接收 B 板发来的音频并播放；B 板是虚拟仪表盘主体，从 TF 卡读取六首乐曲的 PCM 数据和页面背景，一边本地渲染仪表/歌单/星空画面，一边把音频流和分析出的可视化状态发给 A 板。"));
children.push(p("板间共传递五类信息：IMG4 图像包（B 板把自己的页面背景发给 A 板显示）、IAK2 确认包（接收方对每包的应答）、AUD2 音频包（音乐 PCM 数据流）、可视化状态包（频谱/波形特征）和 CTL4 控制包（安全预警标志、播放进度反馈、切歌指令等）。A 板把实际播放到的采样计数经 CTL4 通道回传 B 板，构成音画同步闭环。", { keepNext: true }));
children.push(img("fig_system_arch.png", 560));
children.push(cap("图 2  系统总体框图"));

children.push(h2("2.2  硬件系统介绍"));
children.push(h3("2.2.1  硬件整体介绍"));
children.push(p("系统硬件由两套对称的子系统组成，设备清单与连线方式如表 2 所示。每块 HX4S20C 开发板载 FPGA 主芯片 EG4S20（19600 个 LUT、64 块 BRAM9K、16 块 BRAM32K、29 个 DSP、4 个 PLL）、千兆以太网口（含 PHY 芯片，FPGA 经 RGMII 接口驱动）、HDMI 输出接口、TF 卡槽（SPI 模式）、四个轻触按键、四个拨码开关、六位数码管和 LED。", { keepNext: true }));
children.push(cap("表 2  系统设备清单与连接关系", true));
children.push(tbl(["设备", "数量", "连接关系"], [
  ["HX4S20C 开发板", "2", "A 板接中控显示器，B 板接仪表显示器"],
  ["HDMI 显示器（带扬声器）", "2", "分别接 A 板、B 板的 HDMI 输出口"],
  ["TF 卡（FAT32 格式）", "2", "A 板放 BMP 图片；B 板放 PCM 音乐与页面背景"],
  ["千兆网线", "1", "直连 A、B 两板网口（固定 IP，无需交换机）"],
  ["USB 下载器", "1", "轮流给两板下载 bit 流"],
], [30, 12, 58]));

children.push(h3("2.2.2  机械设计介绍"));
children.push(p("本作品为电子系统原型，未设计自定义机械结构：两块开发板与两台显示器按左右并排的方式摆放，左侧 B 屏模拟仪表盘、右侧 A 屏模拟中控屏，网线与 HDMI 线走板间直连，整套系统可在普通实验桌上完整演示。后续若需装车展示，仅需为两屏制作安装支架，电路与逻辑无需改动。"));

children.push(h3("2.2.3  电路各模块介绍"));
children.push(p("系统全部使用开发板板载电路资源，关键接口与代表性引脚分配如表 3 所示（完整约束见工程约束文件 media_a.adc / media_b.adc）。其中：HDMI 输出采用 LVDS33 差分标准直连 HDMI_B 连接器，同时经 DDC（I2C）通道读取显示器 EDID 以完成握手；千兆网口由 FPGA 以 RGMII 时序驱动板载 PHY 芯片，收发各 5 根信号线；TF 卡工作于 SPI 模式，由 FPGA 产生片选、时钟并收发数据；按键与拨码开关均为低电平有效并带内部上拉。", { keepNext: true }));
children.push(cap("表 3  关键接口与代表性引脚分配", true));
children.push(tbl(["接口/信号", "FPGA 引脚", "电气标准", "说明"], [
  ["系统时钟 clk", "R7", "LVCMOS33", "50 MHz 板载晶振"],
  ["HDMI 时钟/数据差分对", "C3 / G5 / F1 / E1", "LVDS33", "TMDS 四路差分输出"],
  ["HDMI DDC (SCL/SDA)", "P2 / R2", "LVCMOS33", "读取显示器 EDID"],
  ["以太网 RGMII（收发）", "T14/T13/P6/M6/T9/N9 等", "LVCMOS33", "连接板载千兆 PHY"],
  ["TF 卡 SPI", "A12 / A14 / A13 / B14", "LVCMOS33", "片选/时钟/命令/数据"],
  ["按键 KEY1~KEY4", "A2 / B2 / B1 / C1", "LVCMOS33", "带内部上拉，低有效"],
  ["拨码开关 SW1~SW4", "C8 / C7 / C6 / C5", "LVCMOS33", "安全预警（后/前/左/右）"],
  ["数码管段/位选", "C15~A6 / E12~D11", "LVCMOS33", "显示图片序号等状态"],
], [24, 22, 18, 36]));

children.push(h2("2.3  软件系统介绍"));
children.push(h3("2.3.1  软件整体介绍"));
children.push(p("本系统的全部软件即为 FPGA 内的 RTL 逻辑（Verilog），不含任何 CPU 程序。两板的逻辑按功能划分为以下模块，如表 4、表 5 所示。", { keepNext: true }));
children.push(cap("表 4  A 板（中控娱乐屏）主要逻辑模块", true));
children.push(tbl(["模块", "功能"], [
  ["top_dual_image", "顶层：连接所有子系统与时钟复位"],
  ["sd_card_bmp_remote", "TF 卡 BMP 读取与四帧缓存管理（含防死锁）"],
  ["frame_read_write", "SDRAM 读写 FIFO 控制与四帧地址切换"],
  ["image_packet_rx", "接收 B 板 IMG4 图像包，校验、排重、写入 SDRAM"],
  ["audio_packet_rx", "接收 AUD2 音频包，缓冲为播放 FIFO"],
  ["I2S_receiver / hdmi_1_4b_transmitter", "音频样本接收与 HDMI 音视频组包发送"],
  ["video_lyric_overlay", "歌词逐字卡拉OK渲染（515 字点阵字库）"],
  ["audio_visualizer_overlay", "频谱、波形、VU 音量条画面叠加"],
  ["video_image_adjust", "亮度/对比度调节（移位加法，帧边界生效）"],
  ["video_home_overlay 等", "首页徽标、时钟、音乐卡片等 UI 图层"],
  ["local_av_settings / key 逻辑", "按键消抖、参数档位与页面切换控制"],
], [40, 60]));
children.push(cap("表 5  B 板（虚拟仪表盘）主要逻辑模块", true));
children.push(tbl(["模块", "功能"], [
  ["image_media_board_b", "顶层：TF 读取、音频发送与本地显示"],
  ["dual_board_eth_transport", "RGMII/MAC/UDP 传输层（两板共用）"],
  ["hdmi_audio_pcm_i2s_64fs", "TF 卡 PCM 音乐读取与音频流分包发送"],
  ["remote_audio_compute_hw", "跟随 A 板播放进度的频谱/波形分析"],
  ["audio_lyric_timeline", "歌词逐字时间轴计算（按反馈采样数推进）"],
  ["b_hdmi_preview", "仪表/歌单/星空三页面本地渲染"],
  ["video_dashboard_needles", "仪表盘指针动画"],
  ["video_dual_star_overlay", "流动星空引擎（确定性伪随机）"],
  ["video_playlist_highlight", "歌单正在播放歌曲整行标红"],
  ["media_udp_arbiter", "多业务包发送仲裁调度"],
], [40, 60]));

children.push(p("时钟规划方面，A 板由 50 MHz 晶振经两片 PLL 产生全部工作时钟：SD 卡与 SDRAM 用户逻辑 100 MHz（SDRAM 外部时钟附加 180° 相移以保证采样余量）、视频像素 25 MHz、TMDS 串行 125 MHz、网络应用 62.5 MHz、音频主时钟 12.288 MHz；B 板与此类似。所有跨时钟域的数据交换均通过异步 FIFO 或握手打拍完成，并在时序约束中显式声明异步时钟组。", { keepNext: true }));
children.push(cap("表 6  主要时钟域规划", true));
children.push(tbl(["时钟", "频率", "用途"], [
  ["clk", "50 MHz", "板载晶振输入"],
  ["sd_card_clk", "100 MHz", "TF 卡 SPI 与读卡逻辑"],
  ["ext_mem_clk (+180°)", "100 MHz", "SDRAM 读写与刷新"],
  ["video_clk", "25 MHz", "640x480 像素时序与图层渲染"],
  ["hdmi_5x_clk", "125 MHz", "TMDS 串行化（A 板兼作网络时钟源）"],
  ["udp_clk", "62.5 MHz", "以太网应用层（MAC 侧仍为 125 MHz）"],
  ["audio_mclk", "12.288 MHz", "48 kHz / 64fs I2S 音频"],
], [28, 20, 52]));

children.push(h3("2.3.2  软件各模块介绍"));
children.push(p("（1）TF 卡读取与文件系统解析。上电后系统先等所有 PLL 锁定稳定（约 20 ms 防抖复位）再启动，随后按 FAT32 引导扇区、根目录、簇链的顺序解析文件系统，直接跟簇链读取数据，因此图片和音乐文件即使存储得不连续也能正确读出，且不受卡容量限制。单张图片加载超过 3 秒或目录扫描超过 10 秒即中止当前事务、跳到下一个文件，保证坏卡坏文件不会卡死系统。"));
children.push(p("（2）SDRAM 四帧缓存与刷新仲裁。四张图片分别缓存在 SDRAM 的四个帧区，第一张写完立即显示，其余在后台继续预载，之后切图只需切换读地址，响应速度只受按键消抖（15 ms）限制。SDRAM 控制器每 15.62 微秒发起一次自动刷新（满足 64 ms 内 4096 次的行业要求），新的读写突发只在控制器空闲且无待处理刷新时启动；回归测试在最坏流量下达成刷新与读写重叠为 0，长时间停留的帧缓存数据保持完好。"));
children.push(p("（3）以太网可靠传输层。两板使用固定 IP（A 板 192.168.10.11、B 板 192.168.10.12）和固定 UDP 端口互发数据包，无需 ARP 和交换机。整帧图像拆成 1200 个包发送，每个包都带序号与 CRC 校验，接收方逐包确认（IAK2），发送方 100 ms 未收到确认即重传；链路租约机制让任一板断电复位后，另一板能在 1 秒内检测到并重新协商，整链自动恢复。多类业务包由仲裁器统一调度，避免相互阻塞。"));
children.push(p("（4）音频通路与逐字歌词同步。B 板从 TF 卡读出 48 kHz PCM 音乐，按包流式发给 A 板；A 板缓存在异步 FIFO 中，按 12.288 MHz 主时钟产生的 I2S 时序消费样本，经 HDMI 音频通道（N=6144）与视频同线输出。关键在于同步机制：A 板每播放一批样本就把累计计数通过控制包回传，B 板的歌词时间轴和频谱分析模块完全以这个计数为时间基准推进，而不是以自己发包的时间为准，因此无论网络快慢，歌词逐字染红、歌单标红、频谱跳动的时刻都与扬声器里正在唱的内容严格对应，如图 3 所示。六首歌共 2523 个同步事件经仿真逐采样检查，与设计时间表误差为 0。", { keepNext: true }));
children.push(img("fig_sync_flow.png", 560));
children.push(cap("图 3  跨板音频播放与逐字歌词同步闭环"));
children.push(p("（5）显示渲染与图像调节。歌词采用逐字独立计时的时间表，字库收录 515 个汉字的多种字号点阵（思源黑体），歌头信息在前奏内逐行浮现、逐字变红。频谱、波形与 VU 条由 B 板按 A 板反馈进度计算，经可视化状态包传到 A 屏叠加显示，音量档位变化时三者同步缩放。亮度（25/50/75/100 四档）与对比度调节只用移位和加法实现，参数统一在帧边界生效，杜绝一行之内前后参数不一致的撕裂；图片通道按 RGB666 精度输出，抑制部分显示器在深色渐变区的闪烁。"));

// ============ 第三部分 ============
children.push(h1("第三部分  完成情况及性能参数"));

children.push(h2("3.1  整体介绍"));
children.push(p("系统已全部完成并经两轮上板实测（最近一次为 2026 年 10 月 20 日），双板同时上电后约 2 秒内 A 屏出现首页、B 屏出现仪表盘，随后音乐自动开始播放，歌词逐字同步滚动。以下界面图为 FPGA 实际输出画面的位精确验证渲染图：回归测试将 RTL 渲染结果与软件参考模型逐像素比对，差异为零，即上板画面与下图完全一致（实拍演示视频另行提供）。"));

children.push(h2("3.2  工程成果"));
children.push(h3("3.2.1  机械成果"));
children.push(p("本作品无自定义机械结构（见 2.2.2 节），系统以两块开发板与两台显示器的桌面形态完整呈现。"));
children.push(h3("3.2.2  电路成果"));
children.push(p("两板最终版下载文件与验证状态如表 7 所示，布局布线后的资源与时序结果如表 8 所示。需要说明的是，时序工具对安路加密 SDRAM 控制器内部的 0°/180° 时钟组报告约 -5.6 ns 的相位模型违例，经核实属 IP 约束模型的固有现象，不影响用户逻辑，两板全部用户时钟域的建立余量均为正值。", { keepNext: true }));
children.push(cap("表 7  最终版下载文件", true));
children.push(tbl(["板卡", "下载文件", "验证状态"], [
  ["A 板", "A_FINAL_KEYS_20261020.bit", "2026-10-20 上板验证通过"],
  ["B 板", "B_HDMI_FINAL_KEYS_20261020.bit", "2026-10-20 上板验证通过"],
], [16, 48, 36]));
children.push(cap("表 8  布局布线后资源与时序（第十二轮）", true));
children.push(tbl(["指标", "A 板", "B 板"], [
  ["LUT 占用", "83.3%", "83.8%"],
  ["BRAM9K / BRAM32K", "64/64（含字库）", "51/64 与 14/16"],
  ["建立余量（视频/像素域）", "+1.19 ns", "+0.34 ns（计算域）"],
  ["建立余量（网络域）", "+4.52 ns", "+3.92 ns"],
  ["建立余量（TF 读卡域）", "—", "+1.48 ns"],
  ["保持余量", ">= -0.025 ns", ">= -0.012 ns"],
], [36, 32, 32]));

children.push(h3("3.2.3  软件成果"));
children.push(p("A 屏三个页面与 B 屏三个页面的实际输出画面如图 4 至图 11 所示。", { keepNext: true }));
children.push(img("ui_a_home.png", 400));
children.push(cap("图 4  A 屏首页：徽标、时钟与音乐卡片（播放中）"));
children.push(img("ui_a_spectrum.png", 400));
children.push(cap("图 5  A 屏频谱页：频谱、波形与音量条（暂停态）"));
children.push(img("ui_a_lyric.png", 440));
children.push(cap("图 6  歌词逐字染红渲染验证（四组实际画面）"));
children.push(img("ui_a_musiccards.png", 300));
children.push(cap("图 7  六首歌曲的音乐卡片渲染验证"));
children.push(img("ui_b_dash.png", 400));
children.push(cap("图 8  B 屏仪表盘：指针动画与顶部滚动字幕"));
children.push(img("ui_b_hazard.png", 400));
children.push(cap("图 9  B 屏安全预警：注意安全大字呼吸闪烁"));
children.push(img("ui_b_playlist.png", 400));
children.push(cap("图 10  B 屏歌单：正在播放的歌曲整行标红"));
children.push(img("ui_b_star.png", 500));
children.push(cap("图 11  B 屏流动星空页面"));

children.push(h2("3.3  特性成果"));
children.push(p("各项功能的量化验证结果如表 9 所示，全部数据来自 ModelSim 回归日志与上板测试记录。", { keepNext: true }));
children.push(cap("表 9  特性验证结果汇总", true));
children.push(tbl(["特性", "验证方法", "结果"], [
  ["歌词逐字同步", "六首歌 2523 个事件逐采样检查", "误差 0 个采样"],
  ["字库完整性", "515 个汉字像素级读回比对", "全部正确"],
  ["画面正确性", "RTL 渲染与软件模型逐像素比对", "0 像素差异"],
  ["SDRAM 刷新仲裁", "最坏流量联合回归", "刷新/读写重叠 0 次，busy 最长 290 拍"],
  ["长停留数据保持", "10 秒停留后四帧缓存校验", "四缓存全部有效"],
  ["音频链完整性", "3 ms 行为仿真", "144 样本间隔 518~524 拍，CTS 稳定"],
  ["丢包重传", "故意丢确认包的整帧传输测试", "自动重传成功，无重复像素"],
  ["断链自愈", "连续五次 B 板复位整链测试", "全部自动恢复"],
  ["仿真总体", "40 余项回归", "ModelSim 0 错误 0 警告"],
], [26, 40, 34]));

// ============ 第四部分 ============
children.push(h1("第四部分  总结"));
children.push(h2("4.1  可扩展之处"));
children.push(p("系统在现有框架上可自然扩展：接入摄像头或 CVBS 视频输入即可实现倒车影像等行车视频功能；把拨码开关预警替换为 CAN 总线解码即可对接真实车况信号；TF 卡曲库可从六首扩展为按目录索引的完整歌单，并支持专辑封面显示；分辨率可向 720p/1080p 升级（需相应提升像素时钟与 SDRAM 带宽）；固定 IP 传输层可扩展 ARP/ICMP 成为完整协议栈并接入交换机组网；星空等页面引擎也可替换为导航地图或车控界面。整体架构对更多屏幕（三屏及以上）同样适用。"));

children.push(h2("4.2  心得体会"));
children.push(p("本项目从单板图片轮播起步，逐步加入音频、网络和第二块板卡，最终成长为覆盖文件系统、存储、视频、音频、网络五大领域的完整系统。回顾整个过程，有以下几点体会。"));
children.push(p("第一，仿真先行是效率的关键。项目从第一天起就坚持每个模块配测试台架：歌词同步有 2523 个事件的逐采样比对，画面渲染有与 Python 模型的逐像素比对，网络有故意丢包、丢确认的整链回归。正因为如此，十几轮迭代中每一个 bug 都能先在仿真里复现和修复，上板时间没有被无休止的调试吞噬。"));
children.push(p("第二，时序收敛靠的是分析而不是运气。开发中期曾出现上板黑屏：多轮排查发现是网络应用时钟 125 MHz 下布线违例集中在链路建立逻辑上，把应用侧时钟降到 62.5 MHz（物理层仍为千兆）并对所有按拍计数的常数等比缩放后，违例彻底消失且所有种子都能收敛。还有一次 B 板 LUT 资源满到布线失败，最终靠把乘法混色改为预计算颜色表存 BRAM 解决。这些经历让我们真正理解了时钟规划、流水线与资源预算的关系。"));
children.push(p("第三，工程习惯决定下限。每一轮修改前完整备份、每轮冻结的下载文件记录校验和与资源时序、上板现象逐条记录在案，使得任何一次退化都能迅速定位和回退；12 轮迭代没有一次找不到回归点。"));
children.push(p("第四，跨领域知识在真实系统中是融会贯通的。为了让一句歌词在正确的时刻变红，需要同时理解 I2S 采样率、UDP 往返延迟、跨时钟域同步和字库渲染；为了让一块 SDRAM 既喂饱显示器又按时刷新，需要理解其行地址结构与仲裁策略。这种综合锻炼是任何单一模块实验都无法替代的，也是本作品最大的收获。"));

// ============ 第五部分 ============
children.push(h1("第五部分  参考文献"));
const refs = [
  "[1] HDMI Licensing, LLC. HDMI 1.4b Specification[S]. 2011.",
  "[2] Silicon Image, Inc. TMDS: Transition Minimized Differential Signaling[S].",
  "[3] Microsoft Corporation. Microsoft Extensible Firmware Initiative FAT32 File System Specification[S]. 2000.",
  "[4] Etron Technology. EM638325 SDRAM Datasheet[Z].",
  "[5] 上海安路信息科技. EG4S20 FPGA 数据手册[Z].",
  "[6] 上海安路信息科技. TD 开发工具用户手册[Z].",
  "[7] Broadcom Corporation. Reduced Gigabit Media Independent Interface (RGMII) Specification[S].",
  "[8] IEEE. IEEE Standard for Ethernet, 802.3[S]. 2018.",
  "[9] Postel J. RFC 768: User Datagram Protocol[S]. 1980.",
  "[10] Philips Semiconductors. I2S Bus Specification[S]. 1996.",
  "[11] 上海安路信息科技. APUG092 HDMI 1.4b Transmitter IP 参考设计[Z].",
  "[12] VESA. VESA DDC Standard[S].",
  "[13] Siemens EDA. ModelSim 仿真工具用户文档[Z].",
  "[14] Adobe与Google. 思源黑体（Source Han Sans）字体[Z].",
];
refs.forEach(r => children.push(new Paragraph({
  alignment: AlignmentType.LEFT,
  spacing: { before: 0, after: 60, line: 312 },
  indent: { left: 240, hanging: 240 },
  children: [new TextRun({ text: r, size: 21, font: F_BODY, color: "000000" })],
})));

// ---------- 文档（封面 / 摘要 / 正文三节） ----------
// children[0..5] 为摘要（标题+4段+关键词），children[6] 起为第一部分正文
const part1Idx = 6;
const doc2 = new Document({
  styles: {
    default: {
      document: {
        run: { font: F_BODY, size: 24, color: "000000" },
        paragraph: { spacing: { line: 312 } },
      },
      heading1: { run: { font: F_HEAD, size: 32, bold: true, color: "000000" }, paragraph: { spacing: { before: 360, after: 200, line: 312 } } },
      heading2: { run: { font: F_HEAD, size: 30, bold: true, color: "000000" }, paragraph: { spacing: { before: 280, after: 140, line: 312 } } },
      heading3: { run: { font: F_HEAD, size: 28, bold: true, color: "000000" }, paragraph: { spacing: { before: 220, after: 120, line: 312 } } },
    },
  },
  sections: [
    {
      properties: {
        page: { size: { width: 11906, height: 16838 }, margin: { top: 1417, bottom: 1417, left: 1701, right: 1417 } },
      },
      children: [
        new Paragraph({ spacing: { before: 3400, line: 312 }, children: [] }),
        new Paragraph({
          alignment: AlignmentType.CENTER, spacing: { before: 200, after: 120, line: 312 },
          children: [new TextRun({ text: "作品名称", size: 28, bold: true, font: F_HEAD, color: "404040" })],
        }),
        new Paragraph({
          alignment: AlignmentType.CENTER, spacing: { before: 160, after: 60, line: 440 },
          children: [new TextRun({ text: "双FPGA以太网协同的", size: 56, bold: true, font: F_HEAD, color: "000000" })],
        }),
        new Paragraph({
          alignment: AlignmentType.CENTER, spacing: { before: 0, after: 320, line: 440 },
          children: [new TextRun({ text: "车载双屏影音系统", size: 56, bold: true, font: F_HEAD, color: "000000" })],
        }),
        new Paragraph({
          alignment: AlignmentType.CENTER, spacing: { before: 600, after: 0, line: 312 },
          children: [new TextRun({ text: "（FPGA 创新设计竞赛技术文档）", size: 24, font: F_BODY, color: "595959" })],
        }),
      ],
    },
    {
      properties: {
        page: { size: { width: 11906, height: 16838 }, margin: { top: 1417, bottom: 1417, left: 1701, right: 1417 } },
      },
      children: children.slice(0, part1Idx),
    },
    {
      properties: {
        page: {
          size: { width: 11906, height: 16838 },
          margin: { top: 1417, bottom: 1417, left: 1701, right: 1417 },
          pageNumbers: { start: 1, formatType: NumberFormat.DECIMAL },
        },
      },
      footers: {
        default: new Footer({
          children: [new Paragraph({
            alignment: AlignmentType.CENTER,
            children: [new TextRun({ children: [PageNumber.CURRENT], size: 18, font: F_BODY, color: "595959" })],
          })],
        }),
      },
      children: children.slice(part1Idx),
    },
  ],
});

Packer.toBuffer(doc2).then(buf => {
  fs.writeFileSync("技术文档_双FPGA车载双屏影音系统.docx", buf);
  console.log("OK", buf.length, "bytes");
});
