# Balance HUD mockups v12 (milestone M7.5): three warm layouts over a real Mission 2 frame.
# All three: full-width top bar, rounder corners, wood / brass / parchment. They differ in where the
# heroes, the mission messages and the objectives go.
# Run: python v12_hud.py <dir with frame.png and with_hud.png> <out_dir>
import os, sys, math
HERE = os.path.dirname(os.path.abspath(__file__))
SRC, DEST, ONLY = sys.argv[1], sys.argv[2], sys.argv[3:]
sys.argv = [sys.argv[0], SRC, SRC]
sys.path.insert(0, HERE)
from v3_compose import *          # noqa: F401,F403  (Layers, icons, palettes, text, noise)

ROOT = os.path.normpath(os.path.join(HERE, '..', '..'))
TOP = 28                          # top bar height, full width
SX = 752                          # sidebar left edge
R = 7                             # panel corner radius
RB = 5                            # button corner radius

OAK2 = ['#22140a', '#3a2412', '#55361b', '#6e4824', '#875b2f', '#9c6d3a']
GOLD2 = ['#33230a', '#5e4314', '#8f6a22', '#bb9234', '#dcb75a', '#f4dc98']
CHESTNUT = ['#24120c', '#3c1e14', '#56301f', '#6e402a', '#875236', '#9c6342']
PARCH = ['#a88a5a', '#c2a474', '#d8bf90', '#e8d4aa', '#f3e5c4']
STONE = ['#2a241e', '#38302a', '#463d35', '#544a40']
NAVY2 = ['#10203f', '#1f3a70', '#2f5aa0', '#5482c6', '#a8c8ee']
GREEN = ['#16300f', '#2a5a1c', '#3f8a2a', '#62b444', '#b4e49a']

ICONS.update({
    'bolt': [('poly', (9.5, 1.5, 3, 9, 7.5, 9, 6, 14.5, 13, 6.5, 8.5, 6.5))],
    'stop': [('rect', (3.5, 3.5, 12.5, 12.5))],
    'pulse': [('ring', (8, 8), 6.6, 5.2), ('rect', (6.9, 4, 9.1, 12)), ('rect', (4, 6.9, 12, 9.1))],
    'scroll': [('rect', (3.5, 3, 12.5, 13)), ('dot', (3.5, 3.5), 1.6), ('dot', (12.5, 12.5), 1.6)],
    'tick': [('line', (3, 8.5, 6.5, 12), 2.2), ('line', (6.5, 12, 13, 4), 2.2)],
})

THEMES12 = {
    'a': dict(frame=OAK2, trim=GOLD2, parch=PARCH, title='A'),
    'b': dict(frame=WALNUT, trim=BRASS, parch=PARCH3, title='B'),
    'c': dict(frame=CHESTNUT, trim=GOLD2, parch=PARCH, title='C'),
    'd': dict(frame=CHESTNUT, trim=GOLD2, parch=PARCH, title='D'),     # C's look, A's heroes, messages, objectives
}

F_T13 = font('georgiab.ttf', 13)
F_B10 = font('georgiab.ttf', 10)
F_I10 = font('georgiai.ttf', 10)
F_R10 = font('georgia.ttf', 10)
INK, DIM, LIGHT, SH, RED_INK = '#33200e', '#6a4c2a', '#f2e6c4', '#140a04', '#7a1c12'

OBJECTIVES = [('done', 'Bring the Prince to the stony ground'),
              ('open', 'Build a Generator and a Barracks'),
              ('keep', 'Keep the Prince and the Field Commander alive')]


