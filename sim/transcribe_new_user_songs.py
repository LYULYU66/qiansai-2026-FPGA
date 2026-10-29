"""Transcribe the three user-supplied MP3 files locally for lyric timing."""
from pathlib import Path
import json
import os
import subprocess
import sys

ROOT = Path(__file__).resolve().parent.parent
WORK = ROOT / "tmp/lyrics_asr_20261001"
FFMPEG = Path(r"C:/Program Files/EVCapture/ffmpeg.exe")
SOURCES = [
    (3, Path(r"C:/Users/28492/Desktop/车载图片/我落泪情绪零碎 - 周杰伦.mp3")),
    (4, Path(r"C:/Users/28492/Desktop/车载图片/周杰伦 - 搁浅.mp3")),
    (5, Path(r"C:/Users/28492/Desktop/车载图片/272/周杰伦 - 枫.mp3")),
]

sys.path.insert(0, str(WORK / "deps"))
os.environ["HF_HUB_DISABLE_XET"] = "1"
os.environ["HF_HUB_DISABLE_SYMLINKS_WARNING"] = "1"
from faster_whisper import WhisperModel
import numpy as np


def transcribe(model, song_id, source):
    decoded = subprocess.run(
        [str(FFMPEG), "-v", "error", "-nostdin", "-i", str(source),
         "-map", "0:a:0", "-vn", "-ac", "1", "-ar", "16000", "-f", "f32le", "pipe:1"],
        check=True, stdout=subprocess.PIPE).stdout
    audio = np.frombuffer(decoded, dtype="<f4")
    segments, info = model.transcribe(
        audio, language="zh", beam_size=5, word_timestamps=True,
        vad_filter=False, condition_on_previous_text=False)
    rows = []
    for seg in segments:
        rows.append({
            "start": seg.start,
            "end": seg.end,
            "text": seg.text.strip(),
            "words": [{"start": w.start, "end": w.end, "word": w.word,
                       "probability": w.probability}
                      for w in (seg.words or [])],
        })
    out = ROOT / f"tmp/song{song_id}_transcription_20261013.json"
    out.write_text(json.dumps({"song_id": song_id, "source": str(source),
                               "language": info.language, "duration": info.duration,
                               "segments": rows}, ensure_ascii=False, indent=2),
                   encoding="utf-8")
    print(f"song{song_id}: {len(rows)} segments, {info.duration:.2f}s -> {out}", flush=True)


if __name__ == "__main__":
    model = WhisperModel("small", device="cpu", compute_type="int8", cpu_threads=6,
                         download_root=str(WORK / "models"), local_files_only=True)
    for song_id, source in SOURCES:
        transcribe(model, song_id, source)
