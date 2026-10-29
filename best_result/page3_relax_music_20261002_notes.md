# 第三页音乐休闲光点版（2026-10-02）

第三页只保留左上角 BRI / CON / VOL / RES 参数，隐藏滚动字幕、双声道音量条、频谱和波形。背景仍读取TF第三张BMP，叠加八个暖黄色柔光点，随音乐呼吸、缓慢漂移；静音时保留很淡的环境光。没有时间或新增框。其他页面、音频、歌词、串口、BMP双线性缩小和转场保持，危险仍直接进入第四页，原安全边框保留。

## 资源与时序

完整布局布线：LUT 17629/19600（89.94%）、寄存器8660、BRAM9K 46、BRAM32K 7、DSP 6、PLL 3。相比上一版双线性缩小bit，LUT增加684、寄存器增加140，BRAM/DSP/PLL不增加。综合LUT增加718，最终资源以area报告为准。

复用现有调音量后的左右VU和八个频谱频段，不新增分析器。八点LUT RAM与行缓存共享更新/绘制逻辑，帧消隐内24拍更新与8拍行准备。Q4位置/能量平滑、快起慢落、双层光晕，RGB通路不增加延迟。

选用布局种子7，视频建立裕量比种子19更宽，但不是所有指标均改善。**未时序闭合，未上板验证。** 全局建立最差−5.699 ns、保持最差−1.330 ns；视频25 MHz建立+2.577 ns、保持−0.020 ns；SD100 MHz建立−2.450 ns、保持−0.075 ns。SD建立比上一版−0.757 ns变差，全局建立TNS也变差，仿真不能保证板上稳定。未修改SDRAM、FIFO深度、PLL、HDMI PHY、引脚或约束。

## 验证证据

原42项ModelSim仿真和4项独立字库/像素检查新跑通过；新增4项仿真通过：页面选择3200组合、柔光921600像素精确比较及600帧运动边界、48 kHz PCM经原VU/频谱分析器的响应、实际RTL合成614400预览像素。新测试零错误/零警告。此前9项BMP缩小测试相关源码未改，复核原日志哈希和PASS证据，未宣称本次重跑。

78份HDL/IP/约束在构建前后哈希一致；前一版77份中除顶层外76份未改。旧bit和MUSIC.PCM哈希未变。逐文件、逐日志记录见manifest/regression JSON。

预览由实际RTL像素输出，背景为已生成夜间草坡640×480 BMP。音乐预览是可控VU/频谱输入，不是整首歌曲重放；实际音频联动另由48 kHz双声道测试音验证。

## 使用和回退

新版：`lab_ex5_i2s_v1.0_page3_relax_music_20261002.bit`，SHA256 `9528B15C37098EB310299F49066550CA76B5176B15DCDF5E1472638F10FF0B6B`。

未烧板或改TF卡。切到第三页即可观察光点。若希望使用草坡背景，自行以 `output/imagegen/night_hills_20261002/night_hills_640x480.bmp` 或1280×960版替换TF第三张图片，不增加第五张图；音频无需重新复制。

异常时回退 `lab_ex5_i2s_v1.0_bmp_bilinear_downscale_20261002.bit`。源码备份：`backup_before_relax_20261002/`；此前日志：`sim/relax_20261002/pre_run_logs/`。

从工程根目录复现：

```powershell
& sim/run_relax_release_20261002.ps1
& sim/build_lut_opt_20261002.ps1 -SynthesisRun syn_relax_20261002 -PhysicalRun phy_relax_s7_20261002
& 'C:/Users/28492/.cache/codex-runtimes/codex-primary-runtime/dependencies/python/python.exe' -X utf8 -B sim/audit_relax_20261002.py 7
```

单独光点测试：`sim/run_relax_20261002.ps1`，场景预览加 `-PreviewOnly`。
