"""Generate the six-song lyric/event/font ROMs (20261019 sync fix).

Changes against generate_dual_lyrics_song6_20261013.py:
  * Song-head rows are ordinary rows of line bank 6 (id song*5+row+1) and are
    swept red by normal column events, so a lyric row can no longer share an
    id with a head row (rows 22..25 used to be drawn as credits).
  * Every song uses per-character spans: songs 0/1 from their karaoke JSON,
    songs 2..5 from align_song_chars_20261019.py (even spread as fallback).
  * All glyphs are kept.  More than 512 glyphs are addressed by remapping the
    top logical ids of one song (lyric_glyph_map); the font tail beyond the
    fourteen EMB32 blocks is stored in inferred 9K BRAM.
"""
from pathlib import Path
import json, math
from generate_dual_lyrics_song6_20261013 import (ROOT, MANIFEST, CORRECTED_TIMELINE,
                                                  SONG_CREDITS, SONG_TITLES, native_ram)
from generate_home_font_patch import rows
from PIL import Image, ImageFilter

DEST = ROOT / "dual_board/image_link/rtl/dualsong_20261005/dual_lyric_song_data.v"
REPORT = ROOT / "tmp/lyricfix_20261019/rom_report_20261019.json"
CHAR_TIMELINE = ROOT / "tmp/lyricfix_20261019/song_chars_20261019.json"
KARAOKE = {0: ROOT / "assets/lyrics/GAOBAI_3D_USER_AUDIO.karaoke.json",
           1: ROOT / "assets/lyrics/dualsong_20261005/YILU_USER_AUDIO.karaoke.json"}
HEAD_BANK = 6
QQ_SOURCE = ROOT / "assets/qq_music_source.png"
QQ_PREVIEW = ROOT / "tmp/lyricfix_20261019/qq_icon64_preview.png"
ICON_SIZE = 64                # music-card logo, replaces the 64px song cover
ICON_BASE = 2560              # tail word offset; 4 pixels x 4 bits per word
TITLE_ROW = 26
FONT_BRAM32 = 14              # EMB32 blocks available to the font
GLYPH_PIXELS = 22 * 22
BOUNDARY_SLOTS = 64           # boundary_index is 6 bits per song
EVENT_SLOTS = 512             # event_index is 9 bits per song
EARLY_GAP_CS = 400            # gaps longer than this advance the next row early
EARLY_LEAD_CS = 100           # ...this long after the previous row was sung
CODE_BOUNDARY, CODE_START, CODE_END = 32, 33, 63


def head_id(song, row):
    return song * 5 + row + 1


def lyric_slots():
    return [i for i in range(1, 32) if i != TITLE_ROW]


