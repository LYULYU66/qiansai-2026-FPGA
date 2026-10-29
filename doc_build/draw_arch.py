# -*- coding: utf-8 -*-
"""系统总体框图（最终版：纵向流水线布局）。"""
import matplotlib
matplotlib.use("Agg")
import matplotlib.pyplot as plt
from matplotlib.patches import FancyBboxPatch, FancyArrowPatch
import os

plt.rcParams["font.sans-serif"] = ["Microsoft YaHei", "SimHei"]
plt.rcParams["axes.unicode_minus"] = False
OUT = os.path.dirname(os.path.abspath(__file__))

C_A = "#4A6FA5"; C_B = "#8A5A83"; C_NET = "#5E8C61"
C_FILL_A = "#E9EFF7"; C_FILL_B = "#F4EBF2"; C_FILL_N = "#EAF2EB"
C_EDGE = "#3B4754"; C_TXT = "#1F2A36"
DASH = (0, (3, 2))


def box(ax, x, y, w, h, text, fc, ec, fs=10, bold=False, rounding=0.05):
    ax.add_patch(FancyBboxPatch((x, y), w, h,
                 boxstyle=f"round,pad=0.004,rounding_size={rounding}",
                 fc=fc, ec=ec, lw=1.4))
    ax.text(x + w / 2, y + h / 2, text, ha="center", va="center", fontsize=fs,
            color=C_TXT, fontweight="bold" if bold else "normal", linespacing=1.45)


def arrow(ax, x1, y1, x2, y2, color=C_EDGE, lw=1.7, ls="-"):
    ax.add_patch(FancyArrowPatch((x1, y1), (x2, y2), arrowstyle="-|>",
                 mutation_scale=13, color=color, lw=lw, linestyle=ls,
                 shrinkA=1, shrinkB=1))


fig, ax = plt.subplots(figsize=(12.6, 8.2), dpi=200)
ax.set_xlim(0, 12.6); ax.set_ylim(0, 8.2); ax.axis("off")

# ---------- 显示器 ----------
box(ax, 0.9, 7.42, 3.4, 0.5, "HDMI 显示器：中控画面（首页/歌词/频谱）", "#F5F7FA", C_EDGE, 9.5)
box(ax, 8.3, 7.42, 3.4, 0.5, "HDMI 显示器：仪表画面（仪表/歌单/星空）", "#F5F7FA", C_EDGE, 9.5)

# ================= A 板 =================
box(ax, 0.35, 0.45, 5.35, 6.60, "", "#FFFFFF", C_A, rounding=0.07)
ax.text(3.02, 6.72, "A 板：中控娱乐屏（EG4S20）", ha="center", va="center",
        fontsize=13, fontweight="bold", color=C_A)

box(ax, 0.65, 5.60, 1.35, 0.66, "TF 卡接口\nBMP 图片", C_FILL_A, C_A, 8.8)
box(ax, 2.30, 5.60, 1.55, 0.66, "FAT32/簇链解析\n读取防死锁", C_FILL_A, C_A, 8.8)
box(ax, 4.15, 5.60, 1.35, 0.66, "SDRAM\n四帧缓存", C_FILL_A, C_A, 8.8)
box(ax, 0.65, 4.50, 1.30, 0.66, "亮度/对比度\n调节", C_FILL_A, C_A, 8.8)
box(ax, 2.25, 4.50, 3.25, 0.66, "多图层 OSD 合成（图片+UI卡片+字幕）", C_FILL_A, C_A, 8.8)
box(ax, 0.65, 3.40, 2.30, 0.66, "歌词时间轴\n逐字卡拉OK", C_FILL_A, C_A, 8.8)
box(ax, 3.25, 3.40, 2.25, 0.66, "频谱/波形/VU\n可视化叠加", C_FILL_A, C_A, 8.8)
box(ax, 0.65, 2.30, 4.85, 0.66, "HDMI 1.4b 发送核（TMDS 编码 + 音视频组包）", C_FILL_A, C_A, 9.6, bold=True)
box(ax, 0.65, 1.20, 2.30, 0.66, "按键/开关\n切图·调参·预警", C_FILL_A, C_A, 8.8)
box(ax, 3.25, 1.20, 2.25, 0.66, "音频接收缓冲\n→ 48kHz I2S 播放", C_FILL_A, C_A, 8.8)

