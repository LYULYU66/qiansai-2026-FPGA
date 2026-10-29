"""Write the expected schedule/font used by tb_lyric_sync_20261019 and tb_lyric_font_20261019."""
import json
import generate_dual_lyrics_song6_20261019 as g

OUT = g.ROOT / "dual_board/image_link/sim/dualsong_20261005/lyricfix_20261019"

if __name__ == "__main__":
    _, rep = g.build()
    base = json.loads(g.MANIFEST.read_text(encoding="utf-8"))["glyph_order"]
    physical, logical, remap_song, k = g.glyph_layout([rep["songs"][s]["rows"] for s in range(6)], base)
    OUT.mkdir(exist_ok=True)
    (OUT / "font_words.hex").write_text("\n".join(f"{w:04x}" for w in g.font_words(physical, base)) + "\n")
    expected, counts = [], []
    for s in range(6):
        bounds = iter(rep["songs"][s]["boundaries"])
        bias = 5760 if s == 1 else 0          # SONG1_TIMING_BIAS in the RTL
        for cs, code in rep["songs"][s]["seq"]:
            cur = nxt = 0
            if code == g.CODE_BOUNDARY:
                _, cur, nxt = next(bounds)
            expected.append(f"{s} {cs*480+bias} {code} {cur} {nxt}")
        counts.append(len(rep["songs"][s]["seq"]))
    (OUT / "expected_events.txt").write_text("\n".join(expected) + "\n")
    (OUT / "event_counts.vh").write_text("".join(f"localparam integer EVENTS_{s}={n};\n" for s, n in enumerate(counts)))
    # Physical glyph ids expected in the overlay cache for every row.
    cache = []
    for s in range(6):
        for lid, text in enumerate(rep["songs"][s]["rows"]):
            if text:
                cache.append(f"{s} {s} {lid} " + " ".join(str(physical.index(c)) for c in text))
        for hid, text in rep["songs"][s]["head"]:
            cache.append(f"{s} 6 {hid} " + " ".join(str(physical.index(c)) for c in text))
    (OUT / "expected_rows.txt").write_text("\n".join(cache) + "\n", encoding="utf-8")
    # Same rows as fixed 20-word records for $readmemh: song bank id len ids[16].
    words = []
    for row in cache:
        f = list(map(int, row.split()))
        ids = f[3:]
        words += [f[0], f[1], f[2], len(ids)] + ids + [0] * (16 - len(ids))
    (OUT / "expected_rows.hex").write_text("\n".join(f"{w:03x}" for w in words) + "\n")
    (OUT / "row_counts.vh").write_text(f"localparam integer ROWS={len(cache)};\n"
                                       f"localparam integer GLYPHS={len(physical)};\n")
    print("events", counts, "glyphs", len(physical), "font words", len(g.font_words(physical, base)))
