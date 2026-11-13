# Balance style test v10 -- v8 (map layout, units, buildings, HUD) with the terrain repainted after the user's two
# concept images: one sun from the upper left lights a height map of the whole ground, so dunes, rock plates,
# flagstones, basalt, crystals, tree crowns and stones are shaded and cast short shadows.
#   desert: pale sand with soft wind ridges, dark blue-grey slate rock with raised blocks, grey flagstone paths,
#           black basalt Orichalcum rock with glowing amber crystals, a bright blue oasis ringed by bushes.
#   forest: individual trees (round leafy crowns lit yellow-green, teal pines) with visible trunks, sunlit grass,
#           brown dirt with scratch texture, gravel patches with stones, a blue river with stone banks and glints,
#           a grey cracked Orichalcum rock with glowing crystals, boulders, bushes and flower clumps.
# Writes the full map view (x2) and a medium "gameplay" zoom (x3) per biome.
# Run: python v10_compose.py <raw_sprite_dir> <out_dir> [forest desert]
import os, sys, math, inspect
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from v8_compose import *          # noqa: F401,F403
import v3_compose as V3
import v4_compose as V4
import v8_compose as V8

OFF = H - VH                       # the map fills the full height; viewport y + OFF = world y
SUN = np.array([-0.52, -0.64, 0.56], np.float32)
SUN /= np.linalg.norm(SUN)
SUN_XY = SUN[:2] / np.linalg.norm(SUN[:2])

RAMPS = {
    # desert
    'sand': ['#5d4549', '#7a5850', '#9a6e5a', '#b78564', '#cd9b70', '#dcab7c', '#e8b98a', '#f3c999', '#fcdcb2'],
    'slate': ['#0e1019', '#161825', '#1f2230', '#292c3b', '#333647', '#3f4254', '#4e4f62', '#646373', '#7f7a85'],
    'flag': ['#473b38', '#5c4e49', '#71625a', '#85756b', '#97867a', '#a69585', '#b4a391', '#c2b29e', '#d0c1ac'],
    'basalt': ['#050508', '#0b0b11', '#121219', '#1a1b24', '#23242f', '#2d2f3b', '#3a3c4a', '#4c4d5c', '#646473'],
    'oasis': ['#031a2c', '#052a44', '#073c5e', '#0b5279', '#106a94', '#1984ac', '#32a0c2', '#6cc2d8', '#b4e4ee'],
    'bush': ['#081a0c', '#0f2a12', '#173f18', '#215820', '#2e7228', '#408c2e', '#5aa436', '#7cbc42', '#a6d454'],
    'pebble': ['#0c0d12', '#16171e', '#22232b', '#2f3038', '#3d3d45', '#4d4c53', '#605e63', '#77737a'],
    'found_d': ['#20232b', '#2b2f38', '#373c46', '#434954', '#505662', '#5d6470', '#6b737f', '#7c8490', '#9098a3'],
    # forest
    'grass': ['#0c150a', '#141f0c', '#1d2c0f', '#283a12', '#344815', '#415518', '#4f631c', '#5e7020', '#6f7e25',
              '#86902e', '#a2a43a'],
    'dirt': ['#24150b', '#382211', '#4d3017', '#623e1d', '#764c24', '#87592b', '#986833', '#aa793f', '#bf8e52',
             '#d4a669'],
    'gravel': ['#1e1915', '#2d251f', '#3d332a', '#4e4236', '#5f5142', '#70614f', '#82725e', '#95846f', '#ab9a83',
               '#c4b39b'],
    'river': ['#06102a', '#0b1a3e', '#112653', '#183466', '#20447a', '#2a568e', '#3769a0', '#4c80b4', '#6e9cc8',
              '#a4c4e2'],
    'bankst': ['#2a211c', '#433730', '#5e4e44', '#7a6658', '#947d6c', '#ab9480', '#c0aa94', '#d4c0a8', '#e6d6c0'],
    'ore_g': ['#100d0b', '#1d1916', '#2b2621', '#3a342d', '#4a433a', '#5b5348', '#6d6457', '#827868', '#9a8f7c'],
    'boulder': ['#151513', '#24231f', '#35332e', '#47443d', '#5a564d', '#6e695e', '#837d70', '#999283', '#b2ab9a'],
    'trunk': ['#170e08', '#26170c', '#382212', '#4a2e18', '#5c3b1f', '#6e4927'],
    'leafY': ['#08120c', '#101e0e', '#1b2d10', '#2a4012', '#3d5414', '#546818', '#6d7c1c', '#8a9022', '#a8a42a',
              '#c6b834', '#e2cc46'],
    'leafG': ['#06120f', '#0d1d12', '#162a16', '#20391a', '#2c4a1e', '#3a5c22', '#4a6e26', '#5e802c', '#749232',
              '#8ea43c', '#aab84a'],
    'leafO': ['#0a110c', '#141c0e', '#1f2911', '#2b3814', '#394818', '#49581c', '#5a6820', '#6e7826', '#84882c',
              '#9c9a34', '#b6ac40'],
    'pine': ['#04100f', '#081b1b', '#0d2829', '#133636', '#1a4545', '#225555', '#2c6664', '#387874', '#4a8b86',
             '#64a29a', '#88bcb0'],
    'found_f': ['#25272a', '#313437', '#3e4245', '#4b5054', '#585e62', '#666c70', '#757b7f', '#868c8f', '#9aa0a2'],
}
SPILL = '#ff9a30'                  # colour of the light the Orichalcum throws on the ground
MAT = {k: i for i, k in enumerate(RAMPS)}
RAMP_ARR = {MAT[k]: pal(v) for k, v in RAMPS.items()}


