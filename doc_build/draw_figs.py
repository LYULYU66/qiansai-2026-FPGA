# -*- coding: utf-8 -*-
"""生成技术文档插图：系统总体框图、音画/歌词同步数据流图。"""
import matplotlib
matplotlib.use("Agg")
import matplotlib.pyplot as plt
from matplotlib.patches import FancyBboxPatch, FancyArrowPatch
import matplotlib.font_manager as fm
import os

plt.rcParams["font.sans-serif"] = ["Microsoft YaHei", "SimHei"]
plt.rcParams["axes.unicode_minus"] = False

OUT = os.path.dirname(os.path.abspath(__file__))

# 低饱和度配色（莫兰迪风）
C_A = "#4A6FA5"      # A 板主色（蓝）
C_B = "#8A5A83"      # B 板主色（紫）
C_NET = "#5E8C61"    # 网络（绿）
C_FILL_A = "#E8EEF6"
C_FILL_B = "#F3EAF2"
C_FILL_N = "#EAF2EB"
C_EDGE = "#3B4754"
C_TXT = "#1F2A36"


def box(ax, x, y, w, h, text, fc, ec, fs=10.5, bold=False, tc=None, rounding=0.035):
    p = FancyBboxPatch((x, y), w, h,
                       boxstyle=f"round,pad=0.004,rounding_size={rounding}",
                       fc=fc, ec=ec, lw=1.4, mutation_aspect=1.0)
    ax.add_patch(p)
    ax.text(x + w / 2, y + h / 2, text, ha="center", va="center",
            fontsize=fs, color=tc or C_TXT,
            fontweight="bold" if bold else "normal", linespacing=1.5)


def arrow(ax, x1, y1, x2, y2, color=C_EDGE, lw=1.8, style="-|>", ls="-"):
    a = FancyArrowPatch((x1, y1), (x2, y2), arrowstyle=style, mutation_scale=14,
                        color=color, lw=lw, linestyle=ls, shrinkA=2, shrinkB=2)
    ax.add_patch(a)


# ============================================================ 图1 系统总体框图
fig, ax = plt.subplots(figsize=(12.4, 7.6), dpi=200)
ax.set_xlim(0, 12.4); ax.set_ylim(0, 7.6); ax.axis("off")

# 两块板的外框
box(ax, 0.25, 0.55, 5.2, 6.35, "", "#FFFFFF", C_A, rounding=0.08)
box(ax, 6.95, 0.55, 5.2, 6.35, "", "#FFFFFF", C_B, rounding=0.08)
ax.text(2.85, 6.62, "A 板（中控娱乐屏）EG4S20", ha="center", va="center",
        fontsize=13, fontweight="bold", color=C_A)
ax.text(9.55, 6.62, "B 板（虚拟仪表盘）EG4S20", ha="center", va="center",
        fontsize=13, fontweight="bold", color=C_B)

# A 板内部
box(ax, 0.55, 5.30, 1.55, 0.72, "TF 卡\nBMP 图片", C_FILL_A, C_A, 9.5)
box(ax, 2.45, 5.30, 1.55, 0.72, "FAT32/簇链\n读取与防死锁", C_FILL_A, C_A, 9.5)
box(ax, 3.90, 5.30, 1.30, 0.72, "SDRAM\n四帧缓存", C_FILL_A, C_A, 9.5)
box(ax, 0.55, 4.30, 2.20, 0.72, "多图层 OSD 合成\n(图片+卡片+歌词)", C_FILL_A, C_A, 9.5)
box(ax, 3.10, 4.30, 2.10, 0.72, "歌词时间轴\n逐字卡拉OK渲染", C_FILL_A, C_A, 9.5)
box(ax, 0.55, 3.30, 2.20, 0.72, "频谱/波形/VU\n可视化叠加", C_FILL_A, C_A, 9.5)
box(ax, 3.10, 3.30, 2.10, 0.72, "亮度/对比度/音量\n本地调节", C_FILL_A, C_A, 9.5)
box(ax, 1.55, 2.30, 3.10, 0.72, "HDMI 1.4b 发送 (视频+音频)", C_FILL_A, C_A, 10, bold=True)
box(ax, 0.55, 1.10, 1.75, 0.72, "按键 KEY1~4\n开关 SW1~4", C_FILL_A, C_A, 9.5)
box(ax, 2.60, 1.10, 1.55, 0.72, "48kHz 音频\nI2S 播放通路", C_FILL_A, C_A, 9.5)
box(ax, 0.55, 0.75, 1.75, 0.0001, "", C_FILL_A, C_A)  # 占位（不可见）

