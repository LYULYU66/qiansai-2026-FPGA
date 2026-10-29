# 首页圆形导航及音乐封面版（2026-09-29）

基于 2026-09-28 的 `resource_opt_font_bram` 工程及随后蓝色导航卡片修改。原有两个 bit 均保留。

## 交付

- `lab_ex5_i2s_v1.0_home_round_nav_album_20260929.bit`
- SHA256：`BDDAF4561196C098838C2E714FA494C6285A50285AA1E76993D746AF5F7EAAE3`
- `home_round_nav_album_20260929_phy.area`
- `home_round_nav_album_20260929_pr.timing`

## 改动

仅首页图片 1 的前两张状态卡：

1. 第一张卡的搜索目的地图标改成蓝色圆形，中心保留浅色导航箭头。“回家”“公司”及分隔线不变。
2. 第二张卡按“左侧圆形封面、右上歌名、下方上一首/播放/下一首三枚图标”布局，歌名为“告白气球”。右下保留一个小蓝色音乐标识。三个控制图标目前是**画面元素**，没有新增按键控制逻辑。
3. 用户提供的封面原图保存在 `assets/jay_chou_cover_source.png`；`sim/generate_album_cover_rom.py` 生成 40×40、14 色封面及蓝色圆环，一份 4-bit 索引 ROM 存储，HDL 为 `video_album_cover_rom.v`。圆形裁剪在离线生成时完成，不在 FPGA 内计算圆半径。预览图为 `assets/album_cover_round40_preview.png`。

## 验证与资源

- ModelSim `tb_home_navigation_card.sv`：640×480 全帧比较基线；改动只在前两卡，卡外差异 0；圆形边界、封面、歌名、三个按钮均通过。
- ModelSim `tb_video_home_overlay.v`、`tb_bmp_pcm_stream.v`：通过。
- TD 6.2 综合、布线、bitgen 完成。布局种子 8；LUT 14779/19600（75.40%），寄存器 7256/19600，BRAM9K 38/64（封面比上一版 +1），DSP 5/29，PLL 3/4。
- 视频时钟域 setup +2.510 ns，SD 卡时钟域 setup +0.119 ns；hold 无违例。全局 setup WNS −5.699 ns，与旧版相同，为原有 SDRAM 路径。

未进行上板验证。烧录后检查圆形封面可读性、音乐卡按钮位置，以及音频、图片轮换行为。
