"""Transcribe the user's local recording; never downloads the source song.

Recognition packages/model cache live only in tmp/lyrics_asr_20261001.
The JSON is an intermediate ASR result, not an authoritative lyric source.
"""
from pathlib import Path
import json
import os
import sys
import subprocess

ROOT = Path(__file__).resolve().parent.parent
WORK = ROOT / "tmp/lyrics_asr_20261001"
sys.path.insert(0, str(WORK / "deps"))
os.environ["HF_HUB_DISABLE_XET"] = "1"
os.environ["HF_HUB_DISABLE_SYMLINKS_WARNING"] = "1"
from faster_whisper import WhisperModel
import numpy as np

SOURCE = Path(r"C:/Users/28492/xwechat_files/wxid_5n1i5mtgjsdh22_d795/temp/RWTemp/2026-09/9e20f478899dc29eb19741386f9343c8/周杰伦 - 告白气球 (3D环绕版).mp3")
print("Loading local transcription model (small/int8/CPU)...", flush=True)
model = WhisperModel("small", device="cpu", compute_type="int8", cpu_threads=6,
                     download_root=str(WORK / "models"))
decoded = subprocess.run(
    [r"C:/Users/28492/AppData/Local/kzip_sogou/ffmpeg.exe", "-v", "error",
     "-nostdin", "-i", str(SOURCE), "-map", "0:a:0", "-vn", "-ac", "1",
     "-ar", "16000", "-f", "f32le", "pipe:1"],
    check=True, stdout=subprocess.PIPE).stdout
audio = np.frombuffer(decoded, dtype="<f4")
segments, info = model.transcribe(audio, language="zh", beam_size=5,
                                  word_timestamps=True, vad_filter=False,
                                  condition_on_previous_text=False)
output = {"source": str(SOURCE), "language": info.language,
          "duration": info.duration, "segments": []}
for s in segments:
    row = {"start": s.start, "end": s.end, "text": s.text,
           "words": [{"start": w.start, "end": w.end, "word": w.word,
                      "probability": w.probability} for w in (s.words or [])]}
    output["segments"].append(row)
    print(json.dumps(row, ensure_ascii=False), flush=True)
(WORK / "transcription.json").write_text(json.dumps(output, ensure_ascii=False, indent=2), encoding="utf-8")
print("Transcription intermediate saved in workspace.", flush=True)
