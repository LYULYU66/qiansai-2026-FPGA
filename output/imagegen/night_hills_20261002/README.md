# 夜色草坡纯背景（2026-10-02）

使用内置 image_gen 图像生成工具，以用户提供的车机画面为配色与构图参考，生成新的纯背景，不复刻屏幕外壳。画面只保留紫灰夜空和深绿草坡；没有时间、日期、文字、光点、星星或界面边框。

两个尺寸来自同一张生成底图，经标准尺寸/格式导出，构图一致，4:3不裁剪。BMP为24-bit非压缩BI_RGB、40字节信息头、像素偏移54、正高度；文件头及尺寸均检查通过。PNG提供便于查看的版本。没有改HDL、bit或TF卡。

## 文件

- 640×480：night_hills_640x480.bmp / night_hills_640x480.png。BMP 921654字节；SHA256 DBE81E95BF5482F70CFE9269C62B8248369DF5EB676170F32054F43B85B4A05F。
- 1280×960：night_hills_1280x960.bmp / night_hills_1280x960.png。BMP 3686454字节；SHA256 F0EA6B1006FDE6C8EDEC93A0E8DD26F90E7D8FE1D87572C4C54EB6C4D815C025。

night_hills_generated.png 为工具的原生输出。

## 完整提示词（内置工具，无CLI/API回退）

Use case: photorealistic-natural. Asset type: clean static background wallpaper for a vehicle multimedia screen, with separate FPGA overlays added later. Input image 1 is ONLY a visual reference for the landscape wallpaper visible inside its display: do NOT recreate the physical screen, dashboard, clock or light particles. Create one high-resolution 4:3 landscape image, requested size 1280x960, edge-to-edge. Scene: quiet rolling grassy hills at dusk, with a smooth empty muted charcoal-indigo and smoky lavender night sky filling the upper approximately 56 percent. Lower approximately 44 percent: softly undulating deep emerald-green grass hills; a broad foreground rounded slope rising gently toward the right-center and dipping toward the left, with smaller distant hills on the far left, matching the reference's calm silhouette. Fine realistic short grass texture, subtle cool ambient twilight on the upper ridge, naturally dark lower foreground yet enough green detail to remain visible. Elegant understated premium car-system wallpaper, natural and realistic, soft low-contrast lighting, tranquil atmosphere, clean broad sky region for later overlays. Maintain the reference's muted dark-purple sky and deep green terrain. Strictly background only: NO time, NO numbers, NO date, NO letters, NO text of any kind, NO clocks, NO UI, NO logos, NO icons, NO border, NO dashboard or monitor housing. Absolutely NO bright dots, NO glowing points, NO fireflies, NO particles, NO stars, NO sparkles, NO light trails, NO sun or moon. Do not add trees, buildings, roads, vehicles, water or people. No watermark.
