"""Emit one apply_patch payload for every on-screen Noto Sans SC glyph ROM.

Use the bundled Python runtime with Pillow. The script prints the patch and
does not write HDL files itself; source changes are applied with apply_patch.
"""
from pathlib import Path
from PIL import Image, ImageDraw, ImageFont, ImageFilter
import sys

ROOT = Path(__file__).resolve().parent.parent
HDL = ROOT / "src/user_source/hdl_source"
FONT = Path(r"C:\Windows\Fonts\Noto Sans SC Medium (TrueType).otf")
CHARS = "目的地青岛音乐告白气球市天晴29℃周三多云四今"
assert len(CHARS) == 23


def rows(char, width=16, height=16, crisp=False):
    canvas = Image.new("L", (64, 64), 0)
    draw = ImageDraw.Draw(canvas)
    font = ImageFont.truetype(str(FONT), 60)
    draw.text((32, 32), char, font=font, fill=255, anchor="mm")
    img = canvas.resize((width, height), Image.Resampling.LANCZOS)
    if crisp:
        img = img.filter(ImageFilter.UnsharpMask(radius=0.55, percent=170, threshold=6))
    out = []
    for y in range(height):
        values = []
        for x in range(width):
            a = img.getpixel((x, y))
            values.append((0 if a < 48 else 1 if a < 116 else 2 if a < 196 else 3)
                          if crisp else
                          (0 if a < 32 else 1 if a < 112 else 2 if a < 208 else 3))
        out.append(values)
    return out


def make_function(chars=CHARS, width=16, height=16, name="glyph_row_coverage", character_input=False):
    assert width * 2 <= 32
    input_bits = 8 if character_input else (4 if len(chars) <= 16 else 5)
    row_bits = 4
    case_bits = input_bits + row_bits
    lines = [
        f"// Noto Sans SC Medium, {width}x{height}, two-bit antialias coverage.",
        "// Generated from the same font source for all on-screen labels.",
        f"function [{width*2-1}:0] {name};",
        f"    input [{input_bits-1}:0] {'character' if character_input else 'glyph'};",
        "    input [3:0] row;",
        "    begin",
        f"        case ({{{'character' if character_input else 'glyph'},row}})",
    ]
    for gid, char in enumerate(chars):
        for rowno, values in enumerate(rows(char, width, height)):
            code = sum(v << ((width-1-x) * 2) for x, v in enumerate(values))
            if code:
                key = (ord(char) if character_input else gid) * 16 + rowno
                lines.append(f"            {case_bits}'h{key:03X}: {name} = {width*2}'h{code:0{width//2}X}; // {char}")
    lines += [
        f"            default: {name} = {width*2}'d0;",
        "        endcase",
        "    end",
        "endfunction",
    ]
    return "\n".join(lines)


def replacement(old, new):
    return "@@\n" + "\n".join("-" + line for line in old.splitlines()) + "\n" + "\n".join("+" + line for line in new.splitlines()) + "\n"


def main():
    source = (HDL / "video_home_overlay.v").read_text(encoding="utf-8")
    if "function [31:0] glyph_row_coverage;" in source:
        # A quick reproducibility check for the checked-in generated ROMs.
        for filename, marker, expected in [
            ("video_home_overlay.v", "function [31:0] glyph_row_coverage;", make_function()),
            ("osd_alpha_overlay.v", "function [31:0] glyph_row_coverage;", make_function("FPGA创新设计竞赛")),
            ("video_status_overlay.v", "function [19:0] font_row_coverage;", make_function("BRICONVL:012345678 ", 10, 14, "font_row_coverage", True)),
        ]:
            current = (HDL / filename).read_text(encoding="utf-8")
            start = current.index(marker)
            end = current.index("endfunction", start) + len("endfunction")
            # Compare the function body; comments may be edited independently.
            expected_body = expected[expected.index("function "):]
            if current[start:end] != expected_body:
                raise SystemExit(f"generated UI font differs: {filename}")
        print("All three on-screen font ROMs match Noto Sans SC Medium.")
        return
    patch = "*** Begin Patch\n"
    patch += home_patch(source)
    patch += osd_patch((HDL / "osd_alpha_overlay.v").read_text(encoding="utf-8"))
    patch += status_patch((HDL / "video_status_overlay.v").read_text(encoding="utf-8"))
    patch += "*** End Patch\n"
    sys.stdout.write(patch)


def home_patch(source):
    old_pixel = "wire [15:0] row_bits = glyph_row(glyph_id, glyph_y);\nwire glyph_on = text_valid && row_bits[15-glyph_col];"
    new_pixel = """wire [31:0] row_coverage = glyph_row_coverage(glyph_id, glyph_y);
wire [1:0] glyph_cov = row_coverage[(15-glyph_col)*2 +: 2];
wire glyph_on = text_valid && (glyph_cov != 2'd0);
wire heading_text = (card_id == 2'd2) ? (pixel_y < 10'd346) :
                    (pixel_y < 10'd354);
wire [23:0] glyph_color = forecast_text ?
    ((glyph_cov == 2'd3) ? 24'hD5E4EF :
     (glyph_cov == 2'd2) ? 24'h9FB9C9 : 24'h66899C) :
    heading_text ?
    ((glyph_cov == 2'd3) ? 24'hAAECFA :
     (glyph_cov == 2'd2) ? 24'h75B7CA : 24'h487D91) :
    ((glyph_cov == 2'd3) ? 24'hF6FAFC :
     (glyph_cov == 2'd2) ? 24'hB9CDD8 : 24'h6E91A3);"""
    assert old_pixel in source
    old_line = "    glyph_on ? (forecast_text ? 24'hC5D9E6 : 24'hF5FAFF) :"
    new_line = "    glyph_on ? glyph_color :"
    assert old_line in source
    marker = "function [15:0] glyph_row;"
    start = source.index(marker)
    end = source.index("endfunction", start) + len("endfunction")
    old_fn = source[start:end]
    patch = "*** Update File: " + (HDL / "video_home_overlay.v").as_posix() + "\n"
    patch += replacement(old_pixel, new_pixel)
    patch += replacement(old_line, new_line)
    patch += replacement(old_fn, make_function())
    return patch


