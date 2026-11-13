#!/usr/bin/env python3
"""Generate the terrain tile atlases for Balance.

Run from the repo root:  python tools/make_tiles.py

Output goes to assets/tiles/<biome>/:

  <ground>.png   256x256, opaque. An 8x8 block of 32 px tiles that repeats seamlessly.
                 The tile for cell (x, y) is at atlas position (x % 8, y % 8).
  <overlay>.png  2048x512, transparent background. 64 columns x 16 rows of 32 px tiles.
                 Overlay tiles are drawn on a grid shifted by half a cell, so each tile
                 sits on the corner where four cells meet ("dual grid").
                 Column = (i % 8) + 8 * (j % 8) for the tile at shifted position (i, j).
                 Row    = which of the four cells around that corner have this terrain:
                          top-left 1 + top-right 2 + bottom-left 4 + bottom-right 8.
                          Row 0 (none) is empty.
  decor.png      256x32, transparent background. Eight small props scattered on open ground.

Each biome also gets ore_rock.png, an overlay for the Orichalcum rock formation. Its ore
crystals are densest around the texture's origin, so a formation looks best when its middle
sits on a grid corner whose cell coordinates are multiples of 8 (the maps put it there).

It also writes assets/tiles/shroud.png, the black cover over unexplored ground, in the same
layout as an overlay (row = which of the four cells around the corner are unexplored).

The look follows the approved style mockups (mockups/balance_v4_*.png): flat texture
patches made of small repeating elements with per-pixel grit, lit from the north-west.
Everything is generated from fixed seeds, so the output is the same on every run.
"""
import math
import os
import sys

import numpy as np
from PIL import Image

CELL = 32                 # one grid cell, in pixels
PERIOD = 8                # textures repeat every 8 cells
P = CELL * PERIOD         # texture size in pixels
PAD = 8                   # margin computed around each tile so edges and shadows are right
TS = CELL + 2 * PAD
AMP = 0.18                # how far terrain borders wander (0.03 is about one pixel)
EDGE = 0.42               # border threshold; below 0.5 so neighbouring overlays overlap slightly

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
OUT = os.path.join(ROOT, 'assets', 'tiles')

# --- palettes (from the approved v4 mockups) ----------------------------------------------
GRASS = ['#3a4c27', '#44572c', '#4e6232', '#586d38', '#63783f']
FLOOR = ['#141d12', '#1a2616', '#202f1a']
DIRT = ['#5a4730', '#675237', '#745e3f', '#816a48', '#8e7652']
STONE = ['#3e3b35', '#4c4841', '#5a564d', '#69645a', '#787367']
WATER = ['#24465c', '#2b5269', '#335e77', '#3d6c86']
BANK = ['#6e6448', '#7e7354', '#8e8260']
CROWNS = [['#17251a', '#203320', '#2a4226', '#35522d', '#426234'],
          ['#1c2914', '#27381a', '#334920', '#415a28', '#506b31'],
          ['#152624', '#1d342f', '#26433b', '#305347', '#3c6354'],
          ['#222a14', '#2f3a1a', '#3d4b21', '#4c5d29', '#5c6f32']]
SHRUB = [['#2a3a1c', '#384b22', '#475d2a', '#587033']]
PEBBLE_F = [['#35322d', '#4c4841', '#69645a', '#8a8477', '#a39d8e']]
SAND = ['#b98248', '#c48d50', '#cf9959', '#d9a663', '#e2b36f']
DUNE = ['#a6723c', '#b47e46', '#c69052', '#d4a05e']
ROCK = ['#4c4034', '#5b4c3d', '#6a5947', '#7a6752', '#8a765e']
HARD = ['#b08a62', '#bd9870', '#c9a67e', '#d4b48c']
PEBBLE_D = [['#3a2f26', '#54453a', '#6f5c4b', '#8c7660', '#a89078']]
TUFT = [['#5e4c24', '#78602a', '#957a33', '#b0943e']]
ORE = [['#6a3c0c', '#a8661a', '#de962a', '#fbc552', '#fff0b0']]
ORE_ROCK_F = ['#332d28', '#423a33', '#51483f', '#61574b', '#726658']
ORE_ROCK_D = ['#45332a', '#574135', '#694f40', '#7b5e4c', '#8e6e59']
DESERT_DESAT = 0.92