# --- portraits: painted cameo busts (placeholders until the M7.6 art pass) -----------------------------------
def bust(kind, w, h):
    k = 8
    im = Image.new('RGBA', (w * k, h * k))
    d = ImageDraw.Draw(im)
    W_, H_ = w * k, h * k
    top, bot = (hexc('#6f97c0'), hexc('#e8d4a4')) if kind != 'scout' else (hexc('#8a9a6a'), hexc('#e4d2a0'))
    for y in range(H_):
        t = y / H_
        c = tuple(int(v * 255) for v in top * (1 - t) + bot * t)
        d.line([(0, y), (W_, y)], fill=c)

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
        Pg([(0.0, 1.0), (0.06, 0.78), (0.3, 0.68), (0.7, 0.68), (0.94, 0.78), (1.0, 1.0)], '#1f3a70')   # cloak
        Pg([(0.3, 0.68), (0.5, 0.9), (0.7, 0.68)], '#c9b48a')                                            # tunic
        Pg([(0.33, 0.69), (0.5, 0.86), (0.67, 0.69), (0.62, 0.68), (0.5, 0.78), (0.38, 0.68)], '#8a6a2a')
        E(0.18, 0.74, 0.3, 0.84, '#dcb75a')                                                              # clasp
        E(0.7, 0.74, 0.82, 0.84, '#dcb75a')
        Pg([(0.42, 0.58), (0.58, 0.58), (0.6, 0.7), (0.4, 0.7)], skin_d)                                 # neck
        E(0.3, 0.2, 0.7, 0.64, skin)                                                                     # face
        Pg([(0.55, 0.22), (0.7, 0.32), (0.69, 0.5), (0.6, 0.62), (0.56, 0.62)], skin_d)                  # shade
        Pg([(0.27, 0.36), (0.28, 0.2), (0.4, 0.12), (0.6, 0.12), (0.72, 0.2), (0.73, 0.38),
            (0.68, 0.3), (0.5, 0.25), (0.32, 0.3)], '#5a3418')                                           # hair
        Pg([(0.29, 0.27), (0.71, 0.27), (0.7, 0.32), (0.3, 0.32)], '#dcb75a')                            # circlet
        E(0.46, 0.255, 0.54, 0.335, '#3a7ad8')
    elif kind == 'commander':
        Pg([(0.0, 1.0), (0.04, 0.76), (0.26, 0.66), (0.74, 0.66), (0.96, 0.76), (1.0, 1.0)], '#8c9098')  # armour
        E(0.0, 0.66, 0.34, 0.9, '#a8adb6')                                                               # pauldrons
        E(0.66, 0.66, 1.0, 0.9, '#7a7e86')
        Pg([(0.36, 0.7), (0.64, 0.7), (0.6, 1.0), (0.4, 1.0)], '#2f5aa0')                                # tabard
        Pg([(0.42, 0.58), (0.58, 0.58), (0.6, 0.7), (0.4, 0.7)], skin_d)
        E(0.31, 0.24, 0.69, 0.66, skin)
        Pg([(0.55, 0.26), (0.69, 0.36), (0.68, 0.52), (0.6, 0.64), (0.56, 0.64)], skin_d)
        Pg([(0.33, 0.5), (0.4, 0.62), (0.5, 0.67), (0.6, 0.62), (0.67, 0.5), (0.6, 0.56), (0.4, 0.56)], '#8a7c6a')  # beard
        d.chord([X(0.26), Y(0.1), X(0.74), Y(0.5)], 180, 360, fill='#a8adb6')                            # helmet
        Pg([(0.26, 0.3), (0.74, 0.3), (0.74, 0.36), (0.26, 0.36)], '#dcb75a')
        Pg([(0.46, 0.0), (0.54, 0.0), (0.56, 0.14), (0.44, 0.14)], '#3a6ad0')                            # crest
        Pg([(0.26, 0.33), (0.33, 0.33), (0.33, 0.52), (0.27, 0.48)], '#8c9098')                          # cheek guards
        Pg([(0.67, 0.33), (0.74, 0.33), (0.73, 0.48), (0.67, 0.52)], '#7a7e86')
    else:  # scout
        Pg([(0.0, 1.0), (0.05, 0.76), (0.3, 0.64), (0.7, 0.64), (0.95, 0.76), (1.0, 1.0)], '#5a5a32')
        Pg([(0.42, 0.56), (0.58, 0.56), (0.6, 0.68), (0.4, 0.68)], skin_d)
        E(0.33, 0.26, 0.67, 0.64, skin)
        Pg([(0.55, 0.28), (0.67, 0.38), (0.66, 0.52), (0.58, 0.62), (0.55, 0.62)], skin_d)
        d.chord([X(0.22), Y(0.1), X(0.78), Y(0.7)], 180, 360, fill='#4a4a28')                             # hood
        Pg([(0.22, 0.4), (0.33, 0.36), (0.32, 0.7), (0.2, 0.72)], '#4a4a28')
        Pg([(0.78, 0.4), (0.67, 0.36), (0.68, 0.7), (0.8, 0.72)], '#3c3c20')
    # eyes, brows, mouth
    ey = 0.44 if kind != 'scout' else 0.45
    for ex in (0.41, 0.59):
        E(ex - 0.035, ey - 0.018, ex + 0.035, ey + 0.018, '#2a1a10')
        d.line([X(ex - 0.06), Y(ey - 0.05), X(ex + 0.05), Y(ey - 0.055)], fill='#3a2210', width=int(0.025 * W_))
    d.line([X(0.5), Y(0.47), X(0.53), Y(0.53)], fill=skin_d, width=int(0.02 * W_))
    if kind != 'commander':
        d.line([X(0.45), Y(0.575), X(0.55), Y(0.575)], fill='#8a4a34', width=int(0.02 * W_))
    small = im.resize((w, h), Image.LANCZOS)
    a = to_arr(small)
    g = a.mean(-1, keepdims=True)
    return g + (a - g) * 0.85


