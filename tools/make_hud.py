#!/usr/bin/env python3
"""Make the HUD art for Balance: the frame, the panels and buttons, the icons and the portraits.

Run from the repo root:  python tools/make_hud.py

The look is the approved HUD mockup (mockups/balance_v12_hud_d.png, made by
mockups/src/v12_hud.py): warm chestnut wood, gold rims, parchment, navy buttons, a top bar
from one side of the screen to the other, rounded corners. Everything is drawn at three
times the size and shrunk, with the same embossed-layer treatment as the mockups.

Writes to assets/ui/:
  hud_frame.png            the fixed frame (960x540): the top bar with its emblem and boxes,
                           the sidebar's wood and the minimap's frame. Transparent over the map.
  panel_<name>.png         nine-slice pieces for panels and buttons (StyleBoxTexture). Each is
                           PIECE pixels square with PAD transparent pixels around the rim, so a
                           stylebox uses texture margins of MARGIN and expand margins of PAD.
  icons/<name>.png         16x16 icons.
  portraits/<name>.png     PORTRAIT-sized portraits, from the Blender bust shots that
                           tools/render_units.py writes into tools/_raw (run it with
                           "portraits" first). Without a render an existing portrait is
                           kept; a missing one gets a painted placeholder.
"""
import math
import os

import numpy as np
from PIL import Image, ImageDraw, ImageFilter

ROOT = os.path.normpath(os.path.join(os.path.dirname(os.path.abspath(__file__)), '..'))
OUT = os.path.join(ROOT, 'assets', 'ui')

W, H = 960, 540
TOP = 28                    # top bar height, full width
SX = 752                    # sidebar left edge
MINIMAP = (760, 36, 952, 180)
CAPS = dict(plaque=(226, 4, 494, 24), ore=(508, 5, 670, 23), power=(678, 5, 812, 23), time=(820, 5, 952, 23))
EMBLEM = (2, 0, 40, 38)
PIECE, PAD, MARGIN = 192, 3, 16
PORTRAIT = (44, 54)

CHESTNUT = ['#24120c', '#3c1e14', '#56301f', '#6e402a', '#875236', '#9c6342']
CHESTNUT_LIGHT = ['#33190f', '#4c2819', '#673b25', '#7f4c31', '#985e3d', '#ad714a']
GOLD = ['#33230a', '#5e4314', '#8f6a22', '#bb9234', '#dcb75a', '#f4dc98']
GOLD_BRIGHT = ['#4a3410', '#7a5a1c', '#ad862c', '#d8ad44', '#f0cf70', '#fff0b8']
GOLD_DIM = ['#241a0c', '#3a2c16', '#56442a', '#6e5a3c', '#857050', '#9a8466']
PARCH = ['#a88a5a', '#c2a474', '#d8bf90', '#e8d4aa', '#f3e5c4']
PANEL = ['#0c0705', '#150d08', '#20140c', '#2c1c12', '#3a2718']
PANEL_LIGHT = ['#160e09', '#22160d', '#2f1f13', '#3d2a1a', '#4c3722']
NAVY = ['#10203f', '#1f3a70', '#2f5aa0', '#5482c6', '#a8c8ee']
NAVY_LIGHT = ['#18305a', '#2b4c8c', '#3d6cb8', '#6a98d8', '#c0dcf6']
NAVY_DARK = ['#0a1630', '#152a54', '#21447c', '#3a64a4', '#7ea4d8']
GREYWOOD = ['#1e1814', '#2a221c', '#382e26', '#463a30', '#54473b']
IVORY = ['#6b5a3c', '#a8946c', '#d8c69c', '#f4e8c4', '#fffbe8']
ORANGE = ['#6a2a04', '#b85a0c', '#f08a1c', '#ffbe44', '#fff0a0']


# --- noise, blur, palettes (as in the mockup scripts) ----------------------------------------------------------
def hexc(s):
    s = s.lstrip('#')
    return np.array([int(s[i:i + 2], 16) for i in (0, 2, 4)], np.float32) / 255


def ramp(v, cols):
    p = np.stack([hexc(c) for c in cols])
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


def P(S, *c):
    return [v * S for v in c]


