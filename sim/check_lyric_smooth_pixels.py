"""Independently verify smooth native-24px ROM data and actual ModelSim pixels.

Previews come from the HDL's complete composed frames, not a drawn mockup.
The old 20px checker remains available for the earlier delivered build.
"""
from pathlib import Path
import re
from PIL import Image
from generate_lyric_smooth_assets import parse, events
from generate_home_font_patch import rows

ROOT = Path(__file__).resolve().parent.parent
SIM = ROOT / 'sim/lyrics_20261001'
HDL = ROOT / 'src/user_source/hdl_source'
ASSETS = ROOT / 'assets/lyrics'


def read_hex(path):
    return [int(word, 16) for word in path.read_text(encoding='ascii').split()]


def equal(actual, expected, label):
    assert len(actual) == len(expected), (label, len(actual), len(expected))
    for index, (got, wanted) in enumerate(zip(actual, expected)):
        assert got == wanted, (label, index, got, wanted)


def blend(bg, fg, cov):
    if cov == 1:
        return (bg >> 1) + (bg >> 2) + (fg >> 2)
    if cov == 2:
        return (bg >> 2) + (fg >> 1) + (fg >> 2) + (fg & 1)
    return fg if cov == 3 else bg


def check():
    original, boundaries, unique, glyphs = parse()
    sequence, packed = events()
    # Render from the full native 24px source, independently of font_pixels().
    font = []
    for char in glyphs:
        full = rows(char, 24, 24, crisp=True)
        assert all(not cov for y, row in enumerate(full) for x, cov in enumerate(row)
                   if not (1 <= x < 23 and 2 <= y < 24)), ('cropped nonzero pixel', char)
        font.extend(cov for row in full[2:24] for cov in row[1:23])
    assert len(font) == 64372 and len(glyphs) == 133
    source = (HDL / 'lyric_song_data.v').read_text(encoding='utf-8')
    native = source.split('module lyric_font_bank', 1)[1].split('`else', 1)[1].split('`endif', 1)[0]
    native_banks = {}
    for bank, body in re.findall(r'(\d+): begin(.*?)\n\s*end', native, re.S):
        words = [0] * 512
        seen = set()
        for address, word in re.findall(r"set_word\((\d+),16'h([0-9A-F]+)\);", body):
            address = int(address)
            assert address not in seen and 0 <= address < 512
            seen.add(address)
            words[address] = int(word, 16)
        native_banks[int(bank)] = words
    assert set(native_banks) == set(range(16))
    coverage = []
    for bank in range(16):
        words = read_hex(ASSETS / f'font24_bank_{bank:02d}.hex')
        equal(words, native_banks[bank], f'native vs fast-sim font bank {bank}')
        coverage.extend((word >> (lane * 2)) & 3 for word in words for lane in range(8))
    equal(coverage[:len(font)], font, 'full native 24px coverage')
    assert not any(coverage[len(font):]), 'nonzero padding'
    equal(read_hex(SIM / 'font_cov.hex'), font, 'actual synchronous font port')

    # Verify the NEW hardware ROM, not only the uninstantiated old reference.
    # ID 0 (space) is bypassed; each other glyph has 54 18-bit words, with
    # exactly two zero padding pixels. TD inline init and fast-sim hex must
    # match in every word, including unused bank padding.
    packed_native = source.split('module lyric_packed_font_bank', 1)[1].split('`else', 1)[1].split('`endif', 1)[0]
    packed_banks = {}
    for bank, body in re.findall(r'(\d+): begin(.*?)\n\s*end', packed_native, re.S):
        words = [0] * 512
        seen = set()
        for address, word in re.findall(r"rom\[(\d+)\]=18'h([0-9A-F]+);", body):
            address = int(address)
            assert address not in seen and 0 <= address < 512
            seen.add(address)
            words[address] = int(word, 16)
        packed_banks[int(bank)] = words
    assert set(packed_banks) == set(range(14))
    packed_pixels = []
    for bank in range(14):
        words = read_hex(ASSETS / f'font24_packed_{bank:02d}.hex')
        equal(words, packed_banks[bank], f'packed TD vs ModelSim bank {bank}')
        packed_pixels.extend((word >> (lane * 2)) & 3 for word in words for lane in range(9))
    restored = [0] * 484
    assert not any(font[:484]), 'space glyph must be empty'
    for glyph in range(1, 133):
        begin = (glyph - 1) * 486
        restored.extend(packed_pixels[begin:begin + 484])
        assert not any(packed_pixels[begin + 484:begin + 486])
    equal(restored, font, 'lossless fixed-stride 14-BRAM font')
    assert not any(packed_pixels[132 * 486:]), 'packed ROM padding'
    print('PASS preserved packed9 reference: 14 banks; 64372 exact native 24px antialias pixels')

    # Active hardware uses four native BRAM32K blocks. Independently unpack
    # every INIT bit, including padding, and compare TD to behavioral sim.
    b32 = source.split('module lyric_font_bram32_bank', 1)[1].split('`else', 1)[1]
    b32_pixels = []
    for bank in range(4):
        body = b32.split(f'if(BANK_ID=={bank}) begin: bank_{bank}', 1)[1].split('end', 1)[0]
        entries = re.findall(r"\.INIT_([0-9A-F]{2})\(256'h([0-9A-F]{64})\)", body)
        assert len(entries) == 128 and [int(i, 16) for i, _ in entries] == list(range(128))
        words = [(int(bits, 16) >> (16 * lane)) & 0xffff for _, bits in entries for lane in range(16)]
        equal(read_hex(ASSETS / f'font24_bram32_{bank:02d}.hex'), words, f'BRAM32K TD INIT vs ModelSim bank {bank}')
        b32_pixels.extend((word >> (lane * 2)) & 3 for word in words for lane in range(8))
    equal(b32_pixels[:len(font)], font, 'native BRAM32K exact antialias coverage')
    assert not any(b32_pixels[len(font):]), 'BRAM32K padding'
    print('PASS active BRAM32K font: 4 native blocks; 64372 unchanged antialias pixels; all 512 INIT parameters equal ModelSim hex')
    char_native = source.split('module lyric_char_bram32_rom', 1)[1].split('endmodule', 1)[0]
    entries = re.findall(r"\.INIT_([0-9A-F]{2})\(256'h([0-9A-F]{64})\)", char_native)
    assert len(entries) == 128 and [int(i, 16) for i, _ in entries] == list(range(128))
    char_words = [(int(bits, 16) >> (16 * lane)) & 0xffff for _, bits in entries for lane in range(16)]
    char_reference = [0] * 2048
    for address, gid in re.findall(r"rom\[(\d+)\]=8'd(\d+);", source.split('module lyric_line_rom',1)[1].split('endmodule',1)[0]):
        char_reference[int(address)] = int(gid)
    equal(char_words, char_reference, 'native character INIT vs original lookup')
    equal(read_hex(ASSETS/'char_bram32_reference.hex'), char_reference, 'native character test oracle')
    print('PASS native character ROM: 2048 exact words, original lookup and vendor INIT agree; one additional BRAM32K replaces LUT mux')

    event_source = source.split('module lyric_event_rom', 1)[1].split('endmodule', 1)[0]
    assert "rom[n]=18'h3FFFF" in event_source
    native_events = [0x3FFFF] * 512
    for address, word in re.findall(r"rom\[(\d+)\]=18'h([0-9A-F]+);", event_source):
        native_events[int(address)] = int(word, 16)
    wanted_packed = packed + [0x3FFFF] * (512 - len(packed))
    equal(native_events, wanted_packed, 'native 18-bit delta event storage')
    wanted_expanded = [(((word >> 6) * 480) << 6) | (word & 63) for word in packed]
    wanted_expanded += [(0xFFFFFF << 6) | 63] * (512 - len(packed))
    equal(read_hex(SIM / 'events.hex'), wanted_expanded, 'actual two-stage expanded event port')
    elapsed = 0
    for (centiseconds, command), word in zip(sequence, packed):
        elapsed += (word >> 6) * 480
        assert elapsed == centiseconds * 480 and (word & 63) == command
    bsource = source.split('module lyric_boundary_map', 1)[1].split('endmodule', 1)[0]
    actual_boundaries = [(int(i), int(cur), int(nxt)) for i, cur, nxt in re.findall(
        r"6'd(\d+): begin O_current=5'd(\d+); O_next=5'd(\d+); end", bsource)]
    assert actual_boundaries == [(i, cur, nxt) for i, (_, cur, nxt) in enumerate(boundaries)]
    # Middle instrumental rest must already present the next two sung lines.
    empty_times = [sample // 480 for sample, line in original if sample and not line]
    for cs, cur, nxt in boundaries:
        if cs in empty_times:
            future = [lid for sample,lid in original if sample // 480 > cs and lid]
            if future:
                assert 0 < cur < 22 and 0 < nxt < 22, ('blank interlude', cs, cur, nxt)
            else:
                assert cur == 23 and nxt == 24, ('outro lyric flash', cs, cur, nxt)
    assert (0,23,24) in boundaries and (500,24,25) in boundaries
    assert (1000,25,0) in boundaries
    assert (1600,1,2) in boundaries and (2270,1,2) in boundaries, 'first verse not prepared early'
    assert all(sequence.count((cs,command)) == 1 for cs,command in ((480,5),(980,5),(1580,6)))

    lsource = source.split('module lyric_line_rom', 1)[1].split('endmodule', 1)[0]
    actual_chars = {int(address): int(gid) for address, gid in re.findall(
        r"rom\[(\d+)\]=8'd(\d+);", lsource)}
    glyph_map = {char: index for index, char in enumerate(glyphs)}
    wanted_chars = {lid * 32 + col: glyph_map[char] for lid, text in enumerate(unique)
                    for col, char in enumerate(text)}
    assert actual_chars == wanted_chars
    for output in ('O_length', 'O_next_length'):
        actual_lengths = {int(lid): int(length) for lid, length in re.findall(
            rf"8'd(\d+): {output}=5'd(\d+);", lsource)}
        assert actual_lengths == {lid: len(text) for lid, text in enumerate(unique) if text}

    background = Image.open(ROOT / 'best_result/CAR01.BMP').convert('RGB')
    actual_roi = read_hex(SIM / 'actual_pixels.hex')
    assert background.size == (640, 480) and len(actual_roi) == 640 * 72
    total_ink = total_unchanged = 0
    scenarios = [
        ('preview.ppm', 'lyrics_music_card_20261002_preview.png', 14, 15, 177, False, 0),
        ('intro.ppm', 'lyrics_compact_intro_20261002_preview.png', 23, 24, 81, False, 0),
        ('interlude.ppm', 'lyrics_music_card_prepared_20261002_preview.png', 1, 2, 0, False, 0),
    ]
    for filename, output, cur, nxt, red, intro, stage in scenarios:
        preview = Image.open(SIM / filename).convert('RGB')
        assert preview.size == (640, 480)
        ymin, ymax = 232, 304
        rowspec = [
            (unique[cur], 232, 0), (unique[nxt], 268, 1)]
        row_ink = [0] * len(rowspec)
        red_ink = white_ink = feather_ink = 0
        for y in range(ymin, ymax):
            for x in range(640):
                expected = background.getpixel((x, y))
                # The independent oracle also includes the existing L/R
                # meter labels at y299: they are not lyric background pixels.
                label_l = (39 <= x < 41 and 299 <= y < 313) or (39 <= x < 49 and 311 <= y < 313)
                label_r = ((592 <= x < 594 and 299 <= y < 313) or
                           (592 <= x < 600 and (299 <= y < 301 or 305 <= y < 307)) or
                           (598 <= x < 600 and (301 <= y < 305 or 311 <= y < 313)) or
                           (594 <= x < 596 and 307 <= y < 309) or
                           (596 <= x < 598 and 309 <= y < 311))
                if label_l or label_r:
                    expected = (255, 255, 255)
                cov = 0
                ink = (255, 255, 255)
                for row_index, (text, text_y, selected) in enumerate(rowspec):
                    left = 320 - len(text) * 16
                    if left <= x < left + len(text) * 32 and text_y + 2 <= y < text_y + 24:
                        cindex, cell_x = divmod(x - left, 32)
                        col, row = cell_x - 5, y - text_y - 2
                        if 0 <= col < 22:
                            gid = glyph_map[text[cindex]]
                            cov = font[gid * 484 + row * 22 + col]
                        progressive = selected == 0
                        if progressive and red:
                            relative_x, cursor = x - left, red + 4
                            if relative_x + 2 < cursor:
                                ink = (255, 64, 64)
                            elif relative_x + 1 < cursor:
                                ink = (255, 112, 112)
                            elif relative_x < cursor:
                                ink = (255, 184, 184)
                        if cov:
                            row_ink[row_index] += 1
                            if ink == (255, 64, 64):
                                red_ink += 1
                            elif ink == (255, 255, 255):
                                white_ink += 1
                            elif ink in ((255, 112, 112), (255, 184, 184)):
                                feather_ink += 1
                        break
                expected = tuple(blend(bg, fg, cov) for bg, fg in zip(expected, ink))
                assert preview.getpixel((x, y)) == expected, (filename, x, y, expected)
                if filename == 'preview.ppm':
                    packed_rgb = (expected[0] << 16) | (expected[1] << 8) | expected[2]
                    assert actual_roi[(y - 232) * 640 + x] == packed_rgb, ('actual hex pixel', x, y)
                total_ink += bool(cov)
                total_unchanged += not cov and expected == background.getpixel((x, y))
        assert min(row_ink) > 0, ('missing lyric/credit row', filename, row_ink)
        if filename == 'preview.ppm':
            assert red_ink and white_ink and feather_ink, ('missing smooth-sweep colors', red_ink, white_ink, feather_ink)
        elif filename == 'interlude.ppm':
            assert red_ink == 0 and white_ink > 0 and feather_ink == 0
        # Independent full-card oracle: rounded silhouette, one shared indexed
        # album ROM scaled with 5/8, QQ logo, pause/skip symbols and native title.
        check_music_card(preview, background, unique, glyph_map, font)
        preview.save(ROOT / 'best_result' / output)
        print(f'PASS actual frame {filename}: rows={row_ink}, red={red_ink}, white={white_ink}, feather={feather_ink}')

    visual = (HDL / 'audio_visualizer_overlay.v').read_text(encoding='utf-8')
    osd = (HDL / 'osd_alpha_overlay.v').read_text(encoding='utf-8')
    spectrum_y = int(re.search(r"ROW_TOP\s*=\s*10'd(\d+)", visual)[1])
    scroll_y = int(re.search(r"PANEL_Y\s*=\s*10'd(\d+)", osd)[1])
    assert 304 <= spectrum_y < scroll_y
    overlay = (HDL / 'video_lyric_overlay.v').read_text(encoding='utf-8')
    assert 'wire credit_area' not in overlay and 'F3F2F0' not in overlay, 'intro backing remains'
    log = (SIM / 'actual.log').read_text(encoding='utf-8')
    assert 'PASS actual smooth lyrics:' in log and '5836800 composed pixels;' in log
    assert '373 events' in log and 'scroll unchanged' in log and 'shared music card' in log
    assert '# Errors: 0' in log and '** Fatal:' not in log
    print(f'PASS native/hex/actual 24px font: old 16-bank and packed9 references; active four BRAM32K blocks, {len(font)} exact coverage pixels, zero-only crop')
    print(f'PASS delta time map: {len(sequence)} events, {len(boundaries)} boundaries, 512 addresses')
    print(f'PASS source/native line glyphs: {len(unique)} strings, {len(glyphs)} glyphs')
    print(f'PASS composed lyric/credit regions: {total_ink} ink pixels, {total_unchanged} exact background pixels')
    print(f'PASS non-overlap: lyric clip y304, spectrum y{spectrum_y}, scrolling subtitle y{scroll_y}')
    shared_log = (SIM / 'shared_card.log').read_text(encoding='utf-8')
    assert 'PASS shared music card: 1843200 pixels' in shared_log
    assert '# Errors: 0' in shared_log and '** Fatal:' not in shared_log
    print('PASS homepage pixel-exact to immutable old RTL; alternating modes and card-only confinement')


def check_music_card(preview, background, unique, glyph_map, font):
    art_source = (HDL / 'video_album_cover_rom.v').read_text(encoding='utf-8')
    art = [0] * 2048
    for addr, idx in re.findall(r"rom\[11'd(\d+)\] = 4'd(\d+);", art_source):
        art[int(addr)] = int(idx)
    palettes = []
    for body in re.findall(r'case \(O_index\)(.*?)endcase', art_source, re.S):
        palettes.append({int(idx): tuple(bytes.fromhex(rgb)) for idx, rgb in
                         re.findall(r"4'd(\d+): O_rgb = 24'h([0-9A-F]+);", body)})
    assert len(palettes) == 2
    qq_palette, cover_palette = palettes
    inset = [8,5,4,3,2,1,1,1]
    title = unique[26]
    assert title == '告白气球'
    for y in range(128, 212):
        for x in range(144, 496):
            edge = min(y - 128, 211 - y)
            cut = inset[edge] if edge < 8 else 0
            dx, rx = x - 144, 495 - x
            expected = background.getpixel((x, y))
            if dx >= cut and rx >= cut:
                border = edge == 0 or dx == cut or rx == cut
                expected = (220,228,235) if border else (255,255,255)
                if 160 <= x < 224 and 136 <= y < 200:
                    idx = art[((y-136)*5//8)*40+(x-160)*5//8]
                    if idx: expected = cover_palette[idx]
                if 392 <= x < 412 and 146 <= y < 166:
                    idx = art[1600+(y-146)*20+x-392]
                    if idx: expected = qq_palette[idx]
                if 180 <= y < 193:
                    dy = abs(y-186)
                    prev, pause, nxt = x-248, x-328, x-400
                    is_prev = 0 <= prev < 3 or (5 <= prev < 16 and dy <= (prev-5)//2)
                    is_pause = 0 <= pause < 3 or 7 <= pause < 10
                    is_next = 13 <= nxt < 16 or (0 <= nxt < 12 and dy <= (11-nxt)//2)
                    if is_prev or is_next: expected = (51,75,94)
                    if is_pause: expected = (37,107,177)
            if 248 <= x < 376 and 146 <= y < 168:
                index, cell = divmod(x-248,32)
                col = cell-5
                if 0 <= col < 22:
                    cov = font[glyph_map[title[index]]*484+(y-146)*22+col]
                    expected = tuple(blend(bg,fg,cov) for bg,fg in zip(expected,(29,48,66)))
            assert preview.getpixel((x,y)) == expected, ('music card',x,y,expected,preview.getpixel((x,y)))
    print('PASS independent composed music card: 29568 pixels; shared cover/QQ ROM, native 24px title, rounded border and controls')


if __name__ == '__main__':
    check()