# ---------------------------------------------------------------- lighting
def lam(hm):
    """Sunlight on a height map, relative to flat ground (0 = flat, + = facing the sun)."""
    gy, gx = np.gradient(hm)
    nz = 1 / np.sqrt(1 + gx * gx + gy * gy)
    return (-gx * SUN[0] - gy * SUN[1] + SUN[2]) * nz - SUN[2]


def cast(hm, steps=18, slope=1.15):
    """Soft cast shadow: something toward the sun stands higher than the sun ray."""
    h, w = hm.shape
    p = steps + 2
    P = np.pad(hm, p, mode='edge')
    sh = np.zeros_like(hm)
    for i in range(1, steps + 1):
        dx, dy = int(round(SUN_XY[0] * i)), int(round(SUN_XY[1] * i))
        src = P[p + dy:p + dy + h, p + dx:p + dx + w]
        sh = np.maximum(sh, np.clip((src - hm - i * slope) * 0.8, 0, 1))
    return sh


class Field:
    """The ground as height + material + tone; rendered once at the end under one sun."""

    def __init__(self, h, w):
        self.hm = np.zeros((h, w), np.float32)
        self.mat = np.zeros((h, w), np.int16)
        self.base = np.full((h, w), 0.5, np.float32)
        self.gain = np.ones((h, w), np.float32)
        self.lock = np.zeros((h, w), bool)        # pixels whose tone is final (trees): no normal shading
        self.h, self.w = h, w

    def set(self, m, mat, base, gain=1.0, hm=None):
        self.mat[m] = MAT[mat]
        self.base[m] = base[m] if isinstance(base, np.ndarray) else base
        self.gain[m] = gain[m] if isinstance(gain, np.ndarray) else gain
        if hm is not None:
            self.hm[m] = hm[m] if isinstance(hm, np.ndarray) else hm

    def win(self, x, y, r):
        x0, y0 = max(0, int(x - r)), max(0, int(y - r))
        x1, y1 = min(self.w, int(x + r) + 2), min(self.h, int(y + r) + 2)
        yy, xx = np.mgrid[y0:y1, x0:x1].astype(np.float32)
        return (slice(y0, y1), slice(x0, x1)), xx - x, yy - y

    def dome(self, x, y, rx, ry, height, mat, base, gain=1.2, rng=None, rough=0.18, square=False):
        sl, dx, dy = self.win(x, y, max(rx, ry) + 1)
        if square:
            d = np.maximum(np.abs(dx) / rx, np.abs(dy) / ry)
            hh = height * np.clip((1 - d) * 3.2, 0, 1)
        else:
            d = np.sqrt((dx / rx) ** 2 + (dy / ry) ** 2)
            hh = height * np.sqrt(np.clip(1 - d * d, 0, 1))
        if rng is not None and rough:
            d = d + (rng.random(d.shape).astype(np.float32) - 0.5) * rough * 2
        m = (d < 1) & ~self.lock[sl]
        if not m.any():
            return
        g = self.hm[sl]
        g[m] = np.maximum(g[m], self.ground[sl][m] + hh[m])
        self.mat[sl][m] = MAT[mat]
        b = self.base[sl]
        b[m] = base + (rng.random(m.sum()).astype(np.float32) - 0.5) * 0.06 if rng is not None else base
        self.gain[sl][m] = gain

    def render(self, rng, shadow=0.36, grit=0.025, tree_shadow=0.5):
        L = lam(self.hm)
        sh = cast(blur(self.hm, 1, 1))
        v = self.base + np.where(self.lock, 0, self.gain * L) - np.where(self.lock, tree_shadow, shadow) * sh
        v += (rng.random(v.shape).astype(np.float32) - 0.5) * grit * 2
        v = np.clip(v, 0, 0.999)
        out = np.zeros((self.h, self.w, 3), np.float32)
        for k, P in RAMP_ARR.items():
            m = self.mat == k
            if m.any():
                out[m] = ramp_s(v[m], P)
        self.sh = sh
        return out


def jitter(rng, mask, cell, prob=1.0):
    h, w = mask.shape
    pts = []
    for gy in range(0, h, cell):
        for gx in range(0, w, cell):
            if rng.random() > prob:
                continue
            x, y = gx + int(rng.integers(0, cell)), gy + int(rng.integers(0, cell))
            if x < w and y < h and mask[y, x]:
                pts.append((x, y))
    return pts


def padv(a):
    return np.pad(a, ((OFF, 0), (0, 0)), mode='reflect')


def edge_of(m, px=1):
    return m & ~shrink(m, px)


