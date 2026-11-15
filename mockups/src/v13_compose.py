# Balance style test v13 (asked for as "v12"; v12 is the M7.5 HUD set) -- v9 pushed toward a 16-bit arcade look.
#   * Bigger pixels: the whole screen is a 480x270 canvas shown at x4 (v9's gameplay zoom was x3). A map cell is
#     24 art pixels, so the framing matches v9's gameplay zoom.
#   * Ground built only from 24x24 seamless tiles. Paths, rock, water and the Orichalcum rock use corner-based
#     autotiles (straight, diagonal, curved inner/outer corner pieces, each edge piece in two shape variants), and a
#     few "unique" decoration tiles (dune crests, pebbles, tufts, flowers, bushes) repeat everywhere.
#   * Strict palettes: each ground material has 5 colours; every sprite is cut to at most 16 colours
#     (units, buildings) or fewer (trees, crystals, props), with a dark outline and hard 16-bit shadows.
#   * 4 tree types repeat across the forest.
#   * HUD: white gray-blue panels, darker vibrant gray-blue buttons, slightly rounded corners on every box, button,
#     frame and bar, one monospace 5x7 pixel font (drawn here) everywhere, a flat minimap with big unit dots.
# Run: python v13_compose.py <raw_sprite_dir (v9 sprites)> <out_dir> [forest desert]
import os, sys, math
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import numpy as np
from PIL import Image, ImageDraw
import v10_compose as V10          # v8/v9 map layout (masks), unit lists, helpers
import v4_compose as V4
import v8_compose as V8
from v2_compose import RAW, OUT, WHICH, hexc, ROCK_C, VH

SC = 4                             # screen pixels per art pixel
TS = 24                            # tile size in art pixels (v9: 32)
K = TS / 32                        # v9 world px -> art px
SW, SH = 480, 270                  # screen canvas in art pixels
SBX, TBH = 368, 14                 # sidebar left edge, top bar height
NX, NY = 24, 17                    # map size in cells
WW, WH = NX * TS, NY * TS
OFF = V10.OFF
YY, XX = np.mgrid[0:TS, 0:TS].astype(np.float32)


def C(h):
    return (hexc(h) * 255).round().astype(np.uint8)


def P(*hs):
    return np.stack([C(h) for h in hs])


# ---------------------------------------------------------------- palettes (5 colours per ground material)
PAL = {
    'sand': P('#9a5a2a', '#b06c34', '#c47e3e', '#d6914c', '#e8a95e'),
    'hard': P('#8a6a4a', '#b49270', '#c8a782', '#d8ba94', '#ead0aa'),
    'rock': P('#2a2018', '#3e3026', '#544234', '#6a5644', '#86725c'),
    'orer': P('#1c140f', '#2e231b', '#433428', '#5a4838', '#73614e'),
    'pond': P('#14406c', '#1c5a94', '#2a78b8', '#4c9ed8', '#a4dcf6'),
    'grass': P('#2c4a1c', '#3a5e22', '#4a7228', '#5c8630', '#749c3c'),
    'dirt': P('#4a321e', '#604428', '#785634', '#8e6a40', '#a8834e'),
    'stone': P('#383632', '#4e4a44', '#66615a', '#7e786c', '#9a9384'),
    'river': P('#16365e', '#1c4c82', '#2864a2', '#4686c4', '#9ccaee'),
    'oreg': P('#26221e', '#3a352f', '#504a42', '#686157', '#837b6e'),
}
MATS = list(PAL)
MI = {k: i for i, k in enumerate(MATS)}
OUTLINE = C('#160f0c')
CRYS = P('#2a0a54', '#5e1eb0', '#9440f0', '#c07cff', '#f0dcff')


# ---------------------------------------------------------------- seamless 24x24 tile textures (index maps)
def psin(kx, ky, ph):
    return np.sin(2 * np.pi * (kx * XX + ky * YY) / TS + ph)


def pnoise(rng, n=5, kmax=3, amp=1.0):
    out = np.zeros((TS, TS), np.float32)
    for _ in range(n):
        kx, ky = 0, 0
        while kx == 0 and ky == 0:
            kx, ky = int(rng.integers(-kmax, kmax + 1)), int(rng.integers(-kmax, kmax + 1))
        out += psin(kx, ky, float(rng.uniform(0, 6.3))) / math.hypot(kx, ky)
    return out / max(np.abs(out).max(), 1e-6) * amp


def wrap_vor(rng, n):
    pts = rng.random((n, 2)) * TS
    d = []
    for (px, py) in pts:
        dx = np.abs(XX + 0.5 - px)
        dy = np.abs(YY + 0.5 - py)
        dx, dy = np.minimum(dx, TS - dx), np.minimum(dy, TS - dy)
        d.append(np.hypot(dx, dy))
    d = np.stack(d)
    o = np.argsort(d, 0)
    d1, d2 = np.take_along_axis(d, o[:1], 0)[0], np.take_along_axis(d, o[1:2], 0)[0]
    return d1, d2, o[0]


def grooves(idx, crack, lit=4, dark=1):
    """Crack lines: the wall below-right of a groove catches the light, the wall above-left is in shade."""
    idx[np.roll(crack, (1, 1), (0, 1)) & ~crack] = lit
    idx[np.roll(crack, (-1, -1), (0, 1)) & ~crack] = dark
    idx[crack] = 0
    return idx


def tex_sand(rng):
    s = (YY - XX / 3 + 1.3 * psin(1, 0, 0.4) + 0.7 * psin(2, 1, 1.3)) / 8.0
    r = s - np.floor(s)
    idx = np.full((TS, TS), 2)
    idx[r < 0.26] = 1
    idx[r < 0.1] = 0
    idx[(r >= 0.26) & (r < 0.4)] = 3
    g = rng.random((TS, TS))
    idx[(g > 0.985) & (idx == 2)] = 4
    return idx


def tex_cracked(rng, n, base=(2, 3), knobs=0):
    d1, d2, own = wrap_vor(rng, n)
    idx = np.where(own % 2 == 0, base[0], base[1])
    idx = grooves(idx, (d2 - d1) < 1.05)
    for _ in range(knobs):
        x, y = int(rng.integers(0, TS)), int(rng.integers(0, TS))
        idx[y, x] = 4
        idx[(y + 1) % TS, (x + 1) % TS] = 1
        idx[y, (x + 1) % TS] = 3
    return idx


def tex_water(rng):
    idx = np.full((TS, TS), 2)
    idx[pnoise(rng, 4, 2) > 0.55] = 1
    for _ in range(7):
        x, y = int(rng.integers(0, TS)), int(rng.integers(0, TS))
        for k in range(int(rng.integers(2, 5))):
            idx[y, (x + k) % TS] = 3
    for _ in range(3):
        idx[int(rng.integers(0, TS)), int(rng.integers(0, TS))] = 4
    return idx


