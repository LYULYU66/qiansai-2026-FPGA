# 统一时钟版上电花屏/音频卡顿修复候选

用户上板结论：unified_clock_20261002版上电立即花屏、音乐卡顿；回退page3_relax_fast_audio版正常。故障范围收敛到新增时钟版及重新布局布线结果，但未通过板上信号测量证明唯一根因。

## 改动

1. bmp_read.v：生产配置PIPELINED_CLUSTER_ADDR=1，在既有5-bit状态机新增共享ST_CLUSTER_SHIFT=31，将簇号变长移位与32-bit扇区地址相加分拍。六种CALC流程共用；每次地址计算增加一个100MHz周期，不改变扇区内容和顺序。
2. 新增等待周期保持bmp_len_cnt及bmp_byte_idx，确保跨簇时BGR字节不会错位。中止/复位仍优先于状态计算。
3. bmp_bilinear_stream.v：每目标行缓存两个源行邻居，Y_PREP在坐标进位后更新；identity_height在装载开始锁存，避免宽比较/加法/选择器串到逐像素状态使能。增加每目标行一个周期，不减少Q8插值精度。
4. sd_card_bmp.v转发参数，top只在生产实例开启。参数默认0供历史周期等价测试；真实FAT/图片/PCM专项测试使用1。旧播放管理测试的bmp_read桩仅补参数声明，行为未改。

时钟计数/字模/显示、字体、图标、四页功能、歌词、星点、转场、告警、串口保持不变。PLL、引脚、约束、SDRAM仲裁、FIFO深度、TF文件和PCM均未改。

## 验证

42项原有ModelSim测试重新通过，4项独立字模/像素检查通过；12条专项测试记录通过，共54条新日志：3条时钟、4条PCM/地址管线、5条缩放。普通和厂商BRAM模型各42种小尺寸/中止恢复场景；640×480、1280×720、1280×960、1920×1080逐像素对照。1800组随机地址覆盖六种流程、八种簇尺寸、无效簇、32-bit回绕、BMP字节位置保持、中止复位。正常及慢速TF模型各连续消费800个立体声帧，无FIFO越界或断流；均在图片缓存结束之前开始PCM。

波形：sim/fast_audio_20261002/cluster_pipeline.vcd，记录state、cluster_index、cluster_offset_q、sd_sec_read_addr、sd_sec_read、bmp_len_cnt、bmp_byte_idx。不是板上采样，不将行为仿真当作时序/硬件通过。

所有80个源码/IP/约束构建指纹校验通过，相对故障时钟版仅4个生产源码变化；稳定旧bit、故障bit、MUSIC.PCM哈希保持原样。

## 布局布线与限制

选择seed7：LUT17678/19600（90.19%），寄存器8771，BRAM9K47、BRAM32K7、DSP6、PLL3。相对故障时钟版增加35LUT、64寄存器，BRAM/DSP/PLL不变。
视频建立+2.604ns、保持+0.004ns（故障版+0.313/−0.033）；SD读取建立−1.771ns（故障版−3.011，正常旧版−1.862）。全局建立−5.699ns、保持−1.203ns。50MHz保持−1.170ns，HDMI125MHz建立+0.195ns。仍未完全收敛，不能保证所有温度、电压及上电条件下可靠。
seed19视频仅+0.328ns，虽SD建立−1.635ns，综合取舍选择seed7。此前只拆簇地址的中间试验版本有更差的缩放路径（seed7 −9.212ns），未发布使用。源代码修改后已重新完整综合及布局布线，不使用中间DB生成交付bit。

## 文件与复测

新bit：best_result/lab_ex5_i2s_v1.0_clock_startup_fix_20261002.bit
SHA256：B380AAB5FD7DF34706EE5C170E2EF9759CFDE3F2EDF64E028475A5D3EC9D6AF3
字节数：679676
稳定回退：best_result/lab_ex5_i2s_v1.0_page3_relax_fast_audio_20261002.bit
回退SHA256：8CA6F20E0BF3E82982B140C7A736CF0623F99370CABAF1BD89ED7D3B978CB882
备份：backup_before_clock_startup_fix_20261002/。

这是需要上板复测的修复候选，不声称故障已在硬件消失。烧录后断电重启，先检查首图/音乐持续20秒，再切四页、测试串口/报警，并观察时间到09:01。若依然花屏/卡顿，回退稳定bit并反馈出现时间与串口是否响应。TF卡无需替换文件。

复现专项：sim/run_clock_startup_fix_20261002.ps1；加-FullRegression运行原42项。构建：sim/build_lut_opt_20261002.ps1 -SynthesisRun syn_clockfix_rows_20261002 -PhysicalRun phy_clockfix_rows_s7_20261002；审计：sim/audit_clock_startup_fix_20261002.py 7。

