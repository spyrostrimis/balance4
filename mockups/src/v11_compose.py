# Balance style test v11 -- v10 with: more orange, more saturated sand; bigger, bright purple Orichalcum crystals
# (with a violet glow and light spill); lighter, higher-contrast base foundations with team-colour corners and stripe;
# vehicles and radars re-rendered with far more team colour (v11_sprites.py).
# Run: python v11_compose.py <raw_sprite_dir> <out_dir> [forest desert]
import os, sys
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import v10_compose as V10
from v10_compose import *          # noqa: F401,F403

V10.RAMPS['sand'] = ['#5c3e36', '#7d5240', '#a0694a', '#be7f52', '#d3945c', '#e1a568', '#ecb577', '#f5c78b',
                     '#fdd9a6']
V10.RAMPS['found_d'] = ['#262830', '#3a3d46', '#555964', '#6f747f', '#878c96', '#9ea3ab', '#b4b8be', '#c9ccd0',
                        '#dfe1e2']
V10.RAMPS['found_f'] = ['#2a2b2c', '#404244', '#5a5d5e', '#747778', '#8c8f8f', '#a3a5a4', '#b8bab7', '#cccdca',
                        '#e0e0dc']
V10.RAMP_ARR = {V10.MAT[k]: pal(v) for k, v in V10.RAMPS.items()}
V10.SPILL = '#b45cff'
TEAMC = {'found_f': ('#2f5cc8', '#5a8cf0', '#18306e'), 'found_d': ('#c0362c', '#ee6050', '#6a1812')}


def crystals(rgb, rng, mask, n, hmin, hmax, glow):
    """Bright purple Orichalcum crystals, about a third bigger than v10's: lit left facet, dark right, pale tip."""
    pts = jitter(rng, mask, 4, 1.0)
    rng.shuffle(pts)
    pts = sorted(pts[:n], key=lambda p: p[1])
    LIT, MID, DRK, EDGE, TIP = (hexc(c) for c in ('#de9cff', '#b45cff', '#7a2ad6', '#2c0a5c', '#f8ecff'))
    hot = np.zeros(rgb.shape[:2], np.float32)
    for (x, y) in pts:
        hh = float(rng.uniform(hmin, hmax)) * 1.35
        wd = max(1.5, hh * float(rng.uniform(0.3, 0.4)))
        lean = float(rng.uniform(-0.25, 0.25))
        for yy in range(int(-hh), 2):
            t = (yy + hh) / (hh + 1)
            half = wd * min(1.0, t * 2.2) * (1 - max(0, t - 0.8) * 2.5)
            cxr = x + lean * (yy + hh) * 0.5
            for xx in range(int(cxr - half - 1), int(cxr + half + 2)):
                if not (0 <= xx < rgb.shape[1] and 0 <= y + yy < rgb.shape[0]):
                    continue
                u = (xx - cxr) / max(half, 0.6)
                if abs(u) > 1.05:
                    continue
                c = LIT if u < -0.15 else (MID if u < 0.35 else DRK)
                if t < 0.16:
                    c = TIP
                if abs(u) > 0.8 and t > 0.25:
                    c = c * 0.5 + EDGE * 0.5
                rgb[y + yy, xx] = c
                hot[y + yy, xx] = 1.0 if t < 0.5 else 0.75
        for k in (1, 2):
            if 0 <= y + k < rgb.shape[0] and 0 <= x + k < rgb.shape[1]:
                rgb[y + k, x + k] *= 0.55
    g = hot[..., None] * hexc('#b866ff')
    glow += blur(g, 2) * 0.6 + blur(g, 6) * 0.5 + blur(g, 16) * 0.4


def foundation(rgb, x0, y0, tw, th, rng, ramp_name, plate=16):
    """Light stone tiles with strong bevels and dark seams, team-colour corner plates and a team stripe in front."""
    P = pal(V10.RAMPS[ramp_name])
    team, lite, dark = (hexc(c) for c in TEAMC[ramp_name])
    w, h = tw * 32, th * 32
    yy, xx = np.mgrid[0:h, 0:w]
    v = 0.72 + speck(h, w, rng, 0.06)
    for ty in range(0, h, plate):
        for tx in range(0, w, plate):
            v[ty:ty + plate, tx:tx + plate] += float(rng.uniform(-0.04, 0.04))
    u, t = xx % plate, yy % plate
    v[(u == 1) | (t == 1)] += 0.2
    v[(u == plate - 2) | (t == plate - 2)] -= 0.26
    v[(u == 0) | (t == 0) | (u == plate - 1) | (t == plate - 1)] = 0.06
    out = ramp_s(np.clip(v, 0, 0.999), P)
    for (cx, cy) in ((2, 2), (w - 8, 2), (2, h - 8), (w - 8, h - 8)):          # team corner plates
        out[cy:cy + 6, cx:cx + 6] = team
        out[cy, cx:cx + 6] = lite
        out[cy:cy + 6, cx] = lite
        out[cy + 5, cx:cx + 6] = dark
        out[cy:cy + 6, cx + 5] = dark
    out[h - 4:h - 2, 10:w - 10] = team                                        # front stripe
    out[h - 4, 10:w - 10] = lite
    out[0, :], out[:, 0], out[h - 1, :], out[:, w - 1] = (hexc('#16161a'),) * 4
    rgb[y0:y0 + h, x0:x0 + w] = out
    rgb[y0 + h:y0 + h + 2, x0 + 2:x0 + w + 2] *= 0.5
    rgb[y0 + 2:y0 + h + 2, x0 + w:x0 + w + 2] *= 0.5


import v3_compose as V3
import v7_compose as V7
_cache11 = {}


def unit_sprite11(u):
    """v7 grounded sprite; vehicles and buildings get deeper, more saturated team colour (Blender's sun bleaches it)."""
    key = (u[0], u[1])
    if key not in _cache11:
        s = dict(V7.unit_sprite7(u))
        if not u[0].startswith(('inf', 'hero')):
            a = np.clip(s['rgb'], 0, 1) ** 1.3
            g = a.mean(-1, keepdims=True)
            s['rgb'] = np.clip(g + (a - g) * 1.45, 0, 1)
        _cache11[key] = s
    return _cache11[key]


V3.unit_sprite = unit_sprite11
V8.unit_sprite7 = unit_sprite11
V10.crystals = crystals
V10.foundation10 = foundation

if __name__ == '__main__':
    for biome, theme, seed, origin in (('forest', 'blue', 11, (30, 120)), ('desert', 'red', 23, (248, 60))):
        if biome in WHICH:
            world = V10.build_world(biome, seed)
            hud = V10.hud_layer(biome, theme, seed)
            V10.shot(world, hud, 2, None, f'{OUT}/v11_{biome}.png')
            V10.shot(world, hud, 3, origin, f'{OUT}/v11_{biome}_zoom.png')