def rr(d, S, box, r, pad=0.0, fill=255):
    d.rounded_rectangle(P(S, box[0] - pad, box[1] - pad, box[2] + pad, box[3] + pad), max(0.5, r) * S, fill=fill)


class Layers:
    """Embossed layers drawn at S times the size: each mask is filled from a palette by its slope."""

    def __init__(self, w, h, S=3):
        self.w, self.h, self.S = w, h, S
        self.rgb = np.zeros((h * S, w * S, 3), np.float32)
        self.a = np.zeros((h * S, w * S), np.float32)

    def mask(self, fn):
        im = Image.new('L', (self.w * self.S, self.h * self.S), 0)
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
        col = ramp(shade, palette)
        self.rgb = self.rgb * (1 - m[..., None]) + col * m[..., None]
        self.a = np.maximum(self.a, m)

    def image(self):
        S, h, w = self.S, self.h, self.w
        a = self.a.reshape(h, S, w, S).mean((1, 3))
        rgb = (self.rgb * self.a[..., None]).reshape(h, S, w, S, 3).mean((1, 3)) / np.maximum(a, 1e-4)[..., None]
        out = np.concatenate([np.clip(rgb, 0, 1), np.clip(a, 0, 1)[..., None]], -1)
        return Image.fromarray((out * 255).astype(np.uint8), 'RGBA')

    def textures(self, rng):
        hs, ws, S = self.h * self.S, self.w * self.S, self.S
        grain = (fbm(hs, ws, 9 * S, rng, 3, (9, 0.5)) - 0.5) * 0.45 + (fbm(hs, ws, 60 * S, rng, 2) - 0.5) * 0.25
        shine = (fbm(hs, ws, 30 * S, rng, 2, (1.5, 0.6)) - 0.5) * 0.2
        paper = (fbm(hs, ws, 40 * S, rng, 3) - 0.5) * 0.5 + 0.1
        return grain, shine, paper


# --- icons -------------------------------------------------------------------------------------------------------
ICONS = {
    'swords': [('line', (4, 12, 13, 3), 2.0), ('line', (12, 12, 3, 3), 2.0), ('line', (2.5, 9.5, 6.5, 13.5), 1.6),
               ('line', (13.5, 9.5, 9.5, 13.5), 1.6)],
    'stop': [('rect', (3.5, 3.5, 12.5, 12.5))],
    'pulse': [('ring', (8, 8), 6.6, 5.2), ('rect', (6.9, 4, 9.1, 12)), ('rect', (4, 6.9, 12, 9.1))],
    'heal': [('rect', (6.3, 2.5, 9.7, 13.5)), ('rect', (2.5, 6.3, 13.5, 9.7))],
    'hammer': [('line', (3.5, 13, 10, 6.5), 2.2), ('poly', (7.5, 2.5, 13.5, 8.5, 11.5, 10.5, 5.5, 4.5))],
    'castle': [('poly', (2.5, 14, 2.5, 4, 5, 4, 5, 6.5, 7, 6.5, 7, 4, 9, 4, 9, 6.5, 11, 6.5, 11, 4, 13.5, 4, 13.5, 14))],
    'helm': [('chord', (3, 2.5, 13, 13.5), 180, 360), ('rect', (3, 8, 13, 9.6)), ('rect', (3, 9, 5.6, 13)),
             ('rect', (10.4, 9, 13, 13)), ('rect', (7.2, 8, 8.8, 12))],
    'wheel': [('ring', (8, 8), 6, 3.6), ('dot', (8, 8), 1.6), ('rect', (7.3, 2, 8.7, 14)), ('rect', (2, 7.3, 14, 8.7))],
    'cog': [('ring', (8, 8), 4.6, 2.6)] + [('dot', (8 + 5.6 * math.cos(i * math.pi / 4), 8 + 5.6 * math.sin(
        i * math.pi / 4)), 1.5) for i in range(8)],
    'scroll': [('rect', (3.5, 3, 12.5, 13)), ('dot', (3.5, 3.5), 1.6), ('dot', (12.5, 12.5), 1.6)],
    'glass': [('poly', (3.5, 2.5, 12.5, 2.5, 8, 8)), ('poly', (3.5, 13.5, 12.5, 13.5, 8, 8)),
              ('rect', (3, 2, 13, 3.2)), ('rect', (3, 12.8, 13, 14))],
    'gem': [('poly', (8, 1, 13.5, 5.5, 11, 14.5, 5, 14.5, 2.5, 5.5))],
    'bolt': [('poly', (9.5, 1.5, 3, 9, 7.5, 9, 6, 14.5, 13, 6.5, 8.5, 6.5))],
    'flag': [('line', (4, 2.5, 4, 14), 1.6), ('poly', (4.5, 3, 13.5, 6, 4.5, 9))],
    'scales': [('line', (8, 2.5, 8, 13), 1.4), ('line', (2.5, 5, 13.5, 5), 1.4), ('rect', (5, 12.6, 11, 14)),
               ('chord', (0.6, 5.5, 5.6, 10.5), 0, 180), ('chord', (10.4, 5.5, 15.4, 10.5), 0, 180), ('dot', (8, 3), 1.6)],
}
ICON_COLOURS = {'gem': ORANGE, 'bolt': ORANGE}


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


