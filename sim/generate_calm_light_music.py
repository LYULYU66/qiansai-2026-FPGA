"""Generate a calm, loop-friendly soundtrack for the FPGA TF-card player.

Output format required by the HDL reader:
48 kHz, signed 16-bit little-endian, stereo, raw frames ordered L/R.
"""

from array import array
import math
from pathlib import Path
import struct
import wave


SAMPLE_RATE = 48_000
DURATION_SECONDS = 16.0
SAMPLE_COUNT = int(SAMPLE_RATE * DURATION_SECONDS)
OUTPUT_DIR = Path(__file__).resolve().parents[1] / "best_result"
WAV_PATH = OUTPUT_DIR / "calm_light_music_48k.wav"
PCM_PATH = OUTPUT_DIR / "MUSIC.PCM"
TWO_PI = 2.0 * math.pi


NOTE_HZ = {
    "F2": 87.307, "G2": 97.999, "A2": 110.000, "C3": 130.813,
    "E3": 164.814, "F3": 174.614, "G3": 195.998, "A3": 220.000,
    "B3": 246.942, "C4": 261.626, "D4": 293.665, "E4": 329.628,
    "F4": 349.228, "G4": 391.995, "A4": 440.000, "B4": 493.883,
    "C5": 523.251, "D5": 587.330, "E5": 659.255, "G5": 783.991,
    "A5": 880.000, "B5": 987.767,
}

# These are the exact 256-sample Goertzel bin centres used by the FPGA. A very
# quiet, slowly breathing layer at these frequencies keeps all 16 columns alive
# without turning the soundtrack into a test tone.
VISUALIZER_BAND_HZ = (
    187.5, 375.0, 562.5, 750.0, 937.5, 1312.5, 1687.5, 2250.0,
    3000.0, 3937.5, 5250.0, 6937.5, 9187.5, 12187.5, 16125.0,
    21187.5,
)


def smoothstep(value: float) -> float:
    value = max(0.0, min(1.0, value))
    return value * value * (3.0 - 2.0 * value)


def pan_gains(pan: float) -> tuple[float, float]:
    """Equal-power stereo pan, where -1 is left and +1 is right."""
    angle = (pan + 1.0) * math.pi / 4.0
    return math.cos(angle), math.sin(angle)


def add_pad(
    left: array,
    right: array,
    start_s: float,
    duration_s: float,
    frequencies: tuple[float, ...],
) -> None:
    start = max(0, int(start_s * SAMPLE_RATE))
    stop = min(SAMPLE_COUNT, int((start_s + duration_s) * SAMPLE_RATE))
    attack_s = 0.65
    release_s = 0.85

    for voice, frequency in enumerate(frequencies):
        pan = (-0.42, 0.30, -0.18, 0.44)[voice]
        gain_l, gain_r = pan_gains(pan)
        detune = (-0.0017, 0.0012, -0.0008, 0.0019)[voice]
        phase = voice * 0.73
        phase_detuned = voice * 1.19

        for index in range(start, stop):
            time_s = index / SAMPLE_RATE
            local_s = time_s - start_s
            remaining_s = start_s + duration_s - time_s
            envelope = min(smoothstep(local_s / attack_s),
                           smoothstep(remaining_s / release_s))
            fundamental = math.sin(TWO_PI * frequency * time_s + phase)
            chorus = math.sin(TWO_PI * frequency * (1.0 + detune) * time_s +
                              phase_detuned)
            octave = math.sin(TWO_PI * frequency * 2.0 * time_s + phase * 0.4)
            sample = envelope * (0.047 * fundamental +
                                 0.027 * chorus + 0.008 * octave)
            left[index] += sample * gain_l
            right[index] += sample * gain_r


def add_bass(
    left: array,
    right: array,
    start_s: float,
    duration_s: float,
    frequency: float,
) -> None:
    start = int(start_s * SAMPLE_RATE)
    stop = min(SAMPLE_COUNT, int((start_s + duration_s) * SAMPLE_RATE))

    for index in range(start, stop):
        local_s = index / SAMPLE_RATE - start_s
        remaining_s = duration_s - local_s
        envelope = min(smoothstep(local_s / 0.18),
                       smoothstep(remaining_s / 0.45))
        body = math.sin(TWO_PI * frequency * index / SAMPLE_RATE)
        warmth = math.sin(TWO_PI * frequency * 2.0 * index / SAMPLE_RATE + 0.2)
        sample = envelope * (0.075 * body + 0.018 * warmth)
        left[index] += sample * 0.72
        right[index] += sample * 0.72


