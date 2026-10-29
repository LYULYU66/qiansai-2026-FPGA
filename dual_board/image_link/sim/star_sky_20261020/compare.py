"""Compare RTL dumps with the model; report mismatches and write previews."""
import sys
from pathlib import Path
HERE = Path(__file__).resolve().parent
sys.path.insert(0, str(HERE.parent)); sys.path.insert(0, str(HERE))
from PIL import Image
import star_sky_model_20261020 as model
from run_check import FRAMES, load_bg

def read(nm):
    v = [int(l, 16) for l in (HERE / nm).read_text().split()]
    return [v[i*307200:(i+1)*307200] for i in range(len(v)//307200)]

bga, bgb = load_bg("relax_A_left_640x480.png"), load_bg("relax_B_right_640x480.png")
ra, rb = read("out_a.hex"), read("out_b.hex")
total_bad = 0
for i, f in enumerate(FRAMES):
    ga = model.render_view(0, f, bga); gb = model.render_view(640, f, bgb)
    img = Image.new("RGB", (1280, 480))
    for view, rtl, gold, x0 in (("A", ra[i], ga, 0), ("B", rb[i], gb, 640)):
        bad = 0; first = None
        for y in range(480):
            for x in range(640):
                v = rtl[y*640+x]; p = ((v >> 16) & 255, (v >> 8) & 255, v & 255)
                img.putpixel((x0 + x, y), p)
                if p != gold[y][x]:
                    bad += 1
                    if first is None: first = (x, y, p, gold[y][x])
        total_bad += bad
        print(f"frame {i} view {view}: mismatches {bad}" + (f" first {first}" if first else ""))
    img.save(HERE / f"preview_frame{i}.png")
print("TOTAL MISMATCHES", total_bad)
