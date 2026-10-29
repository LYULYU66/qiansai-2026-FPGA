"""Independently check native lyric ROMs and real ModelSim composed pixels.

The PNG is the simulator's complete HDMI image, not a separately drawn mockup.
Both lyric rows, red progress, and all unpainted ROI pixels must match exactly.
"""
from pathlib import Path
import re
from PIL import Image
from generate_lyric_assets import parse, karaoke_events
from generate_home_font_patch import rows


ROOT = Path(__file__).resolve().parent.parent
SIM = ROOT / "sim/lyrics_20261001"
HDL = ROOT / "src/user_source/hdl_source"
ASSETS = ROOT / "assets/lyrics"
OUTPUT = ROOT / "best_result/lyrics_page2_20261001_preview.png"
ROI_TOP, ROI_BOTTOM = 232, 290
CURRENT_Y, NEXT_Y = 236, 264


def read_hex(path):
    return [int(word, 16) for word in path.read_text(encoding="ascii").split()]


def require_equal(actual, expected, description):
    assert len(actual) == len(expected), (description, len(actual), len(expected))
    for index, (got, wanted) in enumerate(zip(actual, expected)):
        assert got == wanted, (description, index, got, wanted)


def native_font_words(source, banks):
    font_source = source.split("module lyric_font_bank", 1)[1]
    native = font_source.split("`else", 1)[1].split("`endif", 1)[0]
    parsed = {}
    for bank, body in re.findall(r"(\d+): begin(.*?)\n\s*end", native, re.S):
        words = [0] * 512
        for address, value in re.findall(r"set_word\((\d+),16'h([0-9A-F]+)\);", body):
            address = int(address)
            assert 0 <= address < 512
            assert words[address] == 0, ("duplicate native font address", bank, address)
            words[address] = int(value, 16)
        parsed[int(bank)] = words
    assert set(parsed) == set(range(banks)), ("native ROM bank IDs", sorted(parsed))
    return parsed


def blend(background, ink, coverage):
    if coverage == 1:
        return (background >> 1) + (background >> 2) + (ink >> 2)
    if coverage == 2:
        return (background >> 2) + (ink >> 1) + (ink >> 2) + (ink & 1)
    if coverage == 3:
        return ink
    return background