# ---------------------------------------------------------------- shared props
def crystals(rgb, rng, mask, n, hmin, hmax, glow):
    """Amber Orichalcum crystals standing upright: lit left facet, dark right facet, white-hot tip, glow."""
    pts = [p for p in jitter(rng, mask, 4, 1.0)]
    rng.shuffle(pts)
    pts = sorted(pts[:n], key=lambda p: p[1])
    LIT, MID, DRK, EDGE, TIP = (hexc(c) for c in ('#ffcf5c', '#f39a2a', '#c4601a', '#5a2208', '#fff3c4'))
    hot = np.zeros(rgb.shape[:2], np.float32)
    for (x, y) in pts:
        hh = float(rng.uniform(hmin, hmax))
        wd = max(1.2, hh * float(rng.uniform(0.26, 0.36)))
        lean = float(rng.uniform(-0.25, 0.25))
        for yy in range(int(-hh), 2):
            t = (yy + hh) / (hh + 1)                      # 0 at the tip, 1 at the foot
            half = wd * min(1.0, t * 2.2) * (1 - max(0, t - 0.8) * 2.5)
            cxr = x + lean * (yy + hh) * 0.5
            for xx in range(int(cxr - half - 1), int(cxr + half + 2)):
                if not (0 <= xx < rgb.shape[1] and 0 <= y + yy < rgb.shape[0]):
                    continue
                u = (xx - cxr) / max(half, 0.6)
                if abs(u) > 1.05:
                    continue
                c = LIT if u < -0.15 else (MID if u < 0.35 else DRK)
                if t < 0.18:
                    c = TIP
                if abs(u) > 0.8 and t > 0.25:
                    c = c * 0.55 + EDGE * 0.45
                rgb[y + yy, xx] = c
                hot[y + yy, xx] = 1.0 if t < 0.5 else 0.7
        for k in (1, 2):                                   # tiny contact shadow, lower right
            if 0 <= y + k < rgb.shape[0] and 0 <= x + k < rgb.shape[1]:
                rgb[y + k, x + k] *= 0.6
    g = hot[..., None] * hexc('#ffa22a')
    glow += blur(g, 2) * 0.55 + blur(g, 6) * 0.45 + blur(g, 16) * 0.35


def flowers(rgb, rng, mask, n):
    cols = ['#f0a8d0', '#c890e0', '#f2eee0', '#f0d050', '#e87890']
    pts = jitter(rng, mask, 20, 1.0)
    rng.shuffle(pts)
    for (x, y) in pts[:n]:
        c = hexc(cols[int(rng.integers(0, len(cols)))])
        for _ in range(int(rng.integers(8, 20))):
            fx, fy = x + int(rng.integers(-6, 7)), y + int(rng.integers(-4, 5))
            if 1 <= fx < rgb.shape[1] - 1 and 1 <= fy < rgb.shape[0] - 1 and mask[fy, fx]:
                rgb[fy + 1, fx] *= 0.7
                rgb[fy, fx] = c


def sparkle(rgb, glow, x, y, k=1.0):
    core, mid = hexc('#fffbe6'), hexc('#ffd77a')
    for d in range(-int(5 * k), int(5 * k) + 1):
        f = 1 - abs(d) / (5 * k + 1)
        for (px, py) in ((x + d, y), (x, y + int(d * 0.6))):
            if 0 <= px < rgb.shape[1] and 0 <= py < rgb.shape[0]:
                rgb[py, px] = rgb[py, px] * (1 - f) + mid * f
    rgb[y, x] = core
    g = np.zeros(rgb.shape[:2], np.float32)
    g[y, x] = 1
    glow += blur(g[..., None] * hexc('#ffcf70'), 3) * 9 * k + blur(g[..., None] * hexc('#ffcf70'), 8) * 14 * k


def foundation10(rgb, x0, y0, tw, th, rng, ramp_name, plate=16):
    """Flush stone tiles: bevelled edges lit on the upper left, dark seams."""
    P = pal(RAMPS[ramp_name])
    w, h = tw * 32, th * 32
    yy, xx = np.mgrid[0:h, 0:w]
    v = 0.52 + speck(h, w, rng, 0.08)
    for ty in range(0, h, plate):
        for tx in range(0, w, plate):
            v[ty:ty + plate, tx:tx + plate] += float(rng.uniform(-0.05, 0.05))
    u, t = xx % plate, yy % plate
    v[(u == 1) | (t == 1)] += 0.22
    v[(u == plate - 2) | (t == plate - 2)] -= 0.16
    v[(u == 0) | (t == 0) | (u == plate - 1) | (t == plate - 1)] = 0.08
    rgb[y0:y0 + h, x0:x0 + w] = ramp_s(np.clip(v, 0, 0.999), P)
    rgb[y0 + h:y0 + h + 2, x0 + 2:x0 + w + 2] *= 0.6
    rgb[y0 + 2:y0 + h + 2, x0 + w:x0 + w + 2] *= 0.6


