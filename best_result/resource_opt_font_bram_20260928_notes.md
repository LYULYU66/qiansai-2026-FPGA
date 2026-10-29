# 字库 BRAM 化 + 删除诊断功能（2026-09-28）

## 交付文件

- `lab_ex5_i2s_v1.0_resource_opt_font_bram_20260928.bit`
- bit 生成时间：2026-09-28 19:22
- SHA256：`423f3a61a5470a7807e8c4da471733ca212b5bfd0c2d849562a8fc98f007bfbd`
- 资源报告：`resource_opt_font_bram_20260928_phy.area`
- 布线后时序报告：`resource_opt_font_bram_20260928_pr.timing`
- 构建目录：`src/td_project/resopt_Runs/{syn,phy}`（流程脚本与布局种子 seed 3 沿用 `lab_ex5_i2s_v1.0_Runs`）

改动前的源码、`.al` 工程文件和 bit 备份在 `backup_before_resource_opt_20260928/`。
本版本**尚未上板验证**。

## 布局布线资源（EG4S20BG256，TD 6.2.168116）

| 资源 | 优化前 | 本版 | 变化 |
|---|---:|---:|---:|
| LUT / 19600 | 15555（79.36%） | 14291（72.91%） | −1264 |
| 寄存器 / 19600 | 7409（37.80%） | 7270（37.09%） | −139 |
| BRAM9K / 64 | 33 | 37 | +4 |
| DSP / 29 | 5 | 5 | 0 |

## 改动

1. `video_home_overlay.v`、`osd_alpha_overlay.v`、`video_status_overlay.v`：
   16×16 / 10×14 抗锯齿字模从 `case` 组合查找表移入同步 BRAM ROM
   （`video_home_glyph_rom` / `osd_glyph_rom` / `video_status_font_rom`）。
   ROM 用下一拍的扫描坐标寻址，输出与当前像素对齐，**像素输出逐拍不变**。
2. 删除诊断功能：`video_pixel_diagnostics` 模块（测试图、帧 CRC、FIFO/AXIS 标志）
   不再例化，工程文件列表中已移除；`uart_audio_control.v` 去掉 `TEST`/`DIAG`/`DCLEAR`
   命令，这三条命令现在回复 `ERR`。其余串口命令不变。
3. 加密模块（HDMI 1.4b 发射核、SDRAM 控制器）未改动。时钟、PLL、约束未改动。

## 验证

- `sim/tb_overlay_font_rom_equivalence.sv`：新旧三个叠加层并行运行，真实 800×525 光栅、
  随机背景、随机使能切换、亮度/对比度/音量全取值、帧中异步复位，每拍比较输出。
  14 帧完整画面（512 万周期）逐位一致。
  1000 帧长测（覆盖 840 帧的完整字幕滚动周期，5192 万周期、3868 万有效像素）逐位一致，
  日志：`sim/resource_opt_20260928/tb_overlay_font_rom_equivalence_1000f.log`。
- `sim/tb_uart_audio_control.v`：已更新，音量/亮度/对比度/STATUS 回归通过，
  删除的三条命令确认返回 `ERR` 且不改变设置。
- 旧回归脚本 `sim/run_resource_regression.ps1` 中的 `tb_video_pixel_diagnostics`、
  `tb_video_frame_crc_monitor` 对应的功能已删除，不再适用。

## 时序

Setup WNS −5.699 ns（与优化前相同，为原有 SDRAM 时钟域路径），Hold 无违例。

## 上板建议检查

图 1 首页文字（目的地/音乐/天气三卡）；图 2～4 底部滚动字幕与左上角状态卡；
串口 `BRI`/`CON`/`VOL` 修改后状态卡数值随之变化；四图切换、音频、方向预警。