def make_icon(name):
    L = Layers(18, 18, 4)
    L.layer(L.mask(lambda d, S: draw_icon(d, S, name, 1, 1, 1.0)), ICON_COLOURS.get(name, IVORY), 1.0, 0.8, None,
            shadow=1)
    return L.image()


# --- the frame ---------------------------------------------------------------------------------------------------
def make_frame(rng):
    L = Layers(W, H)
    grain, shine, paper = L.textures(rng)

    def wood(d, S):
        d.rectangle(P(S, 0, 0, W, TOP), fill=255)
        d.rectangle(P(S, SX, 0, W, H), fill=255)
        # the map's inner corner, where the top bar meets the sidebar, is rounded
        d.rectangle(P(S, SX - 12, TOP, SX, TOP + 12), fill=255)
        d.ellipse(P(S, SX - 24, TOP, SX, TOP + 24), fill=0)
    L.layer(L.mask(wood), CHESTNUT, 2, 0.5, grain, shadow=4)

    def rails(d, S):
        d.rounded_rectangle(P(S, -10, TOP - 3, SX + 12, TOP + 1), 2 * S, fill=255)
        d.rounded_rectangle(P(S, SX - 3, TOP - 3, SX + 1, H + 10), 2 * S, fill=255)
        d.arc(P(S, SX - 25, TOP - 1, SX + 1, TOP + 25), 270, 360, fill=255, width=int(3.5 * S))
        d.ellipse(P(S, *EMBLEM), fill=255)
        for c in CAPS.values():
            rr(d, S, c, 6, 2)
        rr(d, S, MINIMAP, 7, 5)
    L.layer(L.mask(rails), GOLD, 1.8, 1.0, shine, shadow=2.5)

    def insets(d, S):
        for k in ('ore', 'power', 'time'):
            rr(d, S, CAPS[k], 5)
        rr(d, S, MINIMAP, 5)
    L.layer(L.mask(insets), PANEL, 2, -0.6, None)
    L.layer(L.mask(lambda d, S: rr(d, S, CAPS['plaque'], 5)), PARCH, 1.5, -0.3, paper)
    L.layer(L.mask(lambda d, S: d.ellipse(P(S, 6, 4, 36, 34), fill=255)), NAVY, 2.5, 0.8, None)
    L.layer(L.mask(lambda d, S: draw_icon(d, S, 'scales', 10.5, 8.5, 1.35)), IVORY, 1.0, 0.8, None, shadow=1)
    im = L.image()
    # the minimap's own picture goes over its inset; keep the inset fully opaque so nothing shows through
    return im