def check():
    _, unique_lines, glyphs = parse()
    events = karaoke_events()
    font_pixels = [coverage for char in glyphs
                   for row in rows(char, 20, 20, crisp=True) for coverage in row]
    bank_count = (len(font_pixels) + 4095) // 4096
    source = (HDL / "lyric_song_data.v").read_text(encoding="utf-8")
    native = native_font_words(source, bank_count)
    packed_pixels = []
    for bank in range(bank_count):
        words = read_hex(ASSETS / f"font_bank_{bank:02d}.hex")
        require_equal(words, native[bank], f"native vs fast-sim bank {bank}")
        packed_pixels.extend((word >> (lane * 2)) & 3
                             for word in words for lane in range(8))
    require_equal(packed_pixels[:len(font_pixels)], font_pixels, "generated font coverage")
    assert not any(packed_pixels[len(font_pixels):]), "nonzero font padding"
    require_equal(read_hex(SIM / "font_cov.hex"), font_pixels,
                  "actual synchronous native font ROM")
    # Independent content oracle: each cached glyph and both line lengths
    # must be derived from the transcript, not from DUT cached data.
    line_source = source.split("module lyric_line_rom", 1)[1].split("endmodule", 1)[0]
    native_characters = {int(address): int(glyph)
                         for address, glyph in re.findall(r"rom\[(\d+)\] = 8'd(\d+);", line_source)}
    glyph_map = {char: index for index, char in enumerate(glyphs)}
    wanted_characters = {line_id * 32 + col: glyph_map[char]
                         for line_id, text in enumerate(unique_lines)
                         for col, char in enumerate(text)}
    assert native_characters == wanted_characters, "line ROM differs from source text"
    wanted_lengths = {line_id: len(text) for line_id, text in enumerate(unique_lines) if text}
    for output_name in ("O_length", "O_next_length"):
        native_lengths = {int(line_id): int(length) for line_id, length in re.findall(
            rf"8'd(\d+): {output_name}=5'd(\d+);", line_source)}
        assert native_lengths == wanted_lengths, ("line-length lookup differs", output_name)
    # Compare the hardware's inline 30-bit storage separately from both the
    # generator events and the simulator's expanded 39-bit synchronous port.
    event_source = source.split("module lyric_event_rom", 1)[1].split("endmodule", 1)[0]
    assert "rom[n]=30'h3FFF8000" in event_source, "event unused-slot initializer changed"
    native_events = [0x3FFF8000] * 512
    for address, word in re.findall(r"rom\[(\d+)\] = 30'h([0-9A-F]+);", event_source):
        address = int(address)
        assert 0 <= address < 512
        native_events[address] = int(word, 16)
    expected_packed_events = [(cs << 15) | (current << 10) | (following << 5) | sung
                              for cs, current, following, sung in events]
    expected_packed_events += [0x3FFF8000] * (512 - len(events))
    require_equal(native_events, expected_packed_events, "native packed karaoke ROM")
    expected_events = [((cs * 480) << 15) | (current << 10) | (following << 5) | sung
                       for cs, current, following, sung in events]
    expected_events += [(0xFFFFFF << 15)] * (512 - len(events))
    require_equal(read_hex(SIM / "events.hex"), expected_events, "actual karaoke event ROM")

    overlay = (HDL / "video_lyric_overlay.v").read_text(encoding="utf-8")
    assert "CURRENT_Y = 10'd236" in overlay and "NEXT_Y = 10'd264" in overlay
    assert "wire panel_hit" not in overlay and "wire [23:0] backing" not in overlay, \
        "obsolete lyric backing remains in HDL"
    testbench = (ROOT / "sim/tb_lyric_actual_pixels.sv").read_text(encoding="utf-8")
    line_match = re.search(r"reg \[7:0\] line=(\d+),next_line=(\d+);", testbench)
    sung_match = re.search(r"reg \[4:0\] sung_chars=(\d+);", testbench)
    assert line_match and sung_match, "actual simulator lyric scenario was not found"
    current_id, next_id = int(line_match[1]), int(line_match[2])
    sung_count = int(sung_match[1])
    lyric_rows = [(unique_lines[current_id], CURRENT_Y, sung_count),
                  (unique_lines[next_id], NEXT_Y, 0)]
    background = Image.open(ROOT / "best_result/CAR01.BMP").convert("RGB")
    preview = Image.open(SIM / "preview.ppm").convert("RGB")
    assert background.size == preview.size == (640, 480)
    actual_pixels = read_hex(SIM / "actual_pixels.hex")
    assert len(actual_pixels) == 640 * (ROI_BOTTOM - ROI_TOP)
    text_pixels = unchanged_pixels = red_pixels = white_pixels = 0
    row_pixels = [0, 0]
    for y in range(ROI_TOP, ROI_BOTTOM):
        for x in range(640):
            expected = background.getpixel((x, y))
            coverage = 0
            ink = (255, 255, 255)
            for row_index, (text, text_y, sung) in enumerate(lyric_rows):
                left, right = 320 - len(text) * 12, 320 + len(text) * 12
                if left <= x < right and text_y <= y < text_y + 20:
                    character, cell_col = divmod(x - left, 24)
                    col = cell_col - 2
                    if 0 <= col < 20:
                        glyph_id = glyph_map[text[character]]
                        coverage = font_pixels[glyph_id * 400 + (y - text_y) * 20 + col]
                    if character < sung:
                        ink = (255, 64, 64)
                    if coverage:
                        row_pixels[row_index] += 1
                    break
            if coverage:
                text_pixels += 1
                if ink == (255, 64, 64):
                    red_pixels += 1
                else:
                    white_pixels += 1
                expected = tuple(blend(channel, color, coverage)
                                 for channel, color in zip(expected, ink))
            else:
                unchanged_pixels += 1
            packed_expected = (expected[0] << 16) | (expected[1] << 8) | expected[2]
            index = (y - ROI_TOP) * 640 + x
            assert actual_pixels[index] == packed_expected, (
                "dual lyric actual pixel", x, y, actual_pixels[index], packed_expected)
            assert preview.getpixel((x, y)) == expected, ("composed PPM pixel", x, y)
    assert min(row_pixels) > 0 and red_pixels > 0 and white_pixels > 0, \
        ("missing row/red/white coverage", row_pixels, red_pixels, white_pixels)

    visualizer = (HDL / "audio_visualizer_overlay.v").read_text(encoding="utf-8")
    spectrum_top = int(re.search(r"ROW_TOP\s*=\s*10'd(\d+)", visualizer)[1])
    osd = (HDL / "osd_alpha_overlay.v").read_text(encoding="utf-8")
    scroll_top = int(re.search(r"PANEL_Y\s*=\s*10'd(\d+)", osd)[1])
    assert CURRENT_Y + 20 <= NEXT_Y and NEXT_Y + 20 <= spectrum_top < scroll_top, \
        "two lyric rows overlap spectrum or scrolling subtitle"
    log = (SIM / "actual.log").read_text(encoding="utf-8")
    assert "PASS actual dual lyrics:" in log
    assert f"{len(events)} real-time events" in log
    assert "3072000 composed pixels;" in log
    assert "text-only, scroll unchanged" in log
    assert "# Errors: 0" in log and "** Fatal:" not in log
    preview.save(OUTPUT)
    print(f"PASS native/fast/generated/actual font: {bank_count} banks, {len(font_pixels)} pixels")
    print(f"PASS source/native line glyphs: {len(unique_lines)} unique lines")
    print(f"PASS actual karaoke ROM: {len(events)} timed entries, 512 checked addresses")
    print(f"PASS dual text-only ROI: {len(actual_pixels)} pixels, "
          f"{red_pixels} red + {white_pixels} white, {unchanged_pixels} exact original pixels")
    print(f"PASS layout: current y236..255, next y264..283; spectrum y{spectrum_top}; "
          f"scroll y{scroll_top}; {spectrum_top - 284}px clear gap")
    print(f"PNG: {OUTPUT}")


if __name__ == "__main__":
    check()
