# Balance style test v3 -- flat, near top-down (Dune II proportions), muted palette, straight-edged HUD.
# Run: python v3_compose.py <raw_sprite_dir> <out_dir> [forest desert]
import os, sys, math
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from v2_compose import *          # noqa: F401,F403  (shared helpers: noise, sprites, emboss layers, icons, text)

GRASS3 = ['#3a5a26', '#44682b', '#4f7631', '#5b8438', '#699241']
FLOOR3 = ['#22381c', '#2a4420', '#335026', '#3c5c2c']
DIRT3 = ['#6b5234', '#7a5f3c', '#8a6d46', '#9a7c52', '#a88a5e']
STONE3 = ['#4a463e', '#5a554b', '#6a6558', '#7b7566', '#8c8676']
WATER3 = ['#2a5a78', '#32698a', '#3c7a9c', '#4f8eae']
SAND3 = ['#b98248', '#c48d50', '#cf9959', '#d9a663', '#e2b36f']
DUNE3 = ['#a6723c', '#b47e46', '#c69052', '#d4a05e']
ROCKG3 = ['#4c4034', '#5b4c3d', '#6a5947', '#7a6752', '#8a765e']
HARD3 = ['#b08a62', '#bd9870', '#c9a67e', '#d4b48c']


def speck(h, w, rng, amp):
    return (rng.random((h, w)).astype(np.float32) - 0.5) * amp


def relief(rgb, mask, lit, dark):
    """Thin lit north-west edge and dark south-east edge: reads as a low step, not a cliff."""
    nw = mask & ~(np.roll(mask, 1, 0) & np.roll(mask, 1, 1))
    se = mask & ~(np.roll(mask, -1, 0) & np.roll(mask, -1, 1))
    rgb[nw] = hexc(lit)
    rgb[se] = hexc(dark)


def paint_forest3(rng):
    h, w = VH, VW
    yy, xx = np.mgrid[0:h, 0:w].astype(np.float32)
    cx, cy = ROCK_C
    X = xx + (fbm(h, w, 60, rng) - 0.5) * 50
    Y = yy + (fbm(h, w, 60, rng) - 0.5) * 50
    d_clear = np.hypot((X - cx) / 1.3, Y - cy - 6) - 78
    d_p1 = polydist(X, Y, [(cx - 70, cy + 55), (250, 395), (150, 450), (60, 540)]) - 13
    d_p2 = polydist(X, Y, [(cx + 90, cy - 10), (540, 208), (650, 226), (770, 185)]) - 13
    d_dirt = np.minimum(np.minimum(d_clear, d_p1), d_p2)
    dirt = d_dirt + speck(h, w, rng, 4) < 0
    d_st = np.minimum(np.minimum(np.hypot((X - cx) / 1.5, Y - cy - 4) - 46, np.hypot((X - 612) / 1.4, Y - 402) - 46),
                      np.hypot((X - 150) / 1.2, Y - 262) - 32)
    stone = d_st + speck(h, w, rng, 4) < 0
    d_w = polydist(X, Y, [(270, -20), (245, 50), (190, 95), (120, 120), (55, 175), (-30, 205)]) - 13
    water = d_w < 0
    bank = (d_w < 4) & ~water
    edge = 1 - np.minimum(np.minimum(xx, w - xx), np.minimum(yy, h - yy)) / 170
    dense = ((fbm(h, w, 120, rng, 3) - 0.5) * 2.2 + np.clip(edge, 0, 1) * 0.9 > 0.5) & (d_dirt > 20) & (d_w > 12) & (
            d_st > 14)
    densef = blur(dense.astype(np.float32), 7)

    rgb = ramp(np.clip(0.5 + (fbm(h, w, 110, rng, 3) - 0.5) * 1.0 + speck(h, w, rng, 0.42), 0, 0.999), GRASS3)
    fl = ramp(np.clip(0.5 + (fbm(h, w, 60, rng, 3) - 0.5) * 0.9 + speck(h, w, rng, 0.5), 0, 0.999), FLOOR3)
    rgb = np.where((densef > 0.5)[..., None], fl, rgb)
    dc = ramp(np.clip(0.5 + (fbm(h, w, 45, rng, 3) - 0.5) * 0.9 + speck(h, w, rng, 0.4), 0, 0.999), DIRT3)
    rgb = np.where(dirt[..., None], dc, rgb)
    rgb[dirt & ~shrink(dirt, 1)] = hexc('#4f3d26')
    sc = ramp(np.clip(0.5 + (fbm(h, w, 30, rng, 3) - 0.5) * 0.8 + speck(h, w, rng, 0.6), 0, 0.999), STONE3)
    rgb = np.where(stone[..., None], sc, rgb)
    relief(rgb, stone, '#a29b89', '#2f2c26')
    rgb[bank] = ramp(np.clip(0.5 + speck(h, w, rng, 0.9), 0, 0.999), ['#8a7a56', '#9c8c66', '#ae9e76'])[bank]
    wc = ramp(np.clip(0.45 + (fbm(h, w, 30, rng) - 0.5) * 0.8 + speck(h, w, rng, 0.25), 0, 0.999), WATER3)
    rgb = np.where(water[..., None], wc, rgb)
    rgb[water & ~shrink(water, 1)] = hexc('#1f465e')
    rgb = rgb * (1 + 0.07 * (fbm(h, w, 150, rng, 2) - 0.5) * 2)[..., None]

    im = to_img(rgb)
    d = ImageDraw.Draw(im)
    grass = ~dirt & ~water & ~bank & ~stone & (densef < 0.4)
    for (x, y) in scatter(rng, grass, 500):
        d.point([(x, y), (x - 1, y - 1), (x + 1, y - 1)], fill='#7fa650' if rng.random() < 0.5 else '#33501f')
    for (x, y) in scatter(rng, grass & (d_dirt > 6), 14):
        c = ['#e8e0c0', '#d8c060', '#c8a0c8'][int(rng.integers(0, 3))]
        for _ in range(int(rng.integers(3, 7))):
            fx, fy = x + int(rng.integers(-8, 9)), y + int(rng.integers(-6, 7))
            if 1 < fx < w - 2 and 1 < fy < h - 2 and grass[fy, fx]:
                d.point((fx, fy), fill=c)
    for (x, y) in scatter(rng, dirt & (d_dirt < -4) & ~stone, 110):
        d.rectangle([x, y, x + 1, y], fill='#b8a078')
        d.point((x, y + 1), fill='#4f3d26')
    return to_arr(im), dict(dense=dense, densef=densef, d_dirt=d_dirt, d_w=d_w, d_st=d_st)