# ---------------------------------------------------------------- trees
def tree(F, rng, x, y, R, leaf):
    """Leafy tree seen from high above, slightly from the south: trunk foot at (x, y), round crown of leaf clumps."""
    ccx, ccy = x, y - 1.12 * R
    tr = (slice(max(0, int(y - R * 0.9)), min(F.h, int(y) + 1)), slice(max(0, int(x) - 1), min(F.w, int(x) + 2)))
    tm = np.ones(F.lock[tr].shape, bool)
    F.mat[tr][tm] = MAT['trunk']
    tb = np.zeros(F.base[tr].shape, np.float32) + 0.55
    tb[:, -1:] = 0.25
    F.base[tr][tm] = tb[tm]
    F.hm[tr][tm] = F.ground[tr][tm] + 4
    F.lock[tr] |= tm
    sl, dx, dy = F.win(ccx, ccy, R * 1.25 + 2)
    hl = np.zeros(dx.shape, np.float32)
    blobs = [(0.0, 0.0, R * 0.7)]
    n = int(rng.integers(6, 9))
    a0 = float(rng.uniform(0, 6.3))
    for k in range(n):
        a = a0 + k * 2 * math.pi / n + float(rng.uniform(-0.25, 0.25))
        rr = R * float(rng.uniform(0.4, 0.52))
        blobs.append((math.cos(a) * R * 0.56, math.sin(a) * R * 0.5, rr))
    for (bx, by, br) in blobs:
        hl = np.maximum(hl, np.sqrt(np.clip(br * br - (dx - bx) ** 2 - (dy - by) ** 2, 0, None)))
    hd = hl.copy()
    ys, xs = np.nonzero(hl > R * 0.2)
    for _ in range(int(R * 1.7)):                                 # leaf clumps
        if len(ys) == 0:
            break
        i = int(rng.integers(0, len(ys)))
        px, py = xs[i] + dx[0, 0], ys[i] + dy[0, 0]
        cr = float(rng.uniform(3.2, 4.8))
        bump = np.sqrt(np.clip(cr * cr - (dx - px) ** 2 - (dy - py) ** 2, 0, None)) * 0.95
        hl = np.where(bump > 0, np.maximum(hl, hl[ys[i], xs[i]] * 0.9 + bump), hl)
    inside = hl > 0.5
    Ld = lam(blur(hd, 1.5) * 0.8)                                 # the crown as one dome
    Lc = lam(hl) - lam(hd)                                        # the leaf clumps on it
    cav = hl - blur(hl, 1)
    side = np.clip((dx * 0.62 + dy * 0.78) / R, -1, 1)              # + toward the shaded lower right
    v = 0.5 + 0.9 * Ld + 0.55 * Lc - 0.22 * np.clip(side, 0, 1) + 0.06 * np.clip(-side, 0, 1)
    v += 0.1 * np.clip(cav, -2, 2) + (rng.random(hl.shape).astype(np.float32) - 0.5) * 0.02
    v -= 0.18 * (hl < 1.6)                                        # dark rim where the crown meets the shade
    v += float(rng.uniform(-0.05, 0.04))
    m = inside
    F.mat[sl][m] = MAT[leaf]
    F.base[sl][m] = v[m]
    F.hm[sl][m] = F.ground[sl][m] + 8 + hl[m]
    F.lock[sl] |= m


def pine(F, rng, x, y, Hh, W):
    """Conifer: stacked tiers of drooping branches, lit on the left."""
    tiers = int(rng.integers(5, 8))
    sl, dx, dy = F.win(x, y - Hh / 2, max(W, Hh / 2) + 3)
    t = (dy + Hh / 2) / Hh                                       # 0 apex .. 1 foot
    xr = np.abs(dx) / max(W, 1)
    tf = (t * tiers - 0.9 * xr) % 1.0                            # branch tips droop
    ti = np.floor(t * tiers - 0.9 * xr)
    half = W * (0.1 + 0.9 * t) * (0.38 + 0.62 * tf ** 0.8) + (rng.random(dx.shape) - 0.5) * 1.4
    m = (t >= 0) & (t <= 0.93) & (np.abs(dx) < half)
    u = dx / np.maximum(half, 0.8)
    v = 0.6 - 0.42 * u + 0.18 * (1 - tf) - 0.1 * (ti / tiers) + (rng.random(dx.shape) - 0.5) * 0.08
    v[np.abs(u) > 0.78] -= 0.12
    v[tf > 0.86] -= 0.16
    tr = (slice(max(0, int(y - 2)), min(F.h, int(y) + 2)), slice(max(0, int(x)), min(F.w, int(x) + 2)))
    tm = np.ones(F.lock[tr].shape, bool)
    F.mat[tr][tm] = MAT['trunk']
    F.base[tr][tm] = 0.3
    F.lock[tr] |= tm
    F.mat[sl][m] = MAT['pine']
    F.base[sl][m] = v[m]
    F.hm[sl][m] = F.ground[sl][m] + 4 + (1 - t[m]) * Hh * 0.55 * (1 - np.abs(u[m]) * 0.4)
    F.lock[sl] |= m


def plant_trees(F, rng, pts, pine_w, kind_noise):
    """Draw trees back to front; kind_noise picks leaf colour / pine by area so stands share a type."""
    items = []
    for (x, y) in pts:
        k = kind_noise[min(y, F.h - 1), x] + float(rng.uniform(-0.18, 0.18))
        if rng.random() < pine_w[min(y, F.h - 1), x]:
            items.append((y, x, 'pine', float(rng.uniform(30, 40))))
        else:
            leaf = 'leafY' if k > 0.55 else ('leafG' if k > 0.42 else 'leafO')
            items.append((y, x, leaf, float(rng.uniform(11.5, 15.5))))
    for (y, x, kind, s) in sorted(items):
        if kind == 'pine':
            pine(F, rng, x, y, s, s * 0.31)
        else:
            tree(F, rng, x, y, s, kind)