def tex_grass(rng):
    n = pnoise(rng, 5, 2)
    idx = np.where(n > 0.45, 3, np.where(n < -0.5, 1, 2))
    for _ in range(14):                                       # little "v" tufts
        x, y = int(rng.integers(0, TS)), int(rng.integers(0, TS))
        idx[y, x] = 3 if idx[y, x] != 3 else 4
        idx[(y + 1) % TS, (x + 1) % TS] = 1
        idx[y, (x + 2) % TS] = 3
    return idx


def tex_dirt(rng):
    n = pnoise(rng, 5, 3)
    idx = np.where(n > 0.5, 3, np.where(n < -0.45, 1, 2))
    for _ in range(9):
        x, y = int(rng.integers(0, TS)), int(rng.integers(0, TS))
        idx[y, x] = 4
        idx[(y + 1) % TS, x] = 0
    return idx


def tex_stone(rng):
    g = rng.random((TS, TS))
    idx = np.where(g < 0.5, 1, 2)
    for _ in range(11):
        x, y = int(rng.integers(0, TS)), int(rng.integers(0, TS))
        for (dx, dy, v) in ((0, 0, 4), (1, 0, 3), (0, 1, 3), (1, 1, 3), (2, 1, 0), (1, 2, 0), (2, 2, 0)):
            idx[(y + dy) % TS, (x + dx) % TS] = v
    return idx


# ---------------------------------------------------------------- corner autotiles
UU, VV = (XX + 0.5) / TS, (YY + 0.5) / TS
_rt = np.random.default_rng(77)
NA = pnoise(_rt, 6, 2, 0.13)
WIN = np.sin(np.pi * UU) * np.sin(np.pi * VV)
NB = [pnoise(_rt, 5, 3, 0.2) * WIN, pnoise(_rt, 5, 3, 0.2) * WIN]
_TM = {}


def tile_mask(c, var):
    """Shape of a terrain piece from which of its 4 corners lie inside the region (tl, tr, bl, br)."""
    key = (c, var)
    if key not in _TM:
        tl, tr, bl, br = c
        if c == (1, 0, 0, 1):
            f = 1 - np.abs(UU - VV)                            # diagonal piece
        elif c == (0, 1, 1, 0):
            f = 1 - np.abs(UU + VV - 1)
        else:
            f = tl * (1 - UU) * (1 - VV) + tr * UU * (1 - VV) + bl * (1 - UU) * VV + br * UU * VV
        _TM[key] = (f + NA + NB[var]) > 0.5
    return _TM[key]


def layer(V):
    """Assemble a region mask from autotile pieces given a vertex grid (NY+1, NX+1)."""
    M = np.zeros((WH, WW), bool)
    for j in range(NY):
        for i in range(NX):
            c = (int(V[j, i]), int(V[j, i + 1]), int(V[j + 1, i]), int(V[j + 1, i + 1]))
            if not any(c):
                continue
            sl = (slice(j * TS, (j + 1) * TS), slice(i * TS, (i + 1) * TS))
            M[sl] = True if all(c) else tile_mask(c, (i * 7 + j * 13) % 2)
    return M


def vgrid(fn):
    return np.array([[fn(i * 32, j * 32) for i in range(NX + 1)] for j in range(NY + 1)], bool)


def sampler(mask, thr=0.4, r=11):
    h, w = mask.shape

    def f(x, y):
        x, y = min(x, w - 1), min(y, h - 1)
        return mask[max(0, y - r):y + r, max(0, x - r):x + r].mean() > thr
    return f


class Ground:
    """The map as (material, palette index) per art pixel, built from repeated tiles; coloured at the end."""

    def __init__(self, base, tex):
        self.mat = np.full((WH, WW), MI[base], np.int16)
        self.idx = np.tile(tex, (NY, NX)).astype(np.int16)

    def paint(self, M, mat, tex, kind):
        T = np.tile(tex, (NY, NX))
        self.mat[M] = MI[mat]
        self.idx[M] = T[M]
        up, lf = np.roll(M, 1, 0), np.roll(M, 1, 1)
        dn, rt = np.roll(M, -1, 0), np.roll(M, -1, 1)
        if kind == 'raised':                                   # lit top-left rim, dark bottom-right, drop shadow
            sh = np.zeros_like(M)
            for (dy, dx) in ((1, 1), (2, 2), (1, 2), (2, 1), (1, 0), (0, 1)):
                sh |= np.roll(M, (dy, dx), (0, 1))
            sh &= ~M
            self.idx[sh] = np.maximum(self.idx[sh] - 2, 0)
            self.idx[M & (~up | ~lf)] = 4
            self.idx[M & (~dn | ~rt)] = 0
        elif kind == 'flat':
            self.idx[M & (~up | ~lf | ~dn | ~rt)] = 1
        elif kind == 'sunken':
            self.idx[M & (~up | ~lf)] = 0
            self.idx[M & (np.roll(~M, 2, 0) | np.roll(~M, 2, 1)) & ~(~up | ~lf)] = 1
            self.idx[M & (~dn | ~rt)] = 3

    def shade(self, m, k=2):
        self.idx[m] = np.maximum(self.idx[m] - k, 0)

    def rgb(self):
        out = np.zeros((WH, WW, 3), np.uint8)
        for name, i in MI.items():
            m = self.mat == i
            out[m] = PAL[name][np.clip(self.idx[m], 0, 4)]
        return out


# ---------------------------------------------------------------- small pixel sprites (props, trees, crystals)
def spr_from(idxmap, pal):
    """idxmap: -1 = transparent, -2 = outline, else palette index."""
    a = idxmap != -1
    rgb = np.zeros(idxmap.shape + (3,), np.uint8)
    rgb[idxmap >= 0] = pal[idxmap[idxmap >= 0]]
    rgb[idxmap == -2] = OUTLINE
    return rgb, a


def outline(idx):
    a = idx >= 0
    e = np.zeros_like(a)
    for d in ((0, 1), (0, -1), (1, 0), (-1, 0)):
        e |= np.roll(a, d, (0, 1))
    idx[e & ~a] = -2
    return idx