UNITS_F3 = [('inf_blue', 7, 240, 350, 'sel'), ('inf_blue', 6, 262, 364, ''), ('inf_blue', 7, 224, 372, ''),
            ('inf_blue', 6, 248, 388, ''),
            ('inf_red', 1, 560, 214, ''), ('inf_red', 2, 584, 205, ''), ('inf_red', 1, 590, 228, ''),
            ('inf_red', 2, 614, 215, '')]


def forest_entities3(rng, M):
    cx, cy = ROCK_C
    E = [('ori_forest', 0, cx, cy + 4), ('shard_a', 0, cx - 62, cy + 30), ('shard_a', 0, cx + 58, cy + 34)]
    taken = [(cx, cy)]
    ok = (M['d_dirt'] > 18) & (M['d_w'] > 12) & (M['d_st'] > 14)
    wd = np.where(ok, 0.02 + 0.98 * (M['densef'] > 0.45), 0).astype(np.float32)
    for u in UNITS_F3:
        wd[max(0, u[3] - 8):u[3] + 48, max(0, u[2] - 34):u[2] + 34] = 0
    kinds = ['tree_a'] * 6 + ['tree_b'] * 5 + ['tree_c'] * 4 + ['tree_d'] * 4 + ['pine_a'] * 3 + ['pine_b'] * 3 + [
        'tree_aut']
    for (x, y) in place(rng, wd, 150, 25, taken, 9000):
        E.append((kinds[int(rng.integers(0, len(kinds)))], 0, x, y))
    edge = np.where(ok & (M['densef'] > 0.08) & (M['densef'] < 0.5), 1.0, 0.01 * ok).astype(np.float32)
    small = ['bush_a', 'bush_b', 'bush_a', 'rockf_a', 'rockf_b']
    for (x, y) in place(rng, edge, 22, 26, taken):
        E.append((small[int(rng.integers(0, len(small)))], 0, x, y))
    E += [('rockf_c', 0, 596, 398), ('rockf_b', 0, 632, 410), ('rockf_a', 0, 148, 258), ('rockf_b', 0, 330, 236)]
    return E, UNITS_F3


