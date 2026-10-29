# 首页导航卡片蓝色图标版（2026-09-28）

基于 `lab_ex5_i2s_v1.0_resource_opt_font_bram_20260928.bit` 对应工程修改。
原 bit 保留，SHA256 仍为 `423F3A61A5470A7807E8C4DA471733CA212B5BFD0C2D849562A8FC98F007BFBD`。

## 交付

- 新 bit：`lab_ex5_i2s_v1.0_navigation_card_blue_20260928.bit`
- SHA256：`DE12362970607FEF45A999C0092E1763190C168BCFBF8DCF3543DB2784AFED28`
- 资源报告：`navigation_card_blue_20260928_phy.area`
- 时序报告：`navigation_card_blue_20260928_pr.timing`

## 内容

仅首页（图片 1）第一张卡片：蓝色地图定位图标叠浅色导航箭头；下方“搜索目的地”；细竖线分隔右侧“回家”和“公司”快捷入口，各带对应图标。删除原“青岛”目的地文本。音乐、天气卡片、底部导航和其他图片页面不改。六个新汉字与三个图标放入原有 16×16 字模 ROM 的空地址，无新增字库 BRAM。

## 验证

- ModelSim `sim/tb_video_home_overlay.v`：通过。
- ModelSim `sim/tb_home_navigation_card.sv`：640×480 全帧对比基线，第一张卡片外差异像素为 0；蓝色底形、箭头、竖线及三组图文均非空，通过。
- TD 6.2 完成综合、布局布线和 bitgen。资源：LUT 14530/19600（74.13%，比基线 +239）、寄存器 7263/19600、BRAM9K 37/64（不变）、DSP 5/29（不变）、PLL 3/4（不变）。
- 视频时钟域 setup 裕量 +4.455 ns，SD 卡时钟域 +0.150 ns；全局 setup WNS −5.699 ns，和基线相同，来自原有 SDRAM 路径；hold 无违例。

尚未上板验证。烧录新 bit 后请重点检查图片 1 导航图标颜色、字形与对齐，及图片 2～4 和音频行为。