# ---------------------------------------------------------------- forest
def forest_masks(rng):
    """Same calls, in the same order, as v4's paint_forest4, so the layout matches v8 exactly."""
    h, w = VH, VW
    yy, xx = np.mgrid[0:h, 0:w].astype(np.float32)
    cx, cy = ROCK_C
    X = xx + (fbm(h, w, 60, rng) - 0.5) * 50
    Y = yy + (fbm(h, w, 60, rng) - 0.5) * 50
    d_clear = np.hypot((X - cx) / 1.3, Y - cy - 6) - 74
    d_p1 = polydist(X, Y, [(cx - 70, cy + 55), (250, 395), (150, 450), (60, 540)]) - 12
    d_p2 = polydist(X, Y, [(cx + 90, cy - 10), (540, 208), (650, 226), (770, 185)]) - 12
    d_dirt = np.minimum(np.minimum(d_clear, d_p1), d_p2)
    dirt = d_dirt + speck(h, w, rng, 5) < 0
    SW = V4.STONE_W
    d_st = np.minimum(np.hypot((X - 612) / 1.4, Y - 402) - 44, np.hypot((X - SW[0]) / SW[2], Y - SW[1]) - SW[3])
    stone = d_st + speck(h, w, rng, 5) < 0
    d_w = polydist(X, Y, [(270, -20), (245, 50), (190, 95), (120, 120), (55, 175), (-30, 205)]) - 12
    edge = 1 - np.minimum(np.minimum(xx, w - xx), np.minimum(yy, h - yy)) / 190
    fn = (fbm(h, w, 110, rng, 3) - 0.5) * 2.4 + np.clip(edge, 0, 1) * 0.8
    forest = (fn > 0.42) & (d_dirt > 12) & (d_w > 8) & (d_st > 8)
    forest &= speck(h, w, rng, 1.0) + blur(forest.astype(np.float32), 3) > 0.25
    return {k: padv(v) for k, v in dict(dirt=dirt, d_dirt=d_dirt, stone=stone, d_st=d_st, d_w=d_w, fn=fn,
                                         forest=forest).items()}


def clear_zone(units, found, h, w, pad=12):
    z = np.zeros((h, w), bool)
    for u in units:
        r = 22 if u[0].startswith(('tank', 'harv', 'light')) else 12
        z[max(0, u[3] + OFF - r - 8):u[3] + OFF + r, max(0, u[2] - r):u[2] + r] = True
    for (x0, y0) in found:
        z[max(0, y0 + OFF - pad):y0 + OFF + 64 + pad, max(0, x0 - pad):x0 + 64 + pad] = True
    return z


