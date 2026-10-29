"""Transcribe only the user's supplied recording with the cached local model.

No lyrics or audio are downloaded. Output is an ASR draft to be reviewed, not
an authoritative transcription. Keep old song assets and evidence untouched.
"""
from pathlib import Path
import json
import os
import subprocess
import sys

ROOT = Path(__file__).resolve().parent.parent
CACHE = ROOT / "tmp/lyrics_asr_20261001"
OUT = ROOT / "tmp/dualsong_yilu_20261005"
sys.path.insert(0, str(CACHE / "deps"))
os.environ["HF_HUB_DISABLE_XET"] = "1"
os.environ["HF_HUB_DISABLE_SYMLINKS_WARNING"] = "1"
from faster_whisper import WhisperModel
import numpy as np

SOURCE = Path(r"C:/Users/28492/Desktop/车载图片/周杰伦 - 一路向北.mp3")
OUT.mkdir(parents=True, exist_ok=True)
TARGET = OUT / "transcription_draft.json"
if TARGET.exists():
    raise SystemExit("Draft already exists; refusing to overwrite it.")
print("Loading cached local ASR model...", flush=True)
model = WhisperModel("small", device="cpu", compute_type="int8", cpu_threads=6,
                     download_root=str(CACHE / "models"), local_files_only=True)
decoded = subprocess.run(
    [r"C:/Users/28492/AppData/Local/kzip_sogou/ffmpeg.exe", "-v", "error",
     "-nostdin", "-i", str(SOURCE), "-map", "0:a:0", "-vn", "-ac", "1",
     "-ar", "16000", "-f", "f32le", "pipe:1"],
    check=True, stdout=subprocess.PIPE).stdout
segments, info = model.transcribe(np.frombuffer(decoded, dtype="<f4"), language="zh",
                                  beam_size=5, word_timestamps=True, vad_filter=False,
                                  condition_on_previous_text=False)
result = {"source": str(SOURCE), "provenance": "user_supplied_audio_local_asr",
          "status": "unreviewed_draft", "duration": info.duration, "segments": []}
for s in segments:
    result["segments"].append({"start": s.start, "end": s.end, "text": s.text,
        "words": [{"start": w.start, "end": w.end, "word": w.word,
                   "probability": w.probability} for w in (s.words or [])]})
    print(f"Processed {s.end:.1f}s / {info.duration:.1f}s", flush=True)
TARGET.write_text(json.dumps(result, ensure_ascii=False, indent=2), encoding="utf-8")
print(f"Saved draft: {len(result['segments'])} segments", flush=True)
