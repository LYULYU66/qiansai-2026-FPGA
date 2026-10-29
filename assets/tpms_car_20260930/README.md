# 胎压卡片小车素材

使用 imagegen 技能的内置 image_gen 工具生成，不使用 CLI/API 回退。

- `source.png`：生成的原始 1024×1536 RGBA 银白小车，保留透明通道。
- `car_native32x64.png`：按透明边界裁切、等比例缩小到 32×64 的原生 RGBA 素材。
- `car_indexed32x64.png` / `.ppm`：实际 HDL 使用的 15 色加透明索引图，白卡背景合成预览。
- `car_indexed_zoom.png`：仅供观察的 8 倍最近邻放大图，不是板上尺寸。

板上图像范围 x=540..571、y=327..390，位于首页第四个白色圆角卡片的四组胎压数据之间。图像已固化在 bit 中，不需要放入 TF 卡。采用 2048×4 同步 ROM，综合为 1 块 BRAM9K，无在线缩放、滤波、DSP 或新增帧缓存。原始透明边缘在离线阶段合成到白底；索引 0 为透明，15 专用于细小尾灯，以免银白车身挤掉红色调色项。

处理与验证脚本：`sim/generate_tpms_assets.py`、`sim/check_crisp_ui_assets.py`、`sim/tb_nav_toolbar_alignment.sv`。代码修改和 ROM 补丁经 apply_patch 应用。胎压/温度为用户参考图中的固定演示值，不是传感器测量结果。

## 最终生成提示词

Use case: product-mockup. Asset type: isolated automotive tyre-pressure dashboard car sprite. Generate one photorealistic premium silver-white compact passenger car, STRICT orthographic overhead top-down view, front bumper pointing straight upward, rear bumper downward, full car centered. Body is upright and symmetrical, width:length approximately 1:2.2. Clearly recognizable contoured bonnet, roof, dark blue-black windshield and rear window, subtle side mirrors, four visible black rubber tyres beside the body, realistic metallic silver shading, small headlights at front and tiny red tail lights at rear. Clean high-contrast silhouette, crisp dark window/body separations, broad simplified material details that remain readable when reduced to 32 by 64 pixels for a 640 by 480 FPGA car infotainment tyre-pressure widget. Neutral soft studio light. Genuinely transparent background, no floor, no drop shadow extending outside the car, no labels, no tyre data, no writing, no logos, no border, no watermark, no scene. Do not make a perspective or three-quarter view, no rotated or tilted car, no interior UI. Single car only, generous transparent padding.
