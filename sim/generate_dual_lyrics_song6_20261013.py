"""Generate six-song lyric/event/font ROMs for the dual-board player.

Songs 0..1 use the checked-in aligned assets. Songs 2..5 use the corrected
lyrics supplied by the user and locally forced-aligned timelines.
"""
from pathlib import Path
import json, math, re
from generate_lyric_smooth_assets import parse as parse_song0, events as events_song0
from generate_home_font_patch import rows

ROOT = Path(__file__).resolve().parent.parent
DEST = ROOT / "dual_board/image_link/rtl/dualsong_20261005/dual_lyric_song_data.v"
MANIFEST = ROOT / "assets/lyrics/dualsong_20261005/rom_manifest.json"

SONG2_LINES = [
    (2998, "时光是琥珀 泪一滴滴被反锁"), (3496, "情书再不朽 也磨成沙漏"),
    (3868, "青春的上游 白云飞走"), (4628, "苍狗与海鸥 闪过的年头"),
    (4998, "潺潺的流走 命运好幽默"), (5298, "让爱的人都沉默"),
    (5948, "一整个宇宙 换一颗红豆"), (6622, "回忆如困兽 寂寞太久"),
    (7128, "而渐渐温柔 放开了拳头"), (7700, "反而更自由 慢动作"),
    (8048, "缱绻着 重播那一瞬间"), (8718, "我们在告别的演唱会"),
    (9164, "说好不再见 你写给我"), (9388, "我的第一首歌 你和我"),
    (10022, "十指紧扣 摸着肩头"), (10554, "可是那然后呢"),
    (10832, "还好我有我 这一首情歌"), (11418, "轻轻的轻轻哼着"),
    (13970, "明明好幽默 让爱的人都沉默"), (16096, "放开了拳头 反而更自由"),
    (19710, "还好我有我 这一首情歌"),
]
SONG_CREDITS = [
    ["周杰伦 · 告白气球", "词：方文山", "曲：周杰伦", "编曲：林迈可", "告白气球"],
    ["周杰伦 · 一路向北", "词：方文山", "曲：周杰伦", "编曲：蔡科俊", "一路向北"],
    ["情歌-梁静茹(Fish)", "词：陈没", "作曲：伍冠谚", "编曲：陈建骐", ""],
    ["周杰伦-我落泪情绪零碎", "词：方文山", "曲：周杰伦", "编曲：钟兴民", ""],
    ["周杰伦-搁浅", "词：宋健彰", "曲：周杰伦", "编曲：钟兴民", ""],
    ["枫-周杰伦", "词：弹头(宋健彰)", "曲：周杰伦", "编曲：钟兴民", "制作人：周杰伦"],
]
SONG_TITLES = ["告白气球", "一路向北", "情歌", "我落泪情绪零碎", "搁浅", "枫"]

CORRECTED_TIMELINE = ROOT / "tmp/corrected_song_lines_20261015.json"
# These characters are easy to lose when the font is compressed by frequency,
# but they are part of the user-verified lines and must remain visible.
PROTECTED_LYRIC_CHARS = set("分手起风这个季节忍住感觉带刺伤人的很直接")

def han_text(text):
    text = ''.join(c for c in text if '\u3400' <= c <= '\u9fff')
    return text[:16]

