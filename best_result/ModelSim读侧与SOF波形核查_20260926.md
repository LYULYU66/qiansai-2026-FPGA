# ModelSim 读侧与 SOF 波形核查（2026-09-26）

## 上板证据及本轮范围

用户报告：原图 TEST 0 仍闪；两次回复均为 `T=0 A=0 B=0 H=0 C=0 V=1`。原始 RGB 帧 CRC 没有捕获帧间变化；不能以此排除固定错位、CRC 碰撞或 CRC 监测点之后的问题。

按用户要求，本轮重点检查 SOF 和显示读侧对齐。只新增/修改 `sim/` 下的测试与说明，没有改上板 RTL、SDRAM 仲裁、FIFO 深度、PLL、HDMI PHY，也没有生成或替换 bit。此前 SOF 候选版本上板没有改善，不能把仿真边界修复当成已修复闪点。

## 实际使用的仿真器

本轮有效仿真使用 `C:/intelFPGA/18.1/modelsim_ase/win32aloem/vsim.exe`，ModelSim Intel FPGA Starter 10.5b，保存原生 WLF。

ModelSim SE 2020.4 最初因为启动进程未继承现有许可证环境而无法启动；仅给子进程加载系统已有路径后可启动及编译，但加载 Verilog 设计仍报告 `Failure to obtain a Verilog simulation license`、`qhsimvl/msimhdlsim` 功能不可用。因此 SE 的编译不算仿真通过。没有修改许可证文件、系统环境或软件安装。

## 测试设计

实际工程模块：`video_timing_data/color_bar → frame_fifo_read + rfifo_32_32_512 → video_delay → 静止转场路径 → video_image_adjust → video_rgb_to_axis_640x480`。

640×480 有效区，800×525 总光栅；25 MHz 读时钟、100 MHz 写时钟。使用工程原始 FIFO 实现及其 `SHOW_AHEAD_EN=0 / OUTREG_EN=NOREG` 参数。SDRAM 用有序定延迟响应模型替代，地址生成的暗色测试像素逐像素不同，独立参考计数器检查完整帧序列，而非只检查 SOF 次数。

- 正常测试：仿真时钟相位偏置 0/1/3/5/9 ns，响应延迟组合 1/8/10 个写时钟，每组 2 个完整有效帧；每 12 μs 阻止新突发 3.1 μs。
- 连续静止测试：6 个有效帧，阻止新突发窗口加大到 6.5 μs。仅约 0.1 秒有效画面，不等于板上数分钟长时间测试。
- 故障注入：读使能提前一拍、推后一拍、dout 加一拍、禁止首行预取。只在 testbench 注入，不改实际 FIFO 参数或延迟链。
- 记录 DE、read_en、rdusedw、empty、dout、FIFO valid、输出 DE/RGB、AXIS USER/VALID/LAST/DATA。

启动时光栅源的第二级延迟寄存器存在未初始化短暂 X；检查器仅跳过复位释放后前 64 个填充时钟，远早于任何有效像素。初始未发起首个读请求的不可见启动帧不用于 FIFO 像素序列评分，完整 SOF/VALID 检查仍保留。所有正式有效帧均逐像素验证。

## ModelSim 读侧整链路最终结果（全部完成）

下列 PASS 对故障注入项表示检查器成功发现故障，不表示故障画面正确。每一项均有同名 WLF、CSV 和 `_modelsim.log`，目录为 `sim/alignment_20260926/`。

| 测试名 | 相位偏置 / 响应延迟 | 有效帧 | 像素序列错误 | 读空次数 | 结果 |
| --- | --- | --- | --- | --- | --- |
| phase0_lat1 | 0 ns / 1 拍 | 2 | 0 | 0 | PASS |
| phase1_lat8 | 1 ns / 8 拍 | 2 | 0 | 0 | PASS |
| phase3_lat8 | 3 ns / 8 拍 | 2 | 0 | 0 | PASS |
| phase5_lat10 | 5 ns / 10 拍 | 2 | 0 | 0 | PASS |
| phase9_lat10 | 9 ns / 10 拍 | 2 | 0 | 0 | PASS |
| static_6frames | 3 ns / 8 拍，暂停 6.5 μs | 6 | 0 | 0 | PASS |
| early_read | 读使能提前 1 拍 | 1 | 306,720 | 0 | 检出错位 |
| late_read | 读使能推后 1 拍 | 1 | 307,199 | 0 | 检出错位 |
| late_dout | FIFO 数据多延迟 1 拍 | 1 | 307,199 | 0 | 检出错位 |
| starvation | 禁止首行预取 | 1 | 307,199 | 125 | 检出空读与错位 |