arrow(ax, 2.00, 5.93, 2.30, 5.93)                  # TF -> FAT32
arrow(ax, 3.85, 5.93, 4.15, 5.93)                  # FAT32 -> SDRAM
arrow(ax, 4.82, 5.60, 4.82, 5.16)                  # SDRAM -> OSD
arrow(ax, 1.95, 4.83, 2.25, 4.83)                  # 亮度 -> OSD
arrow(ax, 2.60, 4.06, 2.60, 4.50)                  # 歌词 -> OSD
arrow(ax, 4.37, 4.06, 4.37, 4.50)                  # 频谱 -> OSD
arrow(ax, 3.10, 4.50, 3.10, 2.96)                  # OSD -> HDMI（走两行间隙）
arrow(ax, 1.80, 1.86, 1.80, 2.30, ls=DASH)         # 按键 -> HDMI 域
arrow(ax, 4.37, 1.86, 4.37, 2.30, ls=DASH)         # 音频 -> HDMI
arrow(ax, 2.60, 7.05, 2.60, 7.42, color="#9AA6B2") # 板 -> 显示器

# ================= B 板 =================
box(ax, 6.90, 0.45, 5.35, 6.60, "", "#FFFFFF", C_B, rounding=0.07)
ax.text(9.57, 6.72, "B 板：虚拟仪表盘（EG4S20）", ha="center", va="center",
        fontsize=13, fontweight="bold", color=C_B)

box(ax, 7.20, 5.60, 1.35, 0.66, "音频流打包\nAUD2 分包", C_FILL_B, C_B, 8.8)
box(ax, 8.85, 5.60, 1.55, 0.66, "TF 卡接口\nPCM 音乐/图片", C_FILL_B, C_B, 8.8)
box(ax, 10.70, 5.60, 1.35, 0.66, "本地\nSDRAM", C_FILL_B, C_B, 8.8)
box(ax, 7.20, 4.50, 1.55, 0.66, "音频分析\n频谱/波形", C_FILL_B, C_B, 8.8)
box(ax, 9.05, 4.50, 3.00, 0.66, "页面渲染：仪表指针/歌单标红/星空", C_FILL_B, C_B, 8.8)
box(ax, 7.20, 3.40, 1.55, 0.66, "播放进度跟随\n（A 板反馈）", C_FILL_B, C_B, 8.8)
box(ax, 9.90, 3.40, 2.15, 0.66, "HDMI 1.4b 发送", C_FILL_B, C_B, 9.6, bold=True)
box(ax, 7.20, 2.30, 2.40, 0.66, "切歌 KEY4\n暂停/播放 SW1", C_FILL_B, C_B, 8.8)
box(ax, 9.90, 2.30, 2.15, 0.66, "链路守护\n租约/心跳/重传", C_FILL_B, C_B, 8.8)
box(ax, 7.20, 1.20, 4.85, 0.66, "LED 状态指示 / 网口 RGMII 物理层接口", C_FILL_B, C_B, 8.8)

arrow(ax, 8.85, 5.93, 8.55, 5.93)                  # TF -> 打包（向左）
arrow(ax, 10.40, 5.93, 10.70, 5.93)                # TF -> SDRAM
arrow(ax, 9.62, 5.60, 9.62, 5.16)                  # TF -> 音频分析
arrow(ax, 11.37, 5.60, 11.37, 5.16)                # SDRAM -> 页面渲染
arrow(ax, 7.97, 4.50, 7.97, 4.06)                  # 音频分析 -> 进度跟随
arrow(ax, 10.55, 4.50, 10.55, 4.06)                # 页面渲染 -> HDMI
arrow(ax, 10.55, 3.40, 10.55, 2.96, ls=DASH, color="#9AA6B2")  # HDMI -> 链路守护
arrow(ax, 10.00, 7.05, 10.00, 7.42, color="#9AA6B2")           # 板 -> 显示器

# ================= 中间网络 =================
box(ax, 5.82, 3.70, 0.96, 1.70, "千兆\n以太网\nUDP\n直连", C_FILL_N, C_NET, 9.8, bold=True)
arrow(ax, 5.70, 4.55, 5.82, 4.55, color=C_NET, lw=2.0)
arrow(ax, 6.78, 4.55, 6.90, 4.55, color=C_NET, lw=2.0)

ax.text(6.30, 6.05, "IMG4 图像包\nIAK2 确认包\nAUD2 音频包\n可视化状态包\nCTL4 控制/进度反馈",
        ha="center", va="center", fontsize=7.8, color=C_NET, linespacing=1.75)
ax.text(6.30, 2.80, "固定 IP 直连\nA 板 .11\nB 板 .12",
        ha="center", va="center", fontsize=7.8, color=C_NET, linespacing=1.75)

plt.tight_layout(pad=0.3)
plt.savefig(os.path.join(OUT, "fig_system_arch.png"), bbox_inches="tight", facecolor="white")
plt.close(fig)
print("ok")