# --- helpers ------------------------------------------------------------------------------
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


def desat(a, k):
    g = a.mean(-1, keepdims=True)
    return g + (a - g) * k


def tnoise(cells, rng):
    """Smooth value noise that tiles seamlessly over P pixels; `cells` lattice cells across."""
    g = rng.random((cells, cells)).astype(np.float32)
    t = np.arange(P) * cells / P
    i0 = np.floor(t).astype(np.int32)
    f = (t - i0).astype(np.float32)
    f = f * f * (3 - 2 * f)
    i1 = (i0 + 1) % cells
    rows = g[i0] * (1 - f)[:, None] + g[i1] * f[:, None]
    return rows[:, i0] * (1 - f)[None, :] + rows[:, i1] * f[None, :]


def fbm(cells, rng, octaves=3):
    out = np.zeros((P, P), np.float32)
    amp, tot = 1.0, 0.0
    for o in range(octaves):
        out += tnoise(min(P, cells * 2 ** o), rng) * amp
        tot += amp
        amp *= 0.5
    return out / tot


def speck(rng, amp, shape=(P, P)):
    return (rng.random(shape).astype(np.float32) - 0.5) * amp


def tvoronoi(n, rng):
    """Seamless Voronoi cells, n x n of them. Returns nearest and second-nearest distance and a cell value."""
    cell = P / n
    px = ((np.arange(n)[None, :] + rng.random((n, n))) * cell).ravel()
    py = ((np.arange(n)[:, None] + rng.random((n, n))) * cell).ravel()
    val = rng.random(n * n).astype(np.float32)
    yy, xx = np.mgrid[0:P, 0:P].astype(np.float32)
    f1 = np.full((P, P), 1e9, np.float32)
    f2 = f1.copy()
    v = np.zeros((P, P), np.float32)
    for k in range(n * n):
        dx = np.abs(xx - px[k])
        dx = np.minimum(dx, P - dx)
        dy = np.abs(yy - py[k])
        dy = np.minimum(dy, P - dy)
        d = np.hypot(dx, dy)
        f2 = np.minimum(f2, np.maximum(f1, d))
        v = np.where(d < f1, val[k], v)
        f1 = np.minimum(f1, d)
    return f1, f2, v


def shrink1(m):
    out = m.copy()
    for dy in (-1, 0, 1):
        for dx in (-1, 0, 1):
            out &= np.roll(np.roll(m, dy, 0), dx, 1)
    return out


def relief(rgb, mask, lit, dark):
    """Thin lit north-west edge and dark south-east edge: reads as a low step, not a cliff."""
    nw = mask & ~(np.roll(mask, 1, 0) & np.roll(mask, 1, 1))
    se = mask & ~(np.roll(mask, -1, 0) & np.roll(mask, -1, 1))
    rgb[nw] = hexc(lit)
    rgb[se] = hexc(dark)


def stamp_points(rng, cell, rmin, rmax, prob, npal, size=P):
    pts = []
    for gy in range(0, size, cell):
        for gx in range(0, size, cell):
            if rng.random() > prob:
                continue
            x, y = gx + int(rng.integers(0, cell)), gy + int(rng.integers(0, cell))
            pts.append((y % size, x % size, float(rng.uniform(rmin, rmax)), int(rng.integers(0, npal))))
    pts.sort()
    return pts


