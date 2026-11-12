# Balance style test v4 -- Dune II flatness: terrain is texture made of small repeating elements
# (tree tops well under a tile, rubble, ore flecks); no tall props. Units and HUD come from v3.
# Run: python v4_compose.py <raw_sprite_dir> <out_dir> [forest desert]
import os, sys, math
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from v3_compose import *          # noqa: F401,F403
import v3_compose as V3

GRASS4 = ['#3a4c27', '#44572c', '#4e6232', '#586d38', '#63783f']
FLOOR4 = ['#141d12', '#1a2616', '#202f1a']
DIRT4 = ['#5a4730', '#675237', '#745e3f', '#816a48', '#8e7652']
STONE4 = ['#3e3b35', '#4c4841', '#5a564d', '#69645a', '#787367']
CROWNS = [['#17251a', '#203320', '#2a4226', '#35522d', '#426234'],
          ['#1c2914', '#27381a', '#334920', '#415a28', '#506b31'],
          ['#152624', '#1d342f', '#26433b', '#305347', '#3c6354'],
          ['#222a14', '#2f3a1a', '#3d4b21', '#4c5d29', '#5c6f32']]
PEBBLE_F = [['#35322d', '#4c4841', '#69645a', '#8a8477', '#a39d8e']]
PEBBLE_D = [['#3a2f26', '#54453a', '#6f5c4b', '#8c7660', '#a89078']]
ORE = [['#6a3c0c', '#a8661a', '#de962a', '#fbc552', '#fff0b0']]
ORE_ROCK_F = ['#332d28', '#423a33', '#51483f', '#61574b', '#726658']
ORE_ROCK_D = ['#45332a', '#574135', '#694f40', '#7b5e4c', '#8e6e59']
TUFT = [['#5e4c24', '#78602a', '#957a33', '#b0943e']]
SHRUB = [['#2a3a1c', '#384b22', '#475d2a', '#587033']]


def stamps(rgb, rng, mask, cell, rmin, rmax, pals, prob=1.0, shadow=0.38, rough=0.9, metric='round', rim=0.25):
    """Scatter many small shaded elements (tree tops, stones, ore flecks): lit north-west, dark south-east."""
    h, w = mask.shape
    pts = []
    for gy in range(0, h, cell):
        for gx in range(0, w, cell):
            if rng.random() > prob:
                continue
            x, y = gx + int(rng.integers(0, cell)), gy + int(rng.integers(0, cell))
            if x < w and y < h and mask[y, x]:
                pts.append((y, x, float(rng.uniform(rmin, rmax)), int(rng.integers(0, len(pals)))))
    pts.sort()
    if shadow:
        sh = np.zeros((h, w), np.float32)
        yy, xx = np.mgrid[0:h, 0:w]
        for (y, x, r, _) in pts:
            R = int(r) + 3
            y0, y1, x0, x1 = max(0, y - R), min(h, y + R + 3), max(0, x - R), min(w, x + R + 3)
            d = np.hypot(xx[y0:y1, x0:x1] - x - 1.5, yy[y0:y1, x0:x1] - y - 2.0)
            sh[y0:y1, x0:x1] = np.maximum(sh[y0:y1, x0:x1], d < r + 0.3)
        rgb *= (1 - shadow * sh)[..., None]
    P_ = [pal(p) for p in pals]
    for (y, x, r, pi_) in pts:
        R = int(r) + 2
        y0, y1, x0, x1 = max(0, y - R), min(h, y + R + 1), max(0, x - R), min(w, x + R + 1)
        dy, dx = np.mgrid[y0 - y:y1 - y, x0 - x:x1 - x].astype(np.float32)
        if metric == 'round':
            dist = np.hypot(dx, dy)
        elif metric == 'crystal':
            dist = np.abs(dx) * 1.7 + np.abs(dy)
        else:
            dist = np.abs(dx) + np.abs(dy)
        nz = rng.random(dist.shape).astype(np.float32)
        m = dist + (nz - 0.5) * rough * 2 < r
        v = 0.55 - 0.42 * (dx + dy) / (1.5 * r) + (rng.random(dist.shape).astype(np.float32) - 0.5) * 0.3
        v -= rim * ((dist > r - 1.4) & (dx + dy > 0))
        col = ramp(np.clip(v, 0, 0.999), P_[pi_])
        sub = rgb[y0:y1, x0:x1]
        sub[m] = col[m]