def add_soft_key(
    left: array,
    right: array,
    start_s: float,
    duration_s: float,
    frequency: float,
    amplitude: float,
    pan: float,
) -> None:
    start = max(0, int(start_s * SAMPLE_RATE))
    tail_s = 0.55
    stop = min(SAMPLE_COUNT, int((start_s + duration_s + tail_s) * SAMPLE_RATE))
    gain_l, gain_r = pan_gains(pan)

    for index in range(start, stop):
        local_s = index / SAMPLE_RATE - start_s
        if local_s < 0.0:
            continue
        if local_s < duration_s:
            attack = smoothstep(local_s / 0.035)
            sustain = 0.72 + 0.28 * math.exp(-local_s / 0.75)
            envelope = attack * sustain
        else:
            release_pos = (local_s - duration_s) / tail_s
            envelope = 0.72 * (1.0 - smoothstep(release_pos))

        phase = TWO_PI * frequency * local_s
        # Rounded electric-piano timbre: enough harmonics for a visible but
        # non-aggressive spectrum.
        tone = (math.sin(phase) +
                0.24 * math.sin(2.0 * phase + 0.15) +
                0.08 * math.sin(3.0 * phase + 0.45))
        soft_tremolo = 0.94 + 0.06 * math.sin(TWO_PI * 4.1 * local_s)
        sample = amplitude * envelope * soft_tremolo * tone
        left[index] += sample * gain_l
        right[index] += sample * gain_r


def add_reverb(left: array, right: array) -> None:
    dry_left = array("f", left)
    dry_right = array("f", right)
    taps = ((0.173, 0.17), (0.293, 0.105), (0.431, 0.065))

    for delay_s, gain in taps:
        delay = int(delay_s * SAMPLE_RATE)
        for index in range(delay, SAMPLE_COUNT):
            # Cross-feed the echoes to produce width without changing the
            # actual stereo PCM framing expected by the FPGA.
            left[index] += dry_right[index - delay] * gain
            right[index] += dry_left[index - delay] * gain


def add_visualizer_shimmer(left: array, right: array) -> None:
    """Add an inaudible/very quiet broad-band layer for attractive meters."""
    # Ear-sensitive mid bands are deliberately quieter. Ultrasonic-near bands
    # receive a little more numeric energy so the last columns remain visible.
    amplitudes = (
        0.00055, 0.00050, 0.00048, 0.00046,
        0.00043, 0.00040, 0.00038, 0.00036,
        0.00034, 0.00034, 0.00038, 0.00046,
        0.00060, 0.00085, 0.00130, 0.00210,
    )

    for band, (frequency, amplitude) in enumerate(zip(VISUALIZER_BAND_HZ,
                                                       amplitudes)):
        pan = -0.24 if (band & 1) == 0 else 0.24
        gain_l, gain_r = pan_gains(pan)
        phase = band * 0.91
        breath_hz = 0.105 + 0.011 * (band % 7)
        for index in range(SAMPLE_COUNT):
            time_s = index / SAMPLE_RATE
            breath = 0.38 + 0.62 * (0.5 + 0.5 * math.sin(
                TWO_PI * breath_hz * time_s + band * 0.67))
            sample = amplitude * breath * math.sin(
                TWO_PI * frequency * time_s + phase)
            left[index] += sample * gain_l
            right[index] += sample * gain_r