def draw_shadow(sh, x, y, r, owner=None, oid=-1):
    """Mark the short south-east shadow of a round element. Wraps around the array edges."""
    R = int(r) + 3
    ys, xs = np.arange(y - R, y + R + 3), np.arange(x - R, x + R + 3)
    dy, dx = np.meshgrid((ys - y).astype(np.float32), (xs - x).astype(np.float32), indexing='ij')
    m = np.hypot(dx - 1.5, dy - 2.0) < r + 0.3
    ix = np.ix_(ys % sh.shape[0], xs % sh.shape[1])
    sub = sh[ix]
    sub[m] = 1
    sh[ix] = sub
    if owner is not None:
        o = owner[ix]
        o[m] = oid
        owner[ix] = o


def draw_stamp(rgb, x, y, r, p, rng, rough=0.9, metric='round', rim=0.25, alpha=None, owner=None, oid=-1):
    """One small shaded element (tree top, stone): lit north-west, dark south-east. Wraps around."""
    R = int(r) + 2
    ys, xs = np.arange(y - R, y + R + 1), np.arange(x - R, x + R + 1)
    dy, dx = np.meshgrid((ys - y).astype(np.float32), (xs - x).astype(np.float32), indexing='ij')
    if metric == 'round':
        dist = np.hypot(dx, dy)
    elif metric == 'crystal':
        dist = np.abs(dx) * 1.7 + np.abs(dy)
    else:
        dist = np.abs(dx) + np.abs(dy)
    m = dist + (rng.random(dist.shape).astype(np.float32) - 0.5) * rough * 2 < r
    v = 0.55 - 0.42 * (dx + dy) / (1.5 * r) + (rng.random(dist.shape).astype(np.float32) - 0.5) * 0.3
    v -= rim * ((dist > r - 1.4) & (dx + dy > 0))
    col = ramp(np.clip(v, 0, 0.999), p)
    ix = np.ix_(ys % rgb.shape[0], xs % rgb.shape[1])
    sub = rgb[ix]
    sub[m] = col[m]
    rgb[ix] = sub
    if alpha is not None:
        a = alpha[ix]
        a[m] = 1
        alpha[ix] = a
    if owner is not None:
        o = owner[ix]
        o[m] = oid
        owner[ix] = o


def stamps(rgb, rng, cell, rmin, rmax, pals, prob=1.0, shadow=0.38, rough=0.9, metric='round', rim=0.25):
    """Scatter many small shaded elements over a seamless texture."""
    pts = stamp_points(rng, cell, rmin, rmax, prob, len(pals))
    if shadow:
        sh = np.zeros((P, P), np.float32)
        for (y, x, r, _) in pts:
            draw_shadow(sh, x, y, r)
        rgb *= (1 - shadow * sh)[..., None]
    pp = [pal(c) for c in pals]
    for (y, x, r, k) in pts:
        draw_stamp(rgb, x, y, r, pp[k], rng, rough, metric, rim)


def marks(rgb, rng, n, offsets, colours):
    """Scatter tiny pixel marks. `colours` is a list of (probability, [colour per offset])."""
    for _ in range(n):
        x, y = int(rng.integers(0, P)), int(rng.integers(0, P))
        roll, acc = rng.random(), 0.0
        for (pr, cols) in colours:
            acc += pr
            if roll <= acc:
                for (dx, dy), c in zip(offsets, cols):
                    if c:
                        rgb[(y + dy) % P, (x + dx) % P] = hexc(c)
                break


def save_rgb(a, path):
    Image.fromarray((np.clip(a, 0, 1) * 255 + 0.5).astype(np.uint8), 'RGB').save(path, optimize=True)


def save_rgba(a, path):
    a = np.clip(a, 0, 1)
    a[..., :3] *= (a[..., 3:] > 0)
    Image.fromarray((a * 255 + 0.5).astype(np.uint8), 'RGBA').save(path, optimize=True)


# --- the dual-grid field ------------------------------------------------------------------
def _bilinear():
    """For each of the 16 corner combinations, a smooth 0..1 field over a padded tile."""
    t = (np.arange(TS) - PAD + 0.5) / CELL
    v, u = np.meshgrid(t, t, indexing='ij')
    out = []
    for m in range(16):
        tl, tr, bl, br = m & 1, (m >> 1) & 1, (m >> 2) & 1, (m >> 3) & 1
        out.append((tl * (1 - u) * (1 - v) + tr * u * (1 - v) + bl * (1 - u) * v + br * u * v).astype(np.float32))
    return out