def paint_desert3(rng):
    h, w = VH, VW
    yy, xx = np.mgrid[0:h, 0:w].astype(np.float32)
    cx, cy = ROCK_C
    wx = (fbm(h, w, 70, rng) - 0.5) * 60
    wy = (fbm(h, w, 70, rng) - 0.5) * 60
    X, Y = xx + wx, yy + wy
    big = (fbm(h, w, 190, rng, 2) - 0.5) * 2
    phase = (0.28 * xx + yy) / 110 + big * 1.6
    rgb = ramp(np.clip(0.5 + big * 0.3 + 0.10 * np.sin(phase * 2 * math.pi) + speck(h, w, rng, 0.4), 0, 0.999), SAND3)

    d_clear = np.hypot((X - cx) / 1.35, Y - cy - 6) - 76
    d_p1 = polydist(X, Y, [(cx + 80, cy + 50), (520, 380), (640, 440), (760, 470)]) - 15
    d_p2 = polydist(X, Y, [(cx - 90, cy - 20), (210, 190), (110, 150), (-20, 120)]) - 15
    d_hard = np.minimum(np.minimum(d_clear, d_p1), d_p2)
    hard = d_hard + speck(h, w, rng, 5) < 0
    corner = np.maximum(1 - np.hypot(xx - 40, yy - 470) / 250, 1 - np.hypot(xx - 700, yy - 60) / 230)
    corner = np.maximum(corner, 1 - np.hypot(xx - 90, yy - 20) / 150)
    rock = ((fbm(h, w, 100, rng, 3) - 0.5) * 1.3 + corner > 0.52) & (d_hard > 26)
    d_rk = np.hypot((X - cx) / 1.5, Y - cy - 4) - 44
    rock = shrink(grow(rock, 3), 3) | (d_rk + speck(h, w, rng, 4) < 0)

    dn = (fbm(h, w, 130, rng, 3) - 0.5) * 2.4
    dunes = (dn > 0.22) & (d_hard > 22) & ~grow(rock, 8)
    rip = np.sin((yy + 0.3 * xx + wy * 0.5) / 2.3)
    dv = 0.5 + 0.3 * np.sign(rip) * np.minimum(np.abs(rip) * 3, 1) + speck(h, w, rng, 0.3)
    rgb = np.where(dunes[..., None], ramp(np.clip(dv, 0, 0.999), DUNE3), rgb)

    f1, f2, fv = voronoi(h, w, 16, rng)
    hc = ramp(np.clip(0.5 + (fbm(h, w, 50, rng) - 0.5) * 0.9 + speck(h, w, rng, 0.35), 0, 0.999), HARD3)
    hc[(f2 - f1) < 0.8] = hexc('#a07c58')
    rgb = np.where(hard[..., None], hc, rgb)
    rgb[hard & ~shrink(hard, 1)] = hexc('#9c7a54')

    g1, g2, gv = voronoi(h, w, 38, rng)
    rc = ramp(np.clip(0.5 + (fbm(h, w, 40, rng, 3) - 0.5) * 0.8 + speck(h, w, rng, 0.62), 0, 0.999), ROCKG3)
    rc[(g2 - g1) < 0.7] = hexc('#3c3229')
    rgb = np.where(rock[..., None], rc, rgb)
    relief(rgb, rock, '#a8937a', '#2b221b')

    ox, oy = 610, 96
    d_o = np.hypot((X - ox) / 1.5, Y - oy)
    oasis = (d_o < 18) & ~rock
    green = (d_o < 28) & ~oasis & ~rock
    rgb = np.where(green[..., None], ramp(np.clip(0.5 + speck(h, w, rng, 0.9), 0, 0.999), GRASS3[1:]), rgb)
    rgb = np.where(oasis[..., None], ramp(np.clip(0.5 + speck(h, w, rng, 0.5), 0, 0.999), WATER3), rgb)
    rgb[oasis & ~shrink(oasis, 1)] = hexc('#1f465e')
    rgb = rgb * (1 + 0.06 * (fbm(h, w, 170, rng, 2) - 0.5) * 2)[..., None]

    im = to_img(rgb)
    d = ImageDraw.Draw(im)
    sand = ~hard & ~rock & ~oasis & ~green
    for (x, y) in scatter(rng, sand, 150):
        d.point([(x, y), (x - 1, y - 1), (x + 1, y - 1)], fill='#8a6a34')
    for (x, y) in scatter(rng, sand | hard, 150):
        d.rectangle([x, y, x + 1, y], fill='#7a5a3c' if rng.random() < 0.6 else '#ecd0a0')
        d.point((x, y + 1), fill='#6a4a2c')
    return to_arr(im), dict(rock=rock, sand=sand & ~dunes, d_hard=d_hard, d_rk=d_rk)


