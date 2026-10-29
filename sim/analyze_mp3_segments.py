"""Rank 16-second MP3 excerpts for the FPGA audio/visual demo."""

import argparse
import math
from pathlib import Path
import subprocess

import numpy as np


SAMPLE_RATE = 48_000
HOP_SECONDS = 0.5
HOP_SAMPLES = int(SAMPLE_RATE * HOP_SECONDS)
EXCERPT_SECONDS = 16.0
FFMPEG_FALLBACK = Path(r"C:\Users\28492\AppData\Local\kzip_sogou\ffmpeg.exe")


def decode(source: Path) -> np.ndarray:
    command = [
        str(FFMPEG_FALLBACK), "-v", "error", "-i", str(source),
        "-map", "0:a:0", "-ar", str(SAMPLE_RATE), "-ac", "2",
        "-f", "f32le", "-",
    ]
    result = subprocess.run(command, check=True, stdout=subprocess.PIPE)
    return np.frombuffer(result.stdout, dtype="<f4").reshape(-1, 2)


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("source", type=Path)
    args = parser.parse_args()
    audio = decode(args.source)
    hop_count = len(audio) // HOP_SAMPLES
    audio = audio[:hop_count * HOP_SAMPLES]
    chunks = audio.reshape(hop_count, HOP_SAMPLES, 2)

    power = np.mean(chunks * chunks, axis=(1, 2)) + 1.0e-12
    db = 10.0 * np.log10(power)
    mid = 0.5 * (chunks[:, :, 0] + chunks[:, :, 1])
    side = 0.5 * (chunks[:, :, 0] - chunks[:, :, 1])
    width = np.sqrt(np.mean(side * side, axis=1) + 1.0e-12) / (
        np.sqrt(np.mean(mid * mid, axis=1) + 1.0e-12)
    )

    window = np.hanning(HOP_SAMPLES).astype(np.float32)
    spectrum = np.abs(np.fft.rfft(mid * window, axis=1)) ** 2
    frequencies = np.fft.rfftfreq(HOP_SAMPLES, 1.0 / SAMPLE_RATE)
    ranges = ((80, 250), (250, 1000), (1000, 4000), (4000, 12000))
    band_db = []
    for low, high in ranges:
        selection = (frequencies >= low) & (frequencies < high)
        energy = np.mean(spectrum[:, selection], axis=1) + 1.0e-15
        band_db.append(10.0 * np.log10(energy))
    band_db = np.stack(band_db, axis=1)

    span = int(EXCERPT_SECONDS / HOP_SECONDS)
    candidates = []
    for start in range(int(18.0 / HOP_SECONDS), hop_count - span - 8):
        region = slice(start, start + span)
        mean_db = float(np.mean(db[region]))
        quiet_db = float(np.percentile(db[region], 15))
        stability = float(np.std(db[region]))
        mean_width = float(np.mean(width[region]))
        coverage = float(np.mean(np.percentile(band_db[region], 35, axis=0)))
        # Favor a full, stable, stereo section. The start-boundary term prefers
        # a local energy valley so the excerpt begins between musical phrases.
        boundary = float(np.mean(db[max(0, start - 1):start + 1]) - mean_db)
        score = (1.10 * mean_db + 0.35 * quiet_db - 0.55 * stability +
                 2.2 * min(mean_width, 1.4) + 0.055 * coverage -
                 0.18 * max(boundary, 0.0))
        candidates.append((score, start * HOP_SECONDS, mean_db, quiet_db,
                           stability, mean_width, coverage))

    selected = []
    for candidate in sorted(candidates, reverse=True):
        if all(abs(candidate[1] - item[1]) >= EXCERPT_SECONDS for item in selected):
            selected.append(candidate)
        if len(selected) == 8:
            break

    print(f"duration={len(audio) / SAMPLE_RATE:.2f}s")
    print("score   start   mean_dB quiet_dB std_dB width coverage")
    for score, start, mean_db, quiet_db, stability, mean_width, coverage in selected:
        minutes = int(start // 60)
        seconds = start - minutes * 60
        print(f"{score:7.2f}  {minutes}:{seconds:04.1f}  {mean_db:7.2f} "
              f"{quiet_db:8.2f} {stability:6.2f} {mean_width:5.2f} {coverage:8.2f}")


if __name__ == "__main__":
    main()
