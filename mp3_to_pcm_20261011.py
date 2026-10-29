from pathlib import Path
import sys

import av


def main() -> None:
    if len(sys.argv) != 3:
        raise SystemExit("usage: mp3_to_pcm_20261011.py INPUT OUTPUT")

    source = Path(sys.argv[1])
    target = Path(sys.argv[2])
    target.parent.mkdir(parents=True, exist_ok=True)

    container = av.open(str(source))
    audio_stream = container.streams.audio[0]
    resampler = av.audio.resampler.AudioResampler(
        format="s16", layout="stereo", rate=48000
    )
    sample_count = 0

    def write_frames(handle, frames):
        nonlocal sample_count
        if frames is None:
            return
        if not isinstance(frames, list):
            frames = [frames]
        for frame in frames:
            if frame is None:
                continue
            # The requested s16/stereo frame is packed interleaved little
            # endian, but PyAV may expose alignment bytes after the valid
            # samples.  The FPGA consumes exactly 4 bytes per stereo sample.
            handle.write(bytes(frame.planes[0])[: frame.samples * 2 * 2])
            sample_count += frame.samples

    # Do not silently overwrite a previous export; this also makes it harder
    # to accidentally put the old padded-plane file on the TF card.
    with target.open("xb") as handle:
        for decoded in container.decode(audio_stream):
            write_frames(handle, resampler.resample(decoded))
        write_frames(handle, resampler.resample(None))

    duration = sample_count / 48000.0
    print(
        f"source_rate={audio_stream.rate} "
        f"source_layout={audio_stream.layout.name} "
        f"output_rate=48000 output_layout=stereo "
        f"samples={sample_count} duration_seconds={duration:.3f} "
        f"bytes={target.stat().st_size}"
    )
    expected = sample_count * 4
    if target.stat().st_size != expected:
        raise RuntimeError(
            f"invalid packed PCM length: {target.stat().st_size} != {expected}"
        )


if __name__ == "__main__":
    main()
