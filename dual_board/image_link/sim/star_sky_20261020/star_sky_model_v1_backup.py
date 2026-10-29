"""Bit-exact Python model of rtl/star_sky_20261020/video_star_sky.v.

The model is written in canvas coordinates (one 1280-px sky); the two RTL
views (VIEW_X=0 and 640) must both match it pixel for pixel, which also
proves that stars and meteors are continuous across the A|B seam.
"""
import math
import generate_star_sky_20261020 as gen


def gauss(sigma, count, step, peak=255):
    return gen.gauss(sigma, count, step, peak)


GX_FAR = gauss(0.62, 21, 1 / 8)
GY_FAR = gauss(0.62, 3, 1)
GX_NEAR = gauss(0.80, 45, 1 / 8)
GY_NEAR = gauss(0.80, 6, 1)
SH_NEAR = [round(255 * math.exp(-(i / 8) / 1.35)) if i / 8 <= 5.4 else 0 for i in range(45)]
SN_NEAR = gauss(0.42, 45, 1 / 8)
SV_NEAR = [115] + [round(115 * math.exp(-a / 1.35)) for a in range(1, 6)]
GC = gauss(0.50, 12, 1 / 8)
GB = gauss(0.85, 19, 1 / 4)


def tab(t, i):
    return t[i] if 0 <= i < len(t) else 0


LAYERS = {
    "far": dict(CB=4, NCELL=80, ROWS=13, R=2, NEAR=0, SALT=0x5, DENS=7),
    "near": dict(CB=5, NCELL=40, ROWS=7, R=5, NEAR=1, SALT=0xB, DENS=6),
}


def fade(y):
    if y < 110:
        return 255
    if y >= 200:
        return 0
    return (((200 - y) * 45) >> 4) & 0xFF


def cell_job(L, jcell, y, twinkle, l0):
    CB, R, NEAR = L["CB"], L["R"], L["NEAR"]
    CELL = 1 << CB
    NB = 2 * R + 1
    cy = (y >> CB) & 31
    ly = y & (CELL - 1)
    row_ok = (y >> CB) < L["ROWS"]
    fd = fade(y)
    seed = (L["SALT"] << 12) | (cy << 7) | (jcell & 127)
    hx1 = seed ^ (seed >> 8)
    p = (hx1 * 0xA3D3) & 0xFFFFFFFF
    m = p & 0xFFFF
    p = ((m ^ (m >> 7)) * 0x4B2D) & 0xFFFFFFFF
    m = p & 0xFFFF
    h1 = m ^ (m >> 9)
    p = (((h1 ^ 0x9E37) & 0xFFFF) * 0x6F4B) & 0xFFFFFFFF
    h2 = ((p >> 16) & 0xFFFF) ^ (p & 0xFFFF)
    jex = row_ok and (h1 >> 12) < L["DENS"]
    ox = (128 + ((h1 >> 4) & 0xFF)) if NEAR else (64 + ((h1 >> 5) & 0x7F))
    oy = (8 + (h1 & 15)) if NEAR else (4 + (h1 & 7))
    tint = (h2 >> 8) & 3
    sq = ((h2 & 255) * (h2 & 255)) & 0xFFFF
    if NEAR:
        bri = min(255, 70 + (sq >> 8) - (sq >> 11))
    else:
        bri = (34 + (sq >> 9) - (sq >> 11)) & 0xFF
    spark = NEAR and (h2 >> 14) == 3 and (sq >> 14) == 3
    dy = ly - oy
    ady = abs(dy) & 63
    dy0 = dy == 0
    ang = (twinkle + ((h2 >> 11) & 7) * 32) & 255
    twt = (~ang) & 127 if ang & 128 else ang & 127
    if not (h2 >> 10) & 1:
        fac = 255
    else:
        fac = 255 - (twt >> 1) if NEAR else 255 - twt
    ff = (fac * fd) >> 8
    beff = (bri * ff) >> 8
    kc = ((ox - l0 + 8) >> 4) & 31
    kb = (kc - R) & 31
    if not jex or ady > R:
        return dict(ex=False, kb=kb, tint=tint, buf=[0] * NB)
    gy = tab(GY_NEAR if NEAR else GY_FAR, ady & 7)
    bc = (beff * gy) >> 8
    sb = 115 if dy0 else tab(SV_NEAR, ady & 7)
    bs = ((beff * sb) >> 8) if spark else 0
    buf = []
    for e in range(NB):
        slot = (kb + e) & 31
        dxq = l0 + 16 * slot - ox
        axi = (abs(dxq) >> 1) & 63
        gx = tab(GX_NEAR, axi) if NEAR else tab(GX_FAR, axi & 31)
        sp = tab(SH_NEAR, axi) if dy0 else tab(SN_NEAR, axi)
        v = ((bc * gx) >> 8) + (((bs * sp) >> 8) if NEAR else 0)
        buf.append(min(255, v))
    return dict(ex=True, kb=kb, tint=tint, buf=buf)


