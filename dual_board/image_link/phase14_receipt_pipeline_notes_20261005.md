# 第十四阶段：确认包时序切分与首次正式媒体 SRAM 联调包

新增 `rtl/hw_round6_20261005/audio_receipt_hw.v`，其余候选及单板、已验证网口诊断保持冻结。本轮把确认包 CRC/长度/头部资格判断放在最后一个有效 CRC 字节，下一拍仍在原位置输出 receipt_valid。每个有效字节重新计算资格，超长包会清掉资格，截断包不会置位，新包不会沿用旧包结果；原 AAK2/AAK3 格式、错误包过滤、控制字段范围和输出时钟周期都不变。发包模块及实际播放 Gray 计数模块不变。

ModelSim 与原版每时钟核对全部确认输出，AAK2/AAK3 各 1200 包通过；另重跑实际 B 应用顶层与完整首页图像源，以及七项实际播放/分析/音频守卫回归。完整 40 项回归是上一轮 R5 的记录，本轮没有冒充再次执行全部 40 项。

R6 B 完整布局布线 LUT=11726（59.83%）、寄存器=7763，相比 R5 减少 61 LUT，增加 20 寄存器；BRAM9K/32K=28/9，DSP/PLL=3/3 不变。global setup/recovery −3.251 ns（R5 为 −3.706），hold/removal −1.540 ns 不变。原确认解析路径不再位于所报告的 UDP 同域最差十条 setup 列表，但新 UDP 同域最差转到图片 source_ready→首页索引使能，−1.627 ns，**比 R5 的 −0.784 ns 更差**；SD 同域 −1.037 ns。不能说 UDP 已闭合或所有时序都改善。本轮不新增约束例外、不调整 PLL/SDRAM/HDMI IP；精确端点 CDC/复位与 IO 时序审计尚待继续。

为了尽早验证用户已有两板和网线，另以独立项目名生成 **SRAM 工程测试版**，不是稳定发布：A 复用 R3（种子3），B 用 R6（种子1），源码没有删功能。每个测试项目独立重做 route、area、timing 和 bitgen，旧报告不覆盖。测试包的完整物理报告与 R3/R6 一致；两板仍有负裕量，因此不固化、不声称硬件可靠。此前“正式候选脚本不自动 bitgen”的规则保持，本次独立 `build_sram_test.tcl` 明确标记例外为用户请求的可回退硬件联调。

用户报告过网口诊断灯正常，但正式播放器此前没有实板媒体证据。现在用 `board_test_20261005/` 中成对文件按“静止第一页→卡中音乐→四页切换→自动轮播→预警→串口→重连”分层验收；先做图片与声音，不需要等下一轮资源优化。卡放 B、HDMI 接 A、网线接已验证 PHY1；A 默认手动停第一页，K1复位、K2下一页、K3轮播。详细步骤、限制和回退见该目录 README。

此包完整物理资源为 A LUT=14280（72.86%）、BRAM9K/32K=50/7、DSP/PLL=3/4；B LUT=11726（59.83%）、28/9、3/3。A 全局setup/recovery −5.699 ns、hold/removal −0.052 ns，B −3.251/−1.540 ns。A 的 SDRAM 位置与局部时钟布线警告和 R3 相同，未掩盖；外部 IO 延迟尚未完成规格级签核。没有功耗测量，不声称降低了功耗或已通过长时间板测。

重现：运行 `sim/prepare_player_round6.js` 生成独立候选，依次 `sim/run_player_round6.ps1 -Suite Guard`、`-Suite Boundary`、`-Suite Audio`；ModelSim 串行。候选物理检查用 `prj/media_b/build_round6_b.tcl`，无自动 bitgen。临时硬件包先 `sim/prepare_media_sram_test.js`，再分别在 A/B 项目目录运行 `build_sram_test.tcl`，最后 `sim/package_media_sram_test.js` 核验并复制配对文件；不执行实际烧录。旧基线和 R4/R5 哈希保护失配、任何仿真失败、route/bitgen 未完成都会阻止打包。