# --- things taken from the game -------------------------------------------------------------------------------
def sprite_icon(name, w, h):
    im = Image.open(os.path.join(ROOT, 'assets', 'sprites', 'buildings', name + '_blue.png')).convert('RGBA')
    s = min(w / im.size[0], h / im.size[1])
    im = im.resize((max(1, int(im.size[0] * s)), max(1, int(im.size[1] * s))), Image.LANCZOS)
    a = np.asarray(im).astype(np.float32) / 255
    return a[..., :3], a[..., 3]


def put_img(frame, x, y, rgb, a=None):
    if a is None:
        a = np.ones(rgb.shape[:2], np.float32)
    put(frame, int(x), int(y), rgb, a)


def round_mask(w, h, r):
    return shape_mask(lambda d, S: d.rounded_rectangle([0, 0, w * S - 1, h * S - 1], r * S, fill=255), w, h)


# --- one mockup ----------------------------------------------------------------------------------------------
def compose12(v, seed):
    T = THEMES12[v]
    rng = np.random.default_rng(seed)
    frame = to_arr(Image.open(os.path.join(SRC, 'frame.png')))
    L = Layers(3)
    S = L.S
    hs, ws = H * S, W * S
    grain = (fbm(hs, ws, 9 * S, rng, 3, (9, 0.5)) - 0.5) * 0.45 + (fbm(hs, ws, 60 * S, rng, 2) - 0.5) * 0.25
    shine = (fbm(hs, ws, 30 * S, rng, 2, (1.5, 0.6)) - 0.5) * 0.2
    ptex = (fbm(hs, ws, 40 * S, rng, 3) - 0.5) * 0.5 + 0.1

    # layout per variant: boxes are (x0, y0, x1, y1)
    caps = dict(obj=(48, 5, 136, 23), menu=(142, 5, 206, 23), plaque=(226, 4, 494, 24),
                ore=(508, 5, 670, 23), power=(678, 5, 812, 23), time=(820, 5, 952, 23))
    mm = (SX + 8, TOP + 8, SX + 200, TOP + 152)
    parch_boxes, inset_boxes, button_boxes, rim_boxes, hero_boxes = [], [], [], [], []
    wood_boxes = []                      # extra wood panels on the map (variant c's hero dock)
    pressed = []                         # accent (navy) buttons
    cmds, tabs, grid, queue, card, msg, tracker, drop, heroes = [], [], [], None, None, None, None, None, []

    def cmd_row(y, h=30):
        return [(SX + 8 + 49 * i, y, SX + 51 + 49 * i, y + h) for i in range(4)]

    def grid_at(y, ch):
        return [(SX + 8 + 65 * (i % 3), y + (ch + 6) * (i // 3), SX + 69 + 65 * (i % 3), y + (ch + 6) * (i // 3) + ch)
                for i in range(6)]

    if v == 'a':
        card = (SX + 8, 188, W - 8, 290)
        cmds = cmd_row(298)
        tabs = [(SX + 8 + 65 * i, 338, SX + 69 + 65 * i, 356) for i in range(3)]
        grid = grid_at(362, 50)
        queue = (SX + 8, 474, W - 8, 532)
        heroes = [(10, TOP + 10, 58, TOP + 68), (66, TOP + 10, 114, TOP + 68)]
        msg = (10, 472, 470, 532)
    elif v == 'b':
        heroes = [(SX + 8, TOP + 8, SX + 102, TOP + 92), (SX + 106, TOP + 8, W - 8, TOP + 92)]
        mm = (SX + 8, TOP + 98, SX + 200, TOP + 242)
        card = (SX + 8, 276, W - 8, 318)
        cmds = cmd_row(324, 26)
        tabs = [(SX + 8 + 65 * i, 358, SX + 69 + 65 * i, 374) for i in range(3)]
        grid = grid_at(380, 44)
        queue = (SX + 8, 482, W - 8, 532)
        tracker = (10, TOP + 10, 290, TOP + 76)
        msg = (300, TOP + 10, 700, TOP + 66)
    else:
        tabs = [(SX + 8 + 65 * i, 188, SX + 69 + 65 * i, 206) for i in range(3)]
        grid = grid_at(212, 56)
        queue = (SX + 8, 342, W - 8, 388)
        card = (SX + 8, 396, W - 8, 470)
        cmds = cmd_row(478, 52)
        if v == 'd':
            heroes = [(10, TOP + 22, 58, TOP + 80), (10, TOP + 98, 58, TOP + 156)]
            msg = (10, 472, 470, 532)
    if v == 'c':
        drop = (44, TOP - 2, 384, TOP + 92)
        wood_boxes.append((0, 446, 262, H + 12))
        heroes = [(12, 458, 64, 522), (136, 458, 188, 522)]
        msg = (274, 476, 700, 532)

    def parch_all():
        out = [b for b in (card, msg, tracker) if b]
        if v in ('a', 'c', 'd'):
            out.append(queue)
        return out

    def inset_all():
        out = list(grid)
        if v == 'b':
            out.append(queue)
        return out

    def frame_mask(d, S):
        d.rectangle(P(S, 0, 0, W, TOP), fill=255)
        d.rectangle(P(S, SX, 0, W, H), fill=255)
        # round the map's inner corner where the top bar meets the sidebar
        d.rectangle(P(S, SX - 12, TOP, SX, TOP + 12), fill=255)
        d.ellipse(P(S, SX - 24, TOP, SX, TOP + 24), fill=0)
        d.rectangle(P(S, SX - 12, TOP + 12, SX, TOP + 24), fill=0)
        for b in wood_boxes:
            rr(d, S, b, 12)
    L.layer(L.mask(frame_mask), T['frame'], 2, 0.5, grain, shadow=4)

    def rails(d, S):
        d.rounded_rectangle(P(S, -10, TOP - 3, SX + 12, TOP + 1), 2 * S, fill=255)
        d.rounded_rectangle(P(S, SX - 3, TOP - 3, SX + 1, H + 10), 2 * S, fill=255)
        d.arc(P(S, SX - 25, TOP - 1, SX + 1, TOP + 25), 270, 360, fill=255, width=int(3.5 * S))
        d.ellipse(P(S, 2, 0, 40, 38), fill=255)                         # the emblem
        for c in caps.values():
            rr(d, S, c, RB + 1, 2)
        rr(d, S, mm, R, 5)
        for b in parch_all() + inset_all():
            rr(d, S, b, R, 3)
        for b in cmds + tabs:
            rr(d, S, b, RB, 1.8)
        for b in heroes:
            rr(d, S, b, R, 3)
        for b in wood_boxes:
            d.rounded_rectangle(P(S, b[0] - 10, b[1] - 3, b[2] + 3, b[3]), 13 * S, outline=255, width=int(3 * S))
        if drop:
            rr(d, S, drop, R, 3)
    L.layer(L.mask(rails), T['trim'], 1.8, 1.0, shine, shadow=2.5)

    def insets(d, S):
        for k in ('ore', 'power', 'time'):
            rr(d, S, caps[k], RB)
        rr(d, S, mm, R - 2)
        for b in inset_all():
            rr(d, S, b, R - 2)
    L.layer(L.mask(insets), PANEL, 2, -0.6, None)

    def parch(d, S):
        rr(d, S, caps['plaque'], RB)
        for b in parch_all():
            rr(d, S, b, R - 2)
        if drop:
            rr(d, S, drop, R - 2)
    L.layer(L.mask(parch), T['parch'], 1.5, -0.3, ptex)

    def stone(d, S):
        for b in grid:
            rr(d, S, (b[0] + 4, b[1] + 4, b[2] - 4, b[3] - 15), 3)
    L.layer(L.mask(stone), STONE, 1.2, -0.4, grain * 0.6)

    def accent(d, S):
        d.ellipse(P(S, 6, 4, 36, 34), fill=255)
        rr(d, S, caps['obj'], RB)
        rr(d, S, caps['menu'], RB)
        for b in cmds:
            rr(d, S, b, RB - 1)
        rr(d, S, tabs[0], RB - 1)
    L.layer(L.mask(accent), NAVY2, 2.5, 0.8, None)

    def tabs_off(d, S):
        for b in tabs[1:]:
            rr(d, S, b, RB - 1)
    L.layer(L.mask(tabs_off), T['frame'], 2, 0.6, grain)

    def icons(d, S):
        draw_icon(d, S, 'scales', 10.5, 8.5, 1.35)
        draw_icon(d, S, 'scroll', caps['obj'][0] + 5, caps['obj'][1] + 2, 0.85)
        draw_icon(d, S, 'cog', caps['menu'][0] + 5, caps['menu'][1] + 2, 0.85)
        names = ('move', 'swords', 'stop', 'pulse')
        for b, nm in zip(cmds, names):
            k = 1.1 if b[3] - b[1] < 40 else 1.3
            draw_icon(d, S, nm, (b[0] + b[2]) / 2 - 8 * k, (b[1] + b[3]) / 2 - 8 * k - (5 if v in ('c', 'd') else 0), k)
        for b, nm in zip(tabs, ('castle', 'helm', 'cog')):
            draw_icon(d, S, nm, (b[0] + b[2]) / 2 - 6.5, b[1] + (b[3] - b[1]) / 2 - 6.5, 0.8)
        draw_icon(d, S, 'glass', caps['time'][0] + 6, caps['time'][1] + 2, 0.85)
    L.layer(L.mask(icons), IVORY, 1.0, 0.8, None, shadow=1)

    def ore(d, S):
        draw_icon(d, S, 'gem', caps['ore'][0] + 6, caps['ore'][1] + 2, 0.85)
        draw_icon(d, S, 'bolt', caps['power'][0] + 6, caps['power'][1] + 2, 0.85)
    L.layer(L.mask(ore), ORIP, 1.6, 1.0, None)

    hud, ha = L.result()
    frame = frame * (1 - ha[..., None]) + hud * ha[..., None]

    # pictures: minimap, portraits, building icons
    mini = Image.new('RGB', (192, 144), (0, 0, 0))
    mini.paste(Image.open(os.path.join(SRC, 'with_hud.png')).convert('RGB').crop((759, 22, 951, 153)), (0, 13))
    mw, mh = mm[2] - mm[0], mm[3] - mm[1]
    put_img(frame, mm[0], mm[1], to_arr(mini.resize((mw, mh), Image.LANCZOS)), round_mask(mw, mh, R - 3))
    hero_kinds = ['prince', 'commander']
    portraits = []
    for b, kind in zip(heroes, hero_kinds):
        if v == 'b':
            pb = (b[0] + 5, b[1] + 19, b[0] + 41, b[1] + 61)
        else:
            pb = (b[0] + 3, b[1] + 3, b[2] - 3, b[3] - 3)
        pw, ph = pb[2] - pb[0], pb[3] - pb[1]
        put_img(frame, pb[0], pb[1], bust(kind, pw, ph), round_mask(pw, ph, R - 3))
        portraits.append(pb)
    if card and v != 'b':
        pb = (card[0] + 6, card[1] + 6, card[0] + 56, card[1] + 66) if v == 'a' else \
            (card[0] + 6, card[1] + 6, card[0] + 52, card[1] + 62)
        put_img(frame, pb[0], pb[1], bust('prince', pb[2] - pb[0], pb[3] - pb[1]),
                round_mask(pb[2] - pb[0], pb[3] - pb[1], 4))
    if msg:
        mh_ = msg[3] - msg[1] - 10
        put_img(frame, msg[0] + 5, msg[1] + 5, bust('scout', int(mh_ * 0.82), mh_), round_mask(int(mh_ * 0.82), mh_, 4))
    for b, name in zip(grid, ('generator', 'refinery', 'barracks', 'workshop')):
        iw, ih = b[2] - b[0] - 10, b[3] - b[1] - 21
        rgb, a = sprite_icon(name, iw, ih)
        put_img(frame, (b[0] + b[2]) // 2 - rgb.shape[1] // 2, b[1] + 5 + (ih - rgb.shape[0]) // 2, rgb, a)

    # text and bars
    im = to_img(frame)
    d = ImageDraw.Draw(im)
    d.fontmode = '1'
    c = caps['obj']
    text(d, c[0] + 21, c[1] + 3, 'Objectives', F_B10, LIGHT, SH)
    c = caps['menu']
    text(d, c[0] + 21, c[1] + 3, 'Menu', F_B10, LIGHT, SH)
    c = caps['plaque']
    text(d, (c[0] + c[2]) // 2, c[1] + 3, 'Mission 2  -  Holding the Claim', F_B11, INK, None, 'ma')
    for k, label, val in (('ore', 'Orichalcum', '640'), ('power', 'Power', '30 / 40'), ('time', 'Time', '1:28')):
        c = caps[k]
        if label:
            text(d, c[0] + 22, c[1] + 3, label, F_B10, '#e8bf6c', SH)
        text(d, c[2] - 7, c[1] + 2, val, F_B11, LIGHT, SH, 'ra')
    def bar(x, y, w, frac, col='#4a9a3a', top='#86c874', h=5):
        d.rectangle([x, y, x + w, y + h], fill='#2a1a0c')
        d.rectangle([x + 1, y + 1, x + 1 + int((w - 2) * frac), y + h - 1], fill=col)
        d.line([x + 1, y + 1, x + 1 + int((w - 2) * frac), y + 1], fill=top)

    def key_badge(x, y, key, ready, cooldown=''):
        fill = '#2f5aa0' if ready else '#3a2a1a'
        d.rounded_rectangle([x, y, x + 15, y + 13], 4, fill=fill, outline='#dcb75a')
        text(d, x + 8, y + 1, key, F_B10, LIGHT if ready else '#a89878', None, 'ma')
        if cooldown:
            text(d, x + 18, y + 1, cooldown, F_B10, LIGHT, SH)

    # heroes
    hero_info = [('The Prince', 1.0, 'E', True, '', 'Restore'), ('Field Commander', 0.72, 'Q', False, '12 s', 'Mend')]
    for b, pb, (name, hp, key, ready, cd, ab) in zip(heroes, portraits, hero_info):
        if v in ('a', 'd'):
            bar(b[0], b[3] + 5, b[2] - b[0], hp)
            key_badge(b[2] - 17, b[3] - 16, key, ready)
            if cd:
                text(d, b[0] + 5, b[3] - 15, cd, F_S10, LIGHT, SH)
        elif v == 'b':
            x = pb[2] + 4
            text(d, b[0] + 6, b[1] + 4, name.split()[-1], F_S10, LIGHT, SH)
            text(d, x, b[1] + 22, 'Hero', F_I10, '#d8c49a', SH)
            bar(x, b[1] + 38, b[2] - x - 5, hp)
            text(d, x, b[1] + 46, '%d%%' % (hp * 100), F_S9, '#d8c49a', SH)
            bx = (b[0] + 5, b[3] - 22, b[2] - 5, b[3] - 5)
            d.rounded_rectangle(bx, 4, fill='#2f5aa0' if ready else '#3a2a1a', outline='#dcb75a')
            text(d, (bx[0] + bx[2]) // 2, bx[1] + 4, '%s  %s' % (key, ab) + ('  ' + cd if cd else ''), F_S10,
                 LIGHT if ready else '#c8b898', SH, 'ma')
        else:
            x = b[2] + 6
            text(d, x, b[1] + 2, name.split()[-1], F_S10, LIGHT, SH)
            bar(x, b[1] + 16, 58, hp)
            bx = (x, b[1] + 28, x + 58, b[1] + 46)
            d.rounded_rectangle(bx, 5, fill='#2f5aa0' if ready else '#3a2a1a', outline='#dcb75a')
            text(d, (bx[0] + bx[2]) // 2, bx[1] + 4, key + '  ' + (cd if cd else ab), F_S10,
                 LIGHT if ready else '#c8b898', SH, 'ma')
        if name == 'The Prince':           # the selected hero
            d.rounded_rectangle([pb[0] - 2, pb[1] - 2, pb[2] + 1, pb[3] + 1], 5, outline='#fff2a6', width=1)

    # selection card
    if card:
        if v == 'a':
            x = card[0] + 62
            text(d, x, card[1] + 6, 'The Prince', F_B12, INK)
            text(d, x, card[1] + 21, 'Blue leader, hero', F_I10, DIM)
            bar(x, card[1] + 37, W - 16 - x, 1.0, h=6)
            text(d, x, card[1] + 47, 'Health  150 / 150', F_S9, INK)
            text(d, x, card[1] + 60, 'Restore (E)', F_S9, DIM)
            text(d, W - 16, card[1] + 60, 'ready', F_S10, '#2a5a1c', None, 'ra')
            text(d, card[0] + 8, card[1] + 76, 'Encouragement', F_S10, INK)
            text(d, card[0] + 8, card[1] + 88, 'Troops near him: +5% speed', F_S9, DIM)
        elif v == 'b':
            text(d, card[0] + 7, card[1] + 5, 'The Prince', F_B12, INK)
            text(d, W - 15, card[1] + 6, '150 / 150', F_S10, INK, None, 'ra')
            text(d, card[0] + 7, card[1] + 19, 'Encouragement: troops near him', F_S9, DIM)
            text(d, card[0] + 7, card[1] + 29, 'move and fight 5% faster', F_S9, DIM)
        else:
            x = card[0] + 58
            text(d, x, card[1] + 6, 'The Prince', F_B12, INK)
            text(d, x, card[1] + 21, 'Blue leader, hero', F_I10, DIM)
            bar(x, card[1] + 37, W - 16 - x, 1.0, h=6)
            text(d, x, card[1] + 47, 'Health  150 / 150', F_S9, INK)
            text(d, card[0] + 7, card[1] + 62, 'Encouragement: +5% near him', F_S9, DIM)
    if v in ('c', 'd'):
        for b, label in zip(cmds, ('Move', 'Attack', 'Stop', 'Restore')):
            text(d, (b[0] + b[2]) // 2, b[3] - 15, label, F_S9, LIGHT, SH, 'ma')

    # build grid and queue
    for b, (name, cost) in zip(grid, (('Generator', 150), ('Refinery', 400), ('Barracks', 200),
                                      ('Workshop', 400), ('Locked', 0), ('Locked', 0))):
        col = '#e8d8b0' if cost else '#8a7a5a'
        text(d, (b[0] + b[2]) // 2, b[3] - 13, name, F_S9, col, None, 'ma')
        if cost:
            tw = d.textlength(str(cost), font=F_S10)
            d.rounded_rectangle([b[2] - 9 - tw, b[1] + 5, b[2] - 5, b[1] + 16], 3, fill='#1a120c')
            text(d, b[2] - 7, b[1] + 6, str(cost), F_S10, '#e8bf6c', None, 'ra')
    if queue:
        dark = v == 'b'
        ink, dim = (LIGHT, '#c8b898') if dark else (INK, DIM)
        text(d, queue[0] + 7, queue[1] + 5, 'Building: Workshop', F_B10, ink)
        text(d, queue[2] - 7, queue[1] + 5, '35%', F_S10, ink, None, 'ra')
        bar(queue[0] + 7, queue[1] + 19, queue[2] - queue[0] - 14, 0.35, '#c8902a', '#f4d056')
        text(d, queue[0] + 7, queue[1] + 29, 'Power  30 / 40', F_S9, dim)
        if queue[3] - queue[1] > 50:
            bar(queue[0] + 7, queue[1] + 42, queue[2] - queue[0] - 14, 0.75, '#3a6ac8', '#8ab0ee')

    # mission message
    if msg:
        mh_ = msg[3] - msg[1] - 10
        x = msg[0] + 5 + int(mh_ * 0.82) + 8
        text(d, x, msg[1] + 6, 'Scout', F_B11, RED_INK)
        text(d, msg[2] - 8, msg[1] + 6, '1:24', F_S9, DIM, None, 'ra')
        text(d, x, msg[1] + 22, 'Red scouts at the southern ford!', F_R11, INK)
        if msg[3] - msg[1] > 56:
            text(d, x, msg[1] + 38, 'Earlier, the Prince: "Here we stand. We need power and soldiers..."', F_I10, DIM)

    # objectives: tracker (b) or opened list (c)
    def objective_rows(x, y, w, step=15):
        for i, (state, line) in enumerate(OBJECTIVES):
            yy = y + i * step
            box = [x, yy + 1, x + 10, yy + 11]
            if state == 'done':
                d.rectangle(box, outline=DIM)
                d.line([x + 2, yy + 6, x + 4, yy + 9, x + 9, yy + 2], fill='#2a6a1c', width=2)
                text(d, x + 16, yy, line, F_R10, '#8a7458')
                tw = d.textlength(line, font=F_R10)
                d.line([x + 16, yy + 7, x + 16 + tw, yy + 7], fill='#8a7458')
            elif state == 'open':
                d.rectangle(box, outline=INK)
                text(d, x + 16, yy, line, F_B10, INK)
            else:
                d.ellipse([x + 1, yy + 2, x + 9, yy + 10], outline=RED_INK, width=2)
                text(d, x + 16, yy, line, F_R10, RED_INK)

    if tracker:
        text(d, tracker[0] + 8, tracker[1] + 5, 'Objectives', F_B11, INK)
        objective_rows(tracker[0] + 8, tracker[1] + 21, tracker[2] - tracker[0] - 16, 14)
    if drop:
        text(d, drop[0] + 10, drop[1] + 9, 'Objectives', F_T13, INK)
        text(d, drop[2] - 10, drop[1] + 11, 'O to close', F_S9, DIM, None, 'ra')
        d.line([drop[0] + 10, drop[1] + 27, drop[2] - 10, drop[1] + 27], fill='#a88a5a')
        objective_rows(drop[0] + 10, drop[1] + 33, drop[2] - drop[0] - 20, 17)

    out = im.resize((W * 2, H * 2), Image.NEAREST)
    path = os.path.join(DEST, 'balance_v12_hud_%s.png' % v)
    out.save(path)
    print('saved', path)


if __name__ == '__main__':
    for i, v in enumerate(ONLY or ('a', 'b', 'c', 'd')):
        compose12(v, 40 + i)