def forest10(seed):
    M = forest_masks(np.random.default_rng(seed))
    rng = np.random.default_rng(seed + 1000)
    h, w = H, VW
    yy, xx = np.mgrid[0:h, 0:w].astype(np.float32)
    cx, cy = ROCK_C[0], ROCK_C[1] + 2 + OFF
    F = Field(h, w)
    d_w = M['d_w']
    water = d_w < 2
    bank = (d_w >= 1) & (d_w < 6)
    dirt, stone = M['dirt'] & ~water, M['stone'] & ~water
    wob = (fbm(h, w, 22, rng, 2) - 0.5) * 22
    d_o = np.hypot((xx - cx) / 1.4, yy - cy) + wob
    ore = d_o + speck(h, w, rng, 2.5) < 38

    # grass: sun patches, blade texture, small bumps
    patch = fbm(h, w, 70, rng, 3)
    blades = fbm(h, w, 2, rng, 1, stretch=(0.6, 1.6)) - 0.5
    F.hm += (fbm(h, w, 14, rng, 2) - 0.5) * 2.2
    gb = 0.5 + (patch - 0.5) * 0.8 + blades * 0.22 + speck(h, w, rng, 0.05)
    F.set(np.ones((h, w), bool), 'grass', gb, 0.9)
    # dirt: sunken, scratch texture, darker rim, grass fringe left ragged by the edge noise
    scr = np.abs(np.sin(fbm(h, w, 9, rng, 2) * 46)) < 0.16
    db = 0.6 + (fbm(h, w, 30, rng, 2) - 0.5) * 0.3 - 0.1 * scr + speck(h, w, rng, 0.06)
    dd = M['d_dirt']
    db -= 0.2 * np.clip((dd + 4) / 4, 0, 1)
    F.hm[dirt] -= 0.9
    F.set(dirt, 'dirt', db, 0.9)
    # gravel patches (the Blue base stands on the west one)
    gr = 0.5 + speck(h, w, rng, 0.22) + (fbm(h, w, 8, rng, 2) - 0.5) * 0.25
    F.hm += 0.9 * blur(stone.astype(np.float32), 1.5)
    F.set(stone, 'gravel', gr, 1.0)
    # the river
    flow = fbm(h, w, 2, rng, 1, stretch=(2.8, 0.55))
    rb = 0.6 + 0.12 * np.clip(-d_w / 14, 0, 1) + 0.14 * (flow > 0.72) - 0.06 * (flow < 0.3)
    rb += (fbm(h, w, 20, rng, 2) - 0.5) * 0.12
    rb -= 0.14 * np.clip((d_w + 4) / 4, 0, 1)
    F.hm[water] = -1.4
    F.set(water, 'river', rb, 0.15)
    F.set(edge_of(water) , 'river', 0.72, 0.1)              # thin foam line at the bank
    # Orichalcum rock: raised cracked grey plates
    f1, f2, fv = voronoi(h, w, 11, rng)
    pil = np.clip((f2 - f1) / 4, 0, 1)
    F.hm[ore] = 2.6 + 2.2 * pil[ore] + (fv[ore] - 0.5) * 1.2
    F.set(ore, 'ore_g', 0.58 + (fv - 0.5) * 0.25 - 0.32 * ((f2 - f1) < 0.9), 1.25)
    F.ground = F.hm.copy()
    F.hm += 0.0

    # small solid things: bank stones, gravel stones, boulders, bushes
    for (x, y) in jitter(rng, bank & ~dirt, 3, 0.9):
        F.dome(x, y, float(rng.uniform(1.6, 2.6)), float(rng.uniform(1.3, 2.1)), 1.7, 'bankst',
               float(rng.uniform(0.45, 0.6)), 1.3, rng)
    for (x, y) in jitter(rng, shrink(stone, 2), 8, 0.6):
        r = float(rng.uniform(1.7, 3.0))
        F.dome(x, y, r, r * float(rng.uniform(0.7, 1.0)), 1.9, 'gravel', float(rng.uniform(0.56, 0.68)), 1.5, rng, 0.35)
    for (x, y) in jitter(rng, edge_of(stone, 2), 3, 0.5):
        F.dome(x, y, 1.6, 1.4, 1.2, 'gravel', 0.6, 1.2, rng)
    units = V8.F7
    zone = clear_zone(units, [BLUE_R], h, w)
    grass = ~dirt & ~stone & ~water & ~bank & ~ore & ~zone
    open_g = grass & ~grow(M['forest'], 4) & (M['d_dirt'] > 5) & (d_w > 7)
    for (x, y) in jitter(rng, open_g, 46, 0.32):                   # boulder groups
        for _ in range(int(rng.integers(1, 4))):
            bx, by = x + int(rng.integers(-5, 6)), y + int(rng.integers(-3, 4))
            r = float(rng.uniform(1.8, 3.6))
            F.dome(bx, by, r, r * 0.8, r * 0.9, 'boulder', float(rng.uniform(0.52, 0.64)), 1.4, rng, 0.12)
    for (x, y) in jitter(rng, open_g, 30, 0.38):                   # round bushes
        r = float(rng.uniform(2.4, 3.8))
        F.dome(x, y, r, r * 0.85, 2.6, 'bush', float(rng.uniform(0.42, 0.58)), 1.4, rng, 0.2)

    # trees: the dense forest, groves at its edges and lone trees on the grass
    kind = fbm(h, w, 34, rng, 2)
    pine_w = np.clip((fbm(h, w, 45, rng, 2) - 0.42) * 1.6, 0.06, 0.5)
    ok = ~zone & (d_w > 3) & ~stone & ~ore & (M['d_dirt'] > 3)
    pts = jitter(rng, M['forest'] & ok, 19, 1.0)
    pts += jitter(rng, (M['fn'] > 0.3) & ~M['forest'] & ok & (M['d_dirt'] > 8) & (d_w > 6), 18, 0.3)
    pts += jitter(rng, open_g & (M['fn'] <= 0.3), 60, 0.12)
    plant_trees(F, rng, pts, pine_w, kind)
    # the forest floor under the canopy is in deep shade
    canopy = blur(M['forest'].astype(np.float32), 3) > 0.5
    F.base[canopy & ~F.lock] -= 0.45

    rgb = F.render(rng)
    glow = np.zeros_like(rgb)
    flowers(rgb, rng, grass & ~F.lock & (F.sh < 0.3) & (M['d_dirt'] > 4), 70)
    for (x, y) in jitter(rng, dirt & ~ore & (M['d_dirt'] < -2), 5, 0.6):        # small stones in the dirt
        rgb[y, x] = hexc('#c99c6a') if rng.random() < 0.6 else hexc('#3e2a18')
        if y + 1 < h:
            rgb[y + 1, x] *= 0.72
    crystals(rgb, rng, shrink(ore, 4) & (d_o < 31), 52, 3, 7, glow)
    rgb += blur(np.where(ore[..., None], hexc(SPILL), 0) * 1.0, 18) * 0.1       # warm light spill
    ys, xs = np.nonzero(water & (d_w < -6))
    for k in (0.1, 0.42, 0.74):
        i = int(len(ys) * k)
        sparkle(rgb, glow, int(xs[i]), int(ys[i]), 2.6)
    foundation10(rgb, BLUE_R[0], BLUE_R[1] + OFF, 2, 2, rng, 'found_f')
    return rgb, glow, units


