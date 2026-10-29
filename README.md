# 双屏联动车载多媒体安全座舱（HX4S20C / EG4S20 · 双 FPGA）

基于安路 EG4S20 的双板联动车载多媒体系统：

- **A 板**：SDRAM 显存、双屏显示、HDMI 1.4b 音视频输出
- **B 板**：TF 卡图库 / BMP 解码 / 音频解码与重采样 / 网络发送
- **板间互联**：以太网固定 IP UDP 协议（LINK / IMG4 / AUD2 / VIZ2 / AAK3 / CTL4 六类包，CRC + 序号 + 代际租约 + ACK 重传 + 整帧提交），无 ARP/ICMP 的固定 IP 方案节省 4675 LUT

主要功能：TF 卡 BMP 图库轮播、双屏联动显示、48 kHz HDMI 音频（I2S + ACR，N=6144）、歌词/字幕 OSD、频谱可视化、星轨/萤火虫特效、ADAS 前车碰撞警示、拨码播放/暂停。

## 目录结构

| 目录 | 内容 |
| --- | --- |
| `src/` | 单板基础工程（TF 卡 BMP 轮播 + OSD + HDMI，TD 工程 `src/td_project`） |
| `dual_board/` | 双板联动工程：`image_link`（主工程，`prj/_s23_*` 为各轮 bit）、`fixed_udp_hw`、`ethernet_smoke` |
| `sim/` | ModelSim 仿真脚本、testbench 与分析工具（Python） |
| `best_result/` | 历轮验证结果、TF 卡素材清单、验证记录文档 |
| `assets/` | 字库 BRAM 初始化 hex、歌词、图标等素材 |
| `doc/` | 参考文档、图片转换工具（`doc/convert`） |
| `doc_build/` | 技术文档生成脚本与图源 |

## 最新 bit（第 12 轮）

- A 板：`dual_board/image_link/prj/_s23_a4/`
- B 板：`dual_board/image_link/prj/_s23_b3/`

对应时序/面积报告在同目录（`*_phy.area` 为资源层级报告）。第 12 轮为最新版本，板级完整验证截至第 7 轮。

## 文档入口

- [代码说明.md](代码说明.md) — 基础工程（单板 TF 卡 BMP 轮播 + OSD Alpha 混合 + HDMI 音视频）详细说明
- [设计参考例程文档.md](设计参考例程文档.md) / [设计参考例程文档.docx](设计参考例程文档.docx) — 完整版参考文档
- [best_result/UART使用说明.md](best_result/UART使用说明.md) — 串口使用说明

## 重建方法

使用安路 TD 工具链打开 `dual_board/image_link/prj/_s23_a4/*.al`（A 板）与 `_s23_b3/*.al`（B 板），或运行各目录下 `build.tcl` 重新编译。综合/布线数据库（`route.db`、`*_Runs/`）与仿真波形转储（`.wlf/.vcd/.hex`）不入库，可由源码与脚本重新生成。

## 音频素材说明

`*.pcm/*.wav/*.mp3` 等音频文件不入库；PCM 可由 `mp3_to_pcm_20261011.py` 从 MP3 重新生成，TF 卡音频清单见 `best_result/` 各轮目录。