def desert_entities3(rng, M):
    cx, cy = ROCK_C
    E = [('ori_desert', 0, cx, cy + 4), ('shard_b', 0, cx - 60, cy + 30), ('shard_b', 0, cx + 58, cy + 32)]
    taken = [(cx, cy)]
    for nm, x, y in (('palm_a', 584, 96), ('palm_b', 640, 90), ('palm_a', 622, 122), ('succ_a', 572, 122),
                     ('ribs', 196, 372), ('deadtree', 452, 404)):
        E.append((nm, 0, x, y))
        taken.append((x, y))
    free = (M['sand'] & (M['d_hard'] > 12)).astype(np.float32)
    small = ['rockd_a', 'rockd_b', 'rockd_b', 'succ_b', 'drybush', 'drybush', 'drybush']
    for (x, y) in place(rng, free * 0.6, 26, 50, taken):
        E.append((small[int(rng.integers(0, len(small)))], 0, x, y))
    on_rock = (shrink(M['rock'], 14) & (M['d_rk'] > 40)).astype(np.float32)
    for (x, y) in place(rng, on_rock * 0.6, 14, 52, taken):
        E.append((['spire_a', 'spire_b', 'rockd_c', 'rockd_a'][int(rng.integers(0, 4))], 0, x, y))
    units = [('inf_red', 1, 520, 372, 'sel'), ('inf_red', 2, 544, 360, ''), ('inf_red', 1, 548, 388, ''),
             ('inf_red', 2, 572, 376, ''),
             ('inf_blue', 7, 212, 186, ''), ('inf_blue', 6, 188, 174, ''), ('inf_blue', 7, 184, 200, ''),
             ('inf_blue', 6, 160, 186, '')]
    return E, units


HP_DY, SEL_RX, SEL_RY = 31, 9, 4


def unit_sprite(u):
    return sprite(u[0], u[1], outline='outer', colors=32, sat=1.15)


def draw_world3(rgb, E, units):
    h, w = rgb.shape[:2]
    shmap = np.zeros((h, w), np.float32)
    glow = np.zeros((h, w, 3), np.float32)
    items = [(e[3], e, sprite(e[0], e[1], colors=32, sat=1.0)) for e in E]
    items += [(u[3], u, unit_sprite(u)) for u in units]
    for _, e, s in items:
        put(shmap, e[2] - s['ax'], e[3] - s['ay'], None, s['sh'])
    sm = np.clip(shmap, 0, 1)[..., None] * 0.42
    rgb = rgb * (1 - sm) + rgb * hexc('#3a3448') * sm
    im = to_img(rgb)
    d = ImageDraw.Draw(im)
    cx, cy = ROCK_C
    for a in range(0, 360, 6):                                   # control zone around the rock
        x, y = cx + 104 * math.cos(math.radians(a)), cy + 6 + 78 * math.sin(math.radians(a))
        d.point([(x, y + 1), (x + 1, y + 1)], fill='#2a2014')
        d.point([(x, y), (x + 1, y)], fill='#e8dcb0')
    for u in units:
        if u[4] == 'sel':
            d.ellipse([u[2] - SEL_RX, u[3] - SEL_RY, u[2] + SEL_RX, u[3] + SEL_RY + 1], outline='#e8f0d8')
    rgb = to_arr(im)
    for _, e, s in sorted(items, key=lambda t: t[0]):
        x0, y0 = e[2] - s['ax'], e[3] - s['ay']
        put(rgb, x0, y0, s['rgb'], s['a'])
        if e[0].startswith(('ori', 'shard')):
            c = s['rgb']
            hot = (c[..., 0] > 0.9) & (c[..., 1] > 0.55) & (c[..., 2] < 0.7) & (s['a'] > 0)
            put(glow, x0, y0, c, hot.astype(np.float32))
    return rgb, glow


