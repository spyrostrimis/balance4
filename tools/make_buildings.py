#!/usr/bin/env python3
"""Turn the raw Blender renders into the building pictures for Balance.

Run from the repo root, after tools/render_units.py:  python tools/make_buildings.py [raw_dir] [building ...]

With building names after the folder only those pictures are made; otherwise every building
whose raw render is in the folder.

Reads <raw_dir>/<building>_p0_00.png and ..._sh.png (default raw_dir: tools/_raw) and writes
assets/sprites/buildings/<building>.png: the building on its foundation, with a margin of
8 pixels around the cells it covers. The top-left corner of those cells is at pixel (8, 8).

Buildings get the same treatment as units (see tools/make_units.py). Under the building goes
a foundation of small concrete plates, flush with the ground, as in the approved mockups (v6
and v7): each plate has a lit north-west and a dark south-east edge.
"""
import os
import sys

import numpy as np
from PIL import Image

import make_units
from make_units import RAW, ROOT, treat

CELL = 32
MARGIN = 8
PLATE = 16                  # size of one foundation plate in pixels
SLAB = ['#555950', '#61655a', '#6d7165', '#797d70']
SLAB_LIT, SLAB_DARK = '#8d9184', '#3a3d36'
OUT = os.path.join(ROOT, 'assets', 'sprites', 'buildings')
# building -> the cells it covers (across, down)
SIZES = {'refinery': (3, 2), 'headquarters': (2, 2), 'generator': (2, 2), 'barracks': (2, 2), 'workshop': (3, 2)}
BUILDINGS = {'%s_%s' % (kind, team): size for kind, size in SIZES.items() for team in ('blue', 'red')}


def hexc(s):
    s = s.lstrip('#')
    return np.array([int(s[i:i + 2], 16) for i in (0, 2, 4)], np.float32) / 255


def foundation(w, h, rng):
    """Concrete plates over w x h pixels, as an RGB array."""
    shades = np.stack([hexc(c) for c in SLAB])
    v = np.clip(0.5 + (rng.random((h, w)).astype(np.float32) - 0.5) * 0.8, 0, 0.999)
    rgb = shades[(v * len(shades)).astype(np.int32)]
    yy, xx = np.mgrid[0:h, 0:w]
    rgb[(yy % PLATE == 0) | (xx % PLATE == 0)] = hexc(SLAB_LIT)
    rgb[(yy % PLATE == PLATE - 1) | (xx % PLATE == PLATE - 1)] = hexc(SLAB_DARK)
    return rgb


def picture(name, cells, rng):
    w, h = cells[0] * CELL, cells[1] * CELL
    out = np.zeros((h + 2 * MARGIN, w + 2 * MARGIN, 4), np.float32)
    # the foundation, with a short shadow to the south-east
    out[MARGIN + 2:MARGIN + h + 2, MARGIN + 2:MARGIN + w + 2, 3] = 0.4
    out[MARGIN:MARGIN + h, MARGIN:MARGIN + w, :3] = foundation(w, h, rng)
    out[MARGIN:MARGIN + h, MARGIN:MARGIN + w, 3] = 1
    # the building on top; the render is centred on the middle of the footprint
    rgba, solid = treat(name + '_p0_00', rng)
    c = solid.shape[0] // 2
    x0, y0 = c - out.shape[1] // 2, c - out.shape[0] // 2
    window = rgba[y0:y0 + out.shape[0], x0:x0 + out.shape[1]]
    inside = np.zeros_like(solid)
    inside[y0:y0 + out.shape[0], x0:x0 + out.shape[1]] = True
    if (solid & ~inside).any():
        print('  warning: %s does not fit its picture' % name)
    a = window[..., 3:]
    out[..., :3] = window[..., :3] + out[..., :3] * out[..., 3:] * (1 - a)
    out[..., 3:] = a + out[..., 3:] * (1 - a)
    out[..., :3] /= np.maximum(out[..., 3:], 1e-4)
    return out


def main():
    os.makedirs(OUT, exist_ok=True)
    for name in sys.argv[2:] or BUILDINGS:
        if name not in BUILDINGS:
            print('skipped %s: not a building' % name)
            continue
        if not os.path.exists(os.path.join(RAW, '%s_p0_00.png' % name)):
            print('skipped %s: no raw render in %s' % (name, RAW))
            continue
        out = picture(name, BUILDINGS[name], np.random.default_rng(9))
        out[..., :3] *= (out[..., 3:] > 0)
        path = os.path.join(OUT, name + '.png')
        Image.fromarray((np.clip(out, 0, 1) * 255 + 0.5).astype(np.uint8), 'RGBA').save(path, optimize=True)
        print('wrote', path)


if __name__ == '__main__':
    make_units.COLOURS = 56      # a building is larger than a unit and has more materials
    main()
