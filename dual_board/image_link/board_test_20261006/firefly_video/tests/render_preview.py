"""Software raster preview of the verified firefly equations, not board capture.

Only diagnostic output is rendered. TF media, firmware inputs and supplied
reference video are never modified. The backdrop is an existing user asset.
"""
from pathlib import Path
import subprocess
import numpy as np
from PIL import Image

HERE = Path(__file__).resolve().parent
OUT = HERE / 'software_preview'
OUT.mkdir(exist_ok=True)
SOURCE = Path(r'C:/Users/28492/Desktop/车载图片/night_hills_640x480.bmp')
FFMPEG = r'C:/Users/28492/AppData/Local/kzip_sogou/ffmpeg.exe'
base_image = Image.open(SOURCE).convert('RGB')
assert base_image.size == (640, 480)
base = np.tile(np.asarray(base_image, dtype=np.int16), (1, 2, 1))
bx = np.array([43, 53, 40, 47, 56, 39, 50, 44, 54, 48])
by = np.array([95, 172, 78, 206, 134, 66, 188, 120, 164, 88])
seed = np.array([16, 107, 50, 185, 224, 141, 84, 12, 172, 61])
point = np.arange(3)[None, :]
lane = np.arange(10)[:, None]
size = np.where((lane % 3 == 0) & (point == 0), 2,
                np.where((lane % 3 != 0) & (point == 1), 1, 0))
assert dict(zip(*np.unique(size, return_counts=True))) == {0: 20, 1: 6, 2: 4}


def ease(value):
    value = np.asarray(value) % 4096
    tri = np.where(value >= 2048, 4095 - value, value)
    part, rem = tri // 512, tri % 512
    return np.select([part == 0, part == 1, part == 2],
                     [rem // 4, 128 + rem * 3 // 4, 512 + rem * 3 // 4],
                     default=896 + rem // 4)


def frame(phase):
    phase %= 16384
    px = np.where(point == 0, bx[:, None],
                  np.where(point == 1, 120 - bx[:, None], bx[:, None] + 25))
    cx = (px - 16) * 4 + ease(phase + seed[:, None] * 16 + point * 1024) // 8
    cy = (by[:, None] + point * 112 - 16) * 4 + ease(
        phase // 2 + (seed[:, None] ^ 147) * 16 + point * 1365) // 8
    breath = ease(np.where(size == 2, (phase % 1024) * 4, (phase % 2048) * 2)
                  + seed[:, None] * 16 + point * 1365)
    amp = np.where(size == 2, 40 + breath // 8,
                   np.where(size == 1, 18 + breath // 16, 6 + breath // 32))
    delta_y = np.abs(np.arange(480)[:, None, None] * 4 - cy[None, :, :])
    near = np.argmin(delta_y, axis=2)
    yl, lanes = np.indices((480, 10))
    distance = np.minimum(delta_y[yl, lanes, near], 255)
    xpos, amps, scales = cx[lanes, near], amp[lanes, near], size[lanes, near]
    world = (np.arange(1280) * 16 - int(ease(phase // 4)) * 3) % 20480
    selected_lane = world // 2048
    dx = np.abs(world[None, :] % 2048 // 4 - xpos[:, selected_lane]) >> scales[:, selected_lane]
    dy = distance[:, selected_lane] >> scales[:, selected_lane]
    radius = np.maximum(dx, dy) + np.minimum(dx, dy) // 2
    core = np.maximum(0, amps[:, selected_lane] - radius * 16)
    halo = np.maximum(0, amps[:, selected_lane] - radius * 6) // 8
    light = np.where((dx < 64) & (dy < 64) & (radius < 32), core + halo, 0)
    red, blue = light - light // 16, np.where(radius <= 2, light - light // 4, light // 16)
    return np.clip(base + np.stack([red, light, blue], axis=2), 0, 255).astype(np.uint8)


# Cover motion/breathing continuity and the 128-second time wrap in software.
assert np.array_equal(frame(0), frame(16384))
for seconds in [0, 4, 8, 16, 32, 64]:
    Image.fromarray(frame(seconds * 128)).save(OUT / f'preview_{seconds:02d}s.png')
video = OUT / 'firefly_dual_screen_12s.mp4'
if video.exists():
    raise FileExistsError(video)
process = subprocess.Popen([
    FFMPEG, '-hide_banner', '-loglevel', 'error', '-nostdin', '-n',
    '-f', 'rawvideo', '-pixel_format', 'rgb24', '-video_size', '1280x480',
    '-framerate', '30', '-i', 'pipe:0', '-an', '-c:v', 'libx264',
    '-preset', 'fast', '-crf', '18', '-pix_fmt', 'yuv420p', str(video)], stdin=subprocess.PIPE)
try:
    for i in range(360):
        process.stdin.write(frame(i * 128 // 30).tobytes())
    process.stdin.close()
    if process.wait() != 0:
        raise RuntimeError('Preview video encoding failed')
finally:
    if process.poll() is None:
        process.terminate()
print(f'Software preview only; A left/B right, original background repeated. {video}')