# --- HUD: straight frames, small corner radii, one round emblem ------------------------------------------
WALNUT = ['#1a110a', '#2b1c11', '#3f2c1b', '#544027', '#6a5435', '#806844']
BRASS = ['#2a1f0c', '#4c3a16', '#766024', '#a08638', '#c6ab55', '#e6d28a']
IRONWOOD = ['#170f0d', '#281916', '#3c2620', '#50342b', '#644438', '#785648']
BRONZE = ['#22150a', '#44280f', '#6a401a', '#925e28', '#b8833f', '#dcb474']
NAVY = ['#0c1a3a', '#1a3266', '#2c4f96', '#4f7cc4', '#a8c8ee']
OXBLOOD = ['#350c0a', '#641712', '#942a1f', '#bd5440', '#e4ac98']
PARCH3 = ['#9c7f52', '#b89c6c', '#cfb688', '#e0cba2', '#ecdcb8']
T3 = {
    'blue': dict(frame=WALNUT, trim=BRASS, accent=NAVY, name='Guardsman', sub='Blue Infantry',
                 sky=('#5a86b8', '#d8d0b0'), hold='Hold  0:42', bar='#3a6ac8'),
    'red': dict(frame=IRONWOOD, trim=BRONZE, accent=OXBLOOD, name='Legionary', sub='Red Infantry',
                sky=('#a8603c', '#e0c088'), hold='Hold  0:17', bar='#b83a2a'),
}
TB = [(758 + 38.4 * i, 198, 792 + 38.4 * i, 222) for i in range(5)]
CARD3 = (756, 232, 950, 392)
PORT = (764, 240, 830, 322)
PIPS = [(846 + 25 * i, 362, 864 + 25 * i, 380) for i in range(4)]
CM = [(757 + 49 * i, 404, 801 + 49 * i, 440) for i in range(4)]
OBJ3 = (756, 462, 950, 530)


def rr(d, S, box, r, pad=0.0, fill=255):
    d.rounded_rectangle(P(S, box[0] - pad, box[1] - pad, box[2] + pad, box[3] + pad), max(0.5, r) * S, fill=fill)


def diamond(d, S, x, y, r):
    d.polygon(P(S, x, y - r, x + r, y, x, y + r, x - r, y), fill=255)


