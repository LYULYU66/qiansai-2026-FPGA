# 首页无框图标优化版（2026-09-29）

- Bit：`lab_ex5_i2s_v1.0_home_frameless_hdicons_20260929.bit`，SHA-256 `BD869A1786A98A6DC3A131B42553D80192AEE6829F4B4E29441C6E0EF0C713A8`。由 `src/td_project/resopt_Runs` 编译，布局种子 16。旧版 bit 保留。
- 首页顶部 BRI/CON/VOL 不再有状态框；右上角日期、时间与太阳也直接叠在图片上。日期固定显示 `10月1日周一`，时间固定显示 `09:00`，目前未接实时时钟。
- 三个卡片和底部导航栏顶部的蓝色细边已删除。导航卡蓝圆中的白箭头改为居中的东北向箭头。
- 三枚应用图标与晴天图标使用 32×32、各自 15 色加透明色，打包为一份 1024×16 ROM，占两块 BRAM9K；源图保存在 `assets/`，可用 `sim/generate_app_icons_rom.py` 重建。中文“一”复用首页字模 ROM 的空位，没有新增字体 BRAM。
- ModelSim 已通过 `tb_video_home_overlay`、`tb_video_status_overlay`、`tb_home_navigation_card`、`tb_home_dashboard_combined`。预览见 `home_frameless_hdicons_20260929_preview.png`；未在实板确认。
- 资源：LUT 14519/19600（74.08%），寄存器 7258/19600（37.03%），BRAM9K 40/64（62.5%），DSP 5/29。
- 最终时序：视频 +5.533 ns，SD 卡 +0.041 ns，HDMI 125 MHz +0.047 ns，保持最差 +0.023 ns。SD 与 HDMI 裕量较小，上板应重点复核；整体 setup WNS 仍为 −5.699 ns（既存外部 SDRAM 路径），并非全工程时序收敛。详见同名前缀 `.area`、`.timing` 报告。
