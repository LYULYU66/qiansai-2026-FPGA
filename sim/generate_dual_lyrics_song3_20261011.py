"""Generate the three-song lyric ROM used by the 2026-10-11 song build.

The first two banks are regenerated from the checked-in, user-aligned assets;
the third bank is built from the user-provided MP3 transcription.  The ROM is
kept at 16 characters per row, so the three banks still fit one character
BRAM and the extra song needs only one additional font BRAM.
"""
from pathlib import Path
import json
import math
from generate_lyric_smooth_assets import parse as parse_song0, events as events_song0
from generate_home_font_patch import rows

ROOT = Path(__file__).resolve().parent.parent
DEST = ROOT / "dual_board/image_link/rtl/dualsong_20261005/dual_lyric_song_data.v"
MANIFEST = ROOT / "assets/lyrics/dualsong_20261005/rom_manifest.json"

# These are the lines heard in the supplied MP3.  They are deliberately kept
# short enough for the native 24px overlay and use the audio's start times.
SONG3_LINES = [
    (2998, "时光是琥珀 泪一滴滴被反锁"),
    (3496, "情书再不朽 也磨成沙漏"),
    (3868, "青春的上游 白云飞走"),
    (4628, "苍狗与海鸥 闪过的年头"),
    (4998, "潺潺的流走 命运好幽默"),
    (5298, "让爱的人都沉默"),
    (5948, "一整个宇宙 换一颗红豆"),
    (6622, "回忆如困兽 寂寞太久"),
    (7128, "而渐渐温柔 放开了拳头"),
    (7700, "反而更自由 慢动作"),
    (8048, "缱绻着 重播那一瞬间"),
    (8718, "我们在告别的演唱会"),
    (9164, "说好不再见 你写给我"),
    (9388, "我的第一首歌 你和我"),
    (10022, "十指紧扣 摸着肩头"),
    (10554, "可是那然后呢"),
    (10832, "还好我有我 这一首情歌"),
    (11418, "轻轻的轻轻哼着"),
    (13970, "明明好幽默 让爱的人都沉默"),
    (16096, "放开了拳头 反而更自由"),
    (19710, "还好我有我 这一首情歌"),
]
SONG3_CREDITS = ["梁静茹 · 情歌", "词：陈没", "曲：伍冠谚", "演唱：梁静茹", "情歌"]


def native_ram(name, words, addr):
    words = list(words) + [0] * (2048 - len(words))
    result = [
        'EG_PHY_BRAM32K #(.MODE("DP16K"),.DATA_WIDTH_A("16"),.DATA_WIDTH_B("16"),',
        '.REGMODE_A("NOREG"),.REGMODE_B("NOREG"),'
    ]
    for i in range(128):
        value = sum(w << (j * 16) for j, w in enumerate(words[i * 16:(i + 1) * 16]))
        result.append(f".INIT_{i:02X}(256'h{value:064X})" + ("," if i < 127 else ")"))
    result += [
        f"{name}(.doa(O_data),.dia(16'd0),.addra({addr}),.bytea(1'b0),.bytewea(1'b0),",
        ".csa(1'b1),.wea(1'b0),.clka(I_clk),.rsta(1'b0),.ocea(1'b1),",
        ".dob(),.dib(16'd0),.addrb(11'd0),.byteb(1'b0),.byteweb(1'b0),",
        ".csb(1'b0),.web(1'b0),.clkb(1'b0),.rstb(1'b0),.oceb(1'b0));",
    ]
    return result