BIL = _bilinear()


def window(arr, ox, oy):
    """Cut the padded tile whose top-left is at (ox, oy) out of a seamless texture."""
    ys = (oy - PAD + np.arange(TS)) % P
    xs = (ox - PAD + np.arange(TS)) % P
    return arr[np.ix_(ys, xs)]


def make_overlay(path, wobble, style):
    """Render all 64 x 15 border tiles of one overlay terrain.

    `style(F, W, ox, oy)` gets the field F (above EDGE means "inside") and a function W that
    cuts this tile's window out of any seamless texture; it returns (rgb, alpha) for the
    padded tile.
    """
    atlas = np.zeros((16 * CELL, PERIOD * PERIOD * CELL, 4), np.float32)
    for pj in range(PERIOD):
        for pi in range(PERIOD):
            ox, oy = pi * CELL - CELL // 2, pj * CELL - CELL // 2

            def W(a, ox=ox, oy=oy):
                return window(a, ox, oy)

            n = AMP * W(wobble)
            col = pi + PERIOD * pj
            for m in range(1, 16):
                rgb, a = style(BIL[m] + n, W, ox, oy)
                tile = np.dstack([rgb, a])[PAD:PAD + CELL, PAD:PAD + CELL]
                atlas[m * CELL:(m + 1) * CELL, col * CELL:(col + 1) * CELL] = tile
    save_rgba(atlas, path)


def flat_style(tex, grit, edge_colour=None, lit=None, dark=None):
    """An overlay that is one texture with a gritty border, an optional dark edge line and optional relief."""
    def style(F, W, ox, oy):
        inside = F + W(grit) > EDGE
        rgb = W(tex).copy()
        if edge_colour:
            rgb[inside & ~shrink1(inside)] = hexc(edge_colour)
        if lit:
            relief(rgb, inside, lit, dark)
        return rgb, inside.astype(np.float32)
    return style


def ore_rock(path, seed, rock_colours, lit, dark, desat_k=1.0):
    """The Orichalcum rock formation: cracked rock studded with small ore crystals, after
    outcrop() in mockups/src/v4_compose.py. The crystals thin out away from the texture's
    origin, where the middle of a formation is meant to sit."""
    rng = np.random.default_rng(seed)
    wobble = make_wobble(rng)
    grit = speck(rng, 0.14)
    f1, f2, value = tvoronoi(20, rng)
    rock = ramp(np.clip(0.5 + (value - 0.5) * 0.55 + speck(rng, 0.5), 0, 0.999), rock_colours)
    rock[(f2 - f1) < 0.9] = hexc(dark)
    rock = desat(rock, desat_k)
    yy, xx = np.mgrid[0:P, 0:P].astype(np.float32)
    far = np.hypot(np.minimum(xx, P - xx) / 1.45, np.minimum(yy, P - yy))    # distance from the origin, wrapping
    vein = (f2 - f1) < 1.6
    ore = pal(ORE[0])
    for k, (cell, rmin, rmax, prob, reach) in enumerate(((5, 0.9, 1.7, 0.5, 58), (7, 1.6, 2.6, 0.75, 46),
                                                         (13, 2.8, 4.2, 0.8, 31))):
        pts = [p for p in stamp_points(rng, cell, rmin, rmax, prob, 1)
               if far[p[0], p[1]] < reach and (k > 0 or vein[p[0], p[1]])]
        sh = np.zeros((P, P), np.float32)
        for (y, x, r, _) in pts:
            draw_shadow(sh, x, y, r)
        rock *= (1 - 0.3 * sh)[..., None]
        for (y, x, r, _) in pts:
            draw_stamp(rock, x, y, r, ore, rng, 0.25, 'crystal', 0.3)

    def style(F, W, ox, oy):
        inside = F + W(grit) > EDGE
        rgb = W(rock).copy()
        relief(rgb, inside, lit, dark)
        shade = np.roll(np.roll(inside, 2, 0), 2, 1) & ~inside       # a short shadow to the south-east
        rgb[shade] = 0
        return rgb, np.where(inside, 1.0, np.where(shade, 0.4, 0.0)).astype(np.float32)

    make_overlay(path, wobble, style)
    report('ore_rock', rock)