def build_hud3(theme, rng):
    T = T3[theme]
    L = Layers(3)
    hs, ws = H * L.S, W * L.S
    grain = (fbm(hs, ws, 9 * L.S, rng, 3, (9, 0.5)) - 0.5) * 0.5 + (fbm(hs, ws, 60 * L.S, rng, 2) - 0.5) * 0.25
    shine = (fbm(hs, ws, 30 * L.S, rng, 2, (1.5, 0.6)) - 0.5) * 0.22

    def frame(d, S):
        d.rectangle(P(S, 0, 0, W, TOP - 2), fill=255)
        d.rectangle(P(S, SX + 2, TOP - 2, W, H), fill=255)
    L.layer(L.mask(frame), T['frame'], 2, 0.5, grain, shadow=4)

    def rails(d, S):
        d.rectangle(P(S, 0, TOP - 4, W, TOP), fill=255)
        d.rectangle(P(S, SX - 2, TOP - 4, SX + 3, H), fill=255)
        d.rectangle(P(S, 0, 0, W, 1.5), fill=255)
        d.rectangle(P(S, W - 3, TOP, W, H), fill=255)
        d.rectangle(P(S, SX, H - 4, W, H), fill=255)
        d.ellipse(P(S, 3, 0, 45, 42), fill=255)                         # the one round element: the emblem
        for c in CAPS:
            rr(d, S, c, 4, 2)
        rr(d, S, MM, 4, 6)
        for b in TB:
            rr(d, S, b, 3, 1.5)
        rr(d, S, CARD3, 5, 3)
        for b in CM:
            rr(d, S, b, 4, 1.5)
        rr(d, S, OBJ3, 4, 3)
        for y in (TOP + 110, TOP + 256, TOP + 402):
            diamond(d, S, SX + 0.5, y, 6)
        diamond(d, S, SX + 0.5, TOP - 2, 8)
    L.layer(L.mask(rails), T['trim'], 1.8, 1.0, shine, shadow=2)

    def insets(d, S):
        for c in CAPS[1:]:
            rr(d, S, c, 2.5)
        rr(d, S, MM, 2)
    L.layer(L.mask(insets), PANEL, 2, -0.6, None)

    def parch(d, S):
        rr(d, S, CAPS[0], 2.5)
        rr(d, S, CARD3, 3)
        rr(d, S, OBJ3, 2.5)
    L.layer(L.mask(parch), PARCH3, 1.5, -0.3, (fbm(hs, ws, 40 * L.S, rng, 3) - 0.5) * 0.6 + 0.1)

    def rim2(d, S):
        rr(d, S, PORT, 3, 3)
        for b in PIPS:
            rr(d, S, b, 2, 1.5)
    L.layer(L.mask(rim2), T['trim'], 1.5, 1.0, shine, shadow=1.5)

    def inset2(d, S):
        rr(d, S, PORT, 1.5)
        for b in PIPS:
            rr(d, S, b, 1)
        for b in TB[1:]:
            rr(d, S, b, 2)
    L.layer(L.mask(inset2), PANEL, 2, -0.6, None)

    def accent(d, S):
        d.ellipse(P(S, 7, 4, 41, 38), fill=255)
        rr(d, S, TB[0], 2)
        for b in CM:
            rr(d, S, b, 3)
    L.layer(L.mask(accent), T['accent'], 2.5, 0.8, None)

    def icons(d, S):
        draw_icon(d, S, 'scales', 11.5, 8.5, 1.55)
        for i, nm in enumerate(('sword', 'crown', 'castle', 'flag', 'cog')):
            draw_icon(d, S, nm, (TB[i][0] + TB[i][2]) / 2 - 7, TB[i][1] + 5, 0.9)
        for i, nm in enumerate(('move', 'swords', 'shield', 'heal')):
            draw_icon(d, S, nm, (CM[i][0] + CM[i][2]) / 2 - 9.5, CM[i][1] + 8.5, 1.2)
        draw_icon(d, S, 'helm', CAPS[2][0] + 6, CAPS[2][1] + 2, 0.85)
        draw_icon(d, S, 'glass', CAPS[3][0] + 6, CAPS[3][1] + 2, 0.85)
    L.layer(L.mask(icons), IVORY, 1.0, 0.8, None, shadow=1)

    def ore(d, S):
        draw_icon(d, S, 'gem', CAPS[1][0] + 5, CAPS[1][1] + 1.5, 0.9)
    L.layer(L.mask(ore), ORIP, 1.6, 1.0, None)
    return L.result()


def desat(a, k):
    g = a.mean(-1, keepdims=True)
    return g + (a - g) * k


def card_portrait(team, T, pw, ph):
    return desat(portrait_img(team, T['sky'], pw, ph), 0.85)


def card_pip(team, T):
    src = Image.open(f'{RAW}/inf_{team}_portrait.png').convert('RGBA')
    hb = Image.new('RGBA', src.size, tuple(int(v * 255) for v in hexc(T['sky'][0])) + (255,))
    hb.alpha_composite(src)
    return desat(to_arr(hb.crop((150, 95, 340, 285)).resize((18, 18), Image.LANCZOS)), 0.85)