def build_song3():
    original0, boundaries0, lines0, old_glyphs = parse_song0()
    _, events0 = events_song0()
    manifest = json.loads(MANIFEST.read_text(encoding="utf-8"))
    lines1 = manifest["lines1"]
    events1 = [int(v) for v in manifest["events1"]]
    boundaries1 = [tuple(v) for v in manifest["boundaries1"]]

    lines3 = [""] + [text for _, text in SONG3_LINES]
    lines3 += [""] * (22 - len(lines3)) + SONG3_CREDITS
    assert len(lines3) == 27 and max(map(len, lines3)) <= 16

    # Boundary 0..2 show the credits, then preview the first lyric while the
    # intro is playing.  Subsequent boundaries are taken from the MP3.
    boundaries3 = [(0, 23, 24), (500, 24, 25), (1000, 25, 0), (1600, 0, 1)]
    for i, (cs, _) in enumerate(SONG3_LINES):
        cur = i + 1
        nxt = i + 2 if i + 1 < len(SONG3_LINES) else 0
        boundaries3.append((cs, cur, nxt))
    boundaries3.sort()
    assert len(boundaries3) < 64

    # Red-progress events are line-local and sample paced.  Boundary commands
    # win ties, ensuring a clean handoff at a line start.
    pending = {cs: (3, 32) for cs, _, _ in boundaries3}
    for cs, line_id in ((480, 23), (980, 24), (1580, 25)):
        pending[cs] = (2, len(lines3[line_id]))
    for i, (start_cs, text) in enumerate(SONG3_LINES):
        next_cs = SONG3_LINES[i + 1][0] if i + 1 < len(SONG3_LINES) else 25800
        chars = [c for c in text if not c.isspace()]
        span_end = max(start_cs + len(chars), next_cs - 2)
        for n, _ in enumerate(chars, 1):
            end_cs = start_cs + ((span_end - start_cs) * n) // len(chars)
            end_cs = max(start_cs + 1, min(end_cs, next_cs - 1))
            if end_cs not in pending or pending[end_cs][0] < 2:
                pending[end_cs] = (2, n)
            elif pending[end_cs][0] == 2:
                pending[end_cs] = (2, max(n, pending[end_cs][1]))
    packed3, previous = [], 0
    for cs, (_, code) in sorted(pending.items()):
        delta = cs - previous
        assert 0 <= delta <= 4095 and code <= 33
        packed3.append((delta << 6) | code)
        previous = cs
    assert len(packed3) <= 512

    # Use the exact old glyph order (the smooth parser intentionally returns
    # only the first song's compact set); this preserves the existing font
    # pixels and appends the third-song symbols after ID 217.
    glyphs = list(manifest["glyph_order"])
    for text in lines3:
        for char in text:
            if char not in glyphs:
                glyphs.append(char)
    assert len(glyphs) <= 512, len(glyphs)

    # The line RAM is byte-addressed in 16-character rows.  All three banks
    # therefore fit into the same single 32K BRAM primitive.
    line_words = [0] * (3 * 32 * 16)
    for bank, texts in enumerate((lines0, lines1, lines3)):
        for lid, text in enumerate(texts):
            assert len(text) <= 16
            for col, char in enumerate(text):
                line_words[(bank * 32 + lid) * 16 + col] = glyphs.index(char)

    # Preserve every existing glyph pixel and rasterize only the new symbols.
    pixels = []
    for bank in range(16):
        values = [int(x, 16) for x in (ROOT / f"assets/lyrics/font24_bank_{bank:02d}.hex").read_text().split()]
        pixels.extend((value >> (col * 2)) & 3 for value in values for col in range(8))
    pixels = pixels[:133 * 484]
    for char in glyphs[133:]:
        image = rows(char, 24, 24, crisp=True)
        pixels.extend(c for row in image[2:24] for c in row[1:23])
    banks = (len(pixels) + 16383) // 16384
    assert banks <= 16
    font_words = [sum(v << (j * 2) for j, v in enumerate(pixels[i:i + 8]))
                  for i in range(0, len(pixels), 8)]
    font_words += [0] * (banks * 2048 - len(font_words))

    out = [
        "// Generated from the supplied MP3s; third-song timing is estimated from local transcription.",
        "module lyric_event_rom(input I_clk,input [10:0] I_addr,output reg [29:0] O_event);",
        "reg [17:0] rom[0:2047]; /* fehdl force_ram=1, ram_style=\"bram\" */",
        "reg [17:0] raw; integer n; wire [11:0] dt=raw[17:6];",
        "wire [23:0] samples=raw[5:0]==63 ? 24'hffffff : ({3'd0,dt,9'b0}-{7'd0,dt,5'b0});",
        "initial begin for(n=0;n<2048;n=n+1)rom[n]=18'h3ffff;",
    ]
    for bank, values in enumerate((events0, events1, packed3)):
        out += [f"rom[{bank * 512 + i}]=18'h{value:05x};" for i, value in enumerate(values)]
    out += [
        "end", "always @(posedge I_clk)begin raw<=rom[I_addr];O_event<={samples,raw[5:0]};end", "endmodule",
        "module lyric_boundary_map(input [8:0] I_addr,output reg [4:0] O_current,O_next);",
        "always @* begin O_current=0;O_next=0;case(I_addr)",
    ]
    for bank, values in enumerate((boundaries0, boundaries1, boundaries3)):
        out += [f"9'd{bank * 64 + i}:begin O_current=5'd{cur};O_next=5'd{nxt};end"
                for i, (_, cur, nxt) in enumerate(values)]
    out += ["endcase end", "endmodule"]
    out += [
        "module lyric_line_rom(input I_clk,input [10:0] I_addr,input [7:0] I_line,I_next_line,",
        "output [8:0] O_char,output reg [4:0] O_length,O_next_length);",
        "wire [15:0] O_data;assign O_char=O_data[8:0];",
    ] + native_ram("chars", line_words, "I_addr")
    for key, result in (("I_line", "O_length"), ("I_next_line", "O_next_length")):
        out.append(f"always @* begin {result}=0;case({key})")
        for bank, texts in enumerate((lines0, lines1, lines3)):
            out += [f"8'd{bank * 32 + i}:{result}=5'd{len(text)};" for i, text in enumerate(texts) if text]
        out.append("endcase end")
    out += ["endmodule"]

    bank_bits = max(1, math.ceil(math.log2(banks)))
    out += [
        "module lyric_font_packed_rom(input I_clk,input [8:0] I_glyph,input [4:0] I_row,I_col,output [1:0] O_cov);",
        "wire [18:0] glyph_base=({10'd0,I_glyph}<<9)-({10'd0,I_glyph}<<5)+({10'd0,I_glyph}<<2);",
        "wire [18:0] row_base=({14'd0,I_row}<<4)+({14'd0,I_row}<<2)+({14'd0,I_row}<<1);",
        "wire [18:0] address=glyph_base+row_base+{14'd0,I_col};",
        f"wire [{banks * 16 - 1}:0] bank_data;reg [{bank_bits - 1}:0] bank_select;reg [2:0] lane_select;genvar b;",
        f"generate for(b=0;b<{banks};b=b+1)begin:banks",
        "lyric_font_bram32_bank #(.BANK_ID(b)) ram(I_clk,address[13:3],bank_data[b*16+:16]);end endgenerate",
        "always @(posedge I_clk)begin bank_select<=address[17:14];lane_select<=address[2:0];end",
        "wire [15:0] selected=bank_data[{bank_select,4'd0}+:16];assign O_cov=selected[{lane_select,1'b0}+:2];endmodule",
        "module lyric_font_bram32_bank #(parameter BANK_ID=0)(input I_clk,input [10:0] I_addr,output [15:0] O_data);",
        "generate",
    ]
    for bank in range(banks):
        out += [f"if(BANK_ID=={bank})begin:bank_{bank}"] + native_ram("font", font_words[bank * 2048:(bank + 1) * 2048], "I_addr") + ["end"]
    out += ["endgenerate", "endmodule"]
    return out, dict(glyphs=glyphs, events3=packed3, boundaries3=boundaries3, lines3=lines3, font_bram32k=banks)


if __name__ == "__main__":
    lines, info = build_song3()
    DEST.write_text("\n".join(lines) + "\n", encoding="utf-8")
    print(json.dumps({"glyphs": len(info["glyphs"]), "font_bram32k": info["font_bram32k"],
                      "events3": len(info["events3"]), "boundaries3": len(info["boundaries3"])}, ensure_ascii=False))
