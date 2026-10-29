"""Check raw MUSIC.PCM format and its expected FPGA visualizer activity."""

import math
from pathlib import Path
import statistics
import struct


SAMPLE_RATE = 48_000
BLOCK_SIZE = 256
BAND_HZ = (
    187.5, 375.0, 562.5, 750.0, 937.5, 1312.5, 1687.5, 2250.0,
    3000.0, 3937.5, 5250.0, 6937.5, 9187.5, 12187.5, 16125.0,
    21187.5,
)
PCM_PATH = Path(__file__).resolve().parents[1] / "best_result" / "MUSIC.PCM"


def percentile(values: list[float], fraction: float) -> float:
    ordered = sorted(values)
    return ordered[min(len(ordered) - 1, int((len(ordered) - 1) * fraction))]


raw = PCM_PATH.read_bytes()
if len(raw) % 4:
    raise SystemExit("FAIL: raw PCM byte count is not divisible by one stereo frame")

frames = list(struct.iter_unpack("<hh", raw))
duration = len(frames) / SAMPLE_RATE
left = [item[0] for item in frames]
right = [item[1] for item in frames]
mono = [(item[0] + item[1]) * 0.5 / 32768.0 for item in frames]

# Inspect 64 evenly distributed 256-sample windows. Frequencies are exact DFT
# bins, matching the FPGA's Goertzel centres.
band_db = [[] for _ in BAND_HZ]
wave_ranges = []
stereo_differences = []
for probe in range(64):
    start = int((len(frames) - BLOCK_SIZE - 80) * probe / 63)
    block = mono[start:start + BLOCK_SIZE]
    for band, frequency in enumerate(BAND_HZ):
        real = 0.0
        imag = 0.0
        for index, sample in enumerate(block):
            angle = 2.0 * math.pi * frequency * index / SAMPLE_RATE
            real += sample * math.cos(angle)
            imag -= sample * math.sin(angle)
        amplitude = 2.0 * math.hypot(real, imag) / BLOCK_SIZE
        band_db[band].append(20.0 * math.log10(max(amplitude, 1.0e-9)))

    # Emulate the displayed 16 samples: begin at a rising zero crossing and
    # retain every fourth audio frame.
    crossing = None
    for index in range(start, start + BLOCK_SIZE - 65):
        if mono[index] < 0.0 <= mono[index + 1]:
            crossing = index + 1
            break
    if crossing is not None:
        points = mono[crossing:crossing + 64:4]
        wave_ranges.append(max(points) - min(points))

    stereo_differences.append(sum(abs(left[index] - right[index])
                                  for index in range(start, start + BLOCK_SIZE)) /
                              BLOCK_SIZE)

peak = max(max(abs(value) for value in left), max(abs(value) for value in right))
rms_l = math.sqrt(sum(value * value for value in left) / len(left))
rms_r = math.sqrt(sum(value * value for value in right) / len(right))
active_bands = sum(percentile(values, 0.75) > -62.0 for values in band_db)

print(f"PCM bytes={len(raw)} frames={len(frames)} duration={duration:.3f}s")
print(f"peak={peak}/32767 rms_l={rms_l:.1f} rms_r={rms_r:.1f}")
print(f"boundary first={frames[0]} last={frames[-1]}")
print("band dBFS p50/p75/max:")
for index, values in enumerate(band_db):
    print(f"  {index:02d} {BAND_HZ[index]:7.1f}Hz "
          f"{statistics.median(values):6.1f}/{percentile(values, 0.75):6.1f}/{max(values):6.1f}")
print(f"active_bands={active_bands}/16")
print(f"wave_range median={statistics.median(wave_ranges):.3f} "
      f"p75={percentile(wave_ranges, 0.75):.3f}")
print(f"stereo_difference median={statistics.median(stereo_differences):.1f}")

if duration < 1.0:
    raise SystemExit("FAIL: audio duration is too short")
if peak > 25_000:
    raise SystemExit("FAIL: peak headroom is too small")
if active_bands < 16:
    raise SystemExit("FAIL: not all spectrum bands are active")
if statistics.median(wave_ranges) < 0.12:
    raise SystemExit("FAIL: time-domain waveform is too flat")
if statistics.median(stereo_differences) < 100.0:
    raise SystemExit("FAIL: stereo image is too narrow")
print("PASS music format and visual response")
