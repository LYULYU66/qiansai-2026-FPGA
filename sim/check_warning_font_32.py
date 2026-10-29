"""Verify packed warning ROM and actual ModelSim pixels against Noto glyphs."""
from pathlib import Path
import re
from PIL import Image
from generate_home_font_patch import rows

root = Path(__file__).resolve().parent.parent
source = (root / "src/user_source/hdl_source/vehicle_hazard_overlay.v").read_text(encoding="utf-8")
rom = [0] * 512
for address, word in re.findall(r"rom\[9'h([0-9A-F]+)\] = 16'h([0-9A-F]+);", source):
    rom[int(address, 16)] = int(word, 16)
glyphs = [rows(char, 32, 32, crisp=True) for char in "注意安全"]
for glyph, bitmap in enumerate(glyphs):
    for quarter in range(4):
        for y, values in enumerate(bitmap):
            word = sum(values[quarter * 8 + x] << ((7 - x) * 2) for x in range(8))
            address = (glyph << 7) | (quarter << 5) | y
            assert rom[address] == word, (glyph, quarter, y)

image = Image.open(root / "sim/vehicle_warning_4dir_20260930/preview.ppm").convert("RGB")
colors = [(83, 26, 35), (185, 212, 216), (226, 240, 242), (255, 255, 255)]
checked = 0
for ox, oy in [(240, 82), (32, 216), (448, 216), (240, 408)]:
    for char in range(5):
        for y in range(32):
            for x in range(32):
                coverage = glyphs[char][y][x] if char < 4 else (
                    3 if 15 <= x <= 16 and (4 <= y <= 23 or 27 <= y <= 29) else 0)
                actual = image.getpixel((ox + 32 * char + x, oy + y))
                assert actual == colors[coverage], (ox, oy, char, x, y, actual)
                checked += 1
print(f"PASS font packing: 512 words; all four 32px messages: {checked} ModelSim pixels match Noto Sans SC Medium")
