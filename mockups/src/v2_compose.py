# Balance style test v2 -- warm fantasy look: forest (Blue) and desert (Red) mock screenshots.
# Run: python v2_compose.py <raw_sprite_dir> <out_dir> [forest desert]
import sys, os, math
import numpy as np
from PIL import Image, ImageDraw, ImageFilter, ImageFont

RAW, OUT = sys.argv[1], sys.argv[2]
WHICH = sys.argv[3:] or ['forest', 'desert']
os.makedirs(OUT, exist_ok=True)

W, H = 960, 540            # internal resolution, shown x2 -> 1920x1080
TOP = 26                   # top bar height
VW, VH = 746, H - TOP      # map viewport
SS = 4
FONTS = 'C:/Windows/Fonts/'


def font(name, size):
    return ImageFont.truetype(FONTS + name, size)


F_TITLE = font('georgiaz.ttf', 20)
F_B12 = font('georgiab.ttf', 12)
F_B11 = font('georgiab.ttf', 11)
F_R11 = font('georgia.ttf', 11)
F_S10 = font('verdanab.ttf', 9)
F_S9 = font('verdana.ttf', 9)


def hexc(s):
    s = s.lstrip('#')
    return np.array([int(s[i:i + 2], 16) for i in (0, 2, 4)], np.float32) / 255


def pal(cols):
    return np.stack([hexc(c) for c in cols])


def ramp(v, cols):
    """Hard-banded palette lookup (pixel-art shading)."""
    p = pal(cols) if isinstance(cols, list) else cols
    i = np.clip((v * len(p)).astype(np.int32), 0, len(p) - 1)
    return p[i]


def ramp_s(v, cols):
    """Smooth palette lookup (metal, wood)."""
    p = pal(cols) if isinstance(cols, list) else cols
    t = np.clip(v, 0, 1) * (len(p) - 1)
    i = np.clip(t.astype(np.int32), 0, len(p) - 2)
    f = (t - i)[..., None]
    return p[i] * (1 - f) + p[i + 1] * f


def fbm(h, w, scale, rng, octaves=3, stretch=(1.0, 1.0)):
    out = np.zeros((h, w), np.float32)
    amp, tot = 1.0, 0.0
    for o in range(octaves):
        sx, sy = max(1.0, scale * stretch[0] / 2 ** o), max(1.0, scale * stretch[1] / 2 ** o)
        gh, gw = int(h / sy) + 4, int(w / sx) + 4
        g = Image.fromarray(rng.random((gh, gw)).astype(np.float32))
        a = np.asarray(g.resize((int(gw * sx), int(gh * sy)), Image.BICUBIC))
        oy, ox = int(sy), int(sx)
        out += a[oy:oy + h, ox:ox + w] * amp
        tot += amp
        amp *= 0.5
    return out / tot


def box1(a, r, axis):
    if r < 1:
        return a
    padw = [(0, 0)] * a.ndim
    padw[axis] = (r + 1, r)
    c = np.cumsum(np.pad(a, padw, mode='edge'), axis=axis, dtype=np.float64)
    n = a.shape[axis]
    if axis == 0:
        return ((c[2 * r + 1:2 * r + 1 + n] - c[:n]) / (2 * r + 1)).astype(np.float32)
    return ((c[:, 2 * r + 1:2 * r + 1 + n] - c[:, :n]) / (2 * r + 1)).astype(np.float32)


def blur(a, r, passes=2):
    r = int(round(r))
    for _ in range(passes):
        a = box1(box1(a, r, 0), r, 1)
    return a


def grow(mask, px):
    return np.asarray(Image.fromarray((mask * 255).astype(np.uint8)).filter(ImageFilter.MaxFilter(2 * px + 1))) > 127


def shrink(mask, px):
    return np.asarray(Image.fromarray((mask * 255).astype(np.uint8)).filter(ImageFilter.MinFilter(2 * px + 1))) > 127


def polydist(xx, yy, pts, step=5):
    P = []
    for (a, b) in zip(pts, pts[1:]):
        n = max(2, int(math.hypot(b[0] - a[0], b[1] - a[1]) / step))
        for t in np.linspace(0, 1, n, endpoint=False):
            P.append((a[0] + (b[0] - a[0]) * t, a[1] + (b[1] - a[1]) * t))
    P.append(pts[-1])
    d = np.full(xx.shape, 1e12, np.float32)
    for (px, py) in P:
        d = np.minimum(d, (xx - px) ** 2 + (yy - py) ** 2)
    return np.sqrt(d)


def voronoi(h, w, cell, rng):
    gh, gw = h // cell + 3, w // cell + 3
    px = (np.arange(gw)[None, :] - 1 + rng.random((gh, gw))) * cell
    py = (np.arange(gh)[:, None] - 1 + rng.random((gh, gw))) * cell
    val = rng.random((gh, gw)).astype(np.float32)
    yy, xx = np.mgrid[0:h, 0:w]
    iy, ix = yy // cell + 1, xx // cell + 1
    f1 = np.full((h, w), 1e9, np.float32)
    f2 = f1.copy()
    v = np.zeros((h, w), np.float32)
    for oy in (-1, 0, 1):
        for ox in (-1, 0, 1):
            cy_, cx_ = np.clip(iy + oy, 0, gh - 1), np.clip(ix + ox, 0, gw - 1)
            d = np.hypot(px[cy_, cx_] - xx, py[cy_, cx_] - yy).astype(np.float32)
            f2 = np.minimum(f2, np.maximum(f1, d))
            v = np.where(d < f1, val[cy_, cx_], v)
            f1 = np.minimum(f1, d)
    return f1, f2, v


# --- sprites -----------------------------------------------------------------------------
_cache = {}


