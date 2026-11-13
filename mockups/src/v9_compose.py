# Balance style test v9 (experiment, not approved) -- rippled orange sand, purple Orichalcum, lighter bases,
# richer forest (4 tree types, groves, rocks, bushes, flowers, earth patches, water reflections),
# warm-highlight / cool-shadow grade, more contrast, and a medium "gameplay" zoom.
# Run: python v9_compose.py <raw_sprite_dir> <out_dir>
import os, sys, math, inspect
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from v8_compose import *          # noqa: F401,F403
import v3_compose as V3
import v4_compose as V4
import v7_compose as V7
import v8_compose as V8

ORE9 = [['#2e0a58', '#5a18a8', '#8e34ee', '#bf74ff', '#f0d4ff']]
SAND9 = ['#ad6c34', '#b9783a', '#c58440', '#cf9048', '#d99e55']
T_PAL = [['#16261a', '#203620', '#2b4727', '#38592e', '#476c37'],      # 0 oak: round, mid green
         ['#10231c', '#173024', '#1f3f2d', '#294f37', '#346042'],      # 1 pine: star-shaped, dark blue-green
         ['#222c12', '#33421a', '#465a22', '#5b732c', '#739038'],      # 2 lime: lobed, light yellow-green
         ['#2a2412', '#3f3819', '#574f22', '#71682c', '#8d8338']]      # 3 olive: small round, warm olive
ROCKS9 = [['#2f2c28', '#48443d', '#655f55', '#878073', '#a69e8e']]
FOUND9 = ['#84867a', '#909286', '#9c9e91', '#a8aa9c']


def grade(a):
    """More contrast; warm highlights and cool shadows (sunlight against blue sky fill)."""
    a = np.clip(0.42 + (a - 0.42) * 1.2, 0, 1)
    L = (a * np.array([0.3, 0.59, 0.11], np.float32)).sum(-1, keepdims=True)
    hi = np.clip((L - 0.42) / 0.4, 0, 1) ** 1.2
    lo = np.clip((0.42 - L) / 0.32, 0, 1) ** 1.1
    a = a + hi * np.array([0.065, 0.025, -0.055], np.float32) + lo * np.array([-0.03, 0.0, 0.042], np.float32)
    g = a.mean(-1, keepdims=True)
    return np.clip(g + (a - g) * 1.1, 0, 1)


def foundation9(rgb, x0, y0, tw, th, rng, plate=16):
    w, h = tw * 32, th * 32
    base = ramp(np.clip(0.5 + speck(h, w, rng, 0.8), 0, 0.999), FOUND9)
    yy, xx = np.mgrid[0:h, 0:w]
    base[(yy % plate == 0) | (xx % plate == 0)] = hexc('#c9cbbb')
    base[(yy % plate == plate - 1) | (xx % plate == plate - 1)] = hexc('#4e5048')
    rgb[y0:y0 + h, x0:x0 + w] = base


V7.foundation = foundation9
V8.foundation = foundation9
_scene_pic = V8.scene_pic
V8.scene_pic = lambda *a, **k: grade(_scene_pic(*a, **k))


def outcrop9(rgb, rng, cx, cy, rockpal, lit, dark):
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
    for (cell, r0, r1, pr, lim) in ((8, 1.6, 2.6, 0.45, 33), (11, 2.8, 4.0, 0.7, 27), (17, 4.4, 6.0, 0.85, 19)):
        stamps(rgb, rng, d < lim, cell, r0, r1, ORE9, pr, 0.4, 0.25, 'crystal', 0.3)


def sand9(h, w, rng):
    """Fine wind ripples running diagonally: thin light crest, darker lee side, then a slow rise."""
    yy, xx = np.mgrid[0:h, 0:w].astype(np.float32)
    low = (fbm(h, w, 90, rng, 2) - 0.5) * 2
    wig = 0.24 * np.sin(xx / 7.5 + low * 3.0 + 1.3 * np.sin(yy / 23.0))
    ph = (yy + 0.42 * xx) / 12.0 + wig + low * 0.7
    t = ph - np.floor(ph)
    v = np.where(t < 0.13, 0.9, 0.22 + 0.42 * (t - 0.13) / 0.87)
    v = v + low * 0.07 + speck(h, w, rng, 0.24)
    rgb = ramp(np.clip(v, 0, 0.999), SAND9)
    rgb[(t < 0.07) & (speck(h, w, rng, 1.0) > 0.05)] = hexc('#e8b064')
    r = rng.random((h, w))
    rgb[r < 0.004] = hexc('#efc888')
    rgb[r > 0.997] = hexc('#8f5420')
    return rgb