def make_wobble(rng):
    n = fbm(10, rng, 2)
    n = n - n.mean()
    return n / np.abs(n).max()


def report(name, tex, alpha=None):
    c = tex.reshape(-1, 3).mean(0) if alpha is None else tex[alpha > 0.5].mean(0)
    print('  %-8s average colour Color(%.3f, %.3f, %.3f)' % (name, c[0], c[1], c[2]))


# --- forest biome -------------------------------------------------------------------------
def forest_biome():
    out = os.path.join(OUT, 'forest')
    os.makedirs(out, exist_ok=True)
    rng = np.random.default_rng(1104)
    wobble = make_wobble(rng)
    grit = speck(rng, 0.14)

    # grass (ground)
    grass = ramp(np.clip(0.5 + (fbm(2, rng) - 0.5) * 0.7 + speck(rng, 0.6), 0, 0.999), GRASS)
    marks(grass, rng, 460, [(0, 0), (1, -1)], [(0.45, ['#718648', '#718648']), (0.55, ['#2e3d1f', '#2e3d1f'])])
    save_rgb(grass, os.path.join(out, 'grass.png'))
    report('grass', grass)

    # dirt
    dirt = ramp(np.clip(0.5 + (fbm(5, rng) - 0.5) * 0.7 + speck(rng, 0.55), 0, 0.999), DIRT)
    marks(dirt, rng, 110, [(0, 0), (0, 1)], [(1.0, ['#a08a62', '#43361f'])])
    make_overlay(os.path.join(out, 'dirt.png'), wobble, flat_style(dirt, grit, edge_colour='#43361f'))
    report('dirt', dirt)

    # stone
    stone = ramp(np.clip(0.5 + (fbm(8, rng) - 0.5) * 0.6 + speck(rng, 0.75), 0, 0.999), STONE)
    stamps(stone, rng, 9, 1.2, 3.0, PEBBLE_F, 0.6, 0.35, 0.5)
    make_overlay(os.path.join(out, 'stone.png'), wobble, flat_style(stone, grit, lit='#8f897b', dark='#26231f'))
    report('stone', stone)

    # water, with a narrow bank around it
    water = ramp(np.clip(0.45 + (fbm(8, rng, 2) - 0.5) * 0.6 + speck(rng, 0.4), 0, 0.999), WATER)
    bank = ramp(np.clip(0.5 + speck(rng, 0.9), 0, 0.999), BANK)

    def water_style(F, W, ox, oy):
        wet = F > EDGE + 0.09
        shore = (F > EDGE) & ~wet
        rgb = W(water).copy()
        rgb[wet & ~shrink1(wet)] = hexc('#1a3444')
        rgb[shore] = W(bank)[shore]
        return rgb, (wet | shore).astype(np.float32)

    make_overlay(os.path.join(out, 'water.png'), wobble, water_style)
    report('water', water)

    # forest: a dark floor covered in tree tops, each about a third of a cell across
    floor = ramp(np.clip(0.5 + speck(rng, 1.0), 0, 0.999), FLOOR)
    pts = stamp_points(rng, 7, 3.4, 5.6, 0.95, len(CROWNS))
    sh = np.zeros((P, P), np.float32)
    sh_owner = np.full((P, P), -1, np.int32)
    for k, (y, x, r, _) in enumerate(pts):
        draw_shadow(sh, x, y, r, sh_owner, k)
    floor = floor * (1 - 0.5 * sh)[..., None]
    canopy = floor.copy()
    owner = np.full((P, P), -1, np.int32)
    pp = [pal(c) for c in CROWNS]
    for k, (y, x, r, c) in enumerate(pts):
        draw_stamp(canopy, x, y, r, pp[c], rng, owner=owner, oid=k)
    tree_y = np.array([p[0] for p in pts])
    tree_x = np.array([p[1] for p in pts])

    def forest_style(F, W, ox, oy):
        # A tree belongs to the forest if its centre is inside, so tree tops are never cut in half.
        ly = (tree_y - oy + PAD) % P
        lx = (tree_x - ox + PAD) % P
        near = (ly < TS) & (lx < TS)
        keep = np.zeros(len(pts) + 1, bool)                     # last slot stands for "no tree"
        keep[:-1][near] = F[ly[near], lx[near]] > 0.5
        tree = keep[W(owner)]
        ground = (F > 0.6) & ~tree
        shade = keep[W(sh_owner)] & ~tree & ~ground
        rgb = np.where(tree[..., None], W(canopy), W(floor))
        rgb[shade] = 0
        alpha = np.where(tree | ground, 1.0, np.where(shade, 0.5, 0.0)).astype(np.float32)
        return rgb, alpha

    make_overlay(os.path.join(out, 'forest.png'), wobble, forest_style)
    report('forest', canopy)

    # decor: shrubs and lone trees for open grass
    props = [(SHRUB[0], 2.0, 3.2, 0.3)] * 5 + [(CROWNS[0], 3.6, 5.2, 0.4), (CROWNS[1], 3.6, 5.2, 0.4),
                                                (CROWNS[3], 3.6, 5.2, 0.4)]
    make_decor(os.path.join(out, 'decor.png'), rng, props)

    ore_rock(os.path.join(out, 'ore_rock.png'), 3104, ORE_ROCK_F, '#8c8272', '#1f1b17')


