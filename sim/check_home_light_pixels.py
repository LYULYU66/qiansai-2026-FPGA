"""Independently check packed ROM and all five sprites in ModelSim output."""
from pathlib import Path
import re
from PIL import Image
from generate_app_icons_rom import packed_tiles

root = Path(__file__).resolve().parent.parent
source = (root / "src/user_source/hdl_source/video_app_icons_rom.v").read_text(encoding="utf-8")
rom = [0] * 2048
for address, word in re.findall(r"rom\[11'd(\d+)\] = 16'h([0-9A-F]+);", source):
    rom[int(address)] = int(word, 16)
output = Image.open(root / "sim/home_nav_app_20260930/preview.ppm").convert("RGB")
background = Image.open(root / "best_result/CAR01.BMP").convert("RGB")
origins = [(368,316), (420,316), (368,364), (420,364), (500,74), (28,336)]
address = 0
checked = 0
for tile, (size, pixels, palette) in enumerate(packed_tiles()):
    ox, oy = origins[tile]
    for base in range(0, size * size, 4):
        expected_word = sum(pixels[base + lane] << (12 - 4 * lane) for lane in range(4))
        assert rom[address] == expected_word, (tile, address)
        address += 1
    for y in range(size):
        for x in range(size):
            index = pixels[y * size + x]
            expected = palette[index - 1] if index else (
                background.getpixel((ox + x, oy + y)) if tile == 4 else (255, 255, 255))
            assert output.getpixel((ox + x, oy + y)) == expected, (tile, x, y)
            checked += 1
assert address == 2000 and not any(rom[address:])
for xy in [(0, 440), (639, 440), (0, 479), (639, 479)]:
    assert output.getpixel(xy) == (255, 255, 255), ("navbar corner", xy)
print(f"PASS indexed ROM: {address} words; {checked} real ModelSim sprite pixels; all rectangular navbar corners white")