def paint_desert9(rng):
    rgb, M = V4._orig_desert(rng)
    h, w = VH, VW
    cx, cy = ROCK_C
    rgb = desat(rgb, 0.92)
    sand = M['allsand']
    rgb[sand] = sand9(h, w, rng)[sand]
    rock = M['rock'] & (M['d_rk'] > 6)
    stamps(rgb, rng, shrink(rock, 3), 11, 1.2, 3.4, PEBBLE_D, 0.6, 0.35, 0.5)
    stamps(rgb, rng, sand, 44, 1.4, 3.0, PEBBLE_D, 0.25, 0.3, 0.4)
    stamps(rgb, rng, sand, 50, 1.8, 3.0, TUFT, 0.3, 0.25, 1.4)
    yy, xx = np.mgrid[0:h, 0:w]
    ring = (np.hypot((xx - 610) / 1.5, yy - 96) < 30) & (np.hypot((xx - 610) / 1.5, yy - 96) > 17) & ~M['rock']
    stamps(rgb, rng, ring, 7, 2.4, 4.0, CROWNS[1:2] + SHRUB, 0.8, 0.4)
    outcrop9(rgb, rng, cx, cy + 2, ORE_ROCK_D, '#a88e74', '#241a14')
    foundation9(rgb, RED_R[0], RED_R[1], 2, 2, rng)
    return rgb, M


def plant(rgb, rng, trees):
    """Draw tree tops of four kinds, back to front, each with a small ground shadow."""
    h, w = rgb.shape[:2]
    trees = sorted(trees)
    sh = np.zeros((h, w), np.float32)
    for (y, x, r, k) in trees:
        R = int(r) + 4
        y0, y1, x0, x1 = max(0, y - R), min(h, y + R + 3), max(0, x - R), min(w, x + R + 3)
        if y0 >= y1 or x0 >= x1:
            continue
        dy, dx = np.mgrid[y0 - y:y1 - y, x0 - x:x1 - x].astype(np.float32)
        sh[y0:y1, x0:x1] = np.maximum(sh[y0:y1, x0:x1], np.hypot(dx - 1.5, dy - 2.2) < r + 0.3)
    rgb *= (1 - 0.5 * sh)[..., None]
    P_ = [pal(p) for p in T_PAL]
    for (y, x, r, k) in trees:
        R = int(r) + 3
        y0, y1, x0, x1 = max(0, y - R), min(h, y + R + 1), max(0, x - R), min(w, x + R + 1)
        if y0 >= y1 or x0 >= x1:
            continue
        dy, dx = np.mgrid[y0 - y:y1 - y, x0 - x:x1 - x].astype(np.float32)
        dist = np.hypot(dx, dy)
        nz = rng.random(dist.shape).astype(np.float32)
        nz2 = rng.random(dist.shape).astype(np.float32)
        if k == 1:                                               # pine: pointed star with lit ridges
            th = np.arctan2(dy, dx)
            ph = rng.uniform(0, 6.28)
            c7 = np.cos(7 * th + ph)
            m = dist * (1 + 0.27 * c7) + (nz - 0.5) * 0.8 < r * 0.92
            v = 0.48 - 0.3 * (dx + dy) / (1.5 * r) - 0.2 * c7 + 0.3 * (dist < r * 0.28) + (nz2 - 0.5) * 0.2
        elif k == 2:                                             # lime: four soft lobes
            a0 = rng.uniform(0, 6.28)
            lr = 0.62 * r
            best = np.full(dist.shape, 1e9, np.float32)
            sx_ = np.zeros_like(dist)
            for i in range(4):
                cxl, cyl_ = 0.44 * r * math.cos(a0 + i * 1.571), 0.44 * r * math.sin(a0 + i * 1.571)
                dl = np.hypot(dx - cxl, dy - cyl_)
                sx_ = np.where(dl < best, (dx - cxl) + (dy - cyl_), sx_)
                best = np.minimum(best, dl)
            m = best + (nz - 0.5) * 1.4 < lr
            v = 0.56 - 0.42 * sx_ / (1.5 * lr) + (nz2 - 0.5) * 0.3 - 0.25 * ((best > lr - 1.3) & (sx_ > 0))
        else:                                                    # oak / olive: round, dappled
            m = dist + (nz - 0.5) * 1.8 < r
            v = 0.55 - 0.42 * (dx + dy) / (1.5 * r) + (nz2 - 0.5) * 0.3 + 0.12 * (nz > 0.82)
            v -= 0.25 * ((dist > r - 1.4) & (dx + dy > 0))
        col = ramp(np.clip(v, 0, 0.999), P_[k])
        sub = rgb[y0:y1, x0:x1]
        sub[m] = col[m]