def osd_patch(source):
    old_comment = "// 仍采用 24x24 微软雅黑粗体字模，显示时用移位映射压缩到 16x16；\n// 每字占 20 像素（16 像素字形 + 4 像素字距），总宽度为 200。"
    new_comment = "// 与主页同源的 16x16 Noto Sans SC 字模；每字占 20 像素。"
    assert old_comment in source
    old_pixel = source[source.index("wire [4:0] source_glyph_col ="):source.index("// 白色层：")]
    new_pixel = """wire [31:0] glyph_coverage = glyph_row_coverage(small_char_index, text_rel_y[3:0]);
wire [1:0] glyph_cov = glyph_coverage[(15-small_glyph_col[3:0])*2 +: 2];
wire glyph_on = text_area_hit && (small_glyph_col < 5'd16) &&
                (glyph_cov != 2'd0);

"""
    old_color = "assign O_rgb = glyph_on ? {text_r, text_g, text_b} :"
    new_color = """wire [7:0] shade_r = (glyph_cov == 2'd3) ? text_r :
                     (glyph_cov == 2'd2) ? {1'b0,panel_r[7:1]} :
                                            {1'b0,panel_r[7:1]} + {2'b00,panel_r[7:2]};
wire [7:0] shade_g = (glyph_cov == 2'd3) ? text_g :
                     (glyph_cov == 2'd2) ? {1'b0,panel_g[7:1]} :
                                            {1'b0,panel_g[7:1]} + {2'b00,panel_g[7:2]};
wire [7:0] shade_b = (glyph_cov == 2'd3) ? text_b :
                     (glyph_cov == 2'd2) ? {1'b0,panel_b[7:1]} :
                                            {1'b0,panel_b[7:1]} + {2'b00,panel_b[7:2]};
assign O_rgb = glyph_on ? {shade_r, shade_g, shade_b} :"""
    assert old_pixel in source and old_color in source
    old_fn = source[source.index("// 8x16 ASCII 字模"):source.rindex("endmodule")]
    new_fn = make_function("FPGA创新设计竞赛") + "\n\n"
    patch = "*** Update File: " + (HDL / "osd_alpha_overlay.v").as_posix() + "\n"
    for old,new in [(old_comment,new_comment),(old_pixel,new_pixel),(old_color,new_color),(old_fn,new_fn)]:
        patch += replacement(old,new)
    return patch


def status_patch(source):
    old_header = "// Uses a 5x7 procedural font and shift-based alpha background: no ROM, DSP,\n// or BRAM.  Control values are synchronized and committed at a frame edge."
    new_header = "// Uses the shared Noto Sans SC font source and shift-based alpha background.\n// Control values are synchronized and committed at a frame edge."
    assert old_header in source
    old_pixel = source[source.index("wire [2:0] font_col ="):source.index("reg [6:0] bar_width;")]
    new_pixel = """wire [3:0] font_col = char_cell_x;
wire [3:0] font_row_index = pixel_y - line_top;
wire [7:0] current_char = status_char(text_line, char_index,
                                      brightness_frame, contrast_frame,
                                      volume_frame);
wire [19:0] current_font_row = font_row_coverage(current_char, font_row_index);
wire [1:0] text_cov = current_font_row[(9-font_col)*2 +: 2];
wire text_hit = card_hit && text_row_hit &&
                (pixel_x >= TEXT_LEFT) && (pixel_x < TEXT_LEFT + 11'd84) &&
                (char_cell_x < 4'd10) && (text_cov != 2'd0);

"""
    old_color = "assign O_rgb = text_hit ? ((char_index >= 3'd4) ? line_color : 24'hEEF7FF) :"
    new_color = """wire [23:0] label_color = (text_cov == 2'd3) ? 24'hEEF7FF :
                          (text_cov == 2'd2) ? 24'hB3CAD7 : 24'h718E9F;
wire [23:0] value_color = (text_cov == 2'd3) ? line_color :
                          (text_cov == 2'd2) ? {1'b0,line_color[23:17],1'b0,line_color[15:9],1'b0,line_color[7:1]} :
                                                24'h506F70;
assign O_rgb = text_hit ? ((char_index >= 3'd4) ? value_color : label_color) :"""
    assert old_pixel in source and old_color in source
    start = source.index("function [4:0] font_row;")
    end = source.index("endfunction", start) + len("endfunction")
    old_fn = source[start:end]
    new_fn = make_function("BRICONVL:012345678 ",10,14,"font_row_coverage",True)
    patch = "*** Update File: " + (HDL / "video_status_overlay.v").as_posix() + "\n"
    for old,new in [(old_header,new_header),(old_pixel,new_pixel),(old_color,new_color),(old_fn,new_fn)]:
        patch += replacement(old,new)
    return patch


if __name__ == "__main__":
    main()
