# 01_1 高分辨率测试图片

采用内置 image_gen 工具，以用户提供的 C:/Users/28492/Desktop/车载图片/01_1.bmp 为参考作 AI 高清细节重建。这是生成式重建，不是原照片的无损恢复；保留雪山、森林与湖面倒影构图，不增加车机UI。

生成工具实际原生输出为1448×1086、4:3，保存在同目录的 01_1_highres_generated.png。随后使用 System.Drawing 进行标准尺寸/格式导出，得到 01_1_1280x960.bmp。没有修改原输入，没有复制到TF卡，没有改动HDL或bit。

最终BMP已检查：1280×960，24-bit，BI_RGB（compression=0），planes=1，40字节信息头，像素偏移54，正高度底向上存储，3686454字节。适用于本工程仅缩小版本。若复制至TF卡，替换一张现有图片即可，不必增加第五张图片。

SHA256：B9CD8EB0550EA3B06213B1AE4C1AACA5186A64E63ABA8404692689146A83322D。

## 完整生成提示词（内置工具，不使用CLI/API回退）

Use case: identity-preserve / photographic detail reconstruction. Input image 1 is the edit target, a low-resolution 640x480 landscape photo. Create one genuine high-resolution 1280x960 pixel 4:3 landscape version of this SAME scene for an FPGA photo viewer's downscaling test. Preserve the original composition, camera position, mountain silhouettes, forest line, yellow-green grassy shore, deep blue sky with soft white clouds, and calm lake with mirrored mountains and clouds. Enhance natural photographic detail and clarity in the mountain rock strata, individual fir trees, grass textures and water reflection, reconstructing fine detail rather than merely enlarging blurry pixels. Keep the same attractive daylight, exposure and vivid yet believable colors; no stylization or oversharpening halos. Keep all scene geometry and subject placement as close as possible to input. Output one full-bleed edge-to-edge high-resolution image, exactly 4:3, requested dimensions 1280x960, no frame, no letterbox, no text, no UI overlays, no new objects, no watermark.