def paint_forest9(rng):
    h, w = VH, VW
    SW = (160, 322, 1.3, 52)
    yy, xx = np.mgrid[0:h, 0:w].astype(np.float32)
    cx, cy = ROCK_C
    X = xx + (fbm(h, w, 60, rng) - 0.5) * 50
    Y = yy + (fbm(h, w, 60, rng) - 0.5) * 50
    d_clear = np.hypot((X - cx) / 1.3, Y - cy - 6) - 74
    d_p1 = polydist(X, Y, [(cx - 70, cy + 55), (250, 395), (150, 450), (60, 540)]) - 12
    d_p2 = polydist(X, Y, [(cx + 90, cy - 10), (540, 208), (650, 226), (770, 185)]) - 12
    d_dirt = np.minimum(np.minimum(d_clear, d_p1), d_p2)
    dirt = d_dirt + speck(h, w, rng, 5) < 0
    d_st = np.minimum(np.hypot((X - 612) / 1.4, Y - 402) - 44, np.hypot((X - SW[0]) / SW[2], Y - SW[1]) - SW[3])
    stone = d_st + speck(h, w, rng, 5) < 0
    d_w = polydist(X, Y, [(270, -20), (245, 50), (190, 95), (120, 120), (55, 175), (-30, 205)]) - 12
    water = d_w < 0
    bank = (d_w < 3) & ~water
    edge = 1 - np.minimum(np.minimum(xx, w - xx), np.minimum(yy, h - yy)) / 190
    fn = (fbm(h, w, 110, rng, 3) - 0.5) * 2.4 + np.clip(edge, 0, 1) * 0.8
    forest = (fn > 0.42) & (d_dirt > 12) & (d_w > 8) & (d_st > 8)
    forest &= speck(h, w, rng, 1.0) + blur(forest.astype(np.float32), 3) > 0.25
    grass = ~dirt & ~water & ~bank & ~stone & ~forest

    rgb = ramp(np.clip(0.5 + (fbm(h, w, 120, rng, 3) - 0.5) * 0.8 + speck(h, w, rng, 0.6), 0, 0.999), GRASS4)
    # bare-earth and stony patches break up the grass
    openg = grass & (d_dirt > 9) & (d_st > 9)
    earth = openg & ((fbm(h, w, 24, rng, 2) - 0.5) * 2.6 + speck(h, w, rng, 0.25) > 0.62)
    stony = openg & ~earth & ((fbm(h, w, 20, rng, 2) - 0.5) * 2.6 + speck(h, w, rng, 0.25) > 0.7)
    dc = ramp(np.clip(0.5 + (fbm(h, w, 45, rng, 3) - 0.5) * 0.7 + speck(h, w, rng, 0.55), 0, 0.999), DIRT4)
    rgb = np.where((dirt | earth)[..., None], dc, rgb)
    lip = (dirt | earth) & ~shrink(dirt | earth, 1)
    rgb[lip] = hexc('#43361f')
    sc = ramp(np.clip(0.5 + (fbm(h, w, 30, rng, 3) - 0.5) * 0.6 + speck(h, w, rng, 0.75), 0, 0.999), STONE4)
    rgb = np.where((stone | stony)[..., None], sc, rgb)
    relief(rgb, stone | stony, '#8f897b', '#26231f')
    rgb[bank] = ramp(np.clip(0.5 + speck(h, w, rng, 0.9), 0, 0.999), ['#6e6448', '#7e7354', '#8e8260'])[bank]

    # water: dark under the banks, sky-bright in mid-stream, with streaks and sparkles
    mid = np.clip(-d_w / 11, 0, 1)
    wv = 0.12 + 0.62 * mid ** 1.3 + speck(h, w, rng, 0.22)
    streak = (np.sin(yy * 1.15 + xx * 0.2 + (fbm(h, w, 40, rng) - 0.5) * 14) > 0.8) & (mid > 0.3)
    wc = ramp(np.clip(wv + 0.22 * streak, 0, 0.999), ['#17323f', '#1f4558', '#2a5c75', '#3a7895', '#5a9bb8', '#8cc2d8'])
    rgb = np.where(water[..., None], wc, rgb)
    rgb[water & (rng.random((h, w)) < 0.012) & (mid > 0.45)] = hexc('#e2f2f6')
    rgb[water & ~shrink(water, 1)] = hexc('#142a36')

    im = to_img(rgb)
    d = ImageDraw.Draw(im)
    g2 = grass & ~earth & ~stony
    for (x, y) in scatter(rng, g2, 2600):
        d.point([(x, y), (x + 1, y - 1)], fill='#718648' if rng.random() < 0.45 else '#2e3d1f')
    for (x, y) in scatter(rng, (dirt | earth) & ~lip, 320):
        d.point((x, y), fill='#a08a62')
        d.point((x, y + 1), fill='#43361f')
    fcols = ['#ece6cc', '#e8c84a', '#b48ae6', '#d85a4c', '#e89ab8']
    for (x, y) in scatter(rng, g2 & (d_dirt > 5), 30):                    # groups of flowers
        c = fcols[int(rng.integers(0, len(fcols)))]
        for _ in range(int(rng.integers(7, 17))):
            fx, fy = x + int(rng.normal(0, 5)), y + int(rng.normal(0, 4))
            if 1 < fx < w - 2 and 1 < fy < h - 2 and g2[fy, fx]:
                d.point((fx, fy + 1), fill='#2e3d1f')
                d.point((fx, fy), fill=c)
                if rng.random() < 0.3:
                    d.point([(fx - 1, fy), (fx + 1, fy), (fx, fy - 1)], fill=c)
    rgb = to_arr(im)

    floor = ramp(np.clip(0.5 + speck(h, w, rng, 1.0), 0, 0.999), FLOOR4)
    rgb = np.where(shrink(forest, 1)[..., None], floor, rgb)
    stamps(rgb, rng, stone | stony, 9, 1.2, 3.0, PEBBLE_F, 0.6, 0.35, 0.5)
    stamps(rgb, rng, g2 | stony, 52, 3.0, 5.2, ROCKS9, 0.3, 0.42, 0.7)            # rocks
    stamps(rgb, rng, g2 & (d_dirt > 4), 22, 2.0, 3.4, SHRUB, 0.3, 0.32)           # bushes

    keep = np.ones((h, w), bool)                                                  # keep units and the base clear
    for u in F7:
        keep[max(0, u[3] - 26):u[3] + 22, max(0, u[2] - 26):u[2] + 26] = False
    kind_a, kind_b = fbm(h, w, 70, rng, 2), fbm(h, w, 55, rng, 2)

    def kind_at(x, y):
        if kind_a[y, x] < 0.46 and rng.random() < 0.8:
            return 1
        if kind_b[y, x] > 0.56 and rng.random() < 0.7:
            return 2
        return 3 if rng.random() < 0.07 else 0

    trees, taken = [], []
    okg = (g2 & keep & (d_dirt > 14) & (d_st > 12) & (d_w > 10)).astype(np.float32)
    for (x, y) in place(rng, okg * 0.5, 15, 62, taken):                           # small groves
        k0 = kind_at(x, y)
        for _ in range(int(rng.integers(3, 8))):
            tx, ty = x + int(rng.normal(0, 9)), y + int(rng.normal(0, 7))
            if 6 < tx < w - 6 and 6 < ty < h - 6 and okg[ty, tx]:
                trees.append((ty, tx, float(rng.uniform(4.2, 6.4)), k0 if rng.random() < 0.75 else kind_at(tx, ty)))
    for (x, y) in place(rng, okg * 0.4, 24, 30, taken):                           # lone trees
        trees.append((y, x, float(rng.uniform(4.4, 6.6)), kind_at(x, y)))
    for gy in range(0, h, 9):                                                     # the forest canopy
        for gx in range(0, w, 9):
            x, y = gx + int(rng.integers(0, 9)), gy + int(rng.integers(0, 9))
            if x < w and y < h and forest[y, x]:
                k = kind_at(x, y)
                trees.append((y, x, float(rng.uniform(4.2, 6.2) if k == 1 else rng.uniform(4.6, 7.0)), k))
    plant(rgb, rng, trees)
    outcrop9(rgb, rng, cx, cy + 2, ORE_ROCK_F, '#8c8272', '#1f1b17')
    foundation9(rgb, BLUE_R[0], BLUE_R[1], 2, 2, rng)
    return rgb, {}


