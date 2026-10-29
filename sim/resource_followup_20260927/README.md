# 第二轮资源优化验证

基线为 2026-09-27 的 SD 读卡时序优化版，最终交付结果见 `best_result` 中日期为 20260928 的说明。

## RTL 变更

- `audio_visualizer_overlay.v`：已有的消隐期顺序处理器改用快照移位、相邻点寄存，减少宽多路选择器；动态写切片改为固定写通道；平滑步长选择后共用一次加法。保持输入快照、端点处理、限幅、显示更新顺序不变。
- `audio_waveform_analyzer.v`：VU 峰值仅保存后续真正使用的高 8 位；先求最大值后截位与先截位后求最大值等价。波形内部保留原采样精度。固定通道写入。
- `audio_spectrum_analyzer.v`：固定通道写入，不改频段、计算精度或显示增益。
- `video_transition_effects.v`：640 像素行缓存按 512 像素头部和 128 像素尾部拆分，两条乒乓行共享尾部 BRAM，每个图像由 4 块改为 3 块 BRAM9K。两个图像合计由 8 块降为 6 块。维持原 RGB666 精度及读延时；宽度超过 768 时保留原结构。
- `SD/bmp_read.v`：FAT32 簇号无效范围使用位归约判断；MBR 分区地址的非零判断按接收字节登记、再合并。保留之前的 CALC/ADDR 两拍簇地址计算，不增加读卡状态或改变外部握手周期。

字体、首页内容、字幕大小、报警策略、转场类型、音频格式、音量等级、串口命令均未改变。

## ModelSim

在工程根目录运行：

```powershell
powershell -ExecutionPolicy Bypass -File sim/run_resource_regression.ps1
```

27 项测试覆盖原功能及等价性。测试输出位于 `sim/resource_global_20260927`。

- `tb_visualizer_resource_equivalence`：1,228,800 像素逐位对照，覆盖波形、频谱、VU、音量、报警和旁路。
- `tb_visualizer_sequencer_equivalence`：12,377 周期，512 帧随机数据，所有 4 位音量输入、限幅、帧中输入变化、新帧打断以及复位。
- `tb_waveform_resource_equivalence`：120,000 周期、107 次发布，包含静音、直流、满幅、随机样本、间歇有效和使能/复位。
- `tb_transition_resource_equivalence`：675,840 像素，四种转场、全部 32 个步骤、1 至 4 拍短行消隐。
- `tb_bmp_resource_equivalence`：1 至 128 扇区/簇的 8 种配置；无 MBR 与各字节非零的 MBR；碎片目录/图片/PCM、循环播放、FIFO 背压；每拍比较全部外部输出；1,024 个 FAT 簇号边界/高位屏蔽值及 10,000 个随机值。

行为仿真不是上板验证，也不代表时序完全收敛。

## 构建与保持时间修复

工具为 Tang Dynasty 6.2.168116。依次在 `src/td_project/lab_ex5_i2s_v1.0_Runs/syn_1` 和 `phy_1` 下运行：

```powershell
& 'C:\Anlogic\TD_6.2.1_Engineer_6.2.168.116\bin\td_commands_prompt.exe' lab_ex5_i2s_v1.0.tcl
```

`phy_1` 的 Tcl 可编辑区在 route 后执行 `fix_hold`、`fix_hold -buffer_opt`、`fix_hold`，先清除小违例，再由工具补缓冲修复较大违例。未修改时钟、PLL、引脚、SDRAM RTL 或时序例外。

如果 GUI 重新生成了构建脚本，要核对它是否保留上述可编辑区及最终说明中记录的布局 seed。`repair_routed_hold.tcl` 可在 `phy_1` 下对已完成的当前 routed DB 重做相同修复并重新生成报告和 bit。必须核对 `lab_ex5_i2s_v1.0_pr.timing`，不能只看修复前自动导出的 `final_timing.rpt`。

旧 bit 保留。全局 SDRAM 外部路径原有的负裕量不可用 false path 隐藏；最终说明应明确是否仍存在。
