"""Drive tb_star_sky_20261020, compare both views with the Python model, write PNGs."""
import subprocess, sys
from pathlib import Path
HERE = Path(__file__).resolve().parent
sys.path.insert(0, str(HERE.parent))
from PIL import Image
import star_sky_model_20261020 as model

PANO = HERE.parents[1] / "assets/relax_panorama_20261007"
FRAMES = [
    dict(near=0,     far=0,     tw=0,   mon=0, mx=0,     my=0,    env=0),
    dict(near=7777,  far=3891,  tw=77,  mon=1, mx=10080, my=960,  env=255),
    dict(near=20000, far=19999, tw=200, mon=1, mx=11200, my=1000, env=180),
    dict(near=5,     far=3,     tw=128, mon=1, mx=12160, my=900,  env=230),
]

def pack(f):
    v = f["near"]
    for val, bits in ((f["far"], 15), (f["tw"], 8), (f["mon"], 1), (f["mx"] & 0xFFFF, 16),
                      (f["my"], 13), (f["env"], 8)):
        v = (v << bits) | val
    return f"{v:020x}"

def load_bg(name):
    im = Image.open(PANO / name).convert("RGB")
    return [[im.getpixel((x, y)) for x in range(640)] for y in range(480)]

if __name__ == "__main__":
    bga, bgb = load_bg("relax_A_left_640x480.png"), load_bg("relax_B_right_640x480.png")
    for nm, bg in (("bg_a.hex", bga), ("bg_b.hex", bgb)):
        (HERE / nm).write_text("\n".join("%02x%02x%02x" % p for row in bg for p in row) + "\n")
    (HERE / "frames.hex").write_text("\n".join(pack(f) for f in FRAMES) + "\n")
    print("stimulus written; run ModelSim, then: run_check.py compare")