def build_world(biome, seed):
    rng = np.random.default_rng(seed)
    terr, M = (paint_forest9 if biome == 'forest' else paint_desert9)(rng)
    units = F7 if biome == 'forest' else D7
    hot = (terr[..., 2] > 0.8) & (terr[..., 0] > 0.5) & (terr[..., 1] < 0.6)       # purple crystals glow a little
    glow = terr * hot[..., None]
    world, _ = V3.draw_world3(terr, [], units)
    world = grade(world + blur(glow, 2) * 0.22 + blur(glow, 7) * 0.3)
    wim = to_img(world)
    d = ImageDraw.Draw(wim)
    for u in units:
        if u[4] == 'sel':
            x, y = u[2], u[3] - V3.HP_DY
            d.rectangle([x - 8, y, x + 8, y + 3], fill='#1a120c')
            d.rectangle([x - 7, y + 1, x + 4, y + 2], fill='#62c048')
    world = np.pad(to_arr(wim), ((H - VH, 0), (0, 0), (0, 0)), mode='reflect')
    world[H - VH] = world[H - VH + 1]
    return world


_src = inspect.getsource(V8.compose8)
_body = _src[_src.index("    T, C = TH8[theme], CONTENT[theme]\n"):_src.index("    im.save(f'{OUT}/v8_{biome}_native.png')")]
_body = _body.replace("'#e0a23a'", "'#b266f6'")
exec("def hud_draw(frame, biome, theme, seed):\n" + _body + "    return to_arr(im)\n", V8.__dict__)