def asr_lines(song_id, max_lines=26):
    src = ROOT / f"tmp/song{song_id}_transcription_20261013.json"
    data = json.loads(src.read_text(encoding="utf-8"))
    raw = []
    for seg in data["segments"]:
        text = han_text(seg.get("text", ""))
        if len(text) < 2:
            continue
        start = int(round(float(seg["start"]) * 100))
        end = int(round(float(seg["end"]) * 100))
        if raw and start <= raw[-1][0]:
            continue
        # A long ASR segment is divided into display rows and keeps its time.
        chunks = [text[i:i+16] for i in range(0, len(text), 16)]
        for k, chunk in enumerate(chunks):
            if not chunk:
                continue
            a = start + (end-start)*k//len(chunks)
            raw.append((a, chunk))
    # Keep rows distributed through the complete song instead of only the intro.
    if len(raw) > max_lines:
        raw = [raw[(i*(len(raw)-1))//(max_lines-1)] for i in range(max_lines)]
    return raw

def pack_line_set(lyrics, credits, title):
    # Line 26 is reserved for the song title shown by video_lyric_overlay.
    # Rows 1..25 and 27..31 hold up to 30 unique lyric rows. Repeated verses
    # reuse a row, so the full corrected lyrics fit without losing timing.
    unique = []
    for item in lyrics:
        text = item[-1]
        if text not in unique:
            unique.append(text)
    assert len(unique) <= 30, (len(unique), unique)
    lines = [""] * 32
    for i, text in enumerate(unique):
        lid = i + 1 if i < 25 else i + 2
        lines[lid] = text
    # The full five-line credit page is rendered by the shared lyric overlay;
    # keep the lyric title row short for the normal two-row overlay.
    lines[26] = title
    assert len(lines) == 32 and max(map(len, lines)) <= 16
    return lines

def row_id_map(lyrics):
    unique = []
    for item in lyrics:
        text = item[-1]
        if text not in unique:
            unique.append(text)
    return {text: (i + 1 if i < 25 else i + 2) for i, text in enumerate(unique)}

def repair_yilu_timeline(manifest):
    """Rebuild song 1 events so the last visible column precedes boundaries."""
    karaoke_path = ROOT / "assets/lyrics/dualsong_20261005/YILU_USER_AUDIO.karaoke.json"
    if not karaoke_path.exists():
        return [tuple(v) for v in manifest["boundaries1"]], [int(v) for v in manifest["events1"]]
    karaoke = json.loads(karaoke_path.read_text(encoding="utf-8"))
    rows = manifest["lines1"]
    boundaries = [(0, 23, 24), (500, 24, 25), (1000, 25, 0), (1600, 1, 2)]
    pending = {0: (3, 32), 500: (3, 32), 1000: (3, 32), 1600: (3, 32)}
    for i, line in enumerate(karaoke["lines"]):
        cs = int(line["lrc_start_cs"])
        lid = rows.index(line["text"])
        nxt = rows.index(karaoke["lines"][i+1]["text"]) if i+1 < len(karaoke["lines"]) else 0
        boundaries.append((cs, lid, nxt)); pending[cs] = (3, 32)
        next_cs = (int(karaoke["lines"][i+1]["lrc_start_cs"])
                   if i+1 < len(karaoke["lines"]) else 29700)
        for col, ch in enumerate(line["text"]):
            if ch.isspace():
                continue
            end = min(max(cs + 1, int(line["char_end_cs"][col])), next_cs - 1)
            code = col + 1
            old = pending.get(end)
            if old is None or old[0] < 2 or (old[0] == 2 and old[1] < code):
                pending[end] = (2, code)
        finish = int(line["char_end_cs"][-1]) + 80
        if finish + 150 < next_cs:
            future = (rows.index(karaoke["lines"][i+2]["text"])
                      if i+2 < len(karaoke["lines"]) else 0)
            cur, preview = (nxt, future) if nxt else (23, 24)
            boundaries.append((finish, cur, preview)); pending[finish] = (3, 32)
    # Keep the established bank-1 event count; this inert marker preserves
    # the final quiet interval without changing lyric state or red progress.
    if len(pending) < 358:
        pending[29600] = (0, 33)
    boundaries.sort()
    packed, previous = [], 0
    for cs, (_, code) in sorted(pending.items()):
        packed.append(((cs - previous) << 6) | code)
        previous = cs
    return boundaries, packed

def song_events(lyrics, lines):
    row_ids = row_id_map(lyrics)
    # Keep the song head visible through the instrumental intro.  These
    # markers preserve the compact event count without forcing line 0 before
    # the first vocal onset.
    boundaries = [(0, 26, 26), (500, 26, 26), (1000, 26, 26), (1600, 26, 26)]
    for i, item in enumerate(lyrics):
        cs, _, text = item
        cur = row_ids[text]
        nxt = row_ids[lyrics[i + 1][2]] if i + 1 < len(lyrics) else 0
        boundaries.append((cs, cur, nxt))
    boundaries.sort()
    pending = {cs: (3, 32) for cs, _, _ in boundaries}
    for cs, lid in ((480, 27), (980, 28), (1480, 29)):
        pending[cs] = (2, len(lines[lid]))
    for i, (start, end_cs, text) in enumerate(lyrics):
        next_cs = lyrics[i+1][0] if i+1 < len(lyrics) else 30000
        # The red sweep is measured in rendered character columns.  Spaces
        # occupy a column on screen even though they do not have a glyph, so
        # retain their width in the event code and only omit them as events.
        visible = [(pos + 1, c) for pos, c in enumerate(text) if not c.isspace()]
        if not visible:
            continue
        # The alignment file has a real vocal end for every line.  Using the
        # next onset here stretches the sweep through instrumental gaps and
        # makes the red text lag behind the singing.
        span_end = min(max(start + 1, int(end_cs)), next_cs - 1)
        for k, (column, _) in enumerate(visible):
            end = start + ((span_end-start)*(k+1))//len(visible)
            end = max(start+1, min(end, next_cs-1))
            old = pending.get(end)
            if old is None or old[0] < 2 or (old[0] == 2 and old[1] < column):
                pending[end] = (2, column)
    packed, previous = [], 0
    for cs, (_, code) in sorted(pending.items()):
        delta = cs - previous
        assert 0 <= delta <= 4095 and code <= 33
        packed.append((delta << 6) | code)
        previous = cs
    assert len(packed) <= 512
    return boundaries, packed

def native_ram(name, words, addr):
    words = list(words) + [0] * (2048-len(words))
    out = ['EG_PHY_BRAM32K #(.MODE("DP16K"),.DATA_WIDTH_A("16"),.DATA_WIDTH_B("16"),',
           '.REGMODE_A("NOREG"),.REGMODE_B("NOREG"),']
    for i in range(128):
        value = sum(w << (j*16) for j,w in enumerate(words[i*16:(i+1)*16]))
        out.append(f'.INIT_{i:02X}(256\'h{value:064X})' + (',' if i < 127 else ')'))
    out += [f'{name}(.doa(O_data),.dia(16\'d0),.addra({addr}),.bytea(1\'b0),.bytewea(1\'b0),',
            '.csa(1\'b1),.wea(1\'b0),.clka(I_clk),.rsta(1\'b0),.ocea(1\'b1),',
            '.dob(),.dib(16\'d0),.addrb(11\'d0),.byteb(1\'b0),.byteweb(1\'b0),',
            '.csb(1\'b0),.web(1\'b0),.clkb(1\'b0),.rstb(1\'b0),.oceb(1\'b0));']
    return out

def build():
    _, boundaries0, lines0, _ = parse_song0()
    _, events0 = events_song0()
    manifest = json.loads(MANIFEST.read_text(encoding="utf-8"))
    lines1 = manifest["lines1"]
    boundaries1, events1 = repair_yilu_timeline(manifest)
    if not CORRECTED_TIMELINE.exists():
        raise SystemExit(f"missing corrected alignment: {CORRECTED_TIMELINE}")
    corrected = json.loads(CORRECTED_TIMELINE.read_text(encoding="utf-8"))
    song_lyrics = {sid: [(int(row["start_cs"]), int(row["end_cs"]), row["text"])
                         for row in corrected[str(sid)]] for sid in (2, 3, 4, 5)}
    all_lines = [lines0, lines1]
    all_bounds = [boundaries0, boundaries1]
    all_events = [events0, events1]
    for sid in (2,3,4,5):
        lines = pack_line_set(song_lyrics[sid], SONG_CREDITS[sid], SONG_TITLES[sid])
        bounds, events = song_events(song_lyrics[sid], lines)
        all_lines.append(lines); all_bounds.append(bounds); all_events.append(events)
    glyphs = list(manifest["glyph_order"])
    for bank in all_lines:
        for text in bank:
            for char in text:
                if char not in glyphs: glyphs.append(char)
    # The five-line song head shares the lyric overlay font. Keep all credit
    # characters in the shared font pool while trimming rare lyric-only
    # characters below the fourteen-font-bank limit.
    for credits in SONG_CREDITS:
        for text in credits:
            for char in text:
                if char not in glyphs: glyphs.append(char)
    # The EG4S20 has sixteen EMB32 blocks.  The six-song event table uses two,
    # so keep the font at fourteen blocks.  Rare ASR-only characters become a
    # blank cell; common lyric characters and all original three-song glyphs
    # remain intact.
    while len(glyphs) > 473:
        used = {}
        for bank in all_lines[3:6]:
            for text in bank:
                for char in text:
                    if char not in set(manifest["glyph_order"]):
                        used[char] = used.get(char, 0) + 1
        if not used:
            break
        candidates = [c for c in used if c not in PROTECTED_LYRIC_CHARS]
        if not candidates:
            break
        drop = min(candidates, key=lambda c: (used[c], ord(c)))
        for bi in range(3, 6):
            all_lines[bi] = [text.replace(drop, " ") for text in all_lines[bi]]
        glyphs = list(manifest["glyph_order"])
        for bank in all_lines:
            for text in bank:
                for char in text:
                    if char not in glyphs: glyphs.append(char)
        for credits in SONG_CREDITS:
            for text in credits:
                for char in text:
                    if char not in glyphs: glyphs.append(char)
    assert len(glyphs) <= 512
    line_words = [0] * (6*32*16)
    for bank, texts in enumerate(all_lines):
        for lid, text in enumerate(texts):
            for col, char in enumerate(text):
                line_words[(bank*32+lid)*16+col] = glyphs.index(char)
    credit_words = [0] * (6 * 5 * 16)
    credit_lengths = []
    for bank, credits in enumerate(SONG_CREDITS):
        credit_lengths.extend(len(text) for text in credits)
        for lid, text in enumerate(credits):
            for col, char in enumerate(text):
                credit_words[(bank*5+lid)*16+col] = glyphs.index(char)
    pixels = []
    for b in range(16):
        values = [int(x,16) for x in (ROOT/f"assets/lyrics/font24_bank_{b:02d}.hex").read_text().split()]
        pixels.extend((v>>(c*2))&3 for v in values for c in range(8))
    pixels = pixels[:133*484]
    for char in glyphs[133:]:
        image = rows(char,24,24,crisp=True)
        pixels.extend(c for row in image[2:24] for c in row[1:23])
    font_banks = (len(pixels)+16383)//16384
    font_words = [sum(v<<(j*2) for j,v in enumerate(pixels[i:i+8])) for i in range(0,len(pixels),8)]
    font_words += [0]*(font_banks*2048-len(font_words))
    out = ['// Six-song lyric ROM. Songs 3..5 are locally transcribed from supplied MP3s.',
           'module lyric_event_rom(input I_clk,input [11:0] I_addr,output reg [29:0] O_event);',
           'reg [17:0] rom[0:4095]; reg [17:0] raw; integer n; wire [11:0] dt=raw[17:6];',
           'wire [23:0] samples=raw[5:0]==63 ? 24\'hffffff : ({3\'d0,dt,9\'b0}-{7\'d0,dt,5\'b0});',
           'initial begin for(n=0;n<4096;n=n+1)rom[n]=18\'h3ffff;']
    for b, evs in enumerate(all_events):
        out += [f'rom[{b*512+i}]=18\'h{v:05x};' for i,v in enumerate(evs)]
    out += ['end','always @(posedge I_clk)begin raw<=rom[I_addr];O_event<={samples,raw[5:0]};end','endmodule',
            'module lyric_boundary_map(input [8:0] I_addr,output reg [4:0] O_current,O_next);',
            'always @* begin O_current=0;O_next=0;case(I_addr)']
    for b, bounds in enumerate(all_bounds):
        out += [f"9'd{b*64+i}:begin O_current=5'd{cur};O_next=5'd{nxt};end" for i,(_,cur,nxt) in enumerate(bounds)]
    out += ['endcase end','endmodule',
            'module lyric_line_rom(input I_clk,input [11:0] I_addr,input [7:0] I_line,I_next_line,',
            'output reg [8:0] O_char,output reg [4:0] O_length,O_next_length);',
            'reg [8:0] chars[0:3071]; integer n;',
            'initial begin for(n=0;n<3072;n=n+1) chars[n]=0;']
    for i,w in enumerate(line_words): out.append(f'chars[{i}]=9\'d{w};')
    out += ['end','always @(posedge I_clk) O_char<=chars[I_addr];']
    for key,res in (("I_line","O_length"),("I_next_line","O_next_length")):
        out += [f'always @* begin {res}=0;case({key})']
        for b,texts in enumerate(all_lines):
            out += [f"8'd{b*32+i}:{res}=5'd{len(t)};" for i,t in enumerate(texts) if t]
        out += ['endcase end']
    out += ['endmodule',
            '// Credit strings are a LUT case table. Keeping this small page out of',
            '// BRAM is required because the shared font already uses all sixteen',
            '// EG4S20 EMB32 blocks.',
            'module lyric_credit_rom(input I_clk,input [2:0] I_song,input [2:0] I_line,input [3:0] I_col,',
            'output reg [8:0] O_char,output reg [4:0] O_length);',
            'always @* begin O_char=9\'d0;case({I_song,I_line,I_col})']
    for bank in range(6):
        for lid in range(5):
            for col in range(16):
                i = (bank*5+lid)*16+col
                key = (bank<<7) | (lid<<4) | col
                out.append(f"10'd{key}:O_char=9'd{credit_words[i]};")
    out += ['endcase end',
            'always @* begin O_length=0;case({I_song,I_line})']
    for bank in range(6):
        for lid in range(5):
            i = bank*5+lid
            key = (bank<<3) | lid
            out.append(f"6'd{key}:O_length=5'd{credit_lengths[i]};")
    out += ['endcase end','endmodule',
            'module lyric_font_packed_rom(input I_clk,input [8:0] I_glyph,input [4:0] I_row,I_col,output [1:0] O_cov);',
            'wire [18:0] glyph_base=({10\'d0,I_glyph}<<9)-({10\'d0,I_glyph}<<5)+({10\'d0,I_glyph}<<2);',
            'wire [18:0] row_base=({14\'d0,I_row}<<4)+({14\'d0,I_row}<<2)+({14\'d0,I_row}<<1);',
            'wire [18:0] address=glyph_base+row_base+{14\'d0,I_col};',
            f'wire [{font_banks*16-1}:0] bank_data;reg [{max(1,math.ceil(math.log2(font_banks)))-1}:0] bank_select;reg [2:0] lane_select;genvar b;',
            f'generate for(b=0;b<{font_banks};b=b+1)begin:banks',
            'lyric_font_bram32_bank #(.BANK_ID(b)) ram(I_clk,address[13:3],bank_data[b*16+:16]);end endgenerate',
            'always @(posedge I_clk)begin bank_select<=address[17:14];lane_select<=address[2:0];end',
            'wire [15:0] selected=bank_data[{bank_select,4\'d0}+:16];assign O_cov=selected[{lane_select,1\'b0}+:2];endmodule',
            'module lyric_font_bram32_bank #(parameter BANK_ID=0)(input I_clk,input [10:0] I_addr,output [15:0] O_data);',
            'generate']
    for b in range(font_banks):
        out += [f'if(BANK_ID=={b})begin:bank_{b}'] + native_ram('font',font_words[b*2048:(b+1)*2048],'I_addr') + ['end']
    out += ['endgenerate','endmodule']
    return out, {'glyphs':len(glyphs),'events':[len(x) for x in all_events], 'font_banks':font_banks}

if __name__ == '__main__':
    lines, info = build(); DEST.write_text('\n'.join(lines)+'\n',encoding='utf-8'); print(json.dumps(info,ensure_ascii=False))