def outcrop(rgb, rng, cx, cy, rockpal, lit, dark):
    """The Orichalcum formation: a low rock outcrop studded with small ore crystals."""
    h, w = rgb.shape[:2]
    yy, xx = np.mgrid[0:h, 0:w].astype(np.float32)
    wob = (fbm(h, w, 24, rng, 2) - 0.5) * 26
    d = np.hypot((xx - cx) / 1.45, yy - cy) + wob
    rockm = d + speck(h, w, rng, 3) < 40
    f1, f2, fv = voronoi(h, w, 13, rng)
    rc = ramp(np.clip(0.5 + (fv - 0.5) * 0.55 + speck(h, w, rng, 0.5), 0, 0.999), rockpal)
    rc[(f2 - f1) < 0.9] = hexc(dark)
    shade = blur(np.roll(np.roll(rockm.astype(np.float32), 3, 0), 3, 1), 2) * (~rockm)
    rgb *= (1 - 0.45 * shade)[..., None]
    rgb[rockm] = rc[rockm]
    relief(rgb, rockm, lit, dark)
    vein = ((f2 - f1) < 1.6) & (d < 33)
    for k, (cell, r0, r1, pr, lim) in enumerate(((5, 0.9, 1.7, 0.5, 34), (7, 1.6, 2.6, 0.75, 27), (13, 2.8, 4.2, 0.8, 18))):
        mk = (d < lim) & (vein | (k > 0))
        stamps(rgb, rng, mk, cell, r0, r1, ORE, pr, 0.3, 0.25, 'crystal', 0.3)
    return rockm


STONE_W = (150, 262, 1.2, 30)      # west stone patch: centre x, y, x-stretch, radius


def paint_forest4(rng):
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
    d_st = np.minimum(np.hypot((X - 612) / 1.4, Y - 402) - 44, np.hypot((X - STONE_W[0]) / STONE_W[2], Y - STONE_W[1]) - STONE_W[3])
    stone = d_st + speck(h, w, rng, 5) < 0
    d_w = polydist(X, Y, [(270, -20), (245, 50), (190, 95), (120, 120), (55, 175), (-30, 205)]) - 12
    water = d_w < 0
    bank = (d_w < 3) & ~water
    edge = 1 - np.minimum(np.minimum(xx, w - xx), np.minimum(yy, h - yy)) / 190
    fn = (fbm(h, w, 110, rng, 3) - 0.5) * 2.4 + np.clip(edge, 0, 1) * 0.8
    forest = (fn > 0.42) & (d_dirt > 12) & (d_w > 8) & (d_st > 8)
    forest &= speck(h, w, rng, 1.0) + blur(forest.astype(np.float32), 3) > 0.25            # ragged border

    rgb = ramp(np.clip(0.5 + (fbm(h, w, 120, rng, 3) - 0.5) * 0.7 + speck(h, w, rng, 0.6), 0, 0.999), GRASS4)
    dc = ramp(np.clip(0.5 + (fbm(h, w, 45, rng, 3) - 0.5) * 0.7 + speck(h, w, rng, 0.55), 0, 0.999), DIRT4)
    rgb = np.where(dirt[..., None], dc, rgb)
    rgb[dirt & ~shrink(dirt, 1)] = hexc('#43361f')
    sc = ramp(np.clip(0.5 + (fbm(h, w, 30, rng, 3) - 0.5) * 0.6 + speck(h, w, rng, 0.75), 0, 0.999), STONE4)
    rgb = np.where(stone[..., None], sc, rgb)
    relief(rgb, stone, '#8f897b', '#26231f')
    rgb[bank] = ramp(np.clip(0.5 + speck(h, w, rng, 0.9), 0, 0.999), ['#6e6448', '#7e7354', '#8e8260'])[bank]
    wc = ramp(np.clip(0.45 + (fbm(h, w, 30, rng) - 0.5) * 0.6 + speck(h, w, rng, 0.4), 0, 0.999),
              ['#24465c', '#2b5269', '#335e77', '#3d6c86'])
    rgb = np.where(water[..., None], wc, rgb)
    rgb[water & ~shrink(water, 1)] = hexc('#1a3444')

    im = to_img(rgb)
    d = ImageDraw.Draw(im)
    grass = ~dirt & ~water & ~bank & ~stone & ~forest
    for (x, y) in scatter(rng, grass, 2600):                     # small grass tufts
        d.point([(x, y), (x + 1, y - 1)], fill='#718648' if rng.random() < 0.45 else '#2e3d1f')
    for (x, y) in scatter(rng, dirt & (d_dirt < -3), 260):
        d.point((x, y), fill='#a08a62')
        d.point((x, y + 1), fill='#43361f')
    rgb = to_arr(im)

    floor = ramp(np.clip(0.5 + speck(h, w, rng, 1.0), 0, 0.999), FLOOR4)
    rgb = np.where(shrink(forest, 1)[..., None], floor, rgb)
    stamps(rgb, rng, stone, 9, 1.2, 3.0, PEBBLE_F, 0.6, 0.35, 0.5)
    stamps(rgb, rng, grass & (d_dirt > 4), 30, 2.0, 3.2, SHRUB, 0.3, 0.3)
    stamps(rgb, rng, grass & (d_dirt > 8), 44, 3.6, 5.2, CROWNS, 0.22, 0.4)          # lone trees
    stamps(rgb, rng, forest, 7, 3.4, 5.6, CROWNS, 0.95, 0.5)                          # the forest canopy
    outcrop(rgb, rng, cx, cy + 2, ORE_ROCK_F, '#8c8272', '#1f1b17')
    return rgb, {}


