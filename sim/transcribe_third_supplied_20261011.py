"""Transcribe the user-supplied third-song recording locally.

This is an intermediate aid for aligning lyrics in the FPGA asset generator;
the audio never leaves the machine and the result must still be auditioned.
"""
from pathlib import Path
import json, os, subprocess, sys

ROOT = Path(__file__).resolve().parent.parent
WORK = ROOT / "tmp/lyrics_asr_20261001"
SOURCE = Path(r"C:/Users/28492/Downloads/M500000KkqnP00XOVk.mp3")
OUT = ROOT / "tmp/third_song_transcription_20261011.json"
sys.path.insert(0, str(WORK / "deps"))
os.environ["HF_HUB_DISABLE_XET"] = "1"
os.environ["HF_HUB_DISABLE_SYMLINKS_WARNING"] = "1"
from faster_whisper import WhisperModel
import numpy as np

model = WhisperModel("small", device="cpu", compute_type="int8", cpu_threads=6,
                     download_root=str(WORK / "models"), local_files_only=True)
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
for seg in segments:
    row = {"start": seg.start, "end": seg.end, "text": seg.text,
           "words": [{"start": w.start, "end": w.end, "word": w.word,
                      "probability": w.probability}
                     for w in (seg.words or [])]}
    output["segments"].append(row)
    print(json.dumps(row, ensure_ascii=False), flush=True)
OUT.write_text(json.dumps(output, ensure_ascii=False, indent=2), encoding="utf-8")
print(f"saved {OUT}")
