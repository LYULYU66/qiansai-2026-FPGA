"""Generate a loopable 48 kHz stereo soundtrack for the four-image demo."""

from array import array
import math
from pathlib import Path
import struct
import wave


SAMPLE_RATE = 48_000
DURATION_SECONDS = 16
SAMPLE_COUNT = SAMPLE_RATE * DURATION_SECONDS
OUTPUT_DIR = Path(__file__).resolve().parents[1] / "best_result"
WAV_PATH = OUTPUT_DIR / "zhixing_shengshi_vehicle_theme_48k.wav"
PCM_PATH = OUTPUT_DIR / "MUSIC.PCM"


def smoothstep(value: float) -> float:
    value = max(0.0, min(1.0, value))
    return value * value * (3.0 - 2.0 * value)


def render() -> tuple[array, array]:
    left = array("f")
    right = array("f")

    # Dm7, Bbmaj7, Fadd9, Cadd9: calm, technological and non-distracting.
    chords = (
        (146.832, 174.614, 220.000, 261.626),
        (116.541, 146.832, 174.614, 220.000),
        (130.813, 164.814, 195.998, 293.665),
        (130.813, 164.814, 195.998, 261.626),
    )
    accent_notes = (587.330, 698.456, 880.000, 1046.502)

    pad_phases = [0.0, 0.0, 0.0, 0.0]
    bass_phase = 0.0
    accent_phase = 0.0
    two_pi = 2.0 * math.pi
    noise_state = 0x31415926

    for index in range(SAMPLE_COUNT):
        time_s = index / SAMPLE_RATE
        chord_index = int(time_s // 4.0) & 3
        image_phase = int(time_s) & 3
        second_pos = time_s - math.floor(time_s)
        chord_pos = time_s - 4.0 * chord_index

        attack = smoothstep(chord_pos / 0.16)
        release = smoothstep((4.0 - chord_pos) / 0.16)
        pad_env = min(attack, release)

        pad_l = 0.0
        pad_r = 0.0
        for voice, frequency in enumerate(chords[chord_index]):
            pad_phases[voice] += two_pi * frequency / SAMPLE_RATE
            tone = math.sin(pad_phases[voice])
            pan = (-0.35, 0.20, -0.12, 0.38)[voice]
            pad_l += tone * (1.0 - pan) * 0.5
            pad_r += tone * (1.0 + pan) * 0.5

        # One soft bass pulse per image change.
        bass_frequency = chords[chord_index][0] * 0.5
        bass_phase += two_pi * bass_frequency / SAMPLE_RATE
        bass_env = (1.0 - math.exp(-second_pos / 0.008)) * math.exp(-second_pos / 0.30)
        bass = math.sin(bass_phase) * bass_env

        # Four recurring chime pitches mark image positions 1..4.
        accent_phase += two_pi * accent_notes[image_phase] / SAMPLE_RATE
        accent_env = (1.0 - math.exp(-second_pos / 0.006)) * math.exp(-second_pos / 0.24)
        accent = math.sin(accent_phase) * accent_env
        accent_pan = (-0.42, -0.14, 0.14, 0.42)[image_phase]

        # Quiet deterministic high-frequency texture at the half beat.
        noise_state = (1664525 * noise_state + 1013904223) & 0xFFFFFFFF
        noise = ((noise_state >> 8) / 8388607.5) - 1.0
        hat_pos = second_pos - 0.5
        hat_env = math.exp(-hat_pos / 0.035) if hat_pos >= 0.0 else 0.0
        hat = noise * hat_env

        sample_l = (0.105 * pad_env * pad_l + 0.20 * bass +
                    0.12 * accent * (1.0 - accent_pan) + 0.025 * hat)
        sample_r = (0.105 * pad_env * pad_r + 0.20 * bass +
                    0.12 * accent * (1.0 + accent_pan) + 0.025 * hat)
        # A short loop-boundary envelope guarantees a click-free restart.
        loop_env = min(smoothstep(time_s / 0.04),
                       smoothstep((DURATION_SECONDS - time_s) / 0.04))
        left.append(sample_l * loop_env)
        right.append(sample_r * loop_env)

    return left, right


def write_files(left: array, right: array) -> None:
    peak = max(max(abs(value) for value in left), max(abs(value) for value in right))
    scale = 0.82 * 32767.0 / peak

    with wave.open(str(WAV_PATH), "wb") as wav_file, PCM_PATH.open("wb") as pcm_file:
        wav_file.setnchannels(2)
        wav_file.setsampwidth(2)
        wav_file.setframerate(SAMPLE_RATE)

        chunk = bytearray()
        for sample_l, sample_r in zip(left, right):
            value_l = max(-32768, min(32767, round(sample_l * scale)))
            value_r = max(-32768, min(32767, round(sample_r * scale)))
            chunk.extend(struct.pack("<hh", value_l, value_r))
            if len(chunk) >= 64 * 1024:
                wav_file.writeframesraw(chunk)
                pcm_file.write(chunk)
                chunk.clear()
        if chunk:
            wav_file.writeframesraw(chunk)
            pcm_file.write(chunk)

    print(f"WAV: {WAV_PATH} ({WAV_PATH.stat().st_size} bytes)")
    print(f"PCM: {PCM_PATH} ({PCM_PATH.stat().st_size} bytes)")
    print(f"Format: {SAMPLE_RATE} Hz, signed 16-bit little-endian, stereo, {DURATION_SECONDS} s")


if __name__ == "__main__":
    write_files(*render())
