"""Per-character forced alignment for songs 2..5 (same blocks as 20261015).

align_corrected_song6_20261015.py kept only each row's first/last character
time, so the HDL red sweep was spread evenly over a row.  This pass reuses the
identical audio blocks and lyric text and keeps every character's start/end,
which the ROM generator turns into per-column red events.
"""
from pathlib import Path
import json, os, re, subprocess, sys

ROOT = Path(__file__).resolve().parent.parent
CACHE = ROOT / "tmp/lyrics_asr_20261001"
# Python 3.13 wheels; the 20261001 deps folder only has cp312 binaries.
sys.path.insert(0, str(ROOT / "tmp/lyricfix_20261019/deps313"))
os.environ["HF_HUB_DISABLE_XET"] = "1"
os.environ["HF_HUB_DISABLE_SYMLINKS_WARNING"] = "1"
from faster_whisper import WhisperModel
from faster_whisper.tokenizer import Tokenizer
from faster_whisper.audio import pad_or_trim
import numpy as np

OLD = Path(__file__).resolve().parent / "align_corrected_song6_20261015.py"
_src = OLD.read_text(encoding="utf-8")
SPEC = {}
exec(_src[_src.index("COMBINE = {"):_src.index('if __name__ == "__main__":')], SPEC)
_paths = {}
exec("\n".join(l for l in _src.splitlines() if re.match(r"(FFMPEG|SONG\d) = ", l)), _paths)
FFMPEG = _paths["FFMPEG"]
DEST = ROOT / "tmp/lyricfix_20261019/song_chars_20261019.json"


def no_space(s):
    return re.sub(r"\s+", "", s)


def align_file(source, blocks, song_id, model, tokenizer):
    raw = subprocess.run([FFMPEG, "-v", "error", "-nostdin", "-i", source,
                          "-map", "0:a:0", "-vn", "-ac", "1", "-ar", "16000",
                          "-f", "f32le", "pipe:1"], check=True,
                         stdout=subprocess.PIPE).stdout
    audio = np.frombuffer(raw, dtype="<f4")
    result = []
    for bi, (start, stop, lines) in enumerate(blocks):
        features = model.feature_extractor(audio[round(start*16000):round(stop*16000)])
        words = model.find_alignment(tokenizer, [tokenizer.encode(" ".join(lines))],
                                     model.encode(pad_or_trim(features)),
                                     min(features.shape[-1], 3000))[0]
        chars = []
        for w in words:
            text = no_space(w["word"])
            a = start + float(w["start"]); b = start + float(w["end"])
            for i, ch in enumerate(text):
                chars.append((ch, a + (b-a)*i/len(text), a + (b-a)*(i+1)/len(text)))
        if "".join(c for c, _, _ in chars) != no_space("".join(lines)):
            raise RuntimeError(f"song{song_id} block {bi} alignment mismatch")
        off = 0
        for line in lines:
            n = len(no_space(line))
            span = chars[off:off+n]; off += n
            result.append({"text": line,
                           "start_cs": round(span[0][1]*100), "end_cs": round(span[-1][2]*100),
                           "chars": [[c, round(a*100), round(b*100)] for c, a, b in span]})
        print(f"song{song_id} block {bi+1}/{len(blocks)}", flush=True)
    result.sort(key=lambda x: (x["start_cs"], x["end_cs"]))
    return result


def compact(rows, pairs):
    """Same row merges as the 20261015 timeline, keeping the character spans."""
    pair_map = dict(pairs); out = []; i = 0
    while i < len(rows):
        if i + 1 < len(rows) and pair_map.get(rows[i]["text"]) == rows[i+1]["text"]:
            a, b = rows[i], rows[i+1]
            out.append({"text": a["text"] + " " + b["text"], "start_cs": a["start_cs"],
                        "end_cs": b["end_cs"], "chars": a["chars"] + b["chars"]})
            i += 2
        else:
            out.append(rows[i]); i += 1
    return out


if __name__ == "__main__":
    model = WhisperModel("small", device="cpu", compute_type="int8", cpu_threads=6,
                         download_root=str(CACHE / "models"), local_files_only=True)
    tokenizer = Tokenizer(model.hf_tokenizer, True, task="transcribe", language="zh")
    songs = {2: (_paths["SONG2"], SPEC["S2"]), 3: (_paths["SONG3"], SPEC["S3"]),
             4: (_paths["SONG4"], SPEC["S4"]), 5: (_paths["SONG5"], SPEC["S5"])}
    out = {}
    for sid, (src, blocks) in songs.items():
        out[str(sid)] = compact(align_file(src, blocks, sid, model, tokenizer),
                                SPEC["COMBINE"].get(sid, []))
    DEST.write_text(json.dumps(out, ensure_ascii=False, indent=1), encoding="utf-8")
    print(DEST)