正常供数共 16 帧、4,915,200 个有效像素；原始 RGB 与 AXIS 输出的像素序列均正确，SOF/VALID/LAST 与数据逐拍检查均通过。正常供数所有行首最小 `rdusedw=256`；有效区最小余量为 1，发生在帧尾排空，不是空读。断供测试行首 `rdusedw=0, empty=1`。

ModelSim 报告的 3 条 FIFO RAM 端口警告对应未使用的 `doa` 与 `dib`，无编译错误，未修改厂家模型以隐藏警告。首次试跑在复位释放后管线 X 值尚未消失时误报 1 次，已修正检查器只跳过前 64 个启动时钟；表中是修正后完整重跑结果，最后一组于 2026-09-26 11:58:39 完成。

原默认 bit 的 SHA256 仍为 `F1335B4DC9069E76B104A855B21FDD4A7294D7A6A07AC4E8D8EE9EDCF9CF8E1B`；CRC 诊断 bit 仍为 `962D37B6C08A591467238CDAEA360C0A4F3C0C288F758C1477045A3E658A8FCC`。本轮无新 bit。

## SOF 扫描（已完成）

18 组：VS 边沿提前 8～0 拍到达，各覆盖两个边沿方向。

- 提前 1～8 拍的 16 组：现有 SOF 判定通过。
- 恰好同拍的 2 组：首行首像素漏 SOF，下一行首像素误出 SOF；合计 4 次判定不符。
- 仿真专用候选判定将 `pending || 当前 VS 边沿` 与 DE 首像素结合，两组边界及其余 16 组均通过。
- 正常光栅 VS 位于垂直消隐，不能将这个人为边界自动认定为当前板上闪点根因。
- 未修改的 `video_source_test` 连续 2 帧、614,400 像素，SOF/TLAST/RGB 通过。

证据：`sim/alignment_20260926/sof_sweep.wlf`、`sof_sweep_modelsim.log`、`source_sof.wlf`、`source_sof_modelsim.log`。

## 已直接回读的 WLF 首像素证据

ModelSim 回读 `phase0_lat1.wlf`，检查日志为 `wlf_head_inspection.log`。下表均为时钟沿后 1 ns 的稳定值；rdusedw 是读操作完成后的余量，第一读请求沿前为 256。

| 时间 ns | FIFO dout | 输出 DE | 原始 RGB | AXIS VALID | AXIS USER | AXIS RGB |
| --- | --- | --- | --- | --- | --- | --- |
| 18215621 | 00000000 | 0 | 000000 | 0 | 0 | 000000 |
| 18215661 | 04000000 | 1 | 000000（首像素） | 0 | 0 | 000000 |
| 18215701 | 08000000 | 1 | 040000 | 0 | 0 | 000000 |
| 18215741 | 0C000000 | 1 | 080000 | 0 | 0 | 000000 |
| 18215781 | 10000000 | 1 | 0C0000 | 1 | 1 | 000000（首像素） |

这与现有 `de_d[18] → FIFO 读出 → de_d[19] 采样 → de_d[20] 输出` 一致。异步写指针同步影响空标志可见时间，不会在该行为模型中让已接受的非空读取随机多出一拍。

## 复跑与查看

在工程根目录运行 `powershell -NoProfile -File sim/run_modelsim_read_axis_stress.ps1`，默认使用已验证可加载仿真的 Starter 版；`-SE` 仅适用于 SE 的 Verilog 许可证有效时。

在 ModelSim 中，从工程根目录执行：

```tcl
do sim/view_modelsim_read_axis_stress.do
```

会加载正常相位 3 ns 的 WLF，并缩放到首行读出和 SOF 附近。`do sim/view_modelsim_sof_sweep.do` 可查看 VS 同拍边界错误与候选逻辑的对照。SOF 扫描及测试源可分别运行 `sim/run_modelsim_sof_sweep.do`、`sim/run_modelsim_source_sof.do`。

故障对照的 WLF 也已直接回读：`early_read.wlf` 在首个输出 DE 时 RGB 为 `040000`，而应为 `000000`；FIFO 未空。对应日志 `wlf_early_read_inspection.log`。`wlf_sof_inspection.log` 记录了同拍 VS 场景下首行 USER=0 / 下一行 USER=1 的实际波形值，以及候选 USER 的正确值。

## 结论边界

这是 ModelSim RTL 行为仿真，不是布局布线后的 SDF 仿真，也没有模拟真实 SDRAM 电气行为、亚稳态、完整双读/写仲裁、动态图层或 HDMI 串行输出与显示器。真实工程既有时序违例仍需保留在诊断范围。只有找到与实板现象一致的失败条件，才有依据决定修改读使能提前量或输出延迟，不能为了贴合假设强行调拍。
