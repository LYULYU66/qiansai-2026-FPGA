"""Print an apply_patch payload for the homepage navigation card glyphs.

Uses the same Noto Sans SC rasterizer as the other three on-screen overlays.
The three small icons occupy the remaining entries in the existing 512x32 ROM.
"""

from pathlib import Path
from generate_home_font_patch import rows

HDL = Path(__file__).resolve().parent.parent / "src/user_source/hdl_source/video_home_overlay.v"
NEW_CHARS = ((23, 0x641C), (24, 0x7D22), (25, 0x56DE),
             (26, 0x5BB6), (27, 0x516C), (28, 0x53F8))

ICONS = {
    29: [
        "                ", "                ", "          ###   ",
        "         ####   ", "        #####   ", "   ##########   ",
        "    #######     ", "     #####      ", "      ###       ",
        "      ###       ", "     ## ##      ", "    ##   ##     ",
        "   ##     ##    ", "                ", "                ",
        "                ",
    ],
    30: [
        "                ", "       ##       ", "      ####      ",
        "     ##  ##     ", "    ##    ##    ", "   ##      ##   ",
        "  ##        ##  ", " ############## ", "  ##        ##  ",
        "  ##  ####  ##  ", "  ##  #  #  ##  ", "  ##  #  #  ##  ",
        "  ##  #  #  ##  ", "  ############  ", "                ",
        "                ",
    ],
    31: [
        "                ", "     ######     ", "     #    #     ",
        "     #    #     ", "  ############  ", "  ##        ##  ",
        "  ## ##  ## ##  ", "  ## ##  ## ##  ", "  ## ##  ## ##  ",
        "  ## ##  ## ##  ", "  ##        ##  ", "  ##   ##   ##  ",
        "  ##   ##   ##  ", "  ############  ", "                ",
        "                ",
    ],
}


def word(values):
    return sum(value << (2 * (15 - x)) for x, value in enumerate(values))


def main():
    for icon in ICONS.values():
        assert len(icon) == 16 and all(len(row) == 16 for row in icon)
    lines = []
    for glyph_id, codepoint in NEW_CHARS:
        for row_index, pixels in enumerate(rows(chr(codepoint))):
            packed = word(pixels)
            if packed:
                lines.append(f"    rom[9'h{glyph_id * 16 + row_index:03X}] = 32'h{packed:08X};")
    for glyph_id, icon in ICONS.items():
        for row_index, art in enumerate(icon):
            packed = word([3 if c == "#" else 2 if c == "+" else 0 for c in art])
            if packed:
                lines.append(f"    rom[9'h{glyph_id * 16 + row_index:03X}] = 32'h{packed:08X};")
    print("*** Begin Patch")
    print(f"*** Update File: {HDL}")
    print("@@")
    print("     rom[9'h16F] = 32'h00018000; // 今")
    for line in lines:
        print("+" + line)
    print(" end")
    print("*** End Patch")


if __name__ == "__main__":
    main()
