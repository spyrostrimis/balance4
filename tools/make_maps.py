#!/usr/bin/env python3
"""Generate the two maps for Balance as Godot resources.

Run from the repo root:  python tools/make_maps.py

Writes data/maps/forest_01.tres and data/maps/desert_01.tres. Each map is a grid of
one-character terrain symbols (see the terrain files in data/terrain/ for the symbols).
The layouts follow the style mockups: a central clearing with the Orichalcum rock formation
in the middle of it, two tracks leading to opposite corners, rock patches for future bases.
Each map also lists two start positions, one at the end of each track, and the control point
(the middle of the rock formation).

Trees, water and the Orichalcum rock cannot be crossed. The script checks that both start
positions can reach the control area and each other on foot, and stops if they cannot.

The maps are generated from fixed seeds, so the output is the same on every run. They can
also be edited by hand afterwards: the rows in the .tres file are plain text.
"""
import math
import os

import numpy as np
from PIL import Image

W, H = 64, 48
ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
OUT = os.path.join(ROOT, 'data', 'maps')


def fbm(rng, scale, octaves=3):
    """Smooth noise over the map, 0..1; `scale` is the feature size in cells."""
    out = np.zeros((H, W), np.float32)
    amp, tot = 1.0, 0.0
    for o in range(octaves):
        s = max(1.0, scale / 2 ** o)
        gh, gw = int(H / s) + 4, int(W / s) + 4
        g = Image.fromarray(rng.random((gh, gw)).astype(np.float32))
        a = np.asarray(g.resize((int(gw * s), int(gh * s)), Image.BICUBIC))
        out += a[int(s):int(s) + H, int(s):int(s) + W] * amp
        tot += amp
        amp *= 0.5
    return out / tot


def polydist(xx, yy, pts, step=0.25):
    d = np.full(xx.shape, 1e12, np.float32)
    for (a, b) in zip(pts, pts[1:]):
        n = max(2, int(math.hypot(b[0] - a[0], b[1] - a[1]) / step))
        for t in np.linspace(0, 1, n):
            d = np.minimum(d, (xx - (a[0] + (b[0] - a[0]) * t)) ** 2 + (yy - (a[1] + (b[1] - a[1]) * t)) ** 2)
    return np.sqrt(d)


def blob(X, Y, cx, cy, rx, ry):
    """Distance-like value: below 0 inside an ellipse centred on (cx, cy)."""
    return np.hypot((X - cx) / rx, (Y - cy) / ry) - 1.0


def tidy(mask, rounds=2):
    """Drop cells that stick out on their own and fill one-cell holes, so borders draw cleanly."""
    m = mask.copy()
    for _ in range(rounds):
        p = np.pad(m, 1, mode='edge').astype(np.int32)
        n4 = p[:-2, 1:-1] + p[2:, 1:-1] + p[1:-1, :-2] + p[1:-1, 2:]
        m = np.where(m, n4 >= 2, n4 >= 4)
    return m


def drop_small(mask, min_cells):
    """Remove connected patches smaller than min_cells."""
    m = mask.copy()
    seen = np.zeros_like(m)
    for y0 in range(H):
        for x0 in range(W):
            if not m[y0, x0] or seen[y0, x0]:
                continue
            patch, stack = [], [(y0, x0)]
            seen[y0, x0] = True
            while stack:
                y, x = stack.pop()
                patch.append((y, x))
                for (ny, nx) in ((y - 1, x), (y + 1, x), (y, x - 1), (y, x + 1)):
                    if 0 <= ny < H and 0 <= nx < W and m[ny, nx] and not seen[ny, nx]:
                        seen[ny, nx] = True
                        stack.append((ny, nx))
            if len(patch) < min_cells:
                for (y, x) in patch:
                    m[y, x] = False
    return m


