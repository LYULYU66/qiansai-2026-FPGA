# 统一时钟 20261002

上电/复位统一从09:00:00计时。使用现有25MHz视频时钟分频，24小时回绕，切页不重置；所有页面使用同一VS帧锁存时间。

第三页右侧白色小时/分钟上下排列，无底框；第一页替换固定09:00，第二及第四页使用紧凑HH:MM。首页日期仍为演示用10月1日周一，不含日历计数。断电/复位恢复默认值，不是带电池RTC，也不自动获取现实时间。

数字沿用Noto Sans SC Medium，16×24原生2-bit字模，压缩为512×16单块BRAM9K；无新增DSP或PLL，无新增RGB流水延迟。

布局布线seed7：LUT17643/19600（90.02%），寄存器8707，BRAM9K47、BRAM32K7、DSP6、PLL3。相对上一版增加90 LUT、85寄存器、1 BRAM9K。seed19视频建立裕量为负，选择seed7（视频建立+0.313ns）。全局建立−5.699ns、保持−1.263ns，SD100MHz建立−3.011ns；时序尚未收敛，未上板验证。

验证：42项原有ModelSim回归与4项独立资产检查重新通过；新增24小时计时、四页像素、首页固定时间移除、实际第三页组合预览4项通过。另16项未改组件测试继承上一版日志，不声称本轮重跑。全部80个源码/IP/约束构建哈希校验通过；字模3840像素独立生成校验通过。

预览来自真实RTL，音量/频带使用受控测试数据，不是整首音乐回放。TF文件、PCM、引脚、约束、PLL、HDMI、SDRAM和FIFO深度未改。

新bit：best_result/lab_ex5_i2s_v1.0_unified_clock_20261002.bit
SHA256：C0C548B319A5F2A32BF866E76CC1332233B95FA15BE4D5CEF97034DBD71C68DF
回退：best_result/lab_ex5_i2s_v1.0_page3_relax_fast_audio_20261002.bit
备份：backup_before_unified_clock_20261002/

复现：sim/run_unified_clock_20261002.ps1；sim/run_resource_all_20261002.ps1；sim/build_lut_opt_20261002.ps1 -SynthesisRun syn_clock_packed_20261002 -PhysicalRun phy_clock_packed_s7_20261002；sim/audit_unified_clock_20261002.py 7。