def compose3(biome, theme, seed):
    rng = np.random.default_rng(seed)
    if biome == 'forest':
        terr, M = paint_forest3(rng)
        E, units = forest_entities3(rng, M)
    else:
        terr, M = paint_desert3(rng)
        E, units = desert_entities3(rng, M)
    world, glow = draw_world3(terr, E, units)
    world = world + blur(glow, 2) * 0.12 + blur(glow, 7) * 0.18
    wim = to_img(world)
    d = ImageDraw.Draw(wim)
    for u in units:
        if u[4] == 'sel':
            x, y = u[2], u[3] - HP_DY
            d.rectangle([x - 8, y, x + 8, y + 3], fill='#1a120c')
            d.rectangle([x - 7, y + 1, x + 4, y + 2], fill='#62c048')
    px, py = (300, 300) if biome == 'forest' else (470, 330)
    d.polygon([(px, py), (px, py + 11), (px + 3, py + 8), (px + 8, py + 8)], fill='#f0e6c4', outline='#2a1a0c')
    frame = np.zeros((H, W, 3), np.float32)
    frame[TOP:, :VW] = to_arr(wim)

    T = T3[theme]
    hud, ha = build_hud3(theme, np.random.default_rng(seed + 7))
    frame = frame * (1 - ha[..., None]) + hud * ha[..., None]
    mm = desat(minimap(biome, np.random.default_rng(seed + 3)), 0.6)
    w, h = MM[2] - MM[0], MM[3] - MM[1]
    put(frame, MM[0], MM[1], mm, shape_mask(lambda d, S: d.rounded_rectangle([0, 0, w * S - 1, h * S - 1], 2 * S,
                                                                             fill=255), w, h))
    team = 'blue' if theme == 'blue' else 'red'
    pw, ph = PORT[2] - PORT[0], PORT[3] - PORT[1]
    put(frame, PORT[0], PORT[1], card_portrait(team, T, pw, ph), np.ones((ph, pw), np.float32))
    head = card_pip(team, T)
    for b in PIPS:
        put(frame, int(b[0]), int(b[1]), head, np.ones((18, 18), np.float32))

    im = to_img(frame)
    d = ImageDraw.Draw(im)
    d.fontmode = '1'
    ink, light, sh, dim = '#33200e', '#f2e6c4', '#140a04', '#6a4c2a'
    text(d, 52, 0, 'Balance', F_TITLE, '#e8cf88', '#1e1006')
    c = CAPS[0]
    text(d, (c[0] + c[2]) // 2, c[1] + 2, 'Mission 1  -  The First Claim', F_B11, ink, None, 'ma')
    c = CAPS[1]
    text(d, c[0] + 24, c[1] + 2, 'Orichalcum', F_B11, '#e8bf6c', sh)
    text(d, c[2] - 8, c[1] + 2, '340', F_B12, light, sh, 'ra')
    c = CAPS[2]
    text(d, c[0] + 24, c[1] + 2, 'Squad', F_B11, '#e8bf6c', sh)
    text(d, c[2] - 8, c[1] + 2, '4 / 4', F_B12, light, sh, 'ra')
    c = CAPS[3]
    text(d, c[0] + 24, c[1] + 2, T['hold'], F_B11, light, sh)
    c = CAPS[4]
    text(d, (c[0] + c[2]) // 2, c[1] + 2, 'Menu   F10', F_B11, light, sh, 'ma')
    x = PORT[2] + 10
    text(d, x, 240, T['name'], F_B12, ink)
    text(d, x, 255, T['sub'], F_R11, dim)
    d.rectangle([x, 273, x + 102, 281], fill='#33200e')
    d.rectangle([x + 1, 274, x + 76, 280], fill='#4a9a3a')
    d.line([x + 1, 274, x + 76, 274], fill='#86c874')
    text(d, x, 285, 'Health  45 / 60', F_S9, ink)
    for i, (k, v) in enumerate((('Attack', '12'), ('Armour', '4'), ('Range', '1'))):
        text(d, x, 300 + 11 * i, k, F_S9, dim)
        text(d, x + 102, 300 + 11 * i, v, F_S10, ink, None, 'ra')
    text(d, 764, 340, 'Squad', F_B11, ink)
    text(d, 764, 365, '4 of 4 fit', F_S9, dim)
    for i, s in enumerate(('Move', 'Attack', 'Hold', 'Mend')):
        text(d, int((CM[i][0] + CM[i][2]) / 2), 444, s, F_S9, light, sh, 'ma')
    mx = (OBJ3[0] + OBJ3[2]) // 2
    text(d, mx, OBJ3[1] + 5, 'Objective', F_B11, '#7a2a16', None, 'ma')
    text(d, mx, OBJ3[1] + 20, 'Hold the Orichalcum rock', F_R11, ink, None, 'ma')
    bx0, bx1, by = OBJ3[0] + 20, OBJ3[2] - 20, OBJ3[1] + 42
    d.rectangle([bx0, by, bx1, by + 8], fill='#33200e')
    frac = 0.7 if theme == 'blue' else 0.28
    d.rectangle([bx0 + 1, by + 1, int(bx0 + (bx1 - bx0) * frac), by + 7], fill=T['bar'])
    im.save(f'{OUT}/v3_{biome}_native.png')
    im.resize((W * 2, H * 2), Image.NEAREST).save(f'{OUT}/v3_{biome}.png')
    print('saved', biome)


if __name__ == '__main__':
    if 'forest' in WHICH:
        compose3('forest', 'blue', 11)
    if 'desert' in WHICH:
        compose3('desert', 'red', 23)