# The middle of the map, where the Orichalcum rock stands. It is a grid corner whose cell
# coordinates are multiples of 8, which is where the rock's tile texture has its ore.
CENTRE = (W // 2, H // 2)
IMPASSABLE = 'fwo'


def ore_rock(rng):
    """The cells of the Orichalcum rock formation: a small lumpy patch around the map centre."""
    yy, xx = np.mgrid[0:H, 0:W].astype(np.float32)
    lumps = (fbm(rng, 4, 2) - 0.5) * 0.5
    return tidy(blob(xx + 0.5, yy + 0.5, CENTRE[0], CENTRE[1], 3.0, 2.0) + lumps < 0)


def check_reachable(name, grid, starts):
    """Stop if a start position cannot walk to the edge of the rock formation or to the other start."""
    open_ = ~np.isin(grid, list(IMPASSABLE))
    seen = np.zeros_like(open_)
    stack = [(starts[0][1], starts[0][0])]
    seen[stack[0]] = True
    while stack:
        y, x = stack.pop()
        for (ny, nx) in ((y - 1, x), (y + 1, x), (y, x - 1), (y, x + 1)):
            if 0 <= ny < H and 0 <= nx < W and open_[ny, nx] and not seen[ny, nx]:
                seen[ny, nx] = True
                stack.append((ny, nx))
    for (x, y) in starts:
        if not seen[y, x]:
            raise SystemExit('%s: start (%d, %d) is cut off from the other start' % (name, x, y))
    ore = grid == 'o'
    beside = np.zeros_like(ore)
    beside[1:] |= ore[:-1]
    beside[:-1] |= ore[1:]
    beside[:, 1:] |= ore[:, :-1]
    beside[:, :-1] |= ore[:, 1:]
    if not (beside & seen).any():
        raise SystemExit('%s: the rock formation cannot be reached from the starts' % name)
    cut_off = int((open_ & ~seen).sum())
    print('%s: starts and rock are connected; %d walkable cells are cut off from them' % (name, cut_off))


def coords(rng, warp=3.0):
    yy, xx = np.mgrid[0:H, 0:W].astype(np.float32)
    xx += 0.5
    yy += 0.5
    return xx + (fbm(rng, 10) - 0.5) * warp * 2, yy + (fbm(rng, 10) - 0.5) * warp * 2, xx, yy


def forest_map():
    rng = np.random.default_rng(11)
    X, Y, xx, yy = coords(rng)
    cx, cy = W / 2, H / 2
    sw, ne = (10, 38), (54, 10)

    clearing = blob(X, Y, cx, cy, 6.0, 4.6)
    track = np.minimum(polydist(X, Y, [(cx - 4, cy + 3), (22, 31), (16, 33), sw]),
                       polydist(X, Y, [(cx + 4, cy - 3), (42, 18), (48, 15), ne])) - 1.3
    camps = np.minimum(blob(X, Y, sw[0], sw[1], 3.6, 3.0), blob(X, Y, ne[0], ne[1], 3.6, 3.0))
    dirt = tidy((clearing < 0) | (track < 0) | (camps < 0))

    stone_d = np.minimum.reduce([
        blob(X, Y, 6, 43, 4.2, 3.2), blob(X, Y, 58, 5, 4.2, 3.2),          # by each start
        blob(X, Y, 18, 22, 3.0, 2.4), blob(X, Y, 46, 27, 3.0, 2.4),        # flanking the centre
        blob(X, Y, 50, 40, 3.6, 2.6), blob(X, Y, 37, 6, 3.4, 2.6)])
    stone = tidy(stone_d < 0) & ~dirt

    river_d = np.minimum(polydist(X, Y, [(24, -2), (22, 4), (17, 8), (11, 10), (5, 15), (-3, 17)]),
                         polydist(X, Y, [(66, 32), (60, 34), (56, 39), (50, 44.5), (47, 50)])) - 1.2
    water = tidy(river_d < 0) & ~dirt & ~stone

    edge = 1 - np.minimum(np.minimum(xx, W - xx), np.minimum(yy, H - yy)) / 14
    fn = (fbm(rng, 11) - 0.5) * 2.4 + np.clip(edge, 0, 1) * 0.55
    near_open = np.minimum.reduce([clearing * 5.0, track, camps * 3.3, stone_d * 3.0, river_d])
    forest = drop_small(tidy((fn > 0.12) & (near_open > 1.6), 3) & ~dirt & ~stone & ~water, 6)

    grid = np.full((H, W), '.', '<U1')
    grid[dirt] = 'd'
    grid[stone] = 's'
    grid[water] = 'w'
    grid[forest] = 'f'
    grid[ore_rock(np.random.default_rng(111))] = 'o'
    return grid, [sw, ne]


def desert_map():
    rng = np.random.default_rng(23)
    X, Y, xx, yy = coords(rng)
    cx, cy = W / 2, H / 2
    nw, se = (10, 10), (54, 38)

    clearing = blob(X, Y, cx, cy, 6.0, 4.6)
    track = np.minimum(polydist(X, Y, [(cx - 4, cy - 3), (22, 17), (16, 13), nw]),
                       polydist(X, Y, [(cx + 4, cy + 3), (42, 31), (48, 35), se])) - 1.3
    camps = np.minimum(blob(X, Y, nw[0], nw[1], 3.6, 3.0), blob(X, Y, se[0], se[1], 3.6, 3.0))
    hard = tidy((clearing < 0) | (track < 0) | (camps < 0))

    rock_d = np.minimum.reduce([
        blob(X, Y, 5, 5, 4.6, 3.6), blob(X, Y, 59, 43, 4.6, 3.6),          # by each start
        blob(X, Y, 4, 42, 8.0, 6.0), blob(X, Y, 58, 4, 9.0, 6.0),          # big outcrops in the far corners
        blob(X, Y, 21, 30, 3.2, 2.4), blob(X, Y, 44, 16, 3.2, 2.4)])
    rock = tidy(rock_d + (fbm(rng, 6) - 0.5) * 0.5 < 0) & ~hard

    near_open = np.minimum.reduce([clearing * 5.0, track, camps * 3.3, rock_d * 3.5])
    dn = (fbm(rng, 12) - 0.5) * 2.4
    dunes = drop_small(tidy((dn > 0.16) & (near_open > 1.8), 3) & ~hard & ~rock, 14)

    grid = np.full((H, W), '.', '<U1')
    grid[dunes] = 'u'
    grid[hard] = 'h'
    grid[rock] = 'r'
    grid[ore_rock(np.random.default_rng(123))] = 'o'
    return grid, [nw, se]


def write_map(name, display_name, biome, grid, starts):
    check_reachable(name, grid, starts)
    rows = [''.join(r) for r in grid]
    body = ', '.join('"%s"' % r for r in rows)
    text = ('[gd_resource type="Resource" script_class="MapData" load_steps=3 format=3]\n\n'
            '[ext_resource type="Script" path="res://scripts/sim/map_data.gd" id="1"]\n'
            '[ext_resource type="Resource" path="res://data/biomes/%s.tres" id="2"]\n\n'
            '[resource]\n'
            'script = ExtResource("1")\n'
            'display_name = "%s"\n'
            'biome = ExtResource("2")\n'
            'starts = Array[Vector2i]([%s])\n'
            'control_point = Vector2(%d, %d)\n'
            'rows = PackedStringArray(%s)\n') % (biome, display_name,
                                                  ', '.join('Vector2i(%d, %d)' % s for s in starts),
                                                  CENTRE[0], CENTRE[1], body)
    os.makedirs(OUT, exist_ok=True)
    path = os.path.join(OUT, name + '.tres')
    with open(path, 'w', encoding='utf-8', newline='\n') as f:
        f.write(text)
    counts = {s: int((grid == s).sum()) for s in sorted(set(grid.ravel()))}
    print('wrote %s  %dx%d  %s' % (path, W, H, counts))
    for r in rows:
        print('  ' + r)


if __name__ == '__main__':
    write_map('forest_01', 'Forest', 'forest', *forest_map())
    write_map('desert_01', 'Desert', 'desert', *desert_map())