# --- nine-slice pieces ---------------------------------------------------------------------------------------------
def make_piece(rng, fill, rim=GOLD, radius=7, rim_px=3, center=True, wood_tex=False):
    n = PIECE
    L = Layers(n, n)
    grain, shine, paper = L.textures(rng)
    box = (PAD, PAD, n - PAD, n - PAD)
    L.layer(L.mask(lambda d, S: rr(d, S, box, radius)), rim, 1.8, 1.0, shine, shadow=0)
    inner = (PAD + rim_px, PAD + rim_px, n - PAD - rim_px, n - PAD - rim_px)
    if center:
        tex = grain if wood_tex else (paper if fill is PARCH else None)
        bevel, depth = (1.5, -0.3) if fill is PARCH else ((2, 0.5) if wood_tex else (2.2, 0.8 if fill in (
            NAVY, NAVY_LIGHT, NAVY_DARK) else -0.6))
        L.layer(L.mask(lambda d, S: rr(d, S, inner, radius - 2)), fill, bevel, depth, tex)
        return L.image()
    im = L.image()
    hole = Image.new('L', (n * 4, n * 4), 0)
    ImageDraw.Draw(hole).rounded_rectangle([v * 4 for v in inner], (radius - 2) * 4, fill=255)
    hole = hole.resize((n, n), Image.BOX)
    a = np.asarray(im).copy()
    a[..., 3] = (a[..., 3].astype(np.float32) * (1 - np.asarray(hole) / 255.0)).astype(np.uint8)
    return Image.fromarray(a, 'RGBA')


PIECES = {
    'parchment': dict(fill=PARCH),
    'inset': dict(fill=PANEL, radius=6, rim_px=2.5),
    'inset_hover': dict(fill=PANEL_LIGHT, rim=GOLD_BRIGHT, radius=6, rim_px=2.5),
    'inset_pressed': dict(fill=PANEL, rim=GOLD_DIM, radius=6, rim_px=2.5),
    'inset_disabled': dict(fill=PANEL, rim=GOLD_DIM, radius=6, rim_px=2.5),
    'navy': dict(fill=NAVY, radius=6, rim_px=2.5),
    'navy_hover': dict(fill=NAVY_LIGHT, rim=GOLD_BRIGHT, radius=6, rim_px=2.5),
    'navy_pressed': dict(fill=NAVY_DARK, rim=GOLD_DIM, radius=6, rim_px=2.5),
    'navy_disabled': dict(fill=GREYWOOD, rim=GOLD_DIM, radius=6, rim_px=2.5),
    'wood': dict(fill=CHESTNUT, radius=6, rim_px=2.5, wood_tex=True),
    'wood_hover': dict(fill=CHESTNUT_LIGHT, rim=GOLD_BRIGHT, radius=6, rim_px=2.5, wood_tex=True),
    'wood_panel': dict(fill=CHESTNUT, radius=9, rim_px=3, wood_tex=True),
    'cameo': dict(fill=None, radius=6, rim_px=3, center=False),
    'cameo_selected': dict(fill=None, rim=GOLD_BRIGHT, radius=6, rim_px=3, center=False),
}


