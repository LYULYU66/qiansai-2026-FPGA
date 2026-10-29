# 首页四卡与写实胎压小车版（2026-09-30）

## 新烧录文件

`lab_ex5_i2s_v1.0_home_4cards_tpms_car_20260930.bit`

- 大小：644756 字节。
- SHA256：`0915F6532F8EDA5518B4FA99C374111F5F18F46F3042626E2388CFF87EAF650C`。
- 完整综合目录：`src/td_project/resopt_Runs/syn`；本版布局布线目录：`src/td_project/resopt_Runs/phy_home_tpms_car_20260930`；place seed 19，沿用原约束和原生 hold 修复流程。
- 上一版 `lab_ex5_i2s_v1.0_crisp_toolbar_qq_20260930.bit` 保留，未覆盖。

## 页面改动

首页下方横排四个白色圆角卡片：导航、音乐、应用、胎压。共同 y=310..409，间隔 12 像素，卡片分别宽 144、172、116、140 像素。四个应用保留 40×40 原生尺寸，改为 2×2 布局，不增加应用 ROM 容量。底部白色直角导航栏仍为 y=440..479，高 40 像素。顶部参数、日期时间、太阳和其他三个页面保留。

胎压卡片沿用参考图的固定演示值，不是实时传感器数据：

| 位置 | 温度 | 胎压 |
| --- | --- | --- |
| 左前 | 10℃ | 261kPa |
| 右前 | 11℃ | 264kPa |
| 左后 | 15℃ | 266kPa |
| 右后 | 10℃ | 261kPa |

小车由 imagegen 技能的内置 image_gen 工具生成银白色正俯视素材，保留车身、深色玻璃、四个轮胎和红色尾灯层次，再离线等比例缩小并生成 15 色加透明索引图。实际显示为 32×64，位置 x=540..571、y=327..390；不会把 640×480 输出宣称为高清分辨率。小车使用 2048×4 同步 ROM，新增 1 块 BRAM9K。胎压十个 8×12 字符成对放入现有首页字模的五个空闲条目，不新增字体 BRAM、DSP 或帧缓存。全部字体仍来自同一 Noto Sans SC Medium 字体源。

小车素材保存位置和完整最终提示词见 [素材说明](C:/FPGA2026/HX4S20_Contest_2026/7_lab_ex_2026_nosoft/qiansai/lab_ex4_tf/assets/tpms_car_20260930/README.md)。原图为 [source.png](C:/FPGA2026/HX4S20_Contest_2026/7_lab_ex_2026_nosoft/qiansai/lab_ex4_tf/assets/tpms_car_20260930/source.png)，实际索引图为 [car_indexed32x64.png](C:/FPGA2026/HX4S20_Contest_2026/7_lab_ex_2026_nosoft/qiansai/lab_ex4_tf/assets/tpms_car_20260930/car_indexed32x64.png)。原始透明图保留；边缘白底合成、缩放和索引色转换均在离线素材处理阶段完成，不在 FPGA 在线执行。

同时完成上一条要求：前后除霜图标内部改为三条连续平行的风曲线，去掉类似问号的点/箭头形状。底栏 ROM 仍为 1008/1024 个 16-bit 字，仅改两个图标的数据，没有额外 BRAM。音乐仍显示正在播放的暂停双竖线控制符号。

小车、字模、图标全部固化在 bit 中，无需复制到 TF 卡。TF 图片与 PCM 音乐、存储读写逻辑、PLL、HDMI PHY、四方向预警与报警音频没有修改；未进行闪烁排查或板上烧录。

## 最终布局后资源

| 项目 | 本版 | 上一版 |
| --- | --- | --- |
| LUT | 14867 / 19600（75.85%） | 14637（74.68%） |
| 寄存器 | 7330 / 19600（37.40%） | 7313（37.31%） |
| BRAM9K | 46 / 64（71.88%） | 45 / 64 |
| DSP | 5 / 29 | 5 / 29 |
| PLL | 3 / 4 | 3 / 4 |

四卡布局、胎压显示、小车与风曲线修改合计增加 230 LUT、17 寄存器、1 BRAM9K；包括工具布局及 hold 修复带来的资源变化。小车 ROM 在综合层级报告中确认占 1 块 BRAM9K，未摊成大量 LUT。

## 验证与时序限制

- 本次重新运行 Intel ModelSim 首页 6 项及预警/转场/报警音频 9 项回归，全部通过。
- 新增小车的三整帧同步对齐检查：1/2/3 拍行消隐、叠加开关透传、4096 个小车有效区域输出像素；同时检查 51200 个底栏像素。
- 独立检查小车 2048×4 ROM、四类字模、底栏 1008 个字、封面与音乐图标 2000 个字、42696 个实际 ModelSim 输出像素；应用图标另检查 8000 个实际输出像素。
- 与上一版已交付的实际 HDL 渲染逐像素比较：首页新四卡区域和两个风曲线图标之外的像素完全一致。
- 预警四方向 32 像素文字独立检查 512 个 ROM 字与 20480 个输出像素；原有危险直接切页、前后左右报警、背景边框、报警时音乐减弱均通过相关回归。
- 全帧和局部 PNG 来自实际 HDL 仿真，参考底图为工作区 CAR01.BMP，不是另画的界面设计稿。

最终时序：视频 +4.847 ns；读卡 -0.252 ns；HDMI 125 MHz +0.632 ns；SDRAM -5.699 ns；移相输出 -1.990 ns；全局 setup WNS -5.699 ns、TNS -232.521 ns。Hold WNS +0.022 ns，无保持违例。

仍有未收敛的 setup 路径，读卡负裕量比上一版 -0.007 ns 更大；不得据此宣称全板时序通过或上板稳定性已验证。本次只完成所请求的 UI 改动和现有流程验证，未调整时钟、约束或存储控制逻辑。仿真通过不等于实板验证通过。

复现：`sim/run_modelsim_home_light.ps1`、`sim/run_modelsim_warning_4dir.ps1`；小车 ROM 补丁生成：`sim/generate_tpms_assets.py`；字模补丁生成：`sim/generate_crisp_ui_fonts.py`，使用 Python `-X utf8`。补丁生成脚本只输出 apply_patch 内容，源码更改经 apply_patch 应用。

交付文件：本版 `.bit`、`.area`、`.timing`；`home_4cards_tpms_car_20260930_preview.png`、`home_4cards_tpms_car_20260930_cards_preview.png`、`home_4cards_tpms_car_20260930_tpms_zoom.png`；`home_4cards_tpms_car_assets_20260930.zip` 包含更新后的底栏图标和小车素材。