def layer_row(L, view_x, off_q4, y, twinkle):
    CB, NCELL, R = L["CB"], L["NCELL"], L["R"]
    CELL = 1 << CB
    NB = 2 * R + 1
    sx0 = view_x * 16 - off_q4
    if sx0 < 0:
        sx0 += 20480
    c0 = sx0 >> (CB + 4)
    kp0 = (sx0 >> 4) & (CELL - 1)
    l0 = sx0 & 15
    vals, tints = [], []
    cache = {}
    for x in range(640):
        pos = kp0 + x
        col = (c0 + pos // CELL) % NCELL
        kp = pos % CELL
        if col not in cache:
            cache[col] = cell_job(L, col, y, twinkle, l0)
        j = cache[col]
        i = (kp - j["kb"]) & 31
        vals.append(j["buf"][i] if j["ex"] and i < NB else 0)
        tints.append(j["tint"])
    return vals, tints


def tint_far(v, t):
    if t == 0:
        return (v, v, v)
    if t == 3:
        return ((v >> 1) + (v >> 3), v - (v >> 2), v)
    return (v - (v >> 2), v - (v >> 3), v)


def tint_near(v, t):
    if t == 0:
        return (v, v, v)
    if t == 1:
        return (v - (v >> 2) + (v >> 5), v - (v >> 3), v)
    if t == 2:
        return (v, v - (v >> 3) + (v >> 5), (v >> 1) + (v >> 3) + (v >> 4))
    return (v, v - (v >> 2) + (v >> 4), (v >> 1) + (v >> 4))


def render_view(view_x, f, bg):
    """f: dict near far tw mon mx my env; bg: 480 rows x 640 (r,g,b)."""
    out = []
    m_on = f["mon"] and f["env"] != 0
    env = f["env"]
    mx = f["mx"] - 65536 if f["mx"] & 0x8000 else f["mx"]
    d0 = ((mx >> 4) - view_x)
    d0 = ((d0 + 2048) & 4095) - 2048
    hy = f["my"]
    for y in range(480):
        fv, ft = layer_row(LAYERS["far"], view_x, f["far"], y, f["tw"])
        nv, nt = layer_row(LAYERS["near"], view_x, f["near"], y, f["tw"])
        dyl = y * 16 - hy + int(d0 * 8 / 4)
        row = []
        for x in range(640):
            d = ((d0 - x + 2048) & 4095) - 2048
            dy = ((dyl - 2 * x + 32768) & 65535) - 32768
            ady_w = abs(dy) & 0xFFFF
            near_track = ady_w < 48
            ady = ady_w & 63
            tail_ok = m_on and 0 <= d <= 127 and ady < 24 and near_track
            tail_s = (((127 - (d & 127)) * tab(GC, (ady >> 1) & 15)) >> 7) & 255 if tail_ok else 0
            ad = abs(d)
            head_ok = m_on and ad <= 2 and near_track
            a16 = (ad & 3) * 16
            hr = max(a16, ady) + (min(a16, ady) >> 1)
            head_s = tab(GB, hr >> 2) if head_ok and hr < 76 else 0
            shape = min(255, tail_s + head_s)
            mv = (env * shape) >> 8
            mr, mg, mb = mv - (mv >> 3), mv - (mv >> 4), mv
            cf = tint_far(fv[x], ft[x])
            cn = tint_near(nv[x], nt[x])
            light = [min(255, cf[i] + cn[i] + m) for i, m in enumerate((mr, mg, mb))]
            b = bg[y][x]
            row.append(tuple(min(255, b[i] + light[i]) for i in range(3)))
        out.append(row)
    return out