# --- portraits: painted busts, placeholders until the art pass (M7.6) ------------------------------------------------
def bust(kind, w, h):
    k = 8
    im = Image.new('RGBA', (w * k, h * k))
    d = ImageDraw.Draw(im)
    W_, H_ = w * k, h * k
    top, bot = (hexc('#6f97c0'), hexc('#e8d4a4')) if kind != 'scout' else (hexc('#8a9a6a'), hexc('#e4d2a0'))
    for y in range(H_):
        t = y / H_
        d.line([(0, y), (W_, y)], fill=tuple(int(v * 255) for v in top * (1 - t) + bot * t))

    def X(v):
        return v * W_

    def Y(v):
        return v * H_

    def E(x0, y0, x1, y1, col):
        d.ellipse([X(x0), Y(y0), X(x1), Y(y1)], fill=col)

    def Pg(pts, col):
        d.polygon([(X(a), Y(b)) for a, b in pts], fill=col)

    skin, skin_d = '#d9a67a', '#a8744e'
    if kind == 'prince':
        Pg([(0.0, 1.0), (0.06, 0.78), (0.3, 0.68), (0.7, 0.68), (0.94, 0.78), (1.0, 1.0)], '#1f3a70')
        Pg([(0.3, 0.68), (0.5, 0.9), (0.7, 0.68)], '#c9b48a')
        Pg([(0.33, 0.69), (0.5, 0.86), (0.67, 0.69), (0.62, 0.68), (0.5, 0.78), (0.38, 0.68)], '#8a6a2a')
        E(0.18, 0.74, 0.3, 0.84, '#dcb75a')
        E(0.7, 0.74, 0.82, 0.84, '#dcb75a')
        Pg([(0.42, 0.58), (0.58, 0.58), (0.6, 0.7), (0.4, 0.7)], skin_d)
        E(0.3, 0.2, 0.7, 0.64, skin)
        Pg([(0.55, 0.22), (0.7, 0.32), (0.69, 0.5), (0.6, 0.62), (0.56, 0.62)], skin_d)
        Pg([(0.27, 0.36), (0.28, 0.2), (0.4, 0.12), (0.6, 0.12), (0.72, 0.2), (0.73, 0.38),
            (0.68, 0.3), (0.5, 0.25), (0.32, 0.3)], '#5a3418')
        Pg([(0.29, 0.27), (0.71, 0.27), (0.7, 0.32), (0.3, 0.32)], '#dcb75a')
        E(0.46, 0.255, 0.54, 0.335, '#3a7ad8')
    elif kind == 'commander':
        Pg([(0.0, 1.0), (0.04, 0.76), (0.26, 0.66), (0.74, 0.66), (0.96, 0.76), (1.0, 1.0)], '#8c9098')
        E(0.0, 0.66, 0.34, 0.9, '#a8adb6')
        E(0.66, 0.66, 1.0, 0.9, '#7a7e86')
        Pg([(0.36, 0.7), (0.64, 0.7), (0.6, 1.0), (0.4, 1.0)], '#2f5aa0')
        Pg([(0.42, 0.58), (0.58, 0.58), (0.6, 0.7), (0.4, 0.7)], skin_d)
        E(0.31, 0.24, 0.69, 0.66, skin)
        Pg([(0.55, 0.26), (0.69, 0.36), (0.68, 0.52), (0.6, 0.64), (0.56, 0.64)], skin_d)
        Pg([(0.33, 0.5), (0.4, 0.62), (0.5, 0.67), (0.6, 0.62), (0.67, 0.5), (0.6, 0.56), (0.4, 0.56)], '#8a7c6a')
        d.chord([X(0.26), Y(0.1), X(0.74), Y(0.5)], 180, 360, fill='#a8adb6')
        Pg([(0.26, 0.3), (0.74, 0.3), (0.74, 0.36), (0.26, 0.36)], '#dcb75a')
        Pg([(0.46, 0.0), (0.54, 0.0), (0.56, 0.14), (0.44, 0.14)], '#3a6ad0')
        Pg([(0.26, 0.33), (0.33, 0.33), (0.33, 0.52), (0.27, 0.48)], '#8c9098')
        Pg([(0.67, 0.33), (0.74, 0.33), (0.73, 0.48), (0.67, 0.52)], '#7a7e86')
    else:  # scout
        Pg([(0.0, 1.0), (0.05, 0.76), (0.3, 0.64), (0.7, 0.64), (0.95, 0.76), (1.0, 1.0)], '#5a5a32')
        Pg([(0.42, 0.56), (0.58, 0.56), (0.6, 0.68), (0.4, 0.68)], skin_d)
        E(0.33, 0.26, 0.67, 0.64, skin)
        Pg([(0.55, 0.28), (0.67, 0.38), (0.66, 0.52), (0.58, 0.62), (0.55, 0.62)], skin_d)
        d.chord([X(0.22), Y(0.1), X(0.78), Y(0.7)], 180, 360, fill='#4a4a28')
        Pg([(0.22, 0.4), (0.33, 0.36), (0.32, 0.7), (0.2, 0.72)], '#4a4a28')
        Pg([(0.78, 0.4), (0.67, 0.36), (0.68, 0.7), (0.8, 0.72)], '#3c3c20')
    ey = 0.44 if kind != 'scout' else 0.45
    for ex in (0.41, 0.59):
        E(ex - 0.035, ey - 0.018, ex + 0.035, ey + 0.018, '#2a1a10')
        d.line([X(ex - 0.06), Y(ey - 0.05), X(ex + 0.05), Y(ey - 0.055)], fill='#3a2210', width=int(0.025 * W_))
    d.line([X(0.5), Y(0.47), X(0.53), Y(0.53)], fill=skin_d, width=int(0.02 * W_))
    if kind != 'commander':
        d.line([X(0.45), Y(0.575), X(0.55), Y(0.575)], fill='#8a4a34', width=int(0.02 * W_))
    small = np.asarray(im.resize((w, h), Image.LANCZOS)).astype(np.float32) / 255
    rgb = small[..., :3]
    g = rgb.mean(-1, keepdims=True)
    rgb = g + (rgb - g) * 0.85
    out = np.concatenate([rgb, np.ones((h, w, 1), np.float32)], -1)
    return Image.fromarray((np.clip(out, 0, 1) * 255).astype(np.uint8), 'RGBA')