def sprite(name, k=0, outline='inner', colors=40, sat=1.12):
    key = (name, k)
    if key in _cache:
        return _cache[key]
    a = np.asarray(Image.open(f'{RAW}/{name}_{k:02d}.png').convert('RGBA')).astype(np.float32) / 255
    sh = np.asarray(Image.open(f'{RAW}/{name}_{k:02d}_sh.png').convert('RGBA')).astype(np.float32)[..., 3] / 255
    n = a.shape[0] // SS

    def ds(x):
        return x.reshape(n, SS, n, SS, -1).mean((1, 3))

    pa = ds(a[..., 3:])
    col = ds(a[..., :3] * a[..., 3:]) / np.maximum(pa, 1e-4)
    sh = ds(sh[..., None])[..., 0]
    alpha = pa[..., 0] > 0.42
    g = col.mean(-1, keepdims=True)
    col = np.clip(g + (col - g) * sat, 0, 1)
    if colors:                                         # limited palette -> hand-pixelled feel
        fill = col[alpha].mean(0) if alpha.any() else np.zeros(3)
        im = Image.fromarray((np.where(alpha[..., None], col, fill) * 255).astype(np.uint8))
        im = im.quantize(colors=colors, method=Image.Quantize.MEDIANCUT, dither=Image.Dither.NONE).convert('RGB')
        col = np.asarray(im).astype(np.float32) / 255
    if outline:
        nb = np.zeros_like(alpha)
        acc = np.zeros_like(col)
        cnt = np.zeros(alpha.shape, np.float32)
        for dy, dx in ((0, 1), (0, -1), (1, 0), (-1, 0)):
            sa = np.roll(alpha, (dy, dx), (0, 1))
            sc = np.roll(col, (dy, dx), (0, 1))
            if outline == 'outer':
                e = sa & ~alpha
                acc += sc * e[..., None]
                cnt += e
            else:
                nb |= alpha & ~sa
        if outline == 'outer':
            e = cnt > 0
            oc = acc / np.maximum(cnt, 1)[..., None]
            col = np.where(e[..., None], oc * 0.22 + hexc('#140a08') * 0.5, col)
            alpha = alpha | e
        else:
            col = np.where(nb[..., None], col * 0.55 + hexc('#1a0e12') * 0.12, col)
    ys, xs = np.nonzero(alpha | (sh > 0.03))
    y0, y1, x0, x1 = ys.min(), ys.max() + 1, xs.min(), xs.max() + 1
    s = dict(rgb=col[y0:y1, x0:x1], a=alpha[y0:y1, x0:x1].astype(np.float32), sh=sh[y0:y1, x0:x1],
             ax=n // 2 - x0, ay=n // 2 - y0)
    _cache[key] = s
    return s


def put(canvas, x0, y0, rgb, a):
    h, w = a.shape
    Hc, Wc = canvas.shape[:2]
    xs, ys, xe, ye = max(0, x0), max(0, y0), min(Wc, x0 + w), min(Hc, y0 + h)
    if xs >= xe or ys >= ye:
        return
    sa = a[ys - y0:ye - y0, xs - x0:xe - x0]
    if canvas.ndim == 3:
        sa = sa[..., None]
        canvas[ys:ye, xs:xe] = canvas[ys:ye, xs:xe] * (1 - sa) + rgb[ys - y0:ye - y0, xs - x0:xe - x0] * sa
    else:
        canvas[ys:ye, xs:xe] = np.maximum(canvas[ys:ye, xs:xe], sa)


def to_img(a):
    return Image.fromarray((np.clip(a, 0, 1) * 255).astype(np.uint8))


def to_arr(im):
    return np.asarray(im.convert('RGB')).astype(np.float32) / 255


def scatter(rng, mask, n, margin=2):
    ys, xs = np.nonzero(mask[margin:-margin, margin:-margin])
    if len(ys) == 0:
        return []
    i = rng.integers(0, len(ys), n)
    return [(int(xs[j]) + margin, int(ys[j]) + margin) for j in i]


def place(rng, weight, n, mind, taken, tries=6000):
    """Random points with minimum spacing, accepted with probability weight[y, x]."""
    h, w = weight.shape
    out = []
    for _ in range(tries):
        if len(out) >= n:
            break
        x, y = int(rng.integers(0, w)), int(rng.integers(0, h))
        if rng.random() > weight[y, x]:
            continue
        if any((x - a) ** 2 + (y - b) ** 2 < mind * mind for a, b in taken):
            continue
        taken.append((x, y))
        out.append((x, y))
    return out


# --- terrain: forest ------------------------------------------------------------------------
GRASS = ['#2c6a1e', '#3a8024', '#4f982b', '#6bb033', '#8cc63f', '#b4dc55']
FLOOR = ['#1c3d1a', '#25501d', '#316421', '#3f7826', '#4f8c2c']
DIRT = ['#6a4322', '#82552b', '#9c6a37', '#b58246', '#cc9c5a', '#dfb777']
WATER = ['#1b5d8c', '#2278aa', '#2e96c2', '#4fb6d6', '#8adcec']
ROCK_C = (373, 250)        # where the Orichalcum formation stands (viewport pixels)


def paint_forest(rng):
    h, w = VH, VW
    yy, xx = np.mgrid[0:h, 0:w].astype(np.float32)
    cx, cy = ROCK_C
    wx = (fbm(h, w, 60, rng) - 0.5) * 70
    wy = (fbm(h, w, 60, rng) - 0.5) * 70
    X, Y = xx + wx, yy + wy
    fringe = (rng.random((h, w)).astype(np.float32) - 0.5) * 5
    d_clear = np.hypot((X - cx) / 1.3, Y - cy - 8) - 86
    d_p1 = polydist(X, Y, [(cx - 70, cy + 60), (250, 400), (150, 450), (60, 540)]) - 17
    d_p2 = polydist(X, Y, [(cx + 90, cy - 10), (540, 205), (650, 225), (770, 180)]) - 17
    d_dirt = np.minimum(np.minimum(d_clear, d_p1), d_p2)
    dirt = d_dirt + fringe < 0
    d_w = polydist(X, Y, [(270, -20), (245, 50), (190, 95), (120, 120), (55, 175), (-30, 205)]) - 15
    water = d_w < 0
    bank = (d_w < 6) & ~water
    edge = 1 - np.minimum(np.minimum(xx, w - xx), np.minimum(yy, h - yy)) / 170
    dn = fbm(h, w, 120, rng, 3)
    dense = ((dn - 0.5) * 2.2 + np.clip(edge, 0, 1) * 0.9 > 0.5) & (d_dirt > 26) & (d_w > 16)
    densef = blur(dense.astype(np.float32), 9)

    g = 0.52 + (fbm(h, w, 110, rng, 4) - 0.5) * 1.7 + (fbm(h, w, 5, rng, 2, (0.6, 1.6)) - 0.5) * 0.5
    g += (rng.random((h, w)).astype(np.float32) - 0.5) * 0.10
    rgb = ramp(np.clip(g - densef * 0.15, 0, 0.999), GRASS)
    fl = 0.5 + (fbm(h, w, 60, rng, 3) - 0.5) * 1.5 + (rng.random((h, w)).astype(np.float32) - 0.5) * 0.25
    rgb = np.where((densef > 0.5)[..., None], ramp(np.clip(fl, 0, 0.999), FLOOR), rgb)

    dv = 0.5 + (fbm(h, w, 45, rng, 4) - 0.5) * 1.5 + np.clip(-d_dirt / 60, 0, 0.25)
    dv += (rng.random((h, w)).astype(np.float32) - 0.5) * 0.12
    rgb = np.where(dirt[..., None], ramp(np.clip(dv, 0, 0.999), DIRT), rgb)
    lip = dirt & ~shrink(dirt, 1)                       # shadow under the grass lip
    rgb[lip] = hexc('#553318')
    rim = grow(dirt, 1) & ~dirt
    rgb[rim] = hexc('#a6d44e')

    rgb[bank] = ramp(np.clip(0.5 + (fbm(h, w, 12, rng) - 0.5) * 2, 0, 0.999), ['#b89a5c', '#d4b876', '#e8d092'])[bank]
    wv = 0.45 + np.clip(-d_w / 30, 0, 0.3) * -1.0 + (fbm(h, w, 30, rng) - 0.5) * 0.9
    rip = np.sin(xx * 0.45 + yy * 0.8 + wx * 0.25) > 0.93
    wc = ramp(np.clip(wv + 0.35 * rip, 0, 0.999), WATER)
    rgb = np.where(water[..., None], wc, rgb)
    rgb[water & ~shrink(water, 1)] = hexc('#164a70')

    light = 1 + 0.16 * (fbm(h, w, 150, rng, 2) - 0.5) * 2          # broad sun / shade patches
    rgb = rgb * light[..., None]

    im = to_img(rgb)
    d = ImageDraw.Draw(im)
    grass = ~dirt & ~water & ~bank & (densef < 0.4)
    for (x, y) in scatter(rng, grass, 1500):
        c = '#c6e860' if rng.random() < 0.55 else '#2a5e1c'
        d.point([(x, y), (x - 1, y - 1), (x + 1, y - 1)], fill=c)
    fcols = ['#ff4a3a', '#ffd83a', '#fff4e0', '#b56cff', '#ff8ac0', '#ff9a2a']
    for (x, y) in scatter(rng, grass & (d_dirt > 6), 46):
        c = fcols[int(rng.integers(0, len(fcols)))]
        for _ in range(int(rng.integers(3, 9))):
            fx, fy = x + int(rng.integers(-11, 12)), y + int(rng.integers(-8, 9))
            if 1 < fx < w - 2 and 1 < fy < h - 2 and grass[fy, fx]:
                d.point((fx, fy + 1), fill='#2a5e1c')
                d.point((fx, fy), fill=c)
                if rng.random() < 0.5:
                    d.point([(fx - 1, fy), (fx + 1, fy), (fx, fy - 1)], fill=c)
                    d.point((fx, fy), fill='#fff6c0')
    for (x, y) in scatter(rng, dirt & (d_dirt < -4), 170):
        s = int(rng.integers(1, 3))
        d.rectangle([x, y, x + s, y + 1], fill='#e6c890' if rng.random() < 0.6 else '#c8b8a0')
        d.line([x, y + 2, x + s, y + 2], fill='#5a3a1e')
    for (x, y) in scatter(rng, densef > 0.6, 500):
        d.point((x, y), fill=['#d88a2a', '#e8c040', '#8a5a2a'][int(rng.integers(0, 3))])
    for (x, y) in scatter(rng, shrink(water, 3), 14):               # lily pads
        d.ellipse([x - 2, y - 1, x + 2, y + 1], fill='#3c9a3a')
        d.point((x, y - 1), fill='#ff9ac8')
    rgb = to_arr(im)
    return rgb, dict(dirt=dirt, water=water | bank, dense=dense, densef=densef, d_dirt=d_dirt, d_w=d_w)


UNITS_F = [('inf_blue', 7, 250, 356, 'sel'), ('inf_blue', 6, 286, 384, ''), ('inf_blue', 7, 214, 388, ''),
           ('inf_blue', 6, 250, 418, ''),
           ('inf_red', 1, 548, 214, ''), ('inf_red', 2, 590, 196, ''), ('inf_red', 1, 598, 234, ''),
           ('inf_red', 2, 640, 214, '')]


def forest_entities(rng, M):
    h, w = VH, VW
    cx, cy = ROCK_C
    E = [('ori_forest', 0, cx, cy + 6)]
    for nm, dx, dy in (('shard_a', -66, 34), ('shard_a', 58, 40), ('shard_a', 12, 54)):
        E.append((nm, 0, cx + dx, cy + dy))
    taken = [(cx, cy)]
    ok = (M['d_dirt'] > 22) & (M['d_w'] > 14)
    wd = np.where(ok, 0.05 + 0.95 * (M['densef'] > 0.45), 0).astype(np.float32)
    kinds = ['tree_a'] * 6 + ['tree_b'] * 5 + ['tree_c'] * 4 + ['tree_d'] * 3 + ['pine_a'] * 3 + ['pine_b'] * 3 + \
            ['tree_aut'] * 2 + ['tree_pink']
    for u in UNITS_F:
        wd[max(0, u[3] - 14):u[3] + 96, max(0, u[2] - 46):u[2] + 46] = 0
    wd[cy - 30:cy + 110, cx - 90:cx + 90] = 0
    for (x, y) in place(rng, wd, 92, 31, taken):
        E.append((kinds[int(rng.integers(0, len(kinds)))], 0, x, y))
    edge = np.where(ok & (M['densef'] > 0.08) & (M['densef'] < 0.5), 1.0, 0.02 * ok).astype(np.float32)
    for u in UNITS_F:
        edge[max(0, u[3] - 10):u[3] + 40, max(0, u[2] - 30):u[2] + 30] = 0
    small = ['bush_a', 'bush_b', 'bush_a', 'bush_b', 'shroom_r', 'shroom_v', 'rockf_a', 'rockf_b', 'bush_a']
    for (x, y) in place(rng, edge, 26, 26, taken):
        E.append((small[int(rng.integers(0, len(small)))], 0, x, y))
    E += [('rockf_c', 0, 520, 330), ('rockf_b', 0, 236, 250), ('rockf_a', 0, 470, 150), ('shroom_r', 0, 300, 180)]
    return E, UNITS_F


# --- terrain: desert --------------------------------------------------------------------------
SAND = ['#b5531f', '#c96928', '#dc8232', '#eb9d42', '#f6ba5b', '#ffd67c']
HARD = ['#a8623c', '#c07a4c', '#d6945f', '#e6ae78', '#f2c692']
MESA = ['#7c2c1a', '#983d22', '#b2522d', '#ca6a3b', '#de8650']
CLIFF = ['#3f140e', '#571d14', '#70291a', '#883823']


def paint_desert(rng):
    h, w = VH, VW
    yy, xx = np.mgrid[0:h, 0:w].astype(np.float32)
    cx, cy = ROCK_C
    wx = (fbm(h, w, 70, rng) - 0.5) * 80
    wy = (fbm(h, w, 70, rng) - 0.5) * 80
    X, Y = xx + wx, yy + wy
    big = (fbm(h, w, 190, rng, 2) - 0.5) * 2
    phase = (0.28 * xx + yy) / 74 + big * 2.2
    t = phase - np.floor(phase)
    dune = 0.22 + 0.68 * t ** 1.3
    dune += 0.05 * np.sin(yy * 1.5 + xx * 0.35 + big * 40) + (rng.random((h, w)).astype(np.float32) - 0.5) * 0.09
    rgb = ramp(np.clip(dune, 0, 0.999), SAND)

    d_clear = np.hypot((X - cx) / 1.35, Y - cy - 8) - 84
    d_p1 = polydist(X, Y, [(cx + 80, cy + 50), (520, 380), (640, 440), (760, 470)]) - 20
    d_p2 = polydist(X, Y, [(cx - 90, cy - 20), (210, 190), (110, 150), (-20, 120)]) - 20
    d_hard = np.minimum(np.minimum(d_clear, d_p1), d_p2)
    hard = d_hard + (rng.random((h, w)).astype(np.float32) - 0.5) * 6 < 0
    f1, f2, fv = voronoi(h, w, 15, rng)
    hv = 0.45 + (fv - 0.5) * 0.5 + (fbm(h, w, 50, rng) - 0.5) * 0.9
    hc = ramp(np.clip(hv, 0, 0.999), HARD)
    hc[(f2 - f1) < 0.9] = hexc('#935536')
    rgb = np.where(hard[..., None], hc, rgb)
    rgb[grow(hard, 1) & ~hard] = hexc('#ffe296')

    corner = np.maximum(1 - np.hypot(xx - 40, yy - 470) / 250, 1 - np.hypot(xx - 700, yy - 60) / 230)
    corner = np.maximum(corner, 1 - np.hypot(xx - 90, yy - 20) / 150)
    mv = (fbm(h, w, 100, rng, 3) - 0.5) * 1.3 + corner
    mesa = (mv > 0.52) & (d_hard > 30)
    mesa = shrink(grow(mesa, 3), 3)
    CH = 13
    below = np.zeros_like(mesa)
    below[CH:] = mesa[:-CH]
    cl = np.zeros_like(mesa)
    for k in range(1, CH + 1):
        s = np.zeros_like(mesa)
        s[k:] = mesa[:-k]
        cl |= s
    cliff = cl & ~mesa
    g1, g2, gv = voronoi(h, w, 30, rng)
    tv = 0.5 + (gv - 0.5) * 0.55 + (fbm(h, w, 70, rng) - 0.5) * 0.8
    tc = ramp(np.clip(tv, 0, 0.999), MESA)
    tc[(g2 - g1) < 1.0] = hexc('#6a2416')
    rgb = np.where(mesa[..., None], tc, rgb)
    cvv = 0.5 + (fbm(h, w, 14, rng, 2, (0.35, 3.0)) - 0.5) * 1.6
    rgb = np.where(cliff[..., None], ramp(np.clip(cvv, 0, 0.999), CLIFF), rgb)
    top_edge = mesa & ~shrink(mesa, 1)
    rgb[top_edge] = hexc('#f0a060')
    shadow = blur(np.roll(grow(mesa | cliff, 1).astype(np.float32), 9, 1), 4) * (~(mesa | cliff))
    rgb = rgb * (1 - 0.42 * shadow[..., None]) + hexc('#3a1838') * 0.42 * shadow[..., None] * 0.6

    ox, oy = 610, 96                                            # oasis
    d_o = np.hypot((X - ox) / 1.5, Y - oy)
    oasis = (d_o < 24) & ~mesa & ~cliff
    green = (d_o < 36) & ~oasis & ~mesa & ~cliff
    gg = 0.5 + (fbm(h, w, 20, rng) - 0.5) * 1.6
    rgb = np.where(green[..., None], ramp(np.clip(gg, 0, 0.999), ['#4f8a22', '#6aa62b', '#8cc23a', '#b4d850']), rgb)
    wv = 0.4 + (fbm(h, w, 25, rng) - 0.5) * 0.9 + 0.35 * (np.sin(xx * 0.5 + yy * 0.9 + wx * 0.3) > 0.92)
    rgb = np.where(oasis[..., None], ramp(np.clip(wv, 0, 0.999), ['#12787c', '#1a9a98', '#2cbcb0', '#6adccc', '#b4f2e4']),
                   rgb)
    rgb[oasis & ~shrink(oasis, 1)] = hexc('#0e5a60')

    light = 1 + 0.10 * (fbm(h, w, 170, rng, 2) - 0.5) * 2
    rgb = rgb * light[..., None]
    im = to_img(rgb)
    d = ImageDraw.Draw(im)
    sand = ~hard & ~mesa & ~cliff & ~oasis & ~green
    for (x, y) in scatter(rng, sand, 260):
        c = '#e8c85a' if rng.random() < 0.5 else '#9a6a22'
        d.point([(x, y), (x - 1, y - 1), (x + 1, y - 1), (x, y - 2)], fill=c)
    for (x, y) in scatter(rng, sand | hard, 240):
        s = int(rng.integers(1, 3))
        d.rectangle([x, y, x + s, y + 1], fill='#8a3a20' if rng.random() < 0.6 else '#f2d0a0')
        d.line([x, y + 2, x + s, y + 2], fill='#5a2412')
    for (x, y) in scatter(rng, mesa, 120):
        d.point([(x, y), (x + 1, y)], fill='#e89a5c')
    rgb = to_arr(im)
    return rgb, dict(hard=hard, mesa=mesa, cliff=cliff, oasis=oasis | green, d_hard=d_hard, d_o=d_o, sand=sand)


def desert_entities(rng, M):
    cx, cy = ROCK_C
    E = [('ori_desert', 0, cx, cy + 6)]
    for nm, dx, dy in (('shard_b', -64, 36), ('shard_b', 60, 38), ('shard_b', 8, 56)):
        E.append((nm, 0, cx + dx, cy + dy))
    taken = [(cx, cy)]
    for nm, x, y in (('palm_a', 574, 100), ('palm_b', 650, 92), ('palm_a', 628, 128), ('palm_b', 592, 70),
                     ('succ_a', 560, 126), ('succ_b', 664, 118), ('ribs', 196, 372), ('deadtree', 452, 404),
                     ('spire_a', 96, 440), ('spire_b', 690, 40), ('spire_b', 60, 60), ('rockd_c', 168, 300),
                     ('spire_a', 706, 300)):
        E.append((nm, 0, x, y))
        taken.append((x, y))
    free = (M['sand'] & (M['d_hard'] > 14)).astype(np.float32)
    small = ['rockd_a', 'rockd_b', 'rockd_a', 'succ_a', 'succ_b', 'drybush', 'drybush', 'drybush', 'rockd_b']
    for (x, y) in place(rng, free * 0.6, 32, 48, taken):
        E.append((small[int(rng.integers(0, len(small)))], 0, x, y))
    for (x, y) in place(rng, M['mesa'].astype(np.float32) * 0.5, 9, 60, taken):
        E.append((['spire_b', 'rockd_c', 'rockd_a'][int(rng.integers(0, 3))], 0, x, y))
    units = [('inf_red', 1, 516, 372, 'sel'), ('inf_red', 2, 556, 352, ''), ('inf_red', 1, 562, 398, ''),
             ('inf_red', 2, 602, 378, ''),
             ('inf_blue', 7, 214, 184, ''), ('inf_blue', 6, 176, 162, ''), ('inf_blue', 7, 170, 204, ''),
             ('inf_blue', 6, 132, 182, '')]
    return E, units


# --- entity pass ----------------------------------------------------------------------------------
def draw_world(rgb, E, units, ring_col):
    h, w = rgb.shape[:2]
    shmap = np.zeros((h, w), np.float32)
    glow = np.zeros((h, w, 3), np.float32)
    items = [(e[3], e, sprite(e[0], e[1])) for e in E]
    items += [(u[3], u, sprite(u[0], u[1], outline='outer', colors=48, sat=1.2)) for u in units]
    for _, e, s in items:
        put(shmap, e[2] - s['ax'], e[3] - s['ay'], None, s['sh'])
    sm = np.clip(shmap, 0, 1)[..., None] * 0.55
    rgb = rgb * (1 - sm) + rgb * hexc('#3a2a6a') * sm * 1.1
    im = to_img(rgb)
    d = ImageDraw.Draw(im)
    cx, cy = ROCK_C
    for a in range(0, 360, 5):                                   # control zone around the rock
        x = cx + 118 * math.cos(math.radians(a))
        y = cy + 8 + 88 * math.sin(math.radians(a))
        d.rectangle([x - 1, y, x + 1, y + 2], fill='#3a1c08')
        d.rectangle([x - 1, y - 1, x, y], fill=ring_col)
    for u in units:
        if u[4] == 'sel':
            d.ellipse([u[2] - 17, u[3] - 8, u[2] + 17, u[3] + 9], outline='#143a10', width=2)
            d.ellipse([u[2] - 16, u[3] - 7, u[2] + 16, u[3] + 8], outline='#8cff5a')
    rgb = to_arr(im)
    for _, e, s in sorted(items, key=lambda t: t[0]):
        x0, y0 = e[2] - s['ax'], e[3] - s['ay']
        put(rgb, x0, y0, s['rgb'], s['a'])
        if e[0].startswith(('ori', 'shard')) or e[0].startswith('inf'):
            c = s['rgb']
            hot = ((c[..., 0] > 0.9) & (c[..., 1] > 0.55) & (c[..., 2] < 0.75) & (s['a'] > 0)) if not e[0].startswith(
                'inf_blue') else ((c[..., 2] > 0.95) & (c[..., 1] > 0.85) & (c[..., 0] > 0.6) & (s['a'] > 0))
            put(glow, x0, y0, c, hot.astype(np.float32))
    return rgb, glow


def overlays(im, units):
    d = ImageDraw.Draw(im)
    for u in units:
        if u[4] == 'sel':
            x, y = u[2], u[3] - 66
            d.rounded_rectangle([x - 12, y, x + 12, y + 4], 2, fill='#1a100a')
            d.rounded_rectangle([x - 11, y + 1, x + 7, y + 3], 1, fill='#6ae04a')
            d.line([x - 11, y + 1, x + 7, y + 1], fill='#b8ff8a')


# --- HUD ----------------------------------------------------------------------------------------------
GOLD = ['#3a2206', '#6b430e', '#a5701a', '#d6a22c', '#f4d056', '#fff2a6']
COPPER = ['#2e1206', '#5e2a0e', '#96501c', '#cc7c30', '#f0aa52', '#ffe0a0']
OAK = ['#241207', '#3f220e', '#5c3517', '#784a22', '#93602f', '#ab7740']
LACQ = ['#1e0806', '#3a100b', '#571a11', '#74261a', '#8f3524', '#a84a32']
PARCH = ['#a9834c', '#c9a76c', '#e2c88e', '#f1dfae', '#faf0cc']
PANEL = ['#0c0705', '#150d08', '#20140c', '#2c1c12', '#3a2718']
SAPPH = ['#081a52', '#12379a', '#2462dc', '#5aa4ff', '#c8ecff']
RUBY = ['#3c0606', '#7c100c', '#c4241a', '#ff5c40', '#ffc8a8']
ORIP = ['#6a2a04', '#b85a0c', '#f08a1c', '#ffbe44', '#fff0a0']
IVORY = ['#6b5a3c', '#a8946c', '#d8c69c', '#f4e8c4', '#fffbe8']
THEMES = {
    'blue': dict(frame=OAK, trim=GOLD, accent=SAPPH, name='Guardsman', sub='Blue Infantry', sky=('#4a9ae0', '#ffe9b0'),
                 mission='Mission 1  -  The First Claim', hold='Hold  0:42'),
    'red': dict(frame=LACQ, trim=COPPER, accent=RUBY, name='Legionary', sub='Red Infantry', sky=('#c8401c', '#ffd070'),
                mission='Mission 1  -  The First Claim', hold='Hold  0:17'),
}


class Layers:
    def __init__(self, S=3):
        self.S = S
        self.rgb = np.zeros((H * S, W * S, 3), np.float32)
        self.a = np.zeros((H * S, W * S), np.float32)

    def mask(self, fn):
        im = Image.new('L', (W * self.S, H * self.S), 0)
        fn(ImageDraw.Draw(im), self.S)
        return np.asarray(im).astype(np.float32) / 255

    def layer(self, m, palette, bevel=2.0, depth=1.0, tex=None, shadow=0.0, outline=True):
        S = self.S
        if shadow:
            sm = blur(np.roll(np.roll(m, int(shadow * S), 0), int(shadow * S * 0.5), 1), shadow * S * 0.7) * 0.6
            self.rgb *= (1 - sm)[..., None]
            self.a = np.maximum(self.a, sm * (self.a < 0.5))
        if outline:
            e = np.asarray(Image.fromarray((m * 255).astype(np.uint8)).filter(ImageFilter.MaxFilter(5))) / 255.0
            self.rgb *= (1 - 0.75 * e * (1 - m))[..., None]
            self.a = np.maximum(self.a, e * 0.85)
        R = max(1, int(bevel * S))
        hgt = blur(m, R)
        gx = np.zeros_like(hgt)
        gy = np.zeros_like(hgt)
        gx[:, 1:-1] = hgt[:, 2:] - hgt[:, :-2]
        gy[1:-1] = hgt[2:] - hgt[:-2]
        shade = 0.5 + depth * R * 0.55 * (gx + gy * 1.2)
        if tex is not None:
            shade = shade + tex
        col = ramp_s(shade, palette)
        self.rgb = self.rgb * (1 - m[..., None]) + col * m[..., None]
        self.a = np.maximum(self.a, m)

    def result(self):
        S = self.S
        a = self.a.reshape(H, S, W, S).mean((1, 3))
        rgb = (self.rgb * self.a[..., None]).reshape(H, S, W, S, 3).mean((1, 3)) / np.maximum(a, 1e-4)[..., None]
        return rgb, a


def P(S, *c):
    return [v * S for v in c]


ICONS = {
    'sword': [('line', (5, 11, 13, 3), 2.2), ('line', (3, 8.5, 7.5, 13), 1.8), ('dot', (3, 13), 1.4)],
    'swords': [('line', (4, 12, 13, 3), 2.0), ('line', (12, 12, 3, 3), 2.0), ('line', (2.5, 9.5, 6.5, 13.5), 1.6),
               ('line', (13.5, 9.5, 9.5, 13.5), 1.6)],
    'move': [('line', (3, 13, 10, 6), 2.4), ('poly', (13.5, 2.5, 6.5, 4, 12, 9.5))],
    'shield': [('poly', (3, 2.5, 13, 2.5, 13, 8, 8, 14, 3, 8))],
    'heal': [('rect', (6.3, 2.5, 9.7, 13.5)), ('rect', (2.5, 6.3, 13.5, 9.7))],
    'castle': [('poly', (2.5, 14, 2.5, 4, 5, 4, 5, 6.5, 7, 6.5, 7, 4, 9, 4, 9, 6.5, 11, 6.5, 11, 4, 13.5, 4, 13.5, 14))],
    'crown': [('poly', (2, 12.5, 2, 5, 5, 8.5, 8, 3, 11, 8.5, 14, 5, 14, 12.5))],
    'flag': [('line', (4, 2.5, 4, 14), 1.6), ('poly', (4.5, 3, 13.5, 6, 4.5, 9))],
    'cog': [('ring', (8, 8), 4.6, 2.6)] + [('dot', (8 + 5.6 * math.cos(i * math.pi / 4), 8 + 5.6 * math.sin(
        i * math.pi / 4)), 1.5) for i in range(8)],
    'helm': [('chord', (3, 2.5, 13, 13.5), 180, 360), ('rect', (3, 8, 13, 9.6)), ('rect', (3, 9, 5.6, 13)),
             ('rect', (10.4, 9, 13, 13)), ('rect', (7.2, 8, 8.8, 12))],
    'glass': [('poly', (3.5, 2.5, 12.5, 2.5, 8, 8)), ('poly', (3.5, 13.5, 12.5, 13.5, 8, 8)),
              ('rect', (3, 2, 13, 3.2)), ('rect', (3, 12.8, 13, 14))],
    'gem': [('poly', (8, 1, 13.5, 5.5, 11, 14.5, 5, 14.5, 2.5, 5.5))],
    'scales': [('line', (8, 2.5, 8, 13), 1.4), ('line', (2.5, 5, 13.5, 5), 1.4), ('rect', (5, 12.6, 11, 14)),
               ('chord', (0.6, 5.5, 5.6, 10.5), 0, 180), ('chord', (10.4, 5.5, 15.4, 10.5), 0, 180), ('dot', (8, 3), 1.6)],
}


def draw_icon(d, S, name, x, y, k=1.0):
    def T(*c):
        return [(x + c[i] * k) * S if i % 2 == 0 else (y + c[i] * k) * S for i in range(len(c))]

    for op in ICONS[name]:
        if op[0] == 'line':
            d.line(T(*op[1]), fill=255, width=max(1, int(op[2] * k * S)))
        elif op[0] == 'poly':
            d.polygon(T(*op[1]), fill=255)
        elif op[0] == 'rect':
            d.rectangle(T(*op[1]), fill=255)
        elif op[0] == 'dot':
            cx, cy, r = op[1][0], op[1][1], op[2]
            d.ellipse(T(cx - r, cy - r, cx + r, cy + r), fill=255)
        elif op[0] == 'ring':
            cx, cy = op[1]
            d.ellipse(T(cx - op[2], cy - op[2], cx + op[2], cy + op[2]), fill=255)
            d.ellipse(T(cx - op[3], cy - op[3], cx + op[3], cy + op[3]), fill=0)
        elif op[0] == 'chord':
            d.chord(T(*op[1]), op[2], op[3], fill=255)


def spiral(d, S, cx, cy, r, flip=1, wd=1.6):
    pts = []
    for i in range(60):
        t = i / 59 * 2.6 * math.pi
        rr = r * (1 - 0.82 * i / 59)
        pts.append(((cx + flip * (rr * math.cos(t) - r)) * S, (cy - rr * math.sin(t)) * S))
    d.line(pts, fill=255, width=int(wd * S), joint='curve')


SX = 746                      # sidebar left edge
MM = (764, 42, 942, 186)      # minimap inner rect
TABS = [(771 + i * 40.5, 222) for i in range(5)]
CARD = (756, 246, 950, 400)
ARCH = (764, 254, 834, 344)
CMDS = [(773 + i * 51.3, 433) for i in range(4)]
OBJ = (760, 474, 946, 530)
CAPS = [(176, 4, 420, 21), (438, 4, 590, 21), (600, 4, 706, 21), (716, 4, 834, 21), (846, 4, 952, 21)]
PEND = [100, 215, 330, 445, 560, 675]


def build_hud(theme, rng):
    T = THEMES[theme]
    L = Layers(3)
    S = L.S
    hs, ws = H * S, W * S
    grain = (fbm(hs, ws, 9 * S, rng, 3, (9, 0.5)) - 0.5) * 0.55 + (fbm(hs, ws, 60 * S, rng, 2) - 0.5) * 0.3

    def frame(d, S):
        d.rectangle(P(S, 0, 0, W, TOP - 2), fill=255)
        d.rectangle(P(S, SX + 2, TOP - 2, W, H), fill=255)
    L.layer(L.mask(frame), T['frame'], 2, 0.5, grain, shadow=5)

    def rails(d, S):
        d.rectangle(P(S, 0, TOP - 5, W, TOP + 1), fill=255)
        d.rectangle(P(S, SX - 3, TOP - 5, SX + 4, H), fill=255)
        d.rectangle(P(S, 0, 0, W, 1.5), fill=255)
        d.rectangle(P(S, W - 4, TOP, W, H), fill=255)
        d.rectangle(P(S, SX, H - 5, W, H), fill=255)
        for (cy_, ey) in ((TOP + 1, TOP + 1), (H - 16, H - 31)):       # concave corner fillets
            d.rectangle(P(S, SX - 18, cy_, SX - 2, cy_ + 15), fill=255)
            d.ellipse(P(S, SX - 33, ey, SX - 3, ey + 30), fill=0)
        for x in PEND:                                                  # scalloped pendants under the bar
            d.ellipse(P(S, x - 8, TOP - 9, x + 8, TOP + 8), fill=255)
            d.pieslice(P(S, x - 26, TOP - 12, x - 2, TOP + 12), 0, 90, fill=255)
            d.pieslice(P(S, x + 2, TOP - 12, x + 26, TOP + 12), 90, 180, fill=255)
        d.ellipse(P(S, SX - 11, TOP - 13, SX + 13, TOP + 11), fill=255)  # corner boss
        d.ellipse(P(S, SX - 9, H / 2 - 11, SX + 11, H / 2 + 9), fill=255)
        d.ellipse(P(S, 2, 0, 52, 50), fill=255)                         # emblem medallion
        for c in CAPS:
            d.rounded_rectangle(P(S, c[0] - 2, c[1] - 2, c[2] + 2, c[3] + 2), 10.5 * S, fill=255)
        d.rounded_rectangle(P(S, MM[0] - 7, MM[1] - 7, MM[2] + 7, MM[3] + 7), 16 * S, fill=255)
        for (x, y) in TABS:
            d.ellipse(P(S, x - 15, y - 15, x + 15, y + 15), fill=255)
        d.rounded_rectangle(P(S, CARD[0] - 3, CARD[1] - 3, CARD[2] + 3, CARD[3] + 3), 13 * S, fill=255)
        for (x, y) in CMDS:
            d.ellipse(P(S, x - 20, y - 20, x + 20, y + 20), fill=255)
        d.rounded_rectangle(P(S, OBJ[0] - 8, OBJ[1] - 3, OBJ[2] + 8, OBJ[3] + 3), 9 * S, fill=255)
        spiral(d, S, 838, 204, 9, 1)
        spiral(d, S, 868, 204, 9, -1)
    shine = (fbm(hs, ws, 30 * S, rng, 2, (1.5, 0.6)) - 0.5) * 0.28
    L.layer(L.mask(rails), T['trim'], 2.2, 1.0, shine, shadow=3)

    def insets(d, S):
        for c in CAPS[1:]:
            d.rounded_rectangle(P(S, *c), 8.5 * S, fill=255)
        d.rounded_rectangle(P(S, *MM), 10 * S, fill=255)
        d.ellipse(P(S, ARCH[0], ARCH[1], ARCH[2], ARCH[1] + 70), fill=255)
        d.rectangle(P(S, ARCH[0], ARCH[1] + 35, ARCH[2], ARCH[3]), fill=255)
    L.layer(L.mask(insets), PANEL, 2, -0.6, None)

    def parch(d, S):
        d.rounded_rectangle(P(S, *CAPS[0]), 8.5 * S, fill=255)
        d.rounded_rectangle(P(S, *CARD), 10 * S, fill=255)
        d.rounded_rectangle(P(S, OBJ[0], OBJ[1], OBJ[2], OBJ[3]), 4 * S, fill=255)
    ptex = (fbm(hs, ws, 40 * S, rng, 3) - 0.5) * 0.7 + 0.12
    L.layer(L.mask(parch), PARCH, 1.5, -0.35, ptex)

    def arch_rim(d, S):
        a = ARCH
        d.ellipse(P(S, a[0] - 4, a[1] - 4, a[2] + 4, a[1] + 74), fill=255)
        d.rectangle(P(S, a[0] - 4, a[1] + 35, a[2] + 4, a[3] + 4), fill=255)
        d.ellipse(P(S, a[0], a[1], a[2], a[1] + 70), fill=0)
        d.rectangle(P(S, a[0], a[1] + 35, a[2], a[3]), fill=0)
        for i in range(4):
            x, y = 849 + i * 26, 382
            d.ellipse(P(S, x - 11, y - 11, x + 11, y + 11), fill=255)
        for e in (OBJ[0] - 4, OBJ[2] + 4):                               # scroll rollers
            d.rounded_rectangle(P(S, e - 5, OBJ[1] - 5, e + 5, OBJ[3] + 5), 5 * S, fill=255)
    L.layer(L.mask(arch_rim), T['trim'], 1.8, 1.0, shine, shadow=2)

    def gems(d, S):
        d.ellipse(P(S, 8, 6, 46, 44), fill=255)
        for x in PEND:
            d.ellipse(P(S, x - 4, TOP - 4, x + 4, TOP + 4), fill=255)
        d.ellipse(P(S, SX - 5, TOP - 7, SX + 7, TOP + 5), fill=255)
        d.ellipse(P(S, SX - 4, H / 2 - 6, SX + 6, H / 2 + 4), fill=255)
        for (x, y) in ((MM[0] - 2, MM[1] - 2), (MM[2] + 2, MM[1] - 2), (MM[0] - 2, MM[3] + 2), (MM[2] + 2, MM[3] + 2)):
            d.ellipse(P(S, x - 4, y - 4, x + 4, y + 4), fill=255)
        for i, (x, y) in enumerate(TABS):
            if i == 0:
                d.ellipse(P(S, x - 11.5, y - 11.5, x + 11.5, y + 11.5), fill=255)
        for (x, y) in CMDS:
            d.ellipse(P(S, x - 16, y - 16, x + 16, y + 16), fill=255)
        d.ellipse(P(S, 849, 200, 857, 208), fill=255)
    L.layer(L.mask(gems), T['accent'], 3.0, 0.9, None)

    def dark_btn(d, S):
        for i, (x, y) in enumerate(TABS):
            if i:
                d.ellipse(P(S, x - 11.5, y - 11.5, x + 11.5, y + 11.5), fill=255)
        for i in range(4):
            x, y = 849 + i * 26, 382
            d.ellipse(P(S, x - 8.5, y - 8.5, x + 8.5, y + 8.5), fill=255)
    L.layer(L.mask(dark_btn), PANEL, 2, -0.6, None)

    def icons(d, S):
        draw_icon(d, S, 'scales', 13, 12.5, 1.75)
        for i, nm in enumerate(('sword', 'crown', 'castle', 'flag', 'cog')):
            draw_icon(d, S, nm, TABS[i][0] - 7, TABS[i][1] - 7, 0.9)
        for i, nm in enumerate(('move', 'swords', 'shield', 'heal')):
            draw_icon(d, S, nm, CMDS[i][0] - 9.5, CMDS[i][1] - 9.5, 1.2)
        draw_icon(d, S, 'helm', CAPS[2][0] + 6, CAPS[2][1] + 2, 0.85)
        draw_icon(d, S, 'glass', CAPS[3][0] + 6, CAPS[3][1] + 2, 0.85)
    L.layer(L.mask(icons), IVORY, 1.0, 0.8, None, shadow=1)

    def ore(d, S):
        draw_icon(d, S, 'gem', CAPS[1][0] + 5, CAPS[1][1] + 1.5, 0.9)
    L.layer(L.mask(ore), ORIP, 1.6, 1.0, None)
    return L.result()


def shape_mask(fn, w, h, S=4):
    im = Image.new('L', (w * S, h * S), 0)
    fn(ImageDraw.Draw(im), S)
    return np.asarray(im.resize((w, h), Image.BOX)).astype(np.float32) / 255


def text(d, x, y, s, f, fill, shadow=None, anchor='la'):
    if shadow:
        d.text((x + 1, y + 1), s, font=f, fill=shadow, anchor=anchor)
    d.text((x, y), s, font=f, fill=fill, anchor=anchor)


def minimap(biome, rng):
    w, h = MM[2] - MM[0], MM[3] - MM[1]
    yy, xx = np.mgrid[0:h, 0:w].astype(np.float32)
    n1, n2 = fbm(h, w, 34, rng, 3), fbm(h, w, 20, rng, 3)
    wob = (fbm(h, w, 25, rng) - 0.5) * 24
    if biome == 'forest':
        rgb = ramp(np.clip(0.5 + (n1 - 0.5) * 2, 0, 0.999), ['#3a8024', '#4f982b', '#6bb033', '#8cc63f'])
        rgb = np.where((n2 > 0.55)[..., None], ramp(np.clip(n1 * 1.4 - 0.2, 0, 0.999), ['#1c3d1a', '#25501d', '#316421']),
                       rgb)
        pth = polydist(xx + wob, yy + wob, [(20, 130), (60, 100), (92, 76), (130, 60), (172, 40)]) < 4
        riv = polydist(xx + wob, yy, [(60, -5), (50, 30), (20, 50), (-5, 60)]) < 3.5
        rgb[pth] = hexc('#b58246')
        rgb[riv] = hexc('#2e96c2')
        view = (58, 42, 130, 96)
        me, foe = '#3a8cff', '#ff3a2a'
        mine = [(70, 84), (74, 88), (66, 90), (72, 93)]
        theirs = [(112, 62), (117, 59), (119, 65), (124, 62)]
    else:
        rgb = ramp(np.clip(0.5 + (n1 - 0.5) * 2.2, 0, 0.999), ['#c96928', '#dc8232', '#eb9d42', '#f6ba5b'])
        rgb = np.where((n2 > 0.58)[..., None], ramp(np.clip(n1 * 1.4 - 0.2, 0, 0.999), ['#7c2c1a', '#983d22', '#b2522d']),
                       rgb)
        pth = polydist(xx + wob, yy + wob, [(10, 40), (60, 60), (92, 76), (130, 100), (175, 120)]) < 5
        rgb[pth] = hexc('#d6945f')
        oa = np.hypot(xx - 118, yy - 54) < 5
        rgb[oa] = hexc('#2cbcb0')
        view = (58, 46, 130, 100)
        me, foe = '#ff3a2a', '#3a8cff'
        mine = [(108, 88), (112, 86), (113, 91), (117, 89)]
        theirs = [(76, 66), (72, 64), (71, 69), (67, 66)]
    seen = np.clip(1.6 - np.hypot((xx - 94 + wob * 0.4) / 1.25, yy - 72 + wob * 0.4) / 52, 0, 1)
    dth = ((xx.astype(int) + yy.astype(int)) % 2) * 0.25
    vis = np.clip(seen + dth - 0.2, 0, 1) > 0.5
    rgb = np.where(vis[..., None], rgb, rgb * 0.16 + hexc('#0a0604') * 0.6)
    im = to_img(rgb)
    d = ImageDraw.Draw(im)
    d.rectangle([90, 73, 94, 76], fill='#ffb030')
    d.rectangle([91, 72, 93, 74], fill='#fff0a0')
    for (x, y) in mine:
        d.rectangle([x, y, x + 1, y + 1], fill=me)
    for (x, y) in theirs:
        d.rectangle([x, y, x + 1, y + 1], fill=foe)
    d.rounded_rectangle(list(view), 3, outline='#fff6d8')
    return to_arr(im)


def portrait_img(team, sky, w, h):
    src = Image.open(f'{RAW}/inf_{team}_portrait.png').convert('RGBA')
    n = src.size[0]
    grad = np.linspace(0, 1, n)[:, None, None]
    bgc = hexc(sky[0]) * (1 - grad) + hexc(sky[1]) * grad
    bg = Image.fromarray((np.broadcast_to(bgc, (n, n, 3)) * 255).astype(np.uint8)).convert('RGBA')
    bg.alpha_composite(src)
    cw = int(n * w / h)
    x0 = (n - cw) // 2
    im = bg.convert('RGB').crop((x0, 0, x0 + cw, n)).resize((w, h), Image.LANCZOS)
    im = im.quantize(colors=40, method=Image.Quantize.MEDIANCUT, dither=Image.Dither.NONE).convert('RGB')
    return to_arr(im)


def compose(biome, theme, seed):
    rng = np.random.default_rng(seed)
    if biome == 'forest':
        terr, M = paint_forest(rng)
        E, units = forest_entities(rng, M)
    else:
        terr, M = paint_desert(rng)
        E, units = desert_entities(rng, M)
    world, glow = draw_world(terr, E, units, '#fff0b0')
    world = world * np.array([1.04, 1.0, 0.94], np.float32)                 # warm grade
    world = world + blur(glow, 2) * 0.16 + blur(glow, 9) * 0.3
    wim = to_img(world)
    overlays(wim, units)
    d = ImageDraw.Draw(wim)                                                   # pointer
    px, py = (300, 300) if biome == 'forest' else (470, 330)
    d.polygon([(px, py), (px, py + 13), (px + 4, py + 10), (px + 9, py + 9)], fill='#fff2c0', outline='#3a1c08')
    frame = np.zeros((H, W, 3), np.float32)
    frame[TOP:, :VW] = to_arr(wim)

    T = THEMES[theme]
    hud, ha = build_hud(theme, np.random.default_rng(seed + 7))
    frame = frame * (1 - ha[..., None]) + hud * ha[..., None]

    mm = minimap(biome, np.random.default_rng(seed + 3))
    w, h = MM[2] - MM[0], MM[3] - MM[1]
    m = shape_mask(lambda d, S: d.rounded_rectangle([0, 0, w * S - 1, h * S - 1], 10 * S, fill=255), w, h)
    put(frame, MM[0], MM[1], mm, m)
    aw, ah = ARCH[2] - ARCH[0], ARCH[3] - ARCH[1]
    pm = shape_mask(lambda d, S: (d.ellipse([0, 0, aw * S - 1, 70 * S], fill=255),
                                  d.rectangle([0, 35 * S, aw * S - 1, ah * S - 1], fill=255)), aw, ah)
    team = 'blue' if theme == 'blue' else 'red'
    put(frame, ARCH[0], ARCH[1], portrait_img(team, T['sky'], aw, ah), pm)
    src = Image.open(f'{RAW}/inf_{team}_portrait.png').convert('RGBA')
    hb = Image.new('RGBA', src.size, tuple(int(v * 255) for v in hexc(T['sky'][0])) + (255,))
    hb.alpha_composite(src)
    head = to_arr(hb.crop((150, 95, 340, 285)).resize((17, 17), Image.LANCZOS))
    hm = shape_mask(lambda d, S: d.ellipse([0, 0, 17 * S - 1, 17 * S - 1], fill=255), 17, 17)
    for i in range(4):
        put(frame, 849 + i * 26 - 8, 382 - 8, head, hm)

    im = to_img(frame)
    d = ImageDraw.Draw(im)
    d.fontmode = '1'
    ink, light, sh = '#3a1c08', '#fff0c4', '#1a0c04'
    text(d, 60, 0, 'Balance', F_TITLE, '#ffe28a', '#2a1004')
    c = CAPS[0]
    text(d, (c[0] + c[2]) // 2, c[1] + 2, T['mission'], F_B11, ink, None, 'ma')
    c = CAPS[1]
    text(d, c[0] + 24, c[1] + 2, 'Orichalcum', F_B11, '#ffcf70', sh)
    text(d, c[2] - 8, c[1] + 2, '340', F_B12, light, sh, 'ra')
    c = CAPS[2]
    text(d, c[0] + 24, c[1] + 2, 'Squad', F_B11, '#ffcf70', sh)
    text(d, c[2] - 8, c[1] + 2, '4 / 4', F_B12, light, sh, 'ra')
    c = CAPS[3]
    text(d, c[0] + 24, c[1] + 2, T['hold'], F_B11, light, sh)
    c = CAPS[4]
    text(d, (c[0] + c[2]) // 2, c[1] + 2, 'Menu   F10', F_B11, light, sh, 'ma')
    x = ARCH[2] + 12
    text(d, x, 254, T['name'], F_B12, ink)
    text(d, x, 269, T['sub'], F_R11, '#6a4420')
    d.rounded_rectangle([x, 287, x + 96, 296], 4, fill='#3a1c08')
    d.rounded_rectangle([x + 1, 288, x + 72, 295], 3, fill='#3fae32')
    d.line([x + 3, 289, x + 70, 289], fill='#9be87a')
    text(d, x, 300, 'Health  45 / 60', F_S9, ink)
    text(d, x, 316, 'Attack', F_S9, '#6a4420')
    text(d, x + 96, 316, '12', F_S10, ink, None, 'ra')
    text(d, x, 328, 'Armour', F_S9, '#6a4420')
    text(d, x + 96, 328, '4', F_S10, ink, None, 'ra')
    text(d, x, 340, 'Range', F_S9, '#6a4420')
    text(d, x + 96, 340, '1', F_S10, ink, None, 'ra')
    text(d, 764, 352, 'Squad', F_B11, ink)
    text(d, 764, 376, '4 of 4 fit', F_S9, '#6a4420')
    for i, s in enumerate(('Move', 'Attack', 'Hold', 'Mend')):
        text(d, int(CMDS[i][0]), 455, s, F_S9, light, sh, 'ma')
    text(d, (OBJ[0] + OBJ[2]) // 2, OBJ[1] + 3, 'Objective', F_B11, '#8a2a12', None, 'ma')
    text(d, (OBJ[0] + OBJ[2]) // 2, OBJ[1] + 17, 'Hold the Orichalcum rock', F_R11, ink, None, 'ma')
    bx0, bx1, by = OBJ[0] + 22, OBJ[2] - 22, OBJ[1] + 36
    d.rounded_rectangle([bx0, by, bx1, by + 9], 4, fill='#3a1c08')
    frac = 0.7 if theme == 'blue' else 0.28
    d.rounded_rectangle([bx0 + 1, by + 1, int(bx0 + (bx1 - bx0) * frac), by + 8], 3,
                        fill='#2f78e8' if theme == 'blue' else '#d8301e')
    im.save(f'{OUT}/v2_{biome}_native.png')
    big = im.resize((W * 2, H * 2), Image.NEAREST)
    big.save(f'{OUT}/v2_{biome}.png')
    print('saved', biome)


if __name__ == '__main__':
    if 'forest' in WHICH:
        compose('forest', 'blue', 11)
    if 'desert' in WHICH:
        compose('desert', 'red', 23)
