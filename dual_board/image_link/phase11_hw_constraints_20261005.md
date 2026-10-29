# 第十一阶段：正式播放器物理实现首轮检查

用户反馈新固定 UDP 诊断“灯没有问题”，单独记在 `../fixed_udp_hw/hardware_test_20261005.md`。这是诊断实板通过，不是正式播放器通过。

## 本轮范围

正式 A/B 旧 `.al`、单板源码/约束/bit、已通过诊断 bit 不修改。`phase11_baseline_20261005.json` 记录基线哈希；`sim/prepare_player_hw.js` 从原项目机械生成独立硬件候选：

- `prj/media_a/MEDIA_IMAGE_A_HW_20261005.al`
- `prj/media_b/MEDIA_SOURCE_B_HW_20261005.al`
- 新独立引脚/时钟约束：`constraints/media_a.adc/.sdc`、`constraints/media_b.adc/.sdc`
- 构建脚本：对应目录的 `build_hw_a.tcl`、`build_hw_b.tcl`。**没有自动 bitgen**。

A 保留原 HDMI、按键、危险开关、数码管引脚，补入已通过实板测试的 PHY1，引脚中删除已迁出的 PC UART；A TF 输出保持原顶层的安全静态值。B 保留 PHY1/UART/LED，补齐 SD_DCLK=A14、SD_MISO=B14、SD_MOSI=A13、SD_nCS=A12。原 IMGF `board_a/b.adc` 不覆盖。

时钟按实际 PLL 输出命名，清掉旧 video_pll 实例路径。A 的 25MHz 视频与 125MHz UDP/HDMI 串行时钟来自同一个以太网 PLL，不采用旧 exclusive 分组。只把独立 PHY 接收时钟、A 音频 CDC 域分组；没有放宽频率、改变 PLL/FIFO/IP 或删除同域违例。外部 RGMII/SPI/DDC IO 延迟仍未完成规格审计，不能用接近 100% 的 STA 覆盖率代表完全约束。

## 首轮结果：未通过，不发布播放器 bit

两进程都返回 exit 0，但不能据此判定构建成功：

- A：`td_20261005_125016.log` 在 route 报 `PHY-8023 ERROR`，存在布线资源冲突（例如 `u_network_images/u_rx/mux0_syn_113` 与 `frame_read_write_m0/frame_fifo_read_a/rst_dup_298_holdbuf0`）。没有最终 routed timing，不能称为完成布局布线。Placed 报告还有 SDRAM 原有约 -5.843ns 路径及 UDP 负裕量，不能靠换种子解决全部时序问题。
- B：`td_20261005_125031.log` 已完成 route/report，`MEDIA_SOURCE_B_HW_20261005_pr.timing` 的建立 SWNS=-4.069ns、保持 HWNS=-1.540ns，STA 覆盖 99.80%。时序不通过，不能发布为合格 bit。
- 当前硬件候选 gate 资源 A=14035 LUT / 9132 FF，B=11019 LUT / 7513 FF；硬资源与之前一致。这些是在新增时钟约束参与优化后的综合数字，**不是两板最终布局数字**，也不能覆盖第十阶段 A=13453/B=10932 的冻结 gate 统计。

本轮没有改功能 RTL；原第十阶段 40 项仿真针对同一逻辑仍是参考证据，但不是本轮物理实现通过证据。

## 下一步

先按 B 最终、A placed 报告提取具体同域/跨域端点，区分真实长组合路径、第一拍同步器与稳定数据握手。针对真实关键路径做局部流水/复位扇出优化，并验证消息所有字段和帧边界同步；不能把 25/125MHz 相关域整体设异步来消除红字。A 布线冲突需要单独处理，复查后才做新的 route。SDRAM 加密 IP 的旧 IO 路径保留明确的未闭合边界，不擅改加密代码或 PLL 相位。

当前继续使用已通过的诊断 bit，暂时没有新的正式播放器配套下载文件。