# A 板内箭头
arrow(ax, 2.10, 5.66, 2.45, 5.66); arrow(ax, 4.00, 5.66, 3.90, 5.66)
arrow(ax, 4.55, 5.30, 4.15, 5.02)
arrow(ax, 1.65, 5.30, 1.65, 5.02)
arrow(ax, 3.35, 3.30, 3.35, 3.02)
arrow(ax, 4.15, 4.30, 3.35, 3.02, color="#9AA6B2", ls=(0, (4, 3)))
arrow(ax, 1.65, 4.30, 2.60, 3.02)

# B 板内部
box(ax, 7.25, 5.30, 1.55, 0.72, "TF 卡\nPCM 音乐/图片", C_FILL_B, C_B, 9.5)
box(ax, 9.15, 5.30, 1.55, 0.72, "音频打包发送\n(AUD2)", C_FILL_B, C_B, 9.5)
box(ax, 10.95, 5.30, 0.95, 0.72, "本地\nSDRAM", C_FILL_B, C_B, 9.5)
box(ax, 7.25, 4.30, 2.20, 0.72, "音频分析\n频谱/波形/音量", C_FILL_B, C_B, 9.5)
box(ax, 9.85, 4.30, 2.05, 0.72, "仪表盘指针/歌单\n标红/星空引擎", C_FILL_B, C_B, 9.5)
box(ax, 7.25, 3.30, 2.20, 0.72, "歌词进度跟随\n(A 板播放计数)", C_FILL_B, C_B, 9.5)
box(ax, 9.85, 3.30, 2.05, 0.72, "HDMI 1.4b 发送", C_FILL_B, C_B, 10, bold=True)
box(ax, 7.25, 2.30, 1.55, 0.72, "切歌 KEY4\n暂停 SW1", C_FILL_B, C_B, 9.5)
box(ax, 9.10, 2.30, 1.35, 0.72, "链路守护\n租约/重传", C_FILL_B, C_B, 9.5)
box(ax, 10.75, 2.30, 1.15, 0.72, "LED 状态", C_FILL_B, C_B, 9.5)

arrow(ax, 8.80, 5.66, 9.15, 5.66)
arrow(ax, 10.70, 5.66, 10.95, 5.66)
arrow(ax, 8.35, 5.30, 8.35, 5.02)
arrow(ax, 10.60, 4.66, 10.87, 4.66)
arrow(ax, 9.45, 2.66, 9.77, 2.30, color="#9AA6B2", ls=(0, (4, 3)))

# 中间千兆以太网链路
box(ax, 5.62, 3.55, 1.16, 1.55, "千兆\n以太网\nUDP\n直连", C_FILL_N, C_NET, 10.5, bold=True)
arrow(ax, 5.45, 4.55, 5.62, 4.33, color=C_NET, lw=2.2, style="<|-|>")
arrow(ax, 6.78, 4.33, 6.95, 4.55, color=C_NET, lw=2.2, style="<|-|>")
ax.text(6.20, 2.98, "IMG4 图像包 / IAK2 确认\nAUD2 音频包 / 可视化状态包\nCTL4 控制包（预警/播放进度）",
        ha="center", va="center", fontsize=8.8, color=C_NET, linespacing=1.6)

# 显示器
box(ax, 1.45, 7.10, 2.6, 0.42, "HDMI 显示器（中控画面）", "#F5F7FA", C_EDGE, 9.5)
box(ax, 8.35, 7.10, 2.6, 0.42, "HDMI 显示器（仪表画面）", "#F5F7FA", C_EDGE, 9.5)
arrow(ax, 3.10, 2.30, 2.75, 7.10, color="#9AA6B2", lw=1.4)
arrow(ax, 10.87, 4.02, 9.65, 7.10, color="#9AA6B2", lw=1.4)

plt.tight_layout(pad=0.3)
plt.savefig(os.path.join(OUT, "fig_system_arch.png"), bbox_inches="tight", facecolor="white")
plt.close(fig)

# ============================================================ 图2 音画/歌词同步数据流
fig, ax = plt.subplots(figsize=(12.4, 5.6), dpi=200)
ax.set_xlim(0, 12.4); ax.set_ylim(0, 5.6); ax.axis("off")

ax.text(6.2, 5.28, "跨板音频播放与逐字歌词同步闭环", ha="center", fontsize=13.5,
        fontweight="bold", color=C_TXT)

# B 板域
box(ax, 0.30, 0.55, 3.5, 4.05, "", "#FFFFFF", C_B, rounding=0.07)
ax.text(2.05, 4.28, "B 板（音源侧）", ha="center", fontsize=11.5, fontweight="bold", color=C_B)
box(ax, 0.55, 3.20, 1.35, 0.75, "TF 卡\nMUSIC*.PCM", C_FILL_B, C_B, 9)
box(ax, 2.20, 3.20, 1.35, 0.75, "音频流打包\n发送", C_FILL_B, C_B, 9)
box(ax, 0.55, 1.95, 1.35, 0.75, "播放进度\n对齐计算", C_FILL_B, C_B, 9)
box(ax, 2.20, 1.95, 1.35, 0.75, "频谱/波形\n特征提取", C_FILL_B, C_B, 9)
box(ax, 0.55, 0.80, 3.00, 0.72, "可视化状态 + 可视化包发送", C_FILL_B, C_B, 9.5)

