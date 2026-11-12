#!/usr/bin/env python3
"""Turn the raw Blender renders into the unit sprite sheets for Balance.

Run from the repo root, after tools/render_units.py:  python tools/make_units.py [raw_dir]

Reads <raw_dir>/<unit>_p<pose>_<dir>.png and ..._sh.png (default raw_dir: tools/_raw) and
writes assets/sprites/units/<unit>.png: 8 columns (facing 0 south, 2 west, 4 north, 6 east)
by 3 rows (standing, then the two halves of a walking step), 24x24 pixels per sprite, with
the unit's feet at pixel (12, 18) of each sprite.

The treatment is the approved one from the style mockups (v5 and v7): shrink the render,
cut it down to a few colours, add per-pixel grit like the terrain, then give the sprite a
soft dark rim and a tight contact shadow so it sits on the ground.
"""
import os
import sys

import numpy as np
from PIL import Image

SS = 4                      # the raw renders are this many times larger than the sprite
SIZE = 24                   # sprite size in pixels
ANCHOR = (12, 18)           # where the feet are inside a sprite
DIRS, POSES = 8, 3
COLOURS = 20
SATURATION = 0.95
GRIT = 0.14
RIM = (0x15 / 255, 0x11 / 255, 0x0d / 255)
RIM_ALPHA = 0.42

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
RAW = sys.argv[1] if len(sys.argv) > 1 else os.path.join(ROOT, 'tools', '_raw')
OUT = os.path.join(ROOT, 'assets', 'sprites', 'units')
UNITS = ['infantry_blue', 'infantry_red']


def load(name):
    return np.asarray(Image.open(os.path.join(RAW, name)).convert('RGBA')).astype(np.float32) / 255


def shrink(a):
    n = a.shape[0] // SS
    return a.reshape(n, SS, n, SS, -1).mean((1, 3))


def sprite(unit, pose, k, rng):
    """One finished sprite as an RGBA array of SIZE x SIZE."""
    raw = load('%s_p%d_%02d.png' % (unit, pose, k))
    far = shrink(load('%s_p%d_%02d_sh.png' % (unit, pose, k))[..., 3:])[..., 0]
    cover = shrink(raw[..., 3:])
    col = shrink(raw[..., :3] * raw[..., 3:]) / np.maximum(cover, 1e-4)
    solid = cover[..., 0] > 0.42
    grey = col.mean(-1, keepdims=True)
    col = np.clip(grey + (col - grey) * SATURATION, 0, 1)
    # a limited palette gives the hand-pixelled look
    fill = col[solid].mean(0) if solid.any() else np.zeros(3)
    im = Image.fromarray((np.where(solid[..., None], col, fill) * 255).astype(np.uint8))
    im = im.quantize(colors=COLOURS, method=Image.Quantize.MEDIANCUT, dither=Image.Dither.NONE).convert('RGB')
    col = np.asarray(im).astype(np.float32) / 255
    col = np.clip(col * (1 + (rng.random(solid.shape).astype(np.float32) - 0.5)[..., None] * GRIT), 0, 1)
    # soft dark rim: one pixel around the body, half transparent so it blends into the ground
    edge = np.zeros_like(solid)
    for dy, dx in ((0, 1), (0, -1), (1, 0), (-1, 0)):
        edge |= np.roll(solid, (dy, dx), (0, 1))
    edge &= ~solid
    col[edge] = RIM
    alpha = solid.astype(np.float32) + RIM_ALPHA * edge
    # tight contact shadow hugging the lower-right edge, plus a faint trace of the cast shadow
    contact = np.maximum(np.roll(solid, (1, 1), (0, 1)), 0.55 * np.roll(solid, (2, 2), (0, 1))).astype(np.float32)
    shadow = np.maximum(contact * 0.85, far * 0.22) * 0.4
    # shadow underneath, sprite on top
    out_a = alpha + shadow * (1 - alpha)
    out_rgb = col * (alpha / np.maximum(out_a, 1e-4))[..., None]
    rgba = np.dstack([out_rgb, out_a])
    c = solid.shape[0] // 2                 # the render is centred on the unit's feet
    x0, y0 = c - ANCHOR[0], c - ANCHOR[1]
    window = rgba[y0:y0 + SIZE, x0:x0 + SIZE]
    inside = np.zeros_like(solid)
    inside[y0:y0 + SIZE, x0:x0 + SIZE] = True
    if (solid & ~inside).any():
        print('  warning: %s pose %d dir %d does not fit the %dx%d sprite' % (unit, pose, k, SIZE, SIZE))
    return window


def main():
    os.makedirs(OUT, exist_ok=True)
    for unit in UNITS:
        rng = np.random.default_rng(5)
        sheet = np.zeros((POSES * SIZE, DIRS * SIZE, 4), np.float32)
        for pose in range(POSES):
            for k in range(DIRS):
                sheet[pose * SIZE:(pose + 1) * SIZE, k * SIZE:(k + 1) * SIZE] = sprite(unit, pose, k, rng)
        sheet[..., :3] *= (sheet[..., 3:] > 0)
        path = os.path.join(OUT, unit + '.png')
        Image.fromarray((np.clip(sheet, 0, 1) * 255 + 0.5).astype(np.uint8), 'RGBA').save(path, optimize=True)
        print('wrote', path)


if __name__ == '__main__':
    main()
