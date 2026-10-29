# 首页应用卡与单行状态显示版（2026-09-29）

## 交付

- bit：`lab_ex5_i2s_v1.0_home_apps_inline_status_20260929.bit`
- SHA256：`6EFE8F1EE738A075D3B1B4CA8302C8A302457ADB385D96578E5D72B036FF97B2`
- 布线资源：`home_apps_inline_status_20260929_phy.area`
- 布线时序：`home_apps_inline_status_20260929_pr.timing`
- 640×480 合成仿真预览：`assets/home_dashboard_combined_preview.png`（测试色背景，不是 TF 图片）

旧版 bit 均保留，哈希未改变。

## 界面

1. 第一张卡：搜索目的地的蓝色按钮改为水平、垂直对称的 24×24 圆形。
2. 第二张卡：删除右下角小音乐图标；中间显示双竖线暂停按钮，表示音乐**当前正在播放**。上一首和下一首图标保留。该按钮目前是状态画面元素，不是新增触摸/按键输入。
3. 第三张卡：删除天气图文，改为“应用”标题，以及音乐、微信、抖音三枚小图标和文字标签。三张用户提供的图标压缩成 30×30、3-bit 索引图，每 3 个像素打包为一个 9-bit 字，全部共享一块 1024×9 ROM。应用图标只是显示内容，尚未接入应用启动功能。
4. 左上角：亮度、对比度、音量在同一行显示为 `BRI:… CON:… VOL:…`，移除原状态卡背景、边框、侧边线和彩色档位条。文字使用原有字模 ROM 与单像素暗色投影；在所有有效图片页均可见。

图标原图在 `assets/app_*_source.png`；由 `sim/generate_app_icons_rom.py` 机械生成 `video_app_icons_rom.v`。新汉字“应用、微信、抖”复用旧天气字模地址，未增加字体 BRAM。

## 验证与资源

- ModelSim：`tb_home_navigation_card.sv`、`tb_video_home_overlay.v`、`tb_video_status_overlay.v`、`tb_home_dashboard_combined.sv`、`tb_bmp_pcm_stream.v` 均通过。全帧对比确认首页卡片层变化仅在三张卡；顶部状态文字无框无色条；上下两层同时显示无冲突。
- TD 6.2：综合、布局布线、bitgen 完成。布局种子 9；LUT 14423/19600（73.59%），寄存器 7260/19600，BRAM9K 39/64，DSP 5/29，PLL 3/4。相对上一版圆形封面 bit，LUT 减少 356，BRAM 增加 1。
- 视频时钟域 setup +12.275 ns，SD 卡时钟域 setup +0.159 ns；hold 无违例。原有 SDRAM 路径导致全局 setup WNS −5.699 ns，与先前版本相同，未改时钟或约束。

尚未上板验证。建议烧录后检查首页三个卡片、2～4 图状态文字、图片轮换、TF 音频与左右声道。
