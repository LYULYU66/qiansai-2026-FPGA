"""Pixel check of tb_card_status_render output + PNG previews (Python37/PIL)."""
import sys
sys.path.insert(0, r"C:/FPGA2026/HX4S20_Contest_2026/7_lab_ex_2026_nosoft/qiansai/lab_ex4_tf/sim")
from pathlib import Path
from PIL import Image
from generate_status_font24_20261022 import glyph
BG = Path("../dualsong_20261005/lyricfix_20261019")
def load(p): return [int(l, 16) for l in Path(p).read_text().split()]
home, music = load(BG/"home_bg.hex"), load(BG/"music_bg.hex")
out = load("render.hex"); F = 307200
frames = {"home_paused": (home, out[0:F]), "home_playing": (home, out[F:2*F]),
          "music_paused": (music, out[2*F:3*F]), "music_playing": (music, out[3*F:4*F])}
# Expected readout (BRI selected => purple).
def readout(bg):
    img = list(bg)
    for left, text, sel in ((18, "BRI:100", 1), (146, "CON: 50", 0), (274, "VOL:8", 0),
                            (370, "RES:1920x1080", 0)):
        for i, ch in enumerate(text):
            if ch == " ": continue
            g = glyph(ch)
            for r in range(17):
                for c in range(16):
                    x, y = left + 16*i + c, 14 + r
                    cov = g[r][c] if c < 15 else 0
                    left_cov = g[r][c-1] if 1 <= c <= 15 else 0
                    if cov:
                        img[y*640+x] = ([0xA8BAC6, 0xD4E1E9, 0xF4F9FC] if not sel else
                                        [0x7E4AAE, 0xA764E0, 0xC77DFF])[cov-1]
                    elif left_cov:
                        img[y*640+x] = 0x13212E
    return img
def button(page_music, img):
    img = list(img)
    x0, cy = (327, 186) if page_music else (278, 384)
    for y in range(cy-6, cy+7):
        for dx in range(13):
            dy = abs(y-cy)
            img[y*640+x0+dx] = 0x256BB1 if dx < 12 and dy <= (12-dx)//2 else 0xFFFFFF
    return img
bad = 0
for name, (bg, got) in frames.items():
    want = readout(bg)
    if name.endswith("paused"): want = button(name.startswith("music"), want)
    diff = [i for i in range(F) if want[i] != got[i]]
    print(f"{name:14s} mismatches={len(diff)}", diff[:5] and [(i%640, i//640, hex(want[i]), hex(got[i])) for i in diff[:5]])
    bad += len(diff)
    im = Image.new("RGB", (640, 480)); im.putdata([((v>>16)&255, (v>>8)&255, v&255) for v in got])
    im.save(f"{name}.png")
    if name.endswith("paused"):
        x0, y0 = (300, 160) if name.startswith("music") else (220, 360)
        im.crop((x0-80, y0-30, x0+140, y0+50)).resize((880, 320), Image.NEAREST).save(f"{name}_zoom.png")
im = Image.open("home_playing.png"); im.crop((0, 0, 640, 48)).resize((1280, 96), Image.NEAREST).save("readout_zoom.png")
# Old readout (10x14) for comparison: unchanged background crop of the old release render, if any.
print("PASS" if bad == 0 else f"FAIL total mismatches {bad}")