def occurrences(song):
    """[(start_cs, end_cs, text, [(col, start_cs, end_cs) per visible char])]"""
    if song in KARAOKE:
        data = json.loads(KARAOKE[song].read_text(encoding="utf-8"))["lines"]
        out = []
        for line in data:
            text = line["text"]
            spans = [(c, int(line["char_start_cs"][c]), int(line["char_end_cs"][c]))
                     for c, ch in enumerate(text) if not ch.isspace()]
            out.append((int(line["lrc_start_cs"]), spans[-1][2], text, spans))
        return out
    if CHAR_TIMELINE.exists():
        data = json.loads(CHAR_TIMELINE.read_text(encoding="utf-8"))[str(song)]
        out = []
        for row in data:
            text = row["text"]
            cols = [c for c, ch in enumerate(text) if not ch.isspace()]
            assert len(cols) == len(row["chars"]), (song, text)
            spans = [(c, int(a), int(b)) for c, (_, a, b) in zip(cols, row["chars"])]
            out.append((int(row["start_cs"]), int(row["end_cs"]), text, spans))
        return out
    data = json.loads(CORRECTED_TIMELINE.read_text(encoding="utf-8"))[str(song)]
    out = []
    for row in data:
        a, b, text = int(row["start_cs"]), int(row["end_cs"]), row["text"]
        cols = [c for c, ch in enumerate(text) if not ch.isspace()]
        spans = [(c, a + (b-a)*k//len(cols), a + (b-a)*(k+1)//len(cols))
                 for k, c in enumerate(cols)]
        out.append((a, b, text, spans))
    return out


def even_spans(text, start, stop):
    cols = [c for c, ch in enumerate(text) if not ch.isspace()]
    return [(c, start + (stop-start)*k//len(cols), start + (stop-start)*(k+1)//len(cols))
            for k, c in enumerate(cols)]


def build_song(song):
    occ = sorted(occurrences(song), key=lambda o: o[0])
    for i in range(1, len(occ)):
        assert occ[i][0] > occ[i-1][0], (song, occ[i][2])
    lines = [""] * 32
    lines[TITLE_ROW] = SONG_TITLES[song]
    ids = {}
    for _, _, text, _ in occ:
        if text not in ids:
            slot = lyric_slots()[len(ids)]
            ids[text] = slot
            lines[slot] = text
    assert max(map(len, lines)) <= 16
    heads = [(r, t) for r, t in enumerate(SONG_CREDITS[song]) if t]
    assert [r for r, _ in heads[:2]] == [0, 1] and len(heads) <= 5
    head_rows = [(32 | head_id(song, r), t) for r, t in heads]

    # Rows in display order: (start_cs, row code, text, spans).  The head is
    # spread over the instrumental intro and swept like a lyric row.
    first = occ[0][0]
    assert first >= 500, (song, first)
    slot = first / len(head_rows)
    shown = []
    for k, (code, text) in enumerate(head_rows):
        t0 = round(k * slot)
        sweep = max(100, round(0.7 * slot))
        shown.append((t0, code, text, even_spans(text, t0 + 20, t0 + 20 + sweep)))
    for start, end, text, spans in occ:
        shown.append((start, ids[text], text, spans))

    boundaries, pending = [], {}

    def put(cs, prio, code):
        old = pending.get(cs)
        if old is None or old[0] < prio or (old[0] == prio == 2 and old[1] < code):
            pending[cs] = (prio, code)

    # A lyric row normally becomes current at its first sung character.  After
    # a long instrumental gap it is shown (white) shortly after the previous
    # row ends, so the singer's entry is visible before the red sweep starts.
    visible = [0]
    for i in range(1, len(shown)):
        start = shown[i][0]
        if i - 1 >= len(head_rows):
            sung = shown[i-1][3][-1][2]
            if start - sung > EARLY_GAP_CS:
                start = sung + EARLY_LEAD_CS
        assert start > visible[-1], (song, shown[i][2])
        visible.append(start)
    for i, (_, code, text, spans) in enumerate(shown):
        nxt = shown[i+1][1] if i + 1 < len(shown) else 0
        # Row 0 is also the reset state of audio_lyric_timeline; its event at
        # sample 0 re-arms the head when the stream restarts on the same song.
        boundaries.append((visible[i], code, nxt))
        put(visible[i], 3, CODE_BOUNDARY)
        deadline = visible[i+1] - 1 if i + 1 < len(shown) else 10**9
        previous = visible[i]
        for col, a, b in spans:
            count = col + 1
            while count < len(text) and text[count].isspace():
                count += 1
            # Rows that overlap the next onset are compressed; columns that
            # land on the same centisecond collapse to the furthest one.
            b = max(visible[i] + 1, min(max(b, previous), deadline))
            a = max(previous, min(a, b - 1))
            if a > previous + 2:
                put(a, 1, CODE_START)
            put(b, 2, count)
            previous = b
        assert previous <= deadline, (song, text)

    assert boundaries[0] == (0, head_rows[0][0], head_rows[1][0])
    assert len(boundaries) <= BOUNDARY_SLOTS, (song, len(boundaries))
    seq = sorted((cs, code) for cs, (_, code) in pending.items())
    packed, previous = [], 0
    for cs, code in seq:
        while cs - previous > 4095:          # keep 12-bit deltas: inert marker
            previous += 4000
            packed.append((4000 << 6) | CODE_START)
        packed.append(((cs - previous) << 6) | code)
        previous = cs
    assert len(packed) <= EVENT_SLOTS, (song, len(packed))
    assert sum(1 for _, c in seq if c == CODE_BOUNDARY) == len(boundaries)
    return {"lines": lines, "heads": head_rows, "boundaries": boundaries,
            "events": packed, "shown": shown, "seq": seq}


def glyph_layout(banks, base):
    """Logical 9-bit ids per song plus the physical font order."""
    used = {s: set(ch for t in banks[s] for ch in t) for s in range(6)}
    for s in range(6):
        used[s] |= set(ch for t in SONG_CREDITS[s] for ch in t)
    every = set().union(*used.values()) | {" "}
    tail = [c for c in sorted(every - set(base), key=ord)]
    physical = list(base) + tail
    extra = len(physical) - 512
    remap_song, k = 0, 0
    if extra > 0:
        k = extra
        owner = {c: [s for s in range(6) if c in used[s]] for c in tail}
        remap_song = max(range(6), key=lambda s: sum(owner[c] == [s] for c in tail))
        y = [c for c in tail if owner[c] == [remap_song]][:k]
        x = [c for c in tail if remap_song not in owner[c] and c not in y][:k]
        assert len(y) == k and len(x) == k, "not enough exclusive glyphs to remap"
        rest = [c for c in tail if c not in x and c not in y]
        physical = list(base) + rest + x + y
        assert len(physical) == 512 + k
    index = {c: i for i, c in enumerate(physical)}

    def logical(song, ch):
        p = index[ch]
        if p >= 512:
            assert song == remap_song
            return p - k
        if k and song == remap_song:
            assert p < 512 - k, ("remapped song uses a displaced glyph", ch)
        return p
    return physical, logical, remap_song, k


def font_words(physical, base):
    hex_pixels = []
    for b in range(16):
        values = [int(x, 16) for x in (ROOT/f"assets/lyrics/font24_bank_{b:02d}.hex").read_text().split()]
        hex_pixels.extend((v >> (c*2)) & 3 for v in values for c in range(8))
    pixels = []
    for ch in physical:
        if ch in base[:133]:
            i = base.index(ch)
            pixels.extend(hex_pixels[i*GLYPH_PIXELS:(i+1)*GLYPH_PIXELS])
        else:
            image = rows(ch, 24, 24, crisp=True)
            pixels.extend(c for row in image[2:24] for c in row[1:23])
    pixels += [0] * (-len(pixels) % 8)
    return [sum(v << (j*2) for j, v in enumerate(pixels[i:i+8])) for i in range(0, len(pixels), 8)]


def qq_icon_words():
    """64px QQ Music logo, 15 colours + index 0 = card white, 4 px/word."""
    source = Image.open(QQ_SOURCE).convert("RGB").crop((25, 25, 225, 225))
    source = source.resize((ICON_SIZE, ICON_SIZE), Image.LANCZOS)
    source = source.filter(ImageFilter.UnsharpMask(radius=0.6, percent=120, threshold=6))
    q = source.quantize(colors=15, method=Image.MEDIANCUT, dither=Image.NONE)
    raw = q.getpalette()
    colors = [(255, 255, 255)] + [tuple(raw[i*3:i*3+3]) for i in range(15)]
    pixels = []
    preview = Image.new("RGB", (ICON_SIZE, ICON_SIZE))
    for y in range(ICON_SIZE):
        for x in range(ICON_SIZE):
            index = 0 if min(source.getpixel((x, y))) >= 236 else int(q.getpixel((x, y))) + 1
            pixels.append(index)
            preview.putpixel((x, y), colors[index])
    QQ_PREVIEW.parent.mkdir(parents=True, exist_ok=True)
    preview.save(QQ_PREVIEW)
    words = [sum(pixels[i+j] << (4*j) for j in range(4)) for i in range(0, len(pixels), 4)]
    return words, colors


def build():
    manifest = json.loads(MANIFEST.read_text(encoding="utf-8"))
    base = list(manifest["glyph_order"])
    songs = [build_song(s) for s in range(6)]
    banks = [songs[s]["lines"] for s in range(6)]
    head_bank = [""] * 32
    for s in range(6):
        for code, text in songs[s]["heads"]:
            head_bank[code & 31] = text
    all_banks = banks + [head_bank, [""] * 32]
    physical, logical, remap_song, k = glyph_layout(banks, base)
    assert physical[0] == " "

    line_words = [0] * (8*32*16)
    for b, texts in enumerate(all_banks):
        for lid, text in enumerate(texts):
            owner = b if b < 6 else (lid - 1) // 5
            for col, ch in enumerate(text):
                line_words[(b*32+lid)*16+col] = logical(owner, ch)
    words = font_words(physical, base)
    bram_words = FONT_BRAM32 * 2048
    ext_words = words[bram_words:]
    assert len(ext_words) <= ICON_BASE
    icon_words, icon_colors = qq_icon_words()
    tail_words = ext_words + [0] * (ICON_BASE - len(ext_words)) + icon_words
    assert len(tail_words) <= 4096

    out = ['// Six-song lyric ROM (20261019): bank 6 holds the song heads; generated by',
           '// sim/generate_dual_lyrics_song6_20261019.py.  Do not edit by hand.',
           '// Event: delta cs[17:6], code[5:0]: 1..20 column done, 32 next boundary,',
           '// 33 sweep start, 63 end of table.',
           'module lyric_event_rom(input I_clk,input [11:0] I_addr,output reg [29:0] O_event);',
           'reg [17:0] rom[0:4095]; reg [17:0] raw; integer n; wire [11:0] dt=raw[17:6];',
           'wire [23:0] samples=raw[5:0]==63 ? 24\'hffffff : ({3\'d0,dt,9\'b0}-{7\'d0,dt,5\'b0});',
           'initial begin for(n=0;n<4096;n=n+1)rom[n]=18\'h3ffff;']
    for s in range(6):
        out += [f"rom[{s*512+i}]=18'h{v:05x};" for i, v in enumerate(songs[s]["events"])]
    out += ['end', 'always @(posedge I_clk)begin raw<=rom[I_addr];O_event<={samples,raw[5:0]};end', 'endmodule',
            '// Row codes are {head,id}; head rows are drawn from line bank 6.',
            'module lyric_boundary_map(input [8:0] I_addr,output reg [5:0] O_current,O_next);',
            'always @* begin O_current=0;O_next=0;case(I_addr)']
    for s in range(6):
        out += [f"9'd{s*64+i}:begin O_current=6'd{cur};O_next=6'd{nxt};end"
                for i, (_, cur, nxt) in enumerate(songs[s]["boundaries"])]
    out += ['endcase end', 'endmodule',
            'module lyric_line_rom(input I_clk,input [11:0] I_addr,input [7:0] I_line,I_next_line,',
            'output reg [8:0] O_char,output reg [4:0] O_length,O_next_length);',
            'reg [8:0] chars[0:4095]; integer n;',
            'initial begin for(n=0;n<4096;n=n+1) chars[n]=0;']
    out += [f"chars[{i}]=9'd{w};" for i, w in enumerate(line_words) if w]
    out += ['end', 'always @(posedge I_clk) O_char<=chars[I_addr];']
    for key, res in (("I_line", "O_length"), ("I_next_line", "O_next_length")):
        out += [f'always @* begin {res}=0;case({key})']
        for b, texts in enumerate(all_banks):
            out += [f"8'd{b*32+i}:{res}=5'd{len(t)};" for i, t in enumerate(texts) if t]
        out += ['endcase end']
    out += ['endmodule',
            f'// {len(physical)} glyphs exceed the 9-bit line ROM ids; song {remap_song} reuses',
            f'// logical ids {512-k}..511 for physical glyphs 512..{511+k}.',
            'module lyric_glyph_map(input [2:0] I_song,input [8:0] I_glyph,output [9:0] O_glyph);']
    if k:
        out.append(f"assign O_glyph=(I_song==3'd{remap_song} && I_glyph>=9'd{512-k}) ? "
                   f"{{1'b0,I_glyph}}+10'd{k} : {{1'b0,I_glyph}};")
    else:
        out.append("assign O_glyph={1'b0,I_glyph};")
    out += ['endmodule',
            '// Music-card title lengths (the card shows the complete song title).',
            'module lyric_title_length(input [2:0] I_song,output reg [2:0] O_length);',
            'always @* begin O_length=0;case(I_song)']
    assert max(map(len, SONG_TITLES)) <= 7
    out += [f"3'd{s}:O_length=3'd{len(t)};" for s, t in enumerate(SONG_TITLES)]
    out += ['endcase end', 'endmodule',
            f'// {ICON_SIZE}px QQ Music logo palette; index 0 is the white card.',
            'module lyric_icon_palette(input [3:0] I_index,output reg [23:0] O_rgb);',
            'always @* case(I_index)']
    out += [f"4'd{i}:O_rgb=24'h{r:02x}{g:02x}{b:02x};" for i, (r, g, b) in enumerate(icon_colors)]
    out += ['endcase', 'endmodule',
            '// The music-card logo is stored in the free tail words and read through',
            '// the second port of the same 9K blocks, so it costs no extra BRAM.',
            'module lyric_font_packed_rom(input I_clk,input [9:0] I_glyph,input [4:0] I_row,I_col,',
            'input I_icon,input [11:0] I_icon_pixel,output [1:0] O_cov,output [3:0] O_icon_index);',
            'wire [18:0] glyph_base=({9\'d0,I_glyph}<<9)-({9\'d0,I_glyph}<<5)+({9\'d0,I_glyph}<<2);',
            'wire [18:0] row_base=({14\'d0,I_row}<<4)+({14\'d0,I_row}<<2)+({14\'d0,I_row}<<1);',
            'wire [18:0] address=glyph_base+row_base+{14\'d0,I_col};',
            f'wire [{FONT_BRAM32*16-1}:0] bank_data;reg [3:0] bank_select;reg [2:0] lane_select;genvar b;',
            f'generate for(b=0;b<{FONT_BRAM32};b=b+1)begin:banks',
            'lyric_font_bram32_bank #(.BANK_ID(b)) ram(I_clk,address[13:3],bank_data[b*16+:16]);end endgenerate',
            f'// 9K BRAM tail: glyphs after the {FONT_BRAM32} EMB32 blocks ({len(ext_words)} words),',
            f'// then the {ICON_SIZE}px logo at word {ICON_BASE}.',
            f'reg [15:0] tail_rom[0:{len(tail_words)-1}];reg [15:0] tail_data;reg [1:0] icon_lane;integer t;',
            f'initial begin for(t=0;t<{len(tail_words)};t=t+1)tail_rom[t]=0;']
    out += [f"tail_rom[{i}]=16'h{w:04x};" for i, w in enumerate(tail_words) if w]
    out += ['end',
            '// Port A serves glyphs, port B the logo: no mux on the glyph address path.',
            'reg [15:0] icon_data;',
            f"wire [11:0] icon_address=12'd{ICON_BASE}+{{2'd0,I_icon_pixel[11:2]}};",
            'always @(posedge I_clk)begin bank_select<=address[17:14];lane_select<=address[2:0];',
            'tail_data<=tail_rom[address[14:3]];end',
            'always @(posedge I_clk)begin icon_lane<=I_icon_pixel[1:0];if(I_icon)icon_data<=tail_rom[icon_address];end',
            'wire [15:0] selected=(bank_select[3:1]==3\'b111) ? tail_data : bank_data[{bank_select,4\'d0}+:16];',
            'assign O_cov=selected[{lane_select,1\'b0}+:2];',
            'assign O_icon_index=icon_data[{icon_lane,2\'b00}+:4];endmodule',
            'module lyric_font_bram32_bank #(parameter BANK_ID=0)(input I_clk,input [10:0] I_addr,output [15:0] O_data);',
            'generate']
    for b in range(FONT_BRAM32):
        out += [f'if(BANK_ID=={b})begin:bank_{b}'] + native_ram('font', words[b*2048:(b+1)*2048], 'I_addr') + ['end']
    out += ['endgenerate', 'endmodule']
    report = {"glyphs": len(physical), "remap_song": remap_song, "remap_count": k,
              "tail_words": len(ext_words),
              "events": [len(s["events"]) for s in songs],
              "boundaries": [len(s["boundaries"]) for s in songs],
              "lyric_rows": [sum(1 for i in lyric_slots() if s["lines"][i]) for s in songs],
              "songs": {s: {"head": [(c & 31, t) for c, t in songs[s]["heads"]],
                            "rows": songs[s]["lines"],
                            "boundaries": songs[s]["boundaries"],
                            "seq": songs[s]["seq"]} for s in range(6)}}
    return out, report


if __name__ == '__main__':
    lines, report = build()
    with open(DEST, 'w', encoding='utf-8', newline='\n') as handle:
        handle.write('\n'.join(lines) + '\n')
    REPORT.parent.mkdir(parents=True, exist_ok=True)
    REPORT.write_text(json.dumps(report, ensure_ascii=False, indent=1), encoding='utf-8')
    print(json.dumps({k: v for k, v in report.items() if k != "songs"}, ensure_ascii=False))
