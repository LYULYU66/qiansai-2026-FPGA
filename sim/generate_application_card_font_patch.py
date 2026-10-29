"""Print an apply_patch payload that reuses the removed app-label glyph IDs.

The screen keeps its existing 512x32 Noto Sans SC ROM and two BRAMs.
"""
from pathlib import Path
import re
from generate_home_font_patch import rows

ROOT = Path(__file__).resolve().parent.parent
HDL = ROOT / "src/user_source/hdl_source/video_home_overlay.v"
REPLACEMENTS = {13: "一"}


def main():
    source = HDL.read_text(encoding="utf-8")
    print("*** Begin Patch")
    print(f"*** Update File: {HDL}")
    for glyph_id, char in REPLACEMENTS.items():
        first, last = glyph_id * 16, glyph_id * 16 + 15
        pattern = re.compile(
            r"^    rom\[9'h(?:[0-9A-F]{3})\] = 32'h[0-9A-F]{8};[^\n]*$",
            re.MULTILINE,
        )
        old_lines = []
        for match in pattern.finditer(source):
            address = int(match.group(0).split("9'h")[1][:3], 16)
            if first <= address <= last:
                old_lines.append(match.group(0))
        if not old_lines:
            raise SystemExit(f"missing old glyph {glyph_id}")
        print("@@")
        for line in old_lines:
            print("-" + line)
        for row_index, values in enumerate(rows(char)):
            word = sum(value << (2 * (15 - x)) for x, value in enumerate(values))
            if word:
                print(f"+    rom[9'h{first + row_index:03X}] = 32'h{word:08X}; // {char}")
    print("*** End Patch")


if __name__ == "__main__":
    main()