# A 板域
box(ax, 8.60, 0.55, 3.5, 4.05, "", "#FFFFFF", C_A, rounding=0.07)
ax.text(10.35, 4.28, "A 板（播放侧）", ha="center", fontsize=11.5, fontweight="bold", color=C_A)
box(ax, 8.85, 3.20, 1.35, 0.75, "音频包接收\n缓冲", C_FILL_A, C_A, 9)
box(ax, 10.50, 3.20, 1.35, 0.75, "I2S / HDMI\n扬声器播放", C_FILL_A, C_A, 9)
box(ax, 8.85, 1.95, 1.35, 0.75, "已播放采样\n计数器", C_FILL_A, C_A, 9)
box(ax, 10.50, 1.95, 1.35, 0.75, "歌词时间轴\n逐字变红", C_FILL_A, C_A, 9)
box(ax, 8.85, 0.80, 3.00, 0.72, "频谱/波形/VU 画面叠加", C_FILL_A, C_A, 9.5)

arrow(ax, 1.90, 3.575, 2.20, 3.575)                       # TF->打包
arrow(ax, 1.225, 3.20, 1.225, 2.70, color="#9AA6B2")      # TF->对齐
arrow(ax, 2.875, 3.20, 2.875, 2.70, color="#9AA6B2")      # 打包->特征
arrow(ax, 1.90, 2.325, 2.20, 2.325)                       # 对齐->特征
arrow(ax, 2.05, 1.95, 2.05, 1.52)                         # 特征->发送

arrow(ax, 11.175, 3.20, 11.175, 2.70)                     # 播放->计数
arrow(ax, 10.20, 2.325, 10.50, 2.325)                     # 计数->歌词
arrow(ax, 11.175, 1.95, 11.175, 1.52)                     # 计数->叠加
arrow(ax, 10.20, 3.575, 10.50, 3.575)                     # 接收->播放

# 中间三条跨板通路
mid = [(4.28, 8.60, "① 音频 PCM 数据流（AUD2，持续发送）", C_NET),
       (2.325 + 0.0, 8.60, "", C_NET)]
arrow(ax, 3.55, 3.575, 8.85, 3.575, color=C_NET, lw=2.2)
ax.text(6.2, 3.72, "① 音频 PCM 流（AUD2）", ha="center", fontsize=9.5, color=C_NET, fontweight="bold")
arrow(ax, 8.85, 2.325, 3.55, 2.325, color="#B07A3A", lw=2.2)
ax.text(6.2, 2.47, "② 播放进度反馈（已消费采样数）", ha="center", fontsize=9.5, color="#B07A3A", fontweight="bold")
arrow(ax, 3.55, 1.16, 8.85, 1.16, color="#7A5AA5", lw=2.2)
ax.text(6.2, 1.31, "③ 频谱/波形可视化状态", ha="center", fontsize=9.5, color="#7A5AA5", fontweight="bold")

plt.tight_layout(pad=0.3)
plt.savefig(os.path.join(OUT, "fig_sync_flow.png"), bbox_inches="tight", facecolor="white")
plt.close(fig)

# ============================================================ 图3 开发流程
fig, ax = plt.subplots(figsize=(12.4, 2.9), dpi=200)
ax.set_xlim(0, 12.4); ax.set_ylim(0, 2.9); ax.axis("off")

steps = ["需求分析\n功能定义", "总体架构\n双板分工", "模块设计\nRTL 编码",
         "仿真回归\n40+ 测试用例", "板级验证\n上板实测", "时序收敛\n12 轮迭代", "演示固化\n版本冻结"]
n = len(steps)
w = 1.42; gap = (12.4 - 0.6 * 2 - n * w) / (n - 1)
colors = ["#5E8C61", "#4A6FA5", "#4A6FA5", "#8A5A83", "#B07A3A", "#B07A3A", "#5E8C61"]
for i, (s, c) in enumerate(zip(steps, colors)):
    x = 0.6 + i * (w + gap)
    box(ax, x, 0.95, w, 1.05, s, "#F5F7FA", c, 9.8, bold=True, tc=c)
    if i < n - 1:
        arrow(ax, x + w + 0.02, 1.475, x + w + gap - 0.02, 1.475, color=C_EDGE, lw=1.6)

ax.text(6.2, 0.45, "每个环节均以仿真回归与上板实测双重把关，任一环节不通过即回退到上一环节",
        ha="center", fontsize=9.5, color="#6B7684")

plt.tight_layout(pad=0.3)
plt.savefig(os.path.join(OUT, "fig_dev_flow.png"), bbox_inches="tight", facecolor="white")
plt.close(fig)

print("done:", os.listdir(OUT))