def render() -> tuple[array, array]:
    left = array("f", [0.0]) * SAMPLE_COUNT
    right = array("f", [0.0]) * SAMPLE_COUNT

    # Four slow one-bar harmonies: Cmaj7, Am7, Fmaj7, Gadd9.  The final G chord
    # resolves naturally back to C when the raw file loops.
    chords = (
        (0.0, (NOTE_HZ["C3"], NOTE_HZ["G3"], NOTE_HZ["B3"], NOTE_HZ["E4"]), NOTE_HZ["C3"] / 2.0),
        (4.0, (NOTE_HZ["A2"], NOTE_HZ["E3"], NOTE_HZ["G3"], NOTE_HZ["C4"]), NOTE_HZ["A2"] / 2.0),
        (8.0, (NOTE_HZ["F2"], NOTE_HZ["C3"], NOTE_HZ["E3"], NOTE_HZ["A3"]), NOTE_HZ["F2"] / 2.0),
        (12.0, (NOTE_HZ["G2"], NOTE_HZ["D4"], NOTE_HZ["A3"], NOTE_HZ["B3"]), NOTE_HZ["G2"] / 2.0),
    )
    for start_s, frequencies, bass_frequency in chords:
        add_pad(left, right, max(0.0, start_s - 0.22), 4.55, frequencies)
        add_bass(left, right, start_s, 3.85, bass_frequency)

    # Sparse, singable melody. Long note values and the pentatonic contour keep
    # it calm while still giving the waveform and 16-band spectrum movement.
    melody = (
        (0.45, 1.25, "E5",  -0.18),
        (2.00, 0.68, "G5",   0.12),
        (3.02, 0.72, "B5",   0.25),
        (4.30, 1.35, "A5",   0.18),
        (5.95, 0.72, "E5",  -0.22),
        (7.00, 0.72, "G5",   0.08),
        (8.25, 1.18, "A5",  -0.12),
        (9.68, 0.66, "G5",   0.18),
        (10.62, 1.08, "E5", -0.20),
        (12.18, 1.08, "D5",  0.13),
        (13.55, 0.68, "G5", -0.15),
        (14.48, 0.62, "B5",  0.17),
        (15.18, 0.38, "G5",  0.00),
    )
    for start_s, duration_s, note, pan in melody:
        add_soft_key(left, right, start_s, duration_s, NOTE_HZ[note], 0.115, pan)

    # Very quiet one-note-per-beat arpeggio keeps the texture alive without a
    # drum beat or a conspicuous cue on every image transition.
    arpeggios = (
        ("C4", "E4", "G4", "B4"),
        ("A3", "C4", "E4", "G4"),
        ("F3", "A3", "C4", "E4"),
        ("G3", "A3", "D4", "B3"),
    )
    for bar, notes in enumerate(arpeggios):
        for beat, note in enumerate(notes):
            pan = -0.34 if (beat & 1) == 0 else 0.34
            add_soft_key(left, right, bar * 4.0 + beat + 0.08, 0.42,
                         NOTE_HZ[note], 0.031, pan)

    add_reverb(left, right)
    add_visualizer_shimmer(left, right)

    # Short raised-cosine boundary fades make sector-to-sector looping click
    # free, while retaining nearly all of the musical phrase.
    fade_s = 0.12
    for index in range(SAMPLE_COUNT):
        time_s = index / SAMPLE_RATE
        boundary = min(smoothstep(time_s / fade_s),
                       smoothstep((DURATION_SECONDS - time_s) / fade_s))
        left[index] *= boundary
        right[index] *= boundary

    return left, right


def write_files(left: array, right: array) -> None:
    raw_peak = max(max(abs(value) for value in left),
                   max(abs(value) for value in right))
    scale = 0.76 * 32767.0 / raw_peak
    sum_sq_left = 0.0
    sum_sq_right = 0.0
    peak_integer = 0

    with wave.open(str(WAV_PATH), "wb") as wav_file, PCM_PATH.open("wb") as pcm_file:
        wav_file.setnchannels(2)
        wav_file.setsampwidth(2)
        wav_file.setframerate(SAMPLE_RATE)

        chunk = bytearray()
        for sample_l, sample_r in zip(left, right):
            value_l = max(-32768, min(32767, round(sample_l * scale)))
            value_r = max(-32768, min(32767, round(sample_r * scale)))
            peak_integer = max(peak_integer, abs(value_l), abs(value_r))
            sum_sq_left += value_l * value_l
            sum_sq_right += value_r * value_r
            chunk.extend(struct.pack("<hh", value_l, value_r))
            if len(chunk) >= 64 * 1024:
                wav_file.writeframesraw(chunk)
                pcm_file.write(chunk)
                chunk.clear()
        if chunk:
            wav_file.writeframesraw(chunk)
            pcm_file.write(chunk)

    rms_left = math.sqrt(sum_sq_left / SAMPLE_COUNT)
    rms_right = math.sqrt(sum_sq_right / SAMPLE_COUNT)
    print(f"WAV: {WAV_PATH} ({WAV_PATH.stat().st_size} bytes)")
    print(f"PCM: {PCM_PATH} ({PCM_PATH.stat().st_size} bytes)")
    print(f"Format: {SAMPLE_RATE} Hz, signed 16-bit little-endian, stereo, {DURATION_SECONDS:.0f} s")
    print(f"Peak: {peak_integer}/32767 ({peak_integer / 32767.0:.3f})")
    print(f"RMS L/R: {rms_left:.1f}/{rms_right:.1f}")


if __name__ == "__main__":
    write_files(*render())
