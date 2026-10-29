"""Bit-exact model of video_dashboard_subtitle / video_home_logo vs ModelSim."""
import sys
from PIL import Image
S0 = int(sys.argv[1]) if len(sys.argv) > 1 else 700
W, H, F = 640, 480, 8
tick = [int(l, 16) for l in open('ticker_px.hex')]
warn = [int(l, 16) for l in open('warn_px.hex')]
seq = [int(v) for v in open('ticker_seq.txt').read().split()]
lidx = [int(l, 16) for l in open('logo_idx.hex')]
lpal = [int(l, 16) for l in open('logo_palette.hex')]
bg = [int(l, 16) for l in open('dash_bg.hex')]
LV = (0, 1, 2, 4)                       # opacity in quarters


def mix(b, f, k):
    half = (f + b) >> 1
    if k == 2:
        return half
    return (half + (b if k == 1 else f)) >> 1


def blend(b, f, k):
    if k == 0:
        return b
    if k == 4:
        return f
    return (mix(b >> 16, f >> 16, k) << 16) | (mix((b >> 8) & 255, (f >> 8) & 255, k) << 8) | mix(b & 255, f & 255, k)


colour = [int(l, 16) for l in open('colour_rom.hex')]


def sub_frame(f):
    """rev 2: opacity in eighths, colours from the precomputed colour ROM."""
    scroll = (S0 + f + 1) & 1023
    pulse = (f + 1) & 63
    hz = f >= 4
    br = (~pulse & 31) if pulse & 32 else (pulse & 31)
    COV = (0, 3, 6, 8)
    RULE = [0, 2, 4, 6, 6, 6, 6, 4, 2, 0]
    out = list(bg)
    for y in range(76):
        for x in range(W):
            kind = sel = w = 0
            if hz:
                if 192 <= x < 448 and 6 <= y < 70:
                    g = (x - 192) >> 6
                    w = COV[warn[g * 4096 + (y - 6) * 64 + ((x - 192) & 63)]]; kind, sel = 1, br
                elif y < 3 or 73 <= y < 76:
                    kind, sel, w = 3, br, (6 if br >= 16 else 4)
            else:
                c = (x + scroll) & 1023; pos = c >> 5
                if 22 <= y < 54 and pos < len(seq):
                    row = y - 22
                    cov = COV[tick[seq[pos] * 1024 + row * 32 + (c & 31)]]
                    lim = ((x >> 3) & 3) * 2 if x < 32 else ((3 - ((x >> 3) & 3)) * 2 if x >= 608 else 8)
                    kind, sel, w = 0, row, min(cov, lim)
                elif (y == 12 or y == 63) and RULE[x >> 6]:
                    kind, sel, w = 2, 0, RULE[x >> 6]
            if w:
                out[y * W + x] = colour[(kind << 8) | (sel << 3) | (w - 1)]
    return out


def logo_frame():
    out = list(bg)
    for y in range(H):
        for x in range(W):
            if not (18 <= x < 98 and 38 <= y < 92):
                continue
            by, bx = y - 38, x - 18
            er = by if by < 8 else 53 - by
            inset = [5, 3, 2, 1, 1, 0, 0, 0][er] if er < 8 else 0
            ec = bx if bx < 8 else 79 - bx
            if ec < inset:
                continue
            b = bg[y * W + x]
            col = None
            if 24 <= x < 92 and 43 <= y < 87:
                i = lidx[(y - 43) * 68 + (x - 24)]
                if i:
                    col = lpal[i]
            if col is None:
                col = ((0xDB + (b >> 19)) << 16) | ((0xDC + ((b >> 11) & 31)) << 8) | (0xDD + ((b >> 3) & 31))
            out[y * W + x] = col
    return out


def load(fn):
    v = [int(l, 16) for l in open(fn)]
    assert len(v) == W * H * F, len(v)
    return [v[i * W * H:(i + 1) * W * H] for i in range(F)]


def png(px, fn, crop=None):
    im = Image.new('RGB', (W, H)); im.putdata([((p >> 16) & 255, (p >> 8) & 255, p & 255) for p in px])
    if crop:
        im = im.crop(crop).resize(((crop[2] - crop[0]) * 2, (crop[3] - crop[1]) * 2), Image.NEAREST)
    im.save(fn)


bad = 0
B = load('out_b.hex')
for f in range(F):
    exp = sub_frame(f)
    d = sum(1 for a, e in zip(B[f], exp) if a != e)
    bad += d
    print('B frame', f, 'hazard' if f >= 4 else 'normal', 'mismatch', d,
          'changed px', sum(1 for a, e in zip(B[f], bg) if a != e))
A = load('out_a.hex')
le = logo_frame()
for f in range(F):
    d = sum(1 for a, e in zip(A[f], le) if a != e); bad += d
print('A logo mismatch over all frames', sum(1 for f in range(F) for a, e in zip(A[f], le) if a != e))
png(B[1], 'preview_b_normal.png'); png(B[1], 'preview_b_normal_top.png', (0, 0, 640, 80))
png(B[5], 'preview_b_hazard.png'); png(B[5], 'preview_b_hazard_top.png', (0, 0, 640, 80))
png(A[0], 'preview_a_logo_zoom.png', (0, 0, 120, 100))
print('PASS' if bad == 0 else 'FAIL %d' % bad)
