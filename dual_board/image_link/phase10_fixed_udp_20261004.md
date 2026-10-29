# 第十阶段：固定双板轻量 IPv4/UDP

开始于 2026-10-04，2026-10-05 继续验证。上板准备中将 RX 的 `fold(sum)==FFFF` 改为严格等价的 `low16==FFFF-high4` 比较，全部 1048576 种 20-bit sum 已穷举通过。TX 生成任意校验和值的折叠算法不变；此简化去掉接收接受判断中的两级串联进位路径。

本轮只修改隔离的 `dual_board/image_link/`。原单板源码、回退 bit、字模/图标/歌词、MAC/RGMII/PLL、SDRAM、应用协议与旧 Ethernet smoke 工程均不修改。优化前双板源码快照位于 `backup_phase9_fixed_udp/`；它不是可独立烧录的工程。

## 改了什么

正式 A/B 播放器通过 `FIXED_PEER=1` 启用新 `fixed_peer_udp.v`，替换通用加密 `udp_ip_protocol_stack` 的实例。不是解密、修改或删除原 IP 文件。`dual_board_eth_transport.v` 默认仍为 `FIXED_PEER=0`，旧 IMGF 图案工程和 smoke 保留原网络栈；正式工程清单仅追加新 RTL。

| 项目 | A 主板 | B 媒体源与计算板 |
| --- | --- | --- |
| IP / MAC | 192.168.10.11 / 02:00:00:00:00:0b | 192.168.10.12 / 02:00:00:00:00:0c |
| 收发对象 | 只认 B 的固定地址 | 只认 A 的固定地址 |
| UDP 源/目的端口 | 0x5002（20482） | 0x5002（20482） |
| 最大发送/接收载荷 | 18 / 1042 字节 | 1042 / 18 字节 |

B→A 的 IMG4(1042)、AUD2(530)、VIZ2(47)、CTL2(12)、LNK1(10)，以及 A→B 的 IAK 确认(12)、AAK3(18)、LNK1(10) 全部保留。固定网络层不接管音画进度：仍以 A 真正播放的样本序号同步 B 的计算结果和歌词。图片完整校验/SDRAM 写入后提交、CRC 重传、世代握手、受保护缓存复用、本地危险预警等逻辑没有删除。

### 收发与校验

- TX 先 ACK 并缓存整个应用载荷，再生成 Ethernet/IPv4/UDP 头；MAC 的低有效背压只暂停送出，不会丢失应用无背压接口的字节。填充等待超时不向 MAC 发布半包。TX 状态、SOF/EOF/数据在 MAC 未接受时保持。
- RX 先缓存并验证整个 MAC client 帧，再连续发布恰好声明长度的应用载荷，至少一拍 valid 低电平分包。验证固定 MAC/IP/端口、IPv4 version/IHL、未分片、TTL、协议、IP 头校验和、IP/UDP 长度和实际 EOF 边界；大包索引饱和，避免异常巨帧回绕。
- IPv4 UDP 发送 checksum=0，接收只接受 checksum=0，非零值明确拒绝，不装作已经计算验证。原应用层 CRC 保留；MAC 负责 FCS 和坏帧判定。本实现不是与任意主机互通的通用 UDP 栈。
- TX 短帧补零到不含 FCS 的 60 字节。RX 接受“MAC 已去 padding 的精确长度”或“保留到最短 60 字节”的完整形态；二者之间或多出尾部仍拒绝。公开 FIFO RTL 不解析 IP、不会主动去 padding，真正加密 TEMAC 的处理仍需实测。
- 两个小字节 RAM 使用同步读取、按接受节奏预取，不逐项清零 RAM。复位清状态/描述符，旧缓存不会自行发布。A/B 按方向分别限制容量，不为小确认包保留全媒体发送/接收能力。

删掉的通用能力：ARP 查询、ICMP/Ping、动态通信对象、IPv6、VLAN、IP options、分片与路由。板间仍是标准 Ethernet/IPv4/UDP，不是仅套 UDP 名字的自定义以太网帧。固定地址只适用于本双板方案；以后改对端需改参数并重新生成 bit。电脑继续串口接 B，不受不能 Ping 的限制。

## 最终候选的 gate 综合资源

| 指标 | A 第九阶段 | A 本轮 | B 第九阶段 | B 本轮 |
| --- | ---: | ---: | ---: | ---: |
| LUT / 19600 | 15799（80.61%） | 13453（68.64%） | 13261（67.66%） | 10932（55.78%） |
| 寄存器 | 11493 | 9132 | 9898 | 7513 |
| BRAM9K / 64 | 49 | 50 | 27 | 28 |
| BRAM32K / 16 | 7 | 7 | 9 | 9 |
| DSP / 29 | 3 | 3 | 3 | 3 |
| PLL / 4 | 4 | 4 | 3 | 3 |

两板合计 **29060→24385 LUT，净省 4675（本轮减少 16.09%）**；寄存器合计净省 4746。净代价为每板多一块 BRAM9K（新双向缓存三块，旧栈相关 RAM 被裁掉两块），没有增加 BRAM32K、DSP 或 PLL。

总 LUT 相当于一块容量的 124.41%，相对两块总容量为 62.21%。这只是计算口径：不能把总数称为某块板 125% 超载，也不能用两板平均值掩盖 A 的 BRAM9K 78.12%、PLL 4/4 的余量限制。与第八阶段相比，累计省 5208 LUT。以上是 gate 综合，不是布局布线后的数字，更不能与单板布线后 88.74% 直接混算。