def hud_layer(biome, theme, seed):
    """Render the HUD over black and over white to recover its colour and coverage."""
    k = V8.hud_draw(np.zeros((H, W, 3), np.float32), biome, theme, seed)
    wh = V8.hud_draw(np.ones((H, W, 3), np.float32), biome, theme, seed)
    a = np.clip(1 - (wh - k).mean(-1), 0, 1)
    return k / np.maximum(a, 1e-3)[..., None], a


def shot(world, hud, zoom, origin, path):
    vw = VW * 2
    if zoom == 2:
        big = np.repeat(np.repeat(world, 2, 0), 2, 1)[:H * 2, :vw]
    else:
        x0, y0 = origin
        ww, wh = -(-vw // zoom), -(-H * 2 // zoom)
        big = np.repeat(np.repeat(world[y0:y0 + wh, x0:x0 + ww], zoom, 0), zoom, 1)[:H * 2, :vw]
    final = np.zeros((H * 2, W * 2, 3), np.float32)
    final[:, :vw] = big
    C = np.repeat(np.repeat(hud[0], 2, 0), 2, 1)
    A = np.repeat(np.repeat(hud[1], 2, 0), 2, 1)[..., None]
    to_img(final * (1 - A) + np.clip(C, 0, 1) * A).save(path)
    print('saved', os.path.basename(path))


if __name__ == '__main__':
    for biome, theme, seed, origin in (('forest', 'blue', 11, (60, 172)), ('desert', 'red', 23, (246, 170))):
        world = build_world(biome, seed)
        hud = hud_layer(biome, theme, seed)
        shot(world, hud, 2, None, f'{OUT}/v9_{biome}_zoomed_out.png')
        shot(world, hud, 3, origin, f'{OUT}/v9_{biome}_gameplay_zoom.png')