# --- desert biome -------------------------------------------------------------------------
def desert_biome():
    out = os.path.join(OUT, 'desert')
    os.makedirs(out, exist_ok=True)
    rng = np.random.default_rng(2311)
    wobble = make_wobble(rng)
    grit = speck(rng, 0.14)

    # sand (ground)
    big = (fbm(2, rng, 2) - 0.5) * 2
    sand = ramp(np.clip(0.5 + big * 0.3 + (fbm(6, rng, 2) - 0.5) * 0.25 + speck(rng, 0.4), 0, 0.999), SAND)
    marks(sand, rng, 26, [(0, 0), (-1, -1), (1, -1)], [(1.0, ['#8a6a34'] * 3)])
    marks(sand, rng, 26, [(0, 0), (1, 0), (0, 1)],
          [(0.6, ['#7a5a3c', '#7a5a3c', '#6a4a2c']), (0.4, ['#ecd0a0', '#ecd0a0', '#6a4a2c'])])
    sand = desat(sand, DESERT_DESAT)
    save_rgb(sand, os.path.join(out, 'sand.png'))
    report('sand', sand)

    # dunes: wind ripples. The dark bands reach further out than the light ones, so the patch ends in stripes.
    yy, xx = np.mgrid[0:P, 0:P].astype(np.float32)
    warp = (fbm(3, rng, 2) - 0.5) * 9.0
    rip = np.sin(2 * math.pi * (18 * yy + 5 * xx) / P + warp)
    band = np.sign(rip) * np.minimum(np.abs(rip) * 3, 1)
    dunes = desat(ramp(np.clip(0.5 + 0.3 * band + speck(rng, 0.3), 0, 0.999), DUNE), DESERT_DESAT)

    def dune_style(F, W, ox, oy):
        inside = F - 0.10 * W(band) + W(grit) * 0.5 > EDGE + 0.06
        return W(dunes), inside.astype(np.float32)

    make_overlay(os.path.join(out, 'dunes.png'), wobble, dune_style)
    report('dunes', dunes)

    # hardpan: pale cracked ground
    f1, f2, _ = tvoronoi(16, rng)
    hard = ramp(np.clip(0.5 + (fbm(5, rng) - 0.5) * 0.9 + speck(rng, 0.35), 0, 0.999), HARD)
    hard[(f2 - f1) < 0.8] = hexc('#a07c58')
    hard = desat(hard, DESERT_DESAT)
    make_overlay(os.path.join(out, 'hardpan.png'), wobble, flat_style(hard, grit, edge_colour='#96785a'))
    report('hardpan', hard)

    # rock: the only ground that can carry buildings
    g1, g2, _ = tvoronoi(7, rng)
    rock = ramp(np.clip(0.5 + (fbm(6, rng) - 0.5) * 0.8 + speck(rng, 0.62), 0, 0.999), ROCK)
    rock[(g2 - g1) < 0.7] = hexc('#3c3229')
    stamps(rock, rng, 11, 1.2, 3.4, PEBBLE_D, 0.6, 0.35, 0.5)
    rock = desat(rock, DESERT_DESAT)
    make_overlay(os.path.join(out, 'rock.png'), wobble, flat_style(rock, grit, lit='#a8937a', dark='#2b221b'))
    report('rock', rock)

    # decor: dry tufts and loose stones for open sand
    props = [(TUFT[0], 1.8, 3.0, 0.25, 1.4)] * 4 + [(PEBBLE_D[0], 1.2, 2.4, 0.3, 0.4)] * 4
    make_decor(os.path.join(out, 'decor.png'), rng, props, DESERT_DESAT)

    ore_rock(os.path.join(out, 'ore_rock.png'), 3123, ORE_ROCK_D, '#a88e74', '#241a14', DESERT_DESAT)