def blob_sprite(R, lobes, pal, seed, star=False):
    """Tree crown seen from above: lobed or star-shaped, lit from the upper left, max 5 colours + outline."""
    rng = np.random.default_rng(seed)
    n = int(2 * R + 5)
    yy, xx = np.mgrid[0:n, 0:n].astype(np.float32)
    cx = cy = n / 2 - 0.5
    dx, dy = xx - cx, yy - cy
    if star:
        ang = np.arctan2(dy, dx)
        rad = R * (0.62 + 0.38 * np.abs(np.cos(ang * 4)) ** 0.7)
        m = np.hypot(dx, dy) < rad
        v = 0.58 - 0.34 * (dx + dy) / R + 0.18 * np.cos(ang * 8 + 0.4)
    else:
        m = np.hypot(dx, dy) < R * 0.78
        v = 0.55 - 0.32 * (dx + dy) / R
        for k in range(lobes):
            a = k * 2 * math.pi / lobes + 0.3
            lx, ly = math.cos(a) * R * 0.55, math.sin(a) * R * 0.55
            lr = R * 0.5
            d = np.hypot(dx - lx, dy - ly)
            lm = d < lr
            m |= lm
            v = np.where(lm, v + 0.22 * np.clip(-((dx - lx) + (dy - ly)) / lr, -1, 1) * 0.6, v)
    v += (rng.random(v.shape) - 0.5) * 0.12
    idx = np.where(m, np.clip((v * 5).astype(int), 0, 4), -1)
    rim = m & ~(np.roll(m, -1, 0) & np.roll(m, -1, 1))
    idx[rim & (idx >= 0)] = np.maximum(idx[rim & (idx >= 0)] - 1, 0)
    return outline(idx), pal


TREES = {
    'oak': (dict(R=8.5, lobes=6, seed=1), P('#16301a', '#22451f', '#305c26', '#43742e', '#5e8c3a')),
    'pine': (dict(R=8, lobes=0, seed=2, star=True), P('#0e231e', '#163428', '#1f4734', '#2b5c42', '#3c7452')),
    'lime': (dict(R=7.5, lobes=4, seed=3), P('#26381a', '#3a521e', '#557024', '#74902c', '#9cb03c')),
    'olive': (dict(R=5.5, lobes=5, seed=4), P('#2e2a16', '#45401e', '#5e5826', '#7a7230', '#9a8e3c')),
}
_tree_cache = {}