_orig_desert = V3.paint_desert3


def paint_desert4(rng):
    rgb, M = _orig_desert(rng)
    h, w = VH, VW
    cx, cy = ROCK_C
    rgb = desat(rgb, 0.92)
    rock = M['rock'] & (M['d_rk'] > 6)
    stamps(rgb, rng, shrink(rock, 3), 11, 1.2, 3.4, PEBBLE_D, 0.6, 0.35, 0.5)
    stamps(rgb, rng, M['sand'], 40, 1.2, 2.4, PEBBLE_D, 0.25, 0.3, 0.4)
    stamps(rgb, rng, M['sand'], 46, 1.8, 3.0, TUFT, 0.3, 0.25, 1.4)
    yy, xx = np.mgrid[0:h, 0:w]
    ring = (np.hypot((xx - 610) / 1.5, yy - 96) < 30) & (np.hypot((xx - 610) / 1.5, yy - 96) > 17) & ~M['rock']
    stamps(rgb, rng, ring, 7, 2.4, 4.0, CROWNS[1:2] + SHRUB, 0.8, 0.4)
    outcrop(rgb, rng, cx, cy + 2, ORE_ROCK_D, '#a88e74', '#241a14')
    return rgb, M


UNITS_D4 = [('inf_red', 1, 520, 372, 'sel'), ('inf_red', 2, 544, 360, ''), ('inf_red', 1, 548, 388, ''),
            ('inf_red', 2, 572, 376, ''),
            ('inf_blue', 7, 212, 186, ''), ('inf_blue', 6, 188, 174, ''), ('inf_blue', 7, 184, 200, ''),
            ('inf_blue', 6, 160, 186, '')]
V3.paint_forest3 = paint_forest4
V3.forest_entities3 = lambda rng, M: ([], V3.UNITS_F3)
V3.paint_desert3 = paint_desert4
V3.desert_entities3 = lambda rng, M: ([], UNITS_D4)

if __name__ == '__main__':
    if 'forest' in WHICH:
        V3.compose3('forest', 'blue', 11)
    if 'desert' in WHICH:
        V3.compose3('desert', 'red', 23)