# ---------------------------------------------------------------- desert
def desert10(seed):
    _, M0 = V4._orig_desert(np.random.default_rng(seed))        # v8's desert layout
    M = {k: padv(v) for k, v in M0.items()}
    rng = np.random.default_rng(seed + 1000)
    h, w = H, VW
    yy, xx = np.mgrid[0:h, 0:w].astype(np.float32)
    cx, cy = ROCK_C[0], ROCK_C[1] + 2 + OFF
    F = Field(h, w)
    wob = (fbm(h, w, 22, rng, 2) - 0.5) * 24
    d_o = np.hypot((xx - cx) / 1.45, yy - cy) + wob
    ore = d_o + speck(h, w, rng, 2.5) < 38
    halo = (d_o < 46) & ~ore
    rock = M['rock'] & ~grow(ore, 6) & ~(M['d_rk'] < 8)
    hard = M['hard'] & ~ore
    oasis, green = M['oasis'], M['green']
    dunes = M['allsand'] & ~M['sand']

    # sand: broad swells, wind ridges (gentle lit side, steep shaded slip face), fine wind texture
    amp = 0.06 + 4.6 * blur(dunes.astype(np.float32), 14) * np.clip(0.2 + 1.3 * fbm(h, w, 42, rng, 2), 0, 1.2)
    warp = (fbm(h, w, 80, rng, 2) - 0.5) * 46 + (fbm(h, w, 26, rng, 2) - 0.5) * 20
    s = (yy - 0.2 * xx + warp) / 18.0
    ph = s - np.floor(s)
    prof = np.where(ph < 0.64, (ph / 0.64) ** 1.3, ((1 - ph) / 0.36) ** 0.8)
    prof = blur(prof.astype(np.float32), 1.5, 2)
    micro = np.sin((yy - 0.35 * xx + (fbm(h, w, 12, rng, 2) - 0.5) * 30) / 1.25) * 0.05
    F.hm = amp * prof + (fbm(h, w, 150, rng, 2) - 0.5) * 7 + micro + speck(h, w, rng, 0.05)
    sb = 0.6 + (fbm(h, w, 60, rng, 2) - 0.5) * 0.12 + speck(h, w, rng, 0.04)
    F.set(np.ones((h, w), bool), 'sand', sb, 1.55)
    # flagstone hardpan paths
    f1, f2, fv = voronoi(h, w, 15, rng)
    st = np.clip((f2 - f1) / 3, 0, 1)
    hb = 0.55 + (fv - 0.5) * 0.18 + speck(h, w, rng, 0.06) - 0.3 * ((f2 - f1) < 0.85)
    F.hm[hard] = 0.1 + 0.3 * st[hard] + 0.05 * F.hm[hard]
    F.set(hard, 'flag', hb, 0.8)
    F.base[halo] -= 0.5 * np.clip(1 - (d_o[halo] - 38) / 9, 0, 1) ** 1.5
    # slate rock plateau: plates, cracks, raised edge
    g1, g2, gv = voronoi(h, w, 26, rng)
    rk = blur(rock.astype(np.float32), 1.2)
    F.hm += 4.0 * rk
    F.hm[rock] += (gv[rock] - 0.5) * 0.9 - 0.9 * ((g2 - g1)[rock] < 0.9) + (fbm(h, w, 6, rng, 2)[rock] - 0.5) * 0.8
    rb = 0.5 + (gv - 0.5) * 0.1 + (fbm(h, w, 5, rng, 2) - 0.5) * 0.14 - 0.2 * ((g2 - g1) < 0.9)
    F.set(rock, 'slate', rb, 1.35)
    F.base[edge_of(rock)] -= 0.22
    # Orichalcum rock: black basalt pillows
    o1, o2, ov = voronoi(h, w, 10, rng)
    pil = np.clip((o2 - o1) / 4, 0, 1)
    F.hm[ore] = 3.0 + 2.4 * pil[ore] + (ov[ore] - 0.5) * 1.4
    F.set(ore, 'basalt', 0.5 + (ov - 0.5) * 0.25 - 0.3 * ((o2 - o1) < 0.9), 1.45)
    # oasis
    ripple = fbm(h, w, 3, rng, 2, stretch=(2.2, 0.8))
    F.hm[oasis | green] = np.minimum(F.hm[oasis | green], 0.2)
    F.hm[oasis] = -0.8
    F.set(oasis, 'oasis', 0.5 + 0.16 * (ripple > 0.63) - 0.08 * (ripple < 0.36), 0.2)
    F.set(edge_of(oasis), 'oasis', 0.2, 0.2)
    F.set(green, 'bush', 0.32 + speck(h, w, rng, 0.1), 0.9)
    F.ground = F.hm.copy()

    for (x, y) in jitter(rng, shrink(rock, 3), 11, 0.55):                  # raised blocks on the slate
        r = float(rng.uniform(1.8, 3.4))
        F.dome(x, y, r, r * float(rng.uniform(0.7, 1.0)), float(rng.uniform(1.4, 2.4)), 'slate',
               float(rng.uniform(0.5, 0.6)), 1.35, rng, 0.08, square=True)
    for (x, y) in jitter(rng, edge_of(hard, 2) & ~rock & ~ore, 4, 0.5):      # pebbles along the paths
        F.dome(x, y, 1.3, 1.1, 1.0, 'pebble', 0.45, 1.2, rng, 0.1)
    for (x, y) in jitter(rng, green | (edge_of(oasis, 3) & (rng.random((h, w)) < 0.3)), 4, 0.85):
        r = float(rng.uniform(2.0, 3.4))
        F.dome(x, y, r, r * 0.9, 2.6, 'bush', float(rng.uniform(0.48, 0.62)), 1.4, rng, 0.2)
    units = V8.D7
    zone = clear_zone(units, [RED_R], h, w)
    sand = M['sand'] & ~zone & ~hard
    for (x, y) in jitter(rng, sand, 34, 0.4):                               # dark pebbles
        r = float(rng.uniform(1.0, 1.9))
        F.dome(x, y, r, r * 0.85, 1.4, 'pebble', 0.42, 1.3, rng, 0.1)

    rgb = F.render(rng, shadow=0.34)
    glow = np.zeros_like(rgb)
    for (x, y) in jitter(rng, M['allsand'] & ~zone & ~hard, 44, 0.3):        # green tufts
        for (px, py, c) in ((0, 0, '#6e8f2c'), (1, -1, '#8fae3a'), (-1, 0, '#4f6c20'), (0, 1, '#2f3e14'),
                            (1, 1, '#2f3e14')):
            if 0 <= y + py < h and 0 <= x + px < w:
                rgb[y + py, x + px] = hexc(c) if c != '#2f3e14' else rgb[y + py, x + px] * 0.7
    crystals(rgb, rng, shrink(ore, 3) & (d_o < 30), 40, 3.5, 7.5, glow)
    rgb += blur(np.where(ore[..., None], hexc(SPILL), 0) * 1.0, 14) * 0.05
    tracks(rgb, rng)
    foundation10(rgb, RED_R[0], RED_R[1] + OFF, 2, 2, rng, 'found_d')
    return rgb, glow, units


