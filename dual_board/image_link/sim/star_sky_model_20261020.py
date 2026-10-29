"""Bit-exact Python model of rtl/star_sky_20261020/video_star_sky.v.

The model is written in canvas coordinates (one 1280-px sky); the two RTL
views (VIEW_X=0 and 640) must both match it pixel for pixel, which also
proves that stars and meteors are continuous across the A|B seam.
"""
import generate_star_sky_20261020 as gen

GX_NEAR, GY_NEAR, GC, GB = gen.GX_NEAR, gen.GY_NEAR, gen.GC, gen.GB


def tab(t, i):
    return t[i] if 0 <= i < len(t) else 0


FAR = dict(CB=4, NCELL=80, ROWS=13, SALT=0x5, DENS=7)
NEAR = dict(CB=5, NCELL=40, ROWS=7, SALT=0xB, DENS=6, R=3, NB=7)


def fade(y):
    if y < 110:
        return 255
    if y >= 200:
        return 0
    return (((200 - y) * 45) >> 4) & 0xFF


def cell_hash(salt, cy, col):
    seed = (salt << 12) | (cy << 7) | (col & 127)
    m1 = ((seed ^ (seed >> 8)) * 0xA3D3) & 0xFFFF
    m2 = ((m1 ^ (m1 >> 7)) * 0x4B2D) & 0xFFFF
    h1 = m2 ^ (m2 >> 9)
    p3 = (((h1 ^ 0x9E37) & 0xFFFF) * 0x6F4B) & 0xFFFFFFFF
    h2 = ((p3 >> 16) & 0xFFFF) ^ (p3 & 0xFFFF)
    return h1, h2


def twinkle_factor(h2, twinkle, near):
    if not (h2 >> 10) & 1:
        return 255
    ang = (twinkle + ((h2 >> 11) & 7) * 32) & 255
    t = (~ang) & 127 if ang & 128 else ang & 127
    return 255 - (t >> 1) if near else 255 - t


def far_job(col, y, twinkle, l0):
    L = FAR
    cy, ly = (y >> 4) & 31, y & 15
    row_ok = (y >> 4) < L["ROWS"]
    h1, h2 = cell_hash(L["SALT"], cy, col)
    jex = row_ok and (h1 >> 12) < L["DENS"] and ly == 4 + (h1 & 7)
    ox = 64 + ((h1 >> 5) & 0x7F)
    sq = ((h2 & 255) * (h2 & 255)) & 0xFFFF
    bri = (60 + (sq >> 9) - (sq >> 11)) & 0xFF
    ff = (twinkle_factor(h2, twinkle, False) * fade(y)) >> 8
    beff = (bri * ff) >> 8
    pos = ox - l0
    right = ((beff * (pos & 15)) >> 4) & 255
    return dict(ex=jex, kb=(pos >> 4) & 31, buf=[(beff - right) & 255, right])


def near_job(col, y, twinkle, l0):
    L = NEAR
    R, NB = L["R"], L["NB"]
    cy, ly = (y >> 5) & 31, y & 31
    row_ok = (y >> 5) < L["ROWS"]
    h1, h2 = cell_hash(L["SALT"], cy, col)
    jex = row_ok and (h1 >> 12) < L["DENS"]
    ox = 128 + ((h1 >> 4) & 0xFF)
    oy = 8 + (h1 & 15)
    tint = (h2 >> 8) & 3
    sq = ((h2 & 255) * (h2 & 255)) & 0xFFFF
    bri = min(255, 105 + (sq >> 8) - (sq >> 11))
    ady = abs(ly - oy) & 63
    ff = (twinkle_factor(h2, twinkle, True) * fade(y)) >> 8
    beff = (bri * ff) >> 8
    kb = ((((ox - l0 + 8) >> 4) & 31) - R) & 31
    if not jex or ady > R:
        return dict(ex=False, kb=kb, tint=tint, buf=[0] * NB)
    bc = (beff * tab(GY_NEAR, ady & 7)) >> 8
    buf = []
    for e in range(NB):
        slot = (kb + e) & 31
        adx = abs(l0 + 16 * slot - ox)
        buf.append((bc * tab(GX_NEAR, (adx >> 2) & 31)) >> 8)
    return dict(ex=True, kb=kb, tint=tint, buf=buf)


def layer_row(L, job, view_x, off_q4, y, twinkle):
    CB, NCELL = L["CB"], L["NCELL"]
    CELL = 1 << CB
    sx0 = view_x * 16 - off_q4
    if sx0 < 0:
        sx0 += 20480
    c0 = sx0 >> (CB + 4)
    kp0 = (sx0 >> 4) & (CELL - 1)
    l0 = sx0 & 15
    vals, tints, cache = [], [], {}
    for x in range(640):
        pos = kp0 + x
        col = (c0 + pos // CELL) % NCELL
        kp = pos % CELL
        if col not in cache:
            cache[col] = job(col, y, twinkle, l0)
        j = cache[col]
        i = (kp - j["kb"]) & 31
        vals.append(j["buf"][i] if j["ex"] and i < len(j["buf"]) else 0)
        tints.append(j.get("tint", 0))
    return vals, tints


def near_tint(v, t):
    n2, n4, n8 = v >> 1, v >> 2, v >> 3
    r = v - (n4 if t == 1 else 0)
    g = v - (0 if t == 0 else n4 if t == 3 else n8)
    b = v - (n4 if t == 2 else n2 if t == 3 else 0)
    return r, g, b


def render_view(view_x, f, bg):
    """f: dict near far tw mon mx my env; bg: 480 rows x 640 (r,g,b)."""
    out = []
    m_on = f["mon"] and f["env"] != 0
    env = f["env"]
    mx = f["mx"] - 65536 if f["mx"] & 0x8000 else f["mx"]
    d0 = ((((mx >> 4) - view_x) + 2048) & 4095) - 2048
    hy = f["my"]
    for y in range(480):
        fv, _ = layer_row(FAR, far_job, view_x, f["far"], y, f["tw"])
        nv, nt = layer_row(NEAR, near_job, view_x, f["near"], y, f["tw"])
        dyl = y * 16 - hy + 2 * d0
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
            mv = (env * min(255, tail_s + head_s)) >> 8
            v = fv[x]
            cr, cg, cb = near_tint(nv[x], nt[x])
            light = (min(255, (v - (v >> 2)) + cr + (mv - (mv >> 3))),
                     min(255, (v - (v >> 3)) + cg + (mv - (mv >> 4))),
                     min(255, v + cb + mv))
            b = bg[y][x]
            row.append(tuple(min(255, b[i] + light[i]) for i in range(3)))
        out.append(row)
    return out
