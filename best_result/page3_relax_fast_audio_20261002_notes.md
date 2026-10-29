# 16星点 / TF音乐快速启动版（2026-10-02）

## 更改

第三页星点由8个增加到16个，八个运动锚点各带一个较淡的镜像星点，复用行缓存和同一套柔光绘制逻辑。横向轨迹范围约为上一版2倍（约32像素），纵向约4倍（约64像素）；仍使用Q4平滑位置、能量快起慢落、暖色柔光，随音乐变化。只保留第三页左上角BRI/CON/VOL/RES，其他页和安全预警保持。

顶层移除启动音阶发生器，直接连接PCM序列器的连续I2S时钟和数据；准备期间发送零样本，不再播放测试音。FAST_AUDIO_START=1：文件扫描结束即可启动PCM服务，不等四张图片缓存完成。BMP读取在扇区边界让出SD读取器补充PCM，FIFO补足后恢复BMP地址、FAT入口偏移和像素字节组装。音频文件指针跨图片装载保持，不从头重播。保留原512字FIFO、256字补充门槛、128帧播放预缓冲，不改PLL/SDRAM/FIFO深度/引脚/约束。

TF卡初始化、FAT目录扫描、PCM预缓冲仍需时间；本版不能实现上电零等待。歌曲本身的前奏或静音不剪掉。不改TF卡文件或歌曲；未烧板。

## 资源与时序

选择布局种子7，完整布局布线LUT 17553/19600（89.56%）、寄存器8622、BRAM9K 46、BRAM32K 7、DSP 6、PLL 3。比上一版8光点bit少76个LUT、38个寄存器，BRAM/DSP/PLL不变；综合LUT 17079。

**仍未时序闭合，未上板验证。** 全局建立最差−5.699 ns，保持−1.301 ns；视频建立+2.050 ns、保持−0.020 ns；SD建立−1.862 ns、保持−0.004 ns。相比上一版SD建立−2.450 ns有所改善，但仍为负。种子19的视频建立仅+0.357 ns、SD建立−2.208 ns，选种子7不代表全部时序指标均最佳。

## 验证与预览说明

新音频联动测试使用实际FAT/BMP/PCM解析器、缩小器和缓存控制器，只模拟SD扇区传输与音频FIFO消费。四张BMP和音乐均使用不连续簇，检查逐像素双线性结果、原始分辨率提交、上下行方向、手动/自动切换、PCM字节序和循环连续性。

正常25 MHz SPI等效字节周期测试：PCM开始时图片提交数为0，连续消费800双声道帧无断流/溢出。放慢到四倍字节周期并增加4096拍命令等待：连续消费4739帧通过。启动静音测试通过48个静音双声道帧，保留128帧门槛后正确输出TF格式样本，不接音阶源。

光点921600像素精确检查、600帧平滑边界、真实48 kHz PCM经原VU/Goertzel响应测试通过。场景预览是实际RTL的921600个合成像素，包含静音与两个音乐相位；音乐输入为可控VU/频谱夹具，不是整首歌曲重放。原有42项回归、5项BMP集成回归及逐文件哈希审核的最终结果见交付regression/manifest JSON。未改缩小器的4项独立测试复核旧日志哈希，不宣称本次重跑。

## 交付 / 回退

bit：`lab_ex5_i2s_v1.0_page3_relax_fast_audio_20261002.bit`

SHA256：`8CA6F20E0BF3E82982B140C7A736CF0623F99370CABAF1BD89ED7D3B978CB882`

TF图片/音乐不必重新复制。烧录后检查上电无音阶、歌曲起播、四张图切换、第三页运动、歌词、串口与四方向报警。若异常，回退 `lab_ex5_i2s_v1.0_page3_relax_music_20261002.bit`。改动前源码备份在 `backup_before_relax_fast_audio_20261002/`。

从工程根目录复现：

```powershell
& sim/run_resource_all_20261002.ps1
& sim/run_relax_20261002.ps1
& sim/run_relax_20261002.ps1 -PreviewOnly
& sim/run_bmp_downscale_20261002.ps1 -IntegrationOnly
& sim/run_fast_audio_20261002.ps1
& 'C:/intelFPGA/18.1/modelsim_ase/win32aloem/vsim.exe' -c -l sim/fast_audio_20261002/slow.log -do 'vsim -c -lib sim/fast_audio_20261002/work -gBYTE_PERIOD=128 -gCOMMAND_DELAY=4096 tb_fast_audio_cache; run -all; quit -f'
& sim/build_lut_opt_20261002.ps1 -SynthesisRun syn_relax_fast_20261002 -PhysicalRun phy_relax_fast_s7_20261002
& 'C:/Users/28492/.cache/codex-runtimes/codex-primary-runtime/dependencies/python/python.exe' -X utf8 -B sim/audit_relax_fast_20261002.py 7
```