# --- shroud -------------------------------------------------------------------------------
def shroud():
    """The black cover over unexplored ground. Same border-tile layout as an overlay terrain;
    the edge breaks up into scattered pixels instead of ending in a hard line."""
    rng = np.random.default_rng(77)
    wobble = make_wobble(rng)
    dither = rng.random((P, P)).astype(np.float32)
    black = np.zeros((P, P, 3), np.float32) + hexc('#070807')
    lo, hi = EDGE - 0.07, EDGE + 0.13

    def style(F, W, ox, oy):
        cover = np.clip((F - lo) / (hi - lo), 0, 1)
        return W(black), (cover > W(dither)).astype(np.float32)

    make_overlay(os.path.join(OUT, 'shroud.png'), wobble, style)


def make_decor(path, rng, props, desat_k=1.0):
    """One row of small props on a transparent background, each at a random spot inside its tile."""
    atlas = np.zeros((CELL, CELL * len(props), 4), np.float32)
    for i, prop in enumerate(props):
        colours, rmin, rmax, shadow = prop[:4]
        rough = prop[4] if len(prop) > 4 else 0.9
        rgb = np.zeros((CELL, CELL, 3), np.float32)
        alpha = np.zeros((CELL, CELL), np.float32)
        sh = np.zeros((CELL, CELL), np.float32)
        x, y = int(rng.integers(9, CELL - 10)), int(rng.integers(9, CELL - 10))
        r = float(rng.uniform(rmin, rmax))
        draw_shadow(sh, x, y, r)
        draw_stamp(rgb, x, y, r, pal(colours), rng, rough, alpha=alpha)
        rgb = desat(rgb, desat_k)
        a = np.where(alpha > 0, 1.0, sh * shadow)
        atlas[:, i * CELL:(i + 1) * CELL] = np.dstack([rgb, a])
    save_rgba(atlas, path)


if __name__ == '__main__':
    which = sys.argv[1:] or ['forest', 'desert', 'shroud']
    if 'forest' in which:
        print('forest')
        forest_biome()
    if 'desert' in which:
        print('desert')
        desert_biome()
    if 'shroud' in which:
        print('shroud')
        shroud()
    print('wrote', OUT)