def tree_spr(kind):
    if kind not in _tree_cache:
        kw, pal = TREES[kind]
        idx, pal = blob_sprite(pal=pal, **kw)
        rgb, a = spr_from(idx, pal)
        n = idx.shape[0]
        _tree_cache[kind] = dict(rgb=rgb, a=a, ax=n // 2, ay=n // 2 + 2, sh=(a, 2, 3))
    return _tree_cache[kind]


def crystal_spr(v):
    shards = [[(4, 9, 9, 2.4), (8, 10, 6, 1.8), (1, 10, 5, 1.6)],
              [(3, 10, 7, 2.0), (7, 9, 9, 2.4)],
              [(5, 10, 10, 2.6), (2, 10, 5, 1.5), (9, 10, 6, 1.7)]][v]
    idx = np.full((12, 12), -1)
    for (x, foot, h, w) in shards:
        for y in range(foot - h, foot + 1):
            t = (y - (foot - h)) / h
            half = w * min(1, t * 2.4) * (1 - max(0, t - 0.85) * 4)
            for xx in range(int(x - half - 1), int(x + half + 2)):
                if 0 <= xx < 12 and 0 <= y < 12:
                    u = (xx - x) / max(half, 0.5)
                    if abs(u) <= 1:
                        idx[y, xx] = 4 if t < 0.2 else (3 if u < 0 else 2)
    return dict(zip(('rgb', 'a'), spr_from(outline(idx), CRYS)), ax=6, ay=10, sh=None)


def prop_spr(kind):
    """Repeating little 'unique' pieces: bushes, flower clumps, boulders, pebbles, desert tufts."""
    if kind == 'bush':
        idx, pal = blob_sprite(3.2, 4, P('#14301a', '#1f4a20', '#2e6626', '#43842e', '#62a03a'), 9)
        rgb, a = spr_from(idx, pal)
        return dict(rgb=rgb, a=a, ax=idx.shape[1] // 2, ay=idx.shape[0] // 2 + 1, sh=(a, 1, 2))
    if kind in ('flowers_p', 'flowers_y'):
        col = ('#e890c8', '#b070d8') if kind == 'flowers_p' else ('#f0d850', '#f4f0e0')
        idx = np.full((7, 9), -1)
        for (x, y, c) in ((1, 2, 0), (3, 1, 1), (5, 3, 0), (7, 2, 1), (2, 5, 1), (4, 4, 0), (6, 5, 0), (4, 2, 0)):
            idx[y, x] = c
        rgb, a = spr_from(idx, P(*col))
        return dict(rgb=rgb, a=a, ax=4, ay=4, sh=None)
    if kind == 'boulders':
        idx = np.full((8, 11), -1)
        for (cx, cy, r) in ((3.5, 4, 3.0), (8, 5, 2.2)):
            yy, xx = np.mgrid[0:8, 0:11]
            d = np.hypot(xx - cx, yy - cy)
            m = d < r
            v = 2.5 - 1.6 * ((xx - cx) + (yy - cy)) / r
            idx[m] = np.clip(v[m].astype(int), 0, 4)
        rgb, a = spr_from(outline(idx), PAL['stone'])
        return dict(rgb=rgb, a=a, ax=5, ay=5, sh=(a, 1, 1))
    if kind == 'pebbles':
        idx = np.full((5, 7), -1)
        for (x, y) in ((1, 1), (4, 2), (2, 3)):
            idx[y, x], idx[y, x + 1] = 3, 1
        rgb, a = spr_from(outline(idx), PAL['rock'])
        return dict(rgb=rgb, a=a, ax=3, ay=3, sh=None)
    if kind == 'tuft':
        idx = np.full((5, 7), -1)
        for (x, y, c) in ((1, 3, 1), (2, 2, 2), (3, 1, 3), (4, 2, 2), (5, 3, 1), (3, 3, 0)):
            idx[y, x] = c
        rgb, a = spr_from(idx, P('#3e4a18', '#5a6a20', '#7a8a2a', '#9aa838', '#b8c048'))
        return dict(rgb=rgb, a=a, ax=3, ay=3, sh=None)


def ore_crystals(Mo, x0, y0, h):
    """2-4 crystal clusters per Orichalcum-rock cell, placed from a small set of offsets so it repeats."""
    out = []
    sets = [((5, 8), (15, 6), (11, 18), (20, 19)), ((9, 5), (19, 12), (4, 16)), ((3, 6), (13, 11), (8, 21), (20, 22))]
    for n, (dx, dy) in enumerate(sets[h % 3]):
        x, y = x0 + dx, y0 + dy
        if y + 2 < WH and x + 3 < WW and Mo[y, x] and Mo[y + 2, x + 3] and Mo[y - 6, x]:
            out.append((f'crys{(h + n) % 3}', x, y))
    return out


def dune_crest(G, x, y):
    """A 'unique' sand piece: a longer wind crest, drawn in the sand palette."""
    for k in range(-7, 8):
        xx, yy = x + k, y + int(round(-k / 3 + 1.4 * math.sin(k / 3)))
        if 0 <= xx < WW and 1 <= yy < WH - 2 and G.mat[yy, xx] == MI['sand']:
            G.idx[yy - 1, xx] = 4
            G.idx[yy, xx] = 3
            G.idx[yy + 1, xx] = 0
            G.idx[yy + 2, xx] = 1


# ---------------------------------------------------------------- units and buildings from the v9 renders
_spr = {}


def sprite12(name, k, colors=16, sat=1.3):
    """Box-downsample the 128 px/cell render to 24 px/cell, cut to <=16 colours, hard alpha, dark outline,
    hard shadow."""
    key = (name, k)
    if key in _spr:
        return _spr[key]
    src = Image.open(f'{RAW}/{name}_{k:02d}.png').convert('RGBA')
    shs = Image.open(f'{RAW}/{name}_{k:02d}_sh.png').convert('RGBA')
    n = src.size[0] * TS // 128
    a = np.asarray(src).astype(np.float32) / 255
    pm = Image.fromarray((np.concatenate([a[..., :3] * a[..., 3:], a[..., 3:]], -1) * 255).astype(np.uint8))
    sm = np.asarray(pm.resize((n, n), Image.BOX)).astype(np.float32) / 255
    al = sm[..., 3]
    col = sm[..., :3] / np.maximum(al, 1e-4)[..., None]
    g = col.mean(-1, keepdims=True)
    col = np.clip(g + (col - g) * sat, 0, 1) ** 1.08
    alpha = al > 0.45
    fill = col[alpha].mean(0)
    im = Image.fromarray((np.where(alpha[..., None], col, fill) * 255).astype(np.uint8))
    q = np.asarray(im.quantize(colors=colors, method=Image.Quantize.MEDIANCUT, dither=Image.Dither.NONE)
                   .convert('RGB'))
    rgb = q.copy()
    e = np.zeros_like(alpha)
    for d in ((0, 1), (0, -1), (1, 0), (-1, 0)):
        e |= np.roll(alpha, d, (0, 1))
    e &= ~alpha
    rgb[e] = OUTLINE
    sh = np.asarray(shs.resize((n, n), Image.BOX)).astype(np.float32)[..., 3] / 255 > 0.25
    contact = (np.roll(alpha | e, (1, 1), (0, 1)) | sh) & ~(alpha | e)
    s = dict(rgb=rgb, a=alpha | e, ax=n // 2, ay=n // 2, sh=(contact, 0, 0))
    _spr[key] = s
    return s


def blit(canvas, s, x, y):
    x0, y0 = int(round(x)) - s['ax'], int(round(y)) - s['ay']
    h, w = s['a'].shape
    ys, xs = max(0, y0), max(0, x0)
    ye, xe = min(canvas.shape[0], y0 + h), min(canvas.shape[1], x0 + w)
    if ys >= ye or xs >= xe:
        return
    a = s['a'][ys - y0:ye - y0, xs - x0:xe - x0]
    canvas[ys:ye, xs:xe][a] = s['rgb'][ys - y0:ye - y0, xs - x0:xe - x0][a]


def shadow_mask(s, x, y):
    m = np.zeros((WH, WW), bool)
    if not s.get('sh'):
        return m
    a, dx, dy = s['sh']
    x0, y0 = int(round(x)) - s['ax'] + dx, int(round(y)) - s['ay'] + dy
    h, w = a.shape
    ys, xs = max(0, y0), max(0, x0)
    ye, xe = min(WH, y0 + h), min(WW, x0 + w)
    if ys < ye and xs < xe:
        m[ys:ye, xs:xe] = a[ys - y0:ye - y0, xs - x0:xe - x0]
    return m


def foundation12(rgb, cx, cy, team):
    """Blocky 2x2-cell concrete pad: 12 px plates with bevels, team corner blocks, flush with the rock."""
    pal = P('#3a3e46', '#5c626c', '#7e858f', '#a2a9b2', '#c6ccd2')
    tc = P(*(('#16306e', '#2c5ccc', '#6a98f4') if team == 'blue' else ('#6a1410', '#c43028', '#f26a58')))
    w = 2 * TS
    idx = np.full((w, w), 2)
    yy, xx = np.mgrid[0:w, 0:w]
    u, t = xx % 12, yy % 12
    idx[(u == 1) | (t == 1)] = 3
    idx[(u == 10) | (t == 10)] = 1
    idx[(u == 0) | (t == 0) | (u == 11) | (t == 11)] = 0
    out = pal[idx]
    for (x, y) in ((2, 2), (w - 7, 2), (2, w - 7), (w - 7, w - 7)):
        out[y:y + 5, x:x + 5] = tc[1]
        out[y, x:x + 5], out[y:y + 5, x] = tc[2], tc[2]
        out[y + 4, x:x + 5], out[y:y + 5, x + 4] = tc[0], tc[0]
    out[[0, -1], :], out[:, [0, -1]] = OUTLINE, OUTLINE
    rgb[cy:cy + w, cx:cx + w] = out


# ---------------------------------------------------------------- the two maps
def world_xy(x, y_vp):
    return x * K, (y_vp + OFF) * K


def desert12():
    _, M0 = V4._orig_desert(np.random.default_rng(23))
    M = {k: V10.padv(v) for k, v in M0.items()}
    rng = np.random.default_rng(5)
    cx, cy = ROCK_C[0], ROCK_C[1] + OFF
    G = Ground('sand', tex_sand(rng))
    hard = vgrid(sampler(M['hard'] | (M['d_hard'] < 6), 0.35))
    ore = vgrid(lambda x, y: math.hypot((x - cx) / 1.45, y - cy) < 46)
    rock = vgrid(sampler(M['rock'] & (M['d_rk'] > 10), 0.5)) & ~ore
    pond = vgrid(lambda x, y: math.hypot((x - 610) / 1.5, y - 96 - OFF) < 24)
    rock |= pond
    G.paint(layer(hard), 'hard', tex_cracked(rng, 6), 'flat')
    G.paint(layer(rock), 'rock', tex_cracked(rng, 3, knobs=6), 'raised')
    Mo = layer(ore)
    G.paint(Mo, 'orer', tex_cracked(rng, 5, (1, 2), knobs=3), 'raised')
    Mp = layer(pond)
    G.paint(Mp, 'pond', tex_water(rng), 'sunken')
    props, deco = [], []
    for j in range(NY):
        for i in range(NX):
            h = (i * 73856093 ^ j * 19349663) % 100
            x0, y0 = i * TS, j * TS
            if G.mat[y0 + 12, x0 + 12] == MI['sand']:
                if h < 22:
                    dune_crest(G, x0 + 12, y0 + 10)
                elif h < 30:
                    deco.append(('pebbles', x0 + 6 + h % 12, y0 + 8 + h % 9))
                elif h < 37:
                    deco.append(('tuft', x0 + 4 + h % 15, y0 + 5 + h % 13))
            deco += ore_crystals(Mo, x0, y0, h)
    ys, xs = np.nonzero(Mp)
    pcx, pcy, = xs.mean(), ys.mean()
    for k in range(14):                                          # bush ring round the pond
        a = k / 14 * 2 * math.pi
        props.append(('bush', pcx + math.cos(a) * 20, pcy + math.sin(a) * 13))
    foundation = ((V7_RED[0]) * TS, (V7_RED[1]) * TS)
    return G, M, props, deco, V8.D7, foundation, 'red'


def forest12():
    M = V10.forest_masks(np.random.default_rng(11))
    rng = np.random.default_rng(7)
    cx, cy = ROCK_C[0], ROCK_C[1] + OFF
    G = Ground('grass', tex_grass(rng))
    dirt = vgrid(sampler(M['dirt'], 0.35))
    stone = vgrid(sampler(M['stone'], 0.45))
    river = vgrid(sampler(M['d_w'] < 4, 0.3))
    ore = vgrid(lambda x, y: math.hypot((x - cx) / 1.4, y - cy) < 44)
    dirt |= ore
    G.paint(layer(dirt), 'dirt', tex_dirt(rng), 'flat')
    G.paint(layer(stone), 'stone', tex_stone(rng), 'raised')
    G.paint(layer(river), 'river', tex_water(rng), 'sunken')
    Mo = layer(ore)
    G.paint(Mo, 'oreg', tex_cracked(rng, 5, (2, 3), knobs=3), 'raised')
    props, deco = [], []
    clear = np.zeros((NY, NX), bool)
    for u in V8.F7:
        x, y = world_xy(u[2], u[3])
        clear[max(0, int(y // TS) - 1):int(y // TS) + 1, max(0, int(x // TS) - 1):int(x // TS) + 2] = True
    clear[V7_BLUE[1] - 1:V7_BLUE[1] + 3, V7_BLUE[0] - 1:V7_BLUE[0] + 3] = True
    kinds = ['oak', 'lime', 'pine', 'olive']
    floor = np.zeros((WH, WW), bool)
    for j in range(NY):
        for i in range(NX):
            h = (i * 73856093 ^ j * 19349663) % 997
            x0, y0 = i * TS, j * TS
            ground_ok = G.mat[y0 + 12, x0 + 12] == MI['grass'] and not clear[j, i]
            fr = M['forest'][j * 32:(j + 1) * 32, i * 32:(i + 1) * 32].mean()
            fnv = M['fn'][min(j * 32 + 16, M['fn'].shape[0] - 1), min(i * 32 + 16, M['fn'].shape[1] - 1)]
            if ground_ok and fr > 0.45:
                pat = [[(5, 5), (17, 9), (9, 18)], [(15, 4), (5, 13), (18, 19)], [(10, 6), (21, 14), (3, 19)]][h % 3]
                for n_, (dx, dy) in enumerate(pat):
                    k = kinds[(h // 3 + n_ + (i + j) % 2) % 4]
                    props.append((k, x0 + dx, y0 + dy))
            elif ground_ok and (fnv > 0.25 and h % 4 == 0 or h % 23 == 0):
                props.append((kinds[h % 4], x0 + 12, y0 + 12))
            elif ground_ok and h % 9 == 1:
                deco.append(('flowers_p' if h % 2 else 'flowers_y', x0 + 8 + h % 9, y0 + 8 + h % 7))
            elif ground_ok and h % 13 == 2:
                props.append(('bush', x0 + 10 + h % 5, y0 + 12))
            elif ground_ok and h % 17 == 3:
                props.append(('boulders', x0 + 12, y0 + 10))
            deco += ore_crystals(Mo, x0, y0, h)
            if fr > 0.45 and not clear[j, i] and G.mat[y0 + 12, x0 + 12] == MI['grass']:
                floor[y0:y0 + TS, x0:x0 + TS] = True
    G.shade(floor & (G.mat == MI['grass']), 1)
    foundation = (V7_BLUE[0] * TS, V7_BLUE[1] * TS)
    return G, M, props, deco, V8.F7, foundation, 'blue'


V7_BLUE = (4, 10)          # foundation cell (v7's BLUE_R on the stone patch, snapped to the 24 px grid)
V7_RED = (21, 4)


def get_spr(kind):
    if kind in TREES:
        return tree_spr(kind)
    if kind.startswith('crys'):
        return crystal_spr(int(kind[-1]))
    return prop_spr(kind)


def build_world(biome):
    G, M, props, deco, units, (fx, fy), team = (forest12 if biome == 'forest' else desert12)()
    items = []                                                  # (y, sprite, x)
    for (k, x, y) in props:
        items.append((y, get_spr(k), x))
    ulist = []
    for u in units:
        if u[0].startswith('radar'):
            s = sprite12(u[0], 0, 16, 1.25)
            ulist.append((fy + TS, s, fx + TS, u))
        else:
            x, y = world_xy(u[2], u[3])
            ulist.append((y, sprite12(u[0], u[1], 16 if not u[0].startswith('inf') else 12), x, u))
    shadows = np.zeros((WH, WW), bool)
    for (y, s, x) in items:
        shadows |= shadow_mask(s, x, y)
    for (y, s, x, u) in ulist:
        shadows |= shadow_mask(s, x, y)
    G.shade(shadows & (G.mat != MI['pond']) & (G.mat != MI['river']), 2)
    G.shade(shadows & ((G.mat == MI['pond']) | (G.mat == MI['river'])), 1)
    rgb = G.rgb()
    foundation12(rgb, fx, fy, team)
    for (k, x, y) in deco:
        blit(rgb, get_spr(k), x, y)
    cx, cy = world_xy(*ROCK_C)
    for a in range(0, 360, 8):                                  # control-zone ring
        x = int(cx + 78 * math.cos(math.radians(a)))
        y = int(cy + 4 + 58 * math.sin(math.radians(a)))
        if 0 <= x < WW - 1 and 0 <= y < WH - 1:
            rgb[y + 1, x] = OUTLINE
            rgb[y, x] = C('#f4f0e0')
    allit = [(y, s, x, None) for (y, s, x) in items] + ulist
    for (y, s, x, u) in sorted(allit, key=lambda t: t[0]):
        if u is not None and u[4] == 'sel':
            d = ImageDraw.Draw(im := Image.fromarray(rgb))
            d.ellipse([x - 5, y - 1, x + 5, y + 3], outline=(236, 244, 220))
            rgb[:] = np.asarray(im)
        blit(rgb, s, x, y)
        if u is not None and u[4] == 'sel':
            hb = Image.fromarray(rgb)
            d = ImageDraw.Draw(hb)
            d.rounded_rectangle([x - 7, y - 14, x + 7, y - 11], radius=1, fill=tuple(OUTLINE))
            d.rectangle([x - 6, y - 13, x + 3, y - 12], fill=(76, 200, 84))
            rgb[:] = np.asarray(hb)
    return rgb, G


# ---------------------------------------------------------------- pixel font and icons (5x7, monospace)
FONT = {
    'A': ".###.|#...#|#...#|#####|#...#|#...#|#...#", 'B': "####.|#...#|#...#|####.|#...#|#...#|####.",
    'C': ".###.|#...#|#....|#....|#....|#...#|.###.", 'D': "####.|#...#|#...#|#...#|#...#|#...#|####.",
    'E': "#####|#....|#....|####.|#....|#....|#####", 'F': "#####|#....|#....|####.|#....|#....|#....",
    'G': ".###.|#...#|#....|#.###|#...#|#...#|.####", 'H': "#...#|#...#|#...#|#####|#...#|#...#|#...#",
    'I': ".###.|..#..|..#..|..#..|..#..|..#..|.###.", 'J': "..###|...#.|...#.|...#.|#..#.|#..#.|.##..",
    'K': "#...#|#..#.|#.#..|##...|#.#..|#..#.|#...#", 'L': "#....|#....|#....|#....|#....|#....|#####",
    'M': "#...#|##.##|#.#.#|#.#.#|#...#|#...#|#...#", 'N': "#...#|#...#|##..#|#.#.#|#..##|#...#|#...#",
    'O': ".###.|#...#|#...#|#...#|#...#|#...#|.###.", 'P': "####.|#...#|#...#|####.|#....|#....|#....",
    'Q': ".###.|#...#|#...#|#...#|#.#.#|#..#.|.##.#", 'R': "####.|#...#|#...#|####.|#.#..|#..#.|#...#",
    'S': ".####|#....|#....|.###.|....#|....#|####.", 'T': "#####|..#..|..#..|..#..|..#..|..#..|..#..",
    'U': "#...#|#...#|#...#|#...#|#...#|#...#|.###.", 'V': "#...#|#...#|#...#|#...#|#...#|.#.#.|..#..",
    'W': "#...#|#...#|#...#|#.#.#|#.#.#|#.#.#|.#.#.", 'X': "#...#|#...#|.#.#.|..#..|.#.#.|#...#|#...#",
    'Y': "#...#|#...#|.#.#.|..#..|..#..|..#..|..#..", 'Z': "#####|....#|...#.|..#..|.#...|#....|#####",
    '0': ".###.|#...#|#..##|#.#.#|##..#|#...#|.###.", '1': "..#..|.##..|..#..|..#..|..#..|..#..|.###.",
    '2': ".###.|#...#|....#|...#.|..#..|.#...|#####", '3': "####.|....#|....#|.###.|....#|....#|####.",
    '4': "...#.|..##.|.#.#.|#..#.|#####|...#.|...#.", '5': "#####|#....|####.|....#|....#|#...#|.###.",
    '6': ".###.|#....|#....|####.|#...#|#...#|.###.", '7': "#####|....#|...#.|..#..|.#...|.#...|.#...",
    '8': ".###.|#...#|#...#|.###.|#...#|#...#|.###.", '9': ".###.|#...#|#...#|.####|....#|....#|.###.",
    ':': ".....|..#..|..#..|.....|..#..|..#..|.....", '/': "....#|....#|...#.|..#..|.#...|#....|#....",
    '.': ".....|.....|.....|.....|.....|..#..|..#..", ',': ".....|.....|.....|.....|..#..|..#..|.#...",
    '[': ".###.|.#...|.#...|.#...|.#...|.#...|.###.", ']': ".###.|...#.|...#.|...#.|...#.|...#.|.###.",
    '-': ".....|.....|.....|.###.|.....|.....|.....", "'": "..#..|..#..|.#...|.....|.....|.....|.....",
    ' ': ".....|.....|.....|.....|.....|.....|.....",
}
ICON = {
    'gem': "..###..|.#####.|#######|.#####.|..###..|...#...|.......",
    'bolt': "....##.|...##..|..####.|....##.|...##..|..##...|.#.....",
    'castle': "#.#.#.#|#######|.#####.|.##.##.|.##.##.|.#####.|.......",
    'tank': ".......|..###..|..#####|#######|#######|.#.#.#.|.......",
    'helm': "..###..|.#####.|#######|##...##|##...##|#.....#|.......",
    'crown': "#..#..#|##.#.##|#######|#######|.#####.|.......|.......",
    'cog': "..#.#..|.#####.|##...##|.#...#.|##...##|.#####.|..#.#..",
    'move': "..####.|....##.|...#.#.|..#..#.|.#.....|#......|.......",
    'stop': "#.....#|.#...#.|..#.#..|...#...|..#.#..|.#...#.|#.....#",
    'shield': "#######|#######|#######|.#####.|.#####.|..###..|...#...",
    'form': "...#...|..#.#..|..#.#..|.#...#.|.#...#.|#######|.......",
    'lock': "..###..|.#...#.|.#...#.|#######|###.###|###.###|#######",
}
UI = dict(bg=C('#e2e8f0'), bg2=C('#cbd5e2'), line=C('#8494aa'), dark=C('#222c3a'), dim=C('#5e6c80'),
          btn=C('#45679c'), btn_hi=C('#7094cc'), btn_lo=C('#2a4370'), btxt=C('#f4f7fb'), shade=C('#9aa7b8'))


def glyph(canvas, x, y, rows, col):
    for r, line in enumerate(rows.split('|')):
        for c, ch in enumerate(line):
            if ch == '#' and 0 <= y + r < canvas.shape[0] and 0 <= x + c < canvas.shape[1]:
                canvas[y + r, x + c] = col


def text(canvas, x, y, s, col, align='l'):
    s = s.upper()
    w = len(s) * 6 - 1
    if align == 'c':
        x -= w // 2
    elif align == 'r':
        x -= w
    for i, ch in enumerate(s):
        glyph(canvas, x + i * 6, y, FONT.get(ch, FONT[' ']), col)


def icon(canvas, name, cx, cy, col):
    glyph(canvas, cx - 3, cy - 3, ICON[name], col)


def rbox(canvas, box, fill, line=None, r=2):
    im = Image.fromarray(canvas)
    d = ImageDraw.Draw(im)
    d.rounded_rectangle(box, radius=r, fill=tuple(fill), outline=tuple(line) if line is not None else None)
    canvas[:] = np.asarray(im)


def button(canvas, box, r=2):
    x0, y0, x1, y1 = box
    rbox(canvas, box, UI['btn'], UI['btn_lo'], r)
    canvas[y0 + 1, x0 + r:x1 - r + 1] = UI['btn_hi']
    canvas[y1 - 1, x0 + r:x1 - r + 1] = UI['btn_lo']


def bar(canvas, box, frac, col):
    x0, y0, x1, y1 = box
    rbox(canvas, box, UI['dark'], None, 1)
    xe = x0 + 1 + int((x1 - x0 - 2) * frac)
    if xe > x0 + 1:
        rbox(canvas, [x0 + 1, y0 + 1, xe, y1 - 1], col, None, 1)


def pic_on(ground, s, w, h, sx=0, sy=0):
    pic = np.zeros((h, w, 3), np.uint8)
    pic[:] = ground
    blit(pic, s, w // 2 + sx, h // 2 + sy)
    return pic


def framed(canvas, x, y, pic):
    h, w = pic.shape[:2]
    rbox(canvas, [x - 1, y - 1, x + w, y + h], UI['line'], UI['line'], 2)
    canvas[y:y + h, x:x + w] = pic
    for (px, py) in ((x, y), (x + w - 1, y), (x, y + h - 1), (x + w - 1, y + h - 1)):
        canvas[py, px] = UI['line']                             # round the picture's corners too


MM_COL = {'sand': '#d08e4a', 'hard': '#e4c69c', 'rock': '#5a4838', 'orer': '#8a48e0', 'pond': '#2e78c0',
          'grass': '#5c8a32', 'dirt': '#8e6a40', 'stone': '#7e786c', 'river': '#2c68aa', 'oreg': '#8a48e0'}


def minimap(G, units, view, team_found, biome):
    """Flat minimap: one colour per terrain type per cell, forest one flat green, big outlined unit dots."""
    mm = np.zeros((NY * 4, NX * 4, 3), np.uint8)
    for j in range(NY):
        for i in range(NX):
            vals, cnt = np.unique(G.mat[j * TS:(j + 1) * TS, i * TS:(i + 1) * TS], return_counts=True)
            mm[j * 4:(j + 1) * 4, i * 4:(i + 1) * 4] = C(MM_COL[MATS[vals[np.argmax(cnt)]]])
    if biome == 'forest':
        Mf = V10.forest_masks(np.random.default_rng(11))['forest']
        for j in range(NY):
            for i in range(NX):
                if Mf[j * 32:(j + 1) * 32, i * 32:(i + 1) * 32].mean() > 0.45 and MATS[G.mat[j * TS + 12, i * TS + 12]] == 'grass':
                    mm[j * 4:(j + 1) * 4, i * 4:(i + 1) * 4] = C('#2e5a24')
    fx, fy, team = team_found
    tc = {'blue': (C('#3a72f0'), C('#c8dcff')), 'red': (C('#e83a2e'), C('#ffd2c8'))}
    x, y = fx // 6, fy // 6
    mm[y - 1:y + 9, x - 1:x + 9] = OUTLINE
    mm[y:y + 8, x:x + 8] = tc[team][0]
    for u in units:
        if u[0].startswith('radar'):
            continue
        t = 'blue' if 'blue' in u[0] else 'red'
        ux, uy = world_xy(u[2], u[3])
        px, py = int(ux / 6), int(uy / 6)
        mm[max(0, py - 2):py + 3, max(0, px - 2):px + 3] = OUTLINE              # 3x3 dot with dark outline
        mm[max(0, py - 1):py + 2, max(0, px - 1):px + 2] = tc[t][0]
        mm[py - 1, px - 1] = tc[t][1]
    vx, vy = view
    im = Image.fromarray(mm)
    ImageDraw.Draw(im).rectangle([vx // 6, vy // 6, (vx + SBX) // 6, (vy + SH) // 6], outline=(255, 255, 255))
    return np.asarray(im).copy()


def hud(screen, G, units, view, found, biome):
    team = found[2]
    red = team == 'red'
    gnd = PAL['sand'][2] if red else PAL['grass'][2]
    # full-width top bar, rounded at the bottom corners
    rbox(screen, [0, -4, SW - 1, TBH], UI['bg'], UI['line'], 3)
    for (x0, x1, label) in ((3, 68, 'OBJECTIVES'), (71, 136, 'MENU [ESC]')):
        button(screen, [x0, 2, x1, 11])
        text(screen, (x0 + x1) // 2 + 1, 3, label, UI['btxt'], 'c')
    text(screen, 148, 4, 'THE FIRST CLAIM', UI['dark'])
    icon(screen, 'gem', 252, 7, C('#9a48f0'))
    text(screen, 259, 4, '340', UI['dark'])
    icon(screen, 'bolt', 288, 7, C('#3a7ae0'))
    text(screen, 295, 4, '14/20', UI['dark'])
    rbox(screen, [330, 2, 362, 11], UI['dark'], None, 3)
    text(screen, 347, 3, '00:17' if red else '00:42', UI['btxt'], 'c')
    # hero portrait
    rbox(screen, [2, 17, 37, 61], UI['bg'], UI['line'], 3)
    hp = Image.open(f'{RAW}/hero_{team}.png').convert('RGBA')
    bg = Image.new('RGBA', hp.size, tuple(UI['bg2']) + (255,))
    bg.alpha_composite(hp)
    face = bg.convert('RGB').crop((66, 28, 254, 216)).resize((30, 30), Image.BOX)
    face = np.asarray(face.quantize(colors=16, method=Image.Quantize.MEDIANCUT, dither=Image.Dither.NONE)
                      .convert('RGB')).copy()
    framed(screen, 5, 20, face)
    bar(screen, [5, 53, 34, 56], 0.78, C('#44c050'))
    bar(screen, [5, 57, 34, 59], 0.55, C('#3a7ae0'))
    # sidebar
    rbox(screen, [SBX, TBH + 2, SW - 2, SH - 2], UI['bg'], UI['line'], 4)
    x0 = SBX + 4
    rbox(screen, [x0, 20, x0 + 4, 87], UI['dark'], None, 2)                    # power bar
    rbox(screen, [x0 + 1, 40, x0 + 3, 86], C('#3a7ae0'), None, 1)
    mm = minimap(G, units, view, found, biome)
    framed(screen, x0 + 8, 20, mm)
    tabs = ['castle', 'tank', 'helm', 'crown', 'cog']
    sel_tab = 1 if red else 0
    for i, ic in enumerate(tabs):
        bx = x0 + i * 21
        if i == sel_tab:
            button(screen, [bx, 92, bx + 19, 103])
            icon(screen, ic, bx + 10, 97, UI['btxt'])
        else:
            rbox(screen, [bx, 92, bx + 19, 103], UI['bg2'], UI['line'], 2)
            icon(screen, ic, bx + 10, 97, UI['dim'])
    # preview
    rbox(screen, [x0, 107, SW - 6, 155], UI['bg2'], UI['line'], 3)
    sel = 'tank' if red else 'radar'
    if sel == 'tank':
        s = sprite12('tank_red', 7)
        pic = pic_on(gnd, s, 100, 22, 0, 2)
        name, cost, d1, d2 = 'TANK', 'COST 450', 'TRACKED ARMOUR,', 'HARD TO KILL.'
    else:
        s = sprite12('radar_blue', 0, 16, 1.25)
        pic = pic_on(PAL['stone'][2], s, 100, 22, 0, 4)
        name, cost, d1, d2 = 'RADAR', 'COST 600', 'REVEALS TERRAIN', 'AND ENEMY MOVES.'
    framed(screen, x0 + 2, 110, pic[2:20])
    text(screen, x0 + 2, 130, name, UI['dark'])
    text(screen, SW - 9, 130, cost, UI['dim'], 'r')
    text(screen, x0 + 2, 139, d1, UI['dim'])
    text(screen, x0 + 2, 147, d2, UI['dim'])
    # build grid 3x2
    cells = [('light', 'scout'), ('tank', 'tank'), ('harv', 'harv')] if red else [('radar', 'radar')]
    for c in range(6):
        bx, by = x0 + (c % 3) * 35, 159 + (c // 3) * 24
        box = [bx, by, bx + 33, by + 22]
        if c < len(cells):
            kind = cells[c][0]
            selc = (red and c == 1) or (not red and c == 0)
            rbox(screen, box, UI['btn'] if selc else UI['bg2'], UI['btn_lo'] if selc else UI['line'], 2)
            if kind == 'radar':
                s = sprite12('radar_blue', 0, 16, 1.25)
                p = pic_on(PAL['stone'][2], s, 30, 19, 0, 2)
            else:
                s = sprite12(f'{kind}_{team}', 7)
                p = pic_on(gnd, s, 30, 19, 0, 1)
            framed(screen, bx + 2, by + 2, p)
        else:
            rbox(screen, box, UI['bg2'], UI['line'], 2)
            icon(screen, 'lock', bx + 17, by + 11, UI['shade'])
    # build queue
    rbox(screen, [x0, 209, SW - 6, 228], UI['bg2'], UI['line'], 3)
    qs = sprite12('tank_red', 7) if red else sprite12('radar_blue', 0, 16, 1.25)
    framed(screen, x0 + 2, 211, pic_on(gnd if red else PAL['stone'][2], qs, 18, 15, 0, 1))
    text(screen, x0 + 24, 212, 'TANK' if red else 'RADAR', UI['dark'])
    bar(screen, [x0 + 24, 221, SW - 10, 225], 0.35 if red else 0.6, C('#44c050'))
    # commands
    for i, ic in enumerate(('move', 'stop', 'shield', 'form')):
        bx = x0 + i * 26
        button(screen, [bx, 232, bx + 24, 247], 3)
        icon(screen, ic, bx + 12, 239, UI['btxt'])
    # selection strip
    rbox(screen, [x0, 251, SW - 6, 267], UI['bg2'], UI['line'], 3)
    inf = sprite12(f'infs_{team}', 7, 12)
    framed(screen, x0 + 2, 253, pic_on(gnd, inf, 13, 12, 0, 1))
    text(screen, x0 + 19, 253, 'LEGIONARY' if red else 'GUARDSMAN', UI['dark'])
    bar(screen, [x0 + 19, 262, SW - 10, 265], 0.75, C('#44c050'))


def cursor(screen, x, y):
    rows = "#.......|##......|#*#.....|#**#....|#***#...|#****#..|#**###..|##.#*#..|#..#*#..|....##.."
    for r, line in enumerate(rows.split('|')):
        for c, ch in enumerate(line):
            if ch == '#':
                screen[y + r, x + c] = OUTLINE
            elif ch == '*':
                screen[y + r, x + c] = C('#f4f0e0')


def compose(biome, view):
    rgb, G = build_world(biome)
    vx, vy = view
    screen = np.zeros((SH, SW, 3), np.uint8)
    screen[:, :SBX] = rgb[vy:vy + SH, vx:vx + SBX]
    units = V8.F7 if biome == 'forest' else V8.D7
    team = 'blue' if biome == 'forest' else 'red'
    fcell = V7_BLUE if biome == 'forest' else V7_RED
    hud(screen, G, units, view, (fcell[0] * TS, fcell[1] * TS, team), biome)
    cx, cy = world_xy(300, 300) if biome == 'forest' else world_xy(470, 330)
    cursor(screen, int(cx - vx), int(cy - vy))
    Image.fromarray(screen).save(f'{OUT}/v13_{biome}_native.png')
    Image.fromarray(screen).resize((SW * SC, SH * SC), Image.NEAREST).save(f'{OUT}/v13_{biome}.png')
    print('saved', biome)
    return rgb


def colour_report():
    rows = []
    for k in list(TREES) + ['bush', 'flowers_p', 'boulders', 'pebbles', 'tuft', 'crys0', 'crys1', 'crys2']:
        s = get_spr(k)
        rows.append((k, len(np.unique(s['rgb'][s['a']].reshape(-1, 3), axis=0))))
    for nm in ('tank_red', 'tank_blue', 'harv_red', 'light_blue', 'infs_red', 'radar_red', 'radar_blue'):
        s = sprite12(nm, 0, 16, 1.25) if nm.startswith('radar') else sprite12(nm, 7, 12 if nm.startswith('inf') else 16)
        rows.append((nm, len(np.unique(s['rgb'][s['a']].reshape(-1, 3), axis=0))))
    for m in PAL:
        rows.append((f'tile:{m}', len(PAL[m])))
    print('colours per object:', ', '.join(f'{k}={n}' for k, n in rows), '| max', max(n for _, n in rows))


if __name__ == '__main__':
    for biome, view in (('forest', (30, 110)), ('desert', (184, 80))):
        if biome in WHICH:
            compose(biome, view)
    colour_report()