原通用栈与新端点未同时实例化：最终层级报告只有 `fixed_peer$u_udp / fixed_peer_udp`，原 UDP/ARP/ICMP 层级已经裁去。原加密文件保留在 source list 是为了默认 legacy 分支编译，不代表它仍占正式播放器资源。

## ModelSim 验证范围

最终通过结论以 `phase10_validation_20261004.json` 校验并冻结的 `sim/phase10_final_modelsim_20261004.log` 为准，不能用早期失败日志或旧报告替代。

原 34 项回归加六项新测试：

1. `tb_fixed_peer_udp`：独立报文/IP 校验和 oracle，1/10/12/17/18/19/47/255/256/530/1023/1024/1042 长度、最大值越界、随机背压/字节空洞、错误头/校验/长度、padding 两形态、巨帧饱和、缺 EOF 后新 SOF 恢复、填充超时及复位隔离。
2. `tb_fixed_peer_udp_pair`：实际双端并发，按 A TX18/RX1042、B TX1042/RX18 的正式非对称容量，多次完整发送及复位。
3. `tb_fixed_udp_native_fifo`：工程真实 TX/RX client FIFO RTL，四个不同频率时钟、MAC 首字 ACK 延迟/读使能、10/12/18/530/1042 包、RX 暂停、坏 MAC 帧回滚及 TX 中途复位；MAC relay 保留短帧 padding。
4. `tb_fixed_udp_native_fifo_stripped`：同一原生 FIFO 测试，MAC relay 去掉短帧 padding，两种行为均正确传到应用。
5. `tb_audio_offload_fixed`：实际 IMG4/AUD2/VIZ2/CTL2/确认包经过真 Ethernet/IP/UDP 封装，原音频分析器/歌词时间轴、原生 PCM FIFO、48kHz 播放；故意损坏 PCM 应用 CRC、在实际 RX 处丢掉一次完整 ACK，确认重传、断流冻结和音量进度反馈。
6. `tb_media_restart_fixed`：真实 LNK1/媒体包封装、五次 B 独立复位（A 端点没有被一起复位），确认世代恢复、缓存保护/四图预载及 PCM 播放头。初版 fixture 曾用 ar||br 一并清 A 端点，此覆盖缺口已改为按板归属单独复位后再跑。

新增六项已单独运行通过；完整回归应在同一最终 RTL 上重新编译。单元/pair 零警告；媒体/native 测试有原生 RAM 未用输出、旧 fixture 可选 generation 端口、未修改供应商 FIFO 常量位宽警告，必须原样计入 manifest，不称为零警告。

完整运行：`& ./dual_board/image_link/sim/run_modelsim.ps1 -Suite All`。只跑新六项：`-Suite FixedUdp`；独立端点/原生 FIFO/媒体可选 `FixedUdpUnit`、`FixedUdpNative`、`FixedUdpMedia`。WLF 对应 `fixed_udp_unit/pair/native_padded/native_stripped/audio_offload/media_restart.wlf`。脚本统一检查所有 PASS 和 Error/Fatal，不只看 ModelSim 的进程退出码。

### 不能由这些测试证明的事项

原生 FIFO 使用 test-only 同步双口 RAM 行为模型与 MAC relay，**没有模拟加密 TEMAC、RGMII/PHY、线缆、真正 FCS 或碰撞重传**。集成测试输入已解码媒体，不是读取真实 TF/FAT 文件；也没有真实 SDRAM 芯片与 HDMI 屏幕。没有覆盖持续线速、多帧导致 native FIFO 满的压力场景，不能宣称无丢包满千兆吞吐。RX 连续发布时暂停 native FIFO，大媒体包约 8.3µs；现有 TF/stop-and-wait 媒体方式不是持续线速设计，丢包仍依赖已有重传。

第一次新增媒体 DO 运行因波形 log 路径写成不存在的 `forward` 而退出，没有得到媒体通过结论；改成实际 `media_link` 路径后重跑。这是测试脚本路径修复，不是忽略错误。

## 发布边界与下一步

2026-10-05 已另外生成隔离的 `../fixed_udp_hw/` 诊断配套 bit，见[上板步骤](../fixed_udp_hw/README.md)。它测试真实 fixed-peer UDP 的 1042 字节 IMG4 全帧和 12 字节反向 IAK2 确认，ModelSim 已检查两帧、一次丢 ACK 重传和复位。诊断布局后 A=2263/B=1933 LUT，当前继承约束下建立/保持裕量均为正，但完整外部 IO 时序仍待审计、尚未实板验证；这些数字不是播放器资源。诊断不读 TF、不输出 HDMI/音频，专用测试图生成器不替代正式 TF 发包器。可先用 B K2 做新固定端点实板验证，旧 smoke 成功不能替代这一步。

本轮没有更改约束、做布局布线或生成新的正式 A/B 播放器 bit，不能拿旧 IMGF 测试 bit 当正式播放器。主板正式工程仍引用单板 pin/timing：缺 RGMII 引脚/接收时钟、存在旧 video_pll 层级路径；副板正式 pin 缺四根 TF 信号，其时序文件也只是早期 smoke 时钟。下一步要在双板独立约束中补齐，核对共享以太网/视频 PLL 的关系及 SDRAM/HDMI/RGMII 的 IO 时序，然后分别 P&R 并检查约束覆盖与建立/保持裕量，再生成配套 bit。

没有网线时可以完成上述设计/综合/仿真，不能替代最终板上验证。配套 bit 完成后先测握手和一张静态图，再测音频、四图切换、串口参数、预警、频谱/歌词与独立重启。单板源码和已验证 bit 保持可回退。LNK1 世代仍为易失计数，不是安全认证或跨双方断电永久防重放机制。