def tracks(rgb, rng):
    """Faint vehicle tracks in the sand east of the Orichalcum rock."""
    for i in range(0, 60, 3):
        t = i / 60
        x = 478 + 34 * t + 5 * math.sin(t * 3)
        y = 262 + OFF + 46 * t
        for side in (-4, 4):
            px, py = int(x + side), int(y - side * 0.3)
            rgb[py, px:px + 3] *= 0.8
            rgb[py + 1, px:px + 3] *= 0.92


# ---------------------------------------------------------------- compose
def grade(a, warm):
    """Late-afternoon sun: warm highlights, cool teal shadows, a little more saturation."""
    L = (a * np.array([0.3, 0.59, 0.11], np.float32)).sum(-1, keepdims=True)
    hi = np.clip((L - 0.35) / 0.45, 0, 1)
    lo = np.clip((0.3 - L) / 0.3, 0, 1)
    a = a + warm * (hi * np.array([0.05, 0.022, -0.04], np.float32) + lo * np.array([-0.012, 0.004, 0.02], np.float32))
    g = a.mean(-1, keepdims=True)
    return np.clip(g + (a - g) * (1 + 0.12 * warm), 0, 1)


def build_world(biome, seed):
    rgb, glow, units = (forest10 if biome == 'forest' else desert10)(seed)
    rgb = grade(rgb, 1.0 if biome == 'forest' else 0.35)
    units = [(u[0], u[1], u[2], u[3] + OFF, u[4]) for u in units]
    V3.ROCK_C = (ROCK_C[0], ROCK_C[1] + OFF)
    world, _ = V3.draw_world3(rgb, [], units)
    V3.ROCK_C = ROCK_C
    world = world + glow * 0.32
    wim = to_img(world)
    d = ImageDraw.Draw(wim)
    for u in units:
        if u[4] == 'sel':
            x, y = u[2], u[3] - V3.HP_DY
            d.rectangle([x - 8, y, x + 8, y + 3], fill='#1a120c')
            d.rectangle([x - 7, y + 1, x + 4, y + 2], fill='#62c048')
    px, py = (300, 300 + OFF) if biome == 'forest' else (470, 330 + OFF)
    d.polygon([(px, py), (px, py + 11), (px + 3, py + 8), (px + 8, py + 8)], fill='#f0e6c4', outline='#2a1a0c')
    return to_arr(wim)


_src = inspect.getsource(V8.compose8)
_body = _src[_src.index("    T, C = TH8[theme], CONTENT[theme]\n"):_src.index("    im.save(f'{OUT}/v8_{biome}_native.png')")]
exec("def hud_draw10(frame, biome, theme, seed):\n" + _body + "    return to_arr(im)\n", V8.__dict__)


def hud_layer(biome, theme, seed):
    """The v8 HUD, unchanged: rendered over black and over white to recover its colour and coverage."""
    k = V8.hud_draw10(np.zeros((H, W, 3), np.float32), biome, theme, seed)
    wh = V8.hud_draw10(np.ones((H, W, 3), np.float32), biome, theme, seed)
    a = np.clip(1 - (wh - k).mean(-1), 0, 1)
    return k / np.maximum(a, 1e-3)[..., None], a


def shot(world, hud, zoom, origin, path):
    vw = VW * 2
    x0, y0 = origin if origin else (0, 0)
    ww, wh = -(-vw // zoom), -(-H * 2 // zoom)
    big = np.repeat(np.repeat(world[y0:y0 + wh, x0:x0 + ww], zoom, 0), zoom, 1)[:H * 2, :vw]
    final = np.zeros((H * 2, W * 2, 3), np.float32)
    final[:, :vw] = big
    C = np.repeat(np.repeat(hud[0], 2, 0), 2, 1)
    A = np.repeat(np.repeat(hud[1], 2, 0), 2, 1)[..., None]
    to_img(final * (1 - A) + np.clip(C, 0, 1) * A).save(path)
    print('saved', os.path.basename(path))


if __name__ == '__main__':
    for biome, theme, seed, origin in (('forest', 'blue', 11, (30, 120)), ('desert', 'red', 23, (248, 60))):
        if biome in WHICH:
            world = build_world(biome, seed)
            hud = hud_layer(biome, theme, seed)
            shot(world, hud, 2, None, f'{OUT}/v10_{biome}.png')
            shot(world, hud, 3, origin, f'{OUT}/v10_{biome}_zoom.png')
