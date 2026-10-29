"""Emit an apply_patch payload for all four existing UI font ROMs.

Native-size local edge sharpening, no on-chip filter or additional storage.
All character dimensions, synchronous read ports and ROM sizes stay fixed.
"""
from pathlib import Path
import re
from generate_home_font_patch import rows
from generate_bottom_nav_icons import geometry, quantized
from generate_tpms_assets import rom_words as tpms_words

ROOT=Path(__file__).resolve().parent.parent
HDL=ROOT/"src/user_source/hdl_source"
HOME="目的地10月日告白气球9:一29℃周三多云四今搜索回家公司"
assert len(HOME)==29
STATUS="0123456789:BRICONVLESx"
TPMS_SLOTS={14,15,16,18,19,20,21,22,29}


def packed(values):
    return sum(v<<(2*(len(values)-1-x)) for x,v in enumerate(values))


def rom_lines(kind):
    output=[]
    if kind=="home":
        for glyph,ch in enumerate(HOME):
            if glyph in TPMS_SLOTS: continue
            for y,values in enumerate(rows(ch,crisp=True)):
                w=packed(values)
                if w: output.append(f"    rom[9'h{glyph*16+y:03X}] = 32'h{w:08X}; // {ch}")
        # Unused weather/duplicate-digit slots now hold paired TPMS glyphs.
        for address,w in sorted(tpms_words().items()):
            if w: output.append(f"    rom[9'h{address:03X}] = 32'h{w:08X}; // TPMS packed")
        # Home/company shortcut icons retain their native AA edges.
        for glyph,name in ((30,"home"),(31,"vehicle")):
            if glyph==30:
                pix=quantized(geometry(name,16))
            else:
                from PIL import Image,ImageDraw
                im=Image.new("L",(64,64),0);d=ImageDraw.Draw(im)
                d.rectangle((19,6,45,58),outline=255,width=5)
                d.rectangle((6,21,57,58),outline=255,width=5)
                for x in (13,29,45):
                    for y in (29,41): d.rectangle((x,y,x+5,y+5),fill=255)
                pix=quantized(im.resize((16,16),Image.Resampling.LANCZOS))
            for y in range(16):
                w=packed(pix[y*16:(y+1)*16])
                if w: output.append(f"    rom[9'h{glyph*16+y:03X}] = 32'h{w:08X}; // {name} shortcut")
    elif kind=="status":
        for code,ch in enumerate(STATUS):
            for y,values in enumerate(rows(ch,10,14,crisp=True)):
                assert not any(values[:2]+values[8:]), (ch,y,values)
                w=packed(values[2:8])
                if w: output.append(f"    rom[9'h{code*16+y:03X}] = 12'h{w:03X}; // {ch}")
    elif kind=="osd":
        for glyph,ch in enumerate("FPGA创新设计竞赛"):
            for y,values in enumerate(rows(ch,crisp=True)):
                w=packed(values)
                if w: output.append(f"    set_row(8'h{glyph*16+y:03X}, 32'h{w:08X}); // {ch}")
    elif kind=="warning":
        for glyph,ch in enumerate("注意安全"):
            bitmap=rows(ch,32,32,crisp=True)
            for quarter in range(4):
                for y,values in enumerate(bitmap):
                    w=packed(values[quarter*8:quarter*8+8])
                    address=(glyph<<7)|(quarter<<5)|y
                    if w: output.append(f"    rom[9'h{address:03X}] = 16'h{w:04X}; // {ch}")
    return "\n".join(output)


def main():
    print("*** Begin Patch")
    for name,kind in (("video_home_overlay.v","home"),("video_status_overlay.v","status"),
                      ("osd_alpha_overlay.v","osd"),("vehicle_hazard_overlay.v","warning")):
        path=HDL/name;source=path.read_text(encoding="utf-8")
        pattern=(r"    set_row\(8'h[0-9A-F]+, 32'h[0-9A-F]+\);[^\n]*\n" if kind=="osd" else
                 r"    rom\[9'h[0-9A-F]+\] = (?:32|12|16)'h[0-9A-F]+;[^\n]*\n")
        matches=list(re.finditer(pattern,source))
        assert matches,name
        start=matches[0].start();end=matches[-1].end()
        old=source[start:end].rstrip();new=rom_lines(kind)
        print("*** Update File: "+path.relative_to(ROOT).as_posix()+"\n@@")
        print("\n".join("-"+l for l in old.splitlines()))
        print("\n".join("+"+l for l in new.splitlines()))
    print("*** End Patch")


if __name__=="__main__":main()