PORTRAITS = {'prince_blue': 'prince', 'commander_blue': 'commander', 'scout_blue': 'scout'}
RAW = os.path.join(ROOT, 'tools', '_raw')
SKIES = {'scout': ('#7e9468', '#e4d2a0')}
SKY = ('#6f97c0', '#e8d4a4')


def portrait(name, kind, rng):
    """The HUD portrait of a character: the Blender bust shot (tools/render_units.py writes
    tools/_raw/portrait_<name>.png) shrunk to size over a warm sky, with a limited palette and
    a little grit like the sprites. Without the render, the painted placeholder (bust())."""
    raw_path = os.path.join(RAW, 'portrait_%s.png' % name)
    if not os.path.exists(raw_path):
        return bust(kind, *PORTRAIT)
    w, h = PORTRAIT
    raw = np.asarray(Image.open(raw_path).convert('RGBA')).astype(np.float32) / 255
    k = raw.shape[1] // w
    raw = raw[:h * k, :w * k].reshape(h, k, w, k, 4).mean((1, 3))
    alpha = raw[..., 3:]
    colour = raw[..., :3] / np.maximum(alpha, 1e-4)
    top, bottom = (hexc(c) for c in SKIES.get(kind, SKY))
    t = np.linspace(0, 1, h)[:, None, None]
    sky = top * (1 - t) + bottom * t + (fbm(h, w, 6, rng, 2)[..., None] - 0.5) * 0.06
    yy, xx = np.mgrid[0:h, 0:w]
    vignette = 1 - 0.25 * (((xx - w / 2) / w) ** 2 + ((yy - h * 0.4) / h) ** 2)[..., None] * 2
    out = (colour * alpha + sky * (1 - alpha)) * vignette
    g = out.mean(-1, keepdims=True)
    out = np.clip(g + (out - g) * 0.9, 0, 1)
    im = Image.fromarray((out * 255).astype(np.uint8)).filter(ImageFilter.UnsharpMask(1.2, 90, 2))
    im = im.quantize(colors=40, method=Image.Quantize.MEDIANCUT, dither=Image.Dither.NONE).convert('RGB')
    out = np.asarray(im).astype(np.float32) / 255
    out = np.clip(out * (1 + (rng.random((h, w)) - 0.5)[..., None] * 0.05), 0, 1)
    return Image.fromarray((np.concatenate([out, np.ones((h, w, 1))], -1) * 255).astype(np.uint8), 'RGBA')


def main():
    rng = np.random.default_rng(7)
    os.makedirs(os.path.join(OUT, 'icons'), exist_ok=True)
    os.makedirs(os.path.join(OUT, 'portraits'), exist_ok=True)
    make_frame(rng).save(os.path.join(OUT, 'hud_frame.png'))
    for name, spec in PIECES.items():
        make_piece(np.random.default_rng(len(name)), **spec).save(os.path.join(OUT, 'panel_%s.png' % name))
    for name in ICONS:
        make_icon(name).save(os.path.join(OUT, 'icons', name + '.png'))
    for name, kind in PORTRAITS.items():
        path = os.path.join(OUT, 'portraits', name + '.png')
        if not os.path.exists(os.path.join(RAW, 'portrait_%s.png' % name)) and os.path.exists(path):
            print('kept', path, '(no Blender render in tools/_raw to make it from)')
            continue
        portrait(name, kind, np.random.default_rng(len(name))).save(path)
    print('HUD art written to', OUT)


if __name__ == '__main__':
    main()
