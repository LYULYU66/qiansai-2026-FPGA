# 首页状态栏、日期时间与晴天图标版（2026-09-29）

- `lab_ex5_i2s_v1.0_home_clock_sunny_20260929.bit`：由 `src/td_project/resopt_Runs` 的工程编译生成，布局种子 11。SHA-256：`E0A54C548B327D6C05357F45CA40F50D6E49775D6B20F8162AF3BE4A0988DDE6`。
- 首页顶部为 36 像素深色状态栏，保持 BRI/CON/VOL 单行显示；右上方在状态栏下显示固定的 `10月1日`、`09:00` 及晴天图标。日期时间不是实时时钟，当前不走串口/RTC 更新时间。
- 首页第三张应用卡只保留三枚图标，不再显示“应用”标题或汉字标签；其余图片和原功能不改。
- 数字及“月、日”复用首页字模 ROM 已腾出的编号，晴天图标为逻辑图形，不增加 BRAM。文字采用亮色高对比度及深色底，避免浅色背景不清楚。
- ModelSim：`tb_video_home_overlay`、`tb_video_status_overlay`、`tb_home_navigation_card`、`tb_home_dashboard_combined` 均通过；预览为 `home_clock_sunny_20260929_preview.png`。尚未在实板复核。
- 布局布线：LUT 14852/19600（75.78%），寄存器 7272/19600（37.10%），BRAM9K 39/64（60.94%），DSP 5/29。视频路径 setup +4.580 ns，SD 卡路径 setup +0.120 ns，hold 最差 +0.021 ns；整体 setup WNS −5.699 ns 来自既存外部 SDRAM 路径，不能视为全工程时序收敛。
- 对应报告：`lab_ex5_i2s_v1.0_home_clock_sunny_20260929.area`、`lab_ex5_i2s_v1.0_home_clock_sunny_20260929.timing`。
