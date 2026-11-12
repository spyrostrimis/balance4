# Balance style test v8 -- HUD redone in the terrain's flat, gritty style:
# centred top bar with round timer, hero portrait top-left, sidebar with power bar, minimap, tabs,
# preview, build grid, build queue, command buttons and a selection strip.
# Run: python v8_compose.py <raw_sprite_dir> <out_dir> [forest desert]
import os, sys
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from v7_compose import *          # noqa: F401,F403
import v3_compose as V3

ICONS.update({
    'tankic': [('rect', (2, 8, 14, 12)), ('rect', (5, 5, 10, 8)), ('line', (10, 6.5, 15.5, 6.5), 1.4),
               ('dot', (4, 12.6), 1.6), ('dot', (8, 12.6), 1.6), ('dot', (12, 12.6), 1.6)],
    'stop': [('line', (3.5, 3.5, 12.5, 12.5), 2.4), ('line', (12.5, 3.5, 3.5, 12.5), 2.4)],
    'form': [('dot', (8, 3.5), 2.0), ('dot', (3.5, 12), 2.0), ('dot', (12.5, 12), 2.0), ('line', (8, 3.5, 3.5, 12), 1.0),
             ('line', (8, 3.5, 12.5, 12), 1.0), ('line', (3.5, 12, 12.5, 12), 1.0)],
    'bolt': [('poly', (9.5, 1, 4, 9, 7.5, 9, 6, 15, 12, 6.5, 8.5, 6.5))],
    'lock': [('rect', (4, 7.5, 12, 14)), ('ring', (8, 6.5), 3.4, 2.0)],
})
F_C10 = font('georgiab.ttf', 10)
SBX = 746                                   # sidebar left edge
TH8 = {
    'blue': dict(body=['#171c23', '#1c222b', '#212832'], inset=['#0d1014', '#11151a', '#15191f'],
                 acc=['#1f3a7c', '#284a98', '#3158ac'], line='#9c874c', hi='#cbb470', lo='#0a0c0f',
                 text='#e4dabd', dim='#8c8878', bg=('#16202e', '#2c3c58'),
                 name='Guardsman', sub='Blue Infantry'),
    'red': dict(body=['#221715', '#291c19', '#30211d'], inset=['#130c0b', '#18100f', '#1d1412'],
                acc=['#6e1c17', '#882520', '#a02e27'], line='#a67238', hi='#cf9a58', lo='#0c0807',
                text='#e8d8bc', dim='#927f6c', bg=('#2a1513', '#4c231d'),
                name='Legionary', sub='Red Infantry'),
}
CONTENT = {
    'blue': dict(tab=0, ground=STONE4, uground=GRASS4,
                 preview=('Radar', 'Cost  600', 'Reveals terrain and tracks', 'enemy movement nearby.'),
                 cells=[('Radar', 'radar')], sel=0, queue=('Radar', 0.6, 'radar')),
    'red': dict(tab=1, ground=ROCKG3, uground=SAND3,
                preview=('Tank', 'Cost  450', 'Tracked armour, one cannon.', 'Slow, and hard to kill.'),
                cells=[('Light Scout', 'light'), ('Tank', 'tank'), ('Harvester', 'harv')], sel=1,
                queue=('Tank', 0.35, 'tank')),
}


class Hud:
    def __init__(self, frame, T, rng):
        self.f, self.T, self.rng = frame, T, rng
        self.boxes = []

    def fill(self, box, palette, amp=0.9):
        x0, y0, x1, y1 = [int(v) for v in box]
        self.f[y0:y1, x0:x1] = ramp(np.clip(0.5 + speck(y1 - y0, x1 - x0, self.rng, amp), 0, 0.999), palette)

    def panel(self, box, kind='inset', line='line'):
        self.fill(box, self.T[kind])
        self.boxes.append(([int(v) for v in box], line))

    def pic(self, x, y, arr):
        put(self.f, int(x), int(y), arr, np.ones(arr.shape[:2], np.float32))

    def icon(self, name, cx, cy, k=1.0, col=None):
        n = int(16 * k) + 2
        m = shape_mask(lambda d, S: draw_icon(d, S, name, 0, 0, k), n, n)
        put(self.f, int(cx - 8 * k), int(cy - 8 * k), np.broadcast_to(hexc(col or self.T['text']), (n, n, 3)), m)

    def borders(self, d):
        for (x0, y0, x1, y1), line in self.boxes:
            d.rectangle([x0 - 1, y0 - 1, x1, y1], outline=self.T['lo'])
            d.rectangle([x0, y0, x1 - 1, y1 - 1], outline=self.T[line])


def scene_pic(w, h, palette, items, rng, scale=1, found=None):
    """Small in-game picture: speckled ground, optional foundation, sprites with contact shadows."""
    c = ramp(np.clip(0.5 + speck(h, w, rng, 0.8), 0, 0.999), palette)
    if found:
        x0, y0 = found
        ys, ye, xs, xe = max(0, y0), min(h, y0 + 64), max(0, x0), min(w, x0 + 64)
        tmp = np.zeros((64, 64, 3), np.float32)
        foundation(tmp, 0, 0, 2, 2, rng)
        c[ys:ye, xs:xe] = tmp[ys - y0:ye - y0, xs - x0:xe - x0]
    for (nm, k, x, y) in items:
        s = unit_sprite7((nm, k))
        put(c, x - s['ax'], y - s['ay'], np.zeros_like(s['rgb']), s['sh'] * 0.42)
        put(c, x - s['ax'], y - s['ay'], s['rgb'], s['a'])
    if scale > 1:
        c = np.repeat(np.repeat(c, scale, 0), scale, 1)
    return c


def item_pic(kind, team, w, h, C, rng, big=False):
    if kind == 'radar':
        if big:
            return scene_pic(w, h, C['ground'], [(f'radar_{team}', 0, w // 2, h // 2)], rng, 1, (w // 2 - 32, h // 2 - 32))
        full = scene_pic(w * 2, h * 2, C['ground'], [(f'radar_{team}', 0, w, h)], rng, 1, (w - 32, h - 32))
        return full.reshape(h, 2, w, 2, 3).mean((1, 3))
    if big:
        return scene_pic(w // 2, h // 2, C['uground'], [(f'{kind}_{team}', 7, w // 4, h // 4 + 2)], rng, 2)
    return scene_pic(w, h, C['uground'], [(f'{kind}_{team}', 6, w // 2, h // 2 + 2)], rng)


def hero_pic(team, T, rng, n=40):
    src = Image.open(f'{RAW}/hero_{team}.png').convert('RGBA')
    g = np.linspace(0, 1, src.size[1])[:, None, None]
    bg = hexc(T['bg'][0]) * (1 - g) + hexc(T['bg'][1]) * g
    im = Image.fromarray((np.broadcast_to(bg, (src.size[1], src.size[0], 3)) * 255).astype(np.uint8)).convert('RGBA')
    im.alpha_composite(src)
    im = im.convert('RGB').crop((66, 28, 254, 216)).resize((n, n), Image.LANCZOS)
    im = im.quantize(colors=22, method=Image.Quantize.MEDIANCUT, dither=Image.Dither.NONE).convert('RGB')
    a = desat(to_arr(im), 0.8)
    return np.clip(a * (1 + speck(n, n, rng, 0.12)[..., None]), 0, 1)


def compose8(biome, theme, seed):
    rng = np.random.default_rng(seed)
    terr, M = (forest7 if biome == 'forest' else desert7)(rng)
    units = F7 if biome == 'forest' else D7
    world, glow = V3.draw_world3(terr, [], units)
    world = world + blur(glow, 2) * 0.12 + blur(glow, 7) * 0.18
    wim = to_img(world)
    d = ImageDraw.Draw(wim)
    for u in units:
        if u[4] == 'sel':
            x, y = u[2], u[3] - V3.HP_DY
            d.rectangle([x - 8, y, x + 8, y + 3], fill='#1a120c')
            d.rectangle([x - 7, y + 1, x + 4, y + 2], fill='#62c048')
    px, py = (300, 300) if biome == 'forest' else (470, 330)
    d.polygon([(px, py), (px, py + 11), (px + 3, py + 8), (px + 8, py + 8)], fill='#f0e6c4', outline='#2a1a0c')
    world = np.pad(to_arr(wim), ((H - VH, 0), (0, 0), (0, 0)), mode='reflect')   # map now fills the full height
    frame = np.zeros((H, W, 3), np.float32)
    world[H - VH] = world[H - VH + 1]            # drop the lit seam row left by the edge relief
    frame[:, :VW] = world

    T, C = TH8[theme], CONTENT[theme]
    team = theme
    hr = np.random.default_rng(seed + 31)
    hud = Hud(frame, T, hr)

    # --- centred top bar (centred on the map view), with the round mission timer on its right end
    BX0, BX1, BH = 132, 598, 22
    frame[BH:BH + 3, BX0:BX1] *= 0.6
    hud.panel((BX0, 0, BX1, BH), 'body')
    hud.panel((BX0 + 6, 3, BX0 + 82, 18))
    hud.panel((BX0 + 86, 3, BX0 + 166, 18))
    hud.icon('gem', BX0 + 306, 11, 0.75, '#e0a23a')
    hud.icon('bolt', BX0 + 354, 11, 0.75, '#6ea6dc')

    # --- hero portrait, always visible top-left
    frame[8:70, 8:56] *= 0.6
    hud.panel((5, 5, 53, 67), 'body')
    hud.pic(9, 9, hero_pic(team, T, hr))
    hud.boxes.append(([9, 9, 49, 49], 'line'))

    # --- sidebar
    hud.fill((SBX, 0, W, H), T['body'])
    hud.panel((SBX + 5, 8, SBX + 14, 152))                                  # power bar
    pfill = 0.68
    py0 = int(152 - 142 * pfill)
    frame[py0:151, SBX + 6:SBX + 13] = ramp(np.clip(0.5 + speck(151 - py0, 7, hr, 0.9), 0, 0.999),
                                            ['#2c5c94', '#3a70ac', '#4a86c4'])
    mmx, mmy = SBX + 22, 8
    mm = desat(minimap(biome, np.random.default_rng(seed + 3)), 0.55)
    hud.pic(mmx, mmy, mm)
    hud.boxes.append(([mmx, mmy, mmx + mm.shape[1], mmy + mm.shape[0]], 'line'))
    tabs = [(SBX + 5 + i * 41, 158, SBX + 43 + i * 41, 180) for i in range(5)]
    for i, b in enumerate(tabs):
        hud.panel(b, 'acc' if i == C['tab'] else 'inset', 'hi' if i == C['tab'] else 'line')
        hud.icon(('castle', 'tankic', 'helm', 'crown', 'cog')[i], (b[0] + b[2]) / 2, 169, 0.85,
                 T['text'] if i == C['tab'] else T['dim'])
    hud.panel((SBX + 5, 186, W - 7, 284))                                   # preview
    sel_kind = C['cells'][C['sel']][1]
    hud.pic(SBX + 7, 188, item_pic(sel_kind, team, 198, 52, C, hr, big=True))
    hud.boxes.append(([SBX + 7, 188, SBX + 205, 240], 'line'))
    cells = []
    for i in range(6):                                                      # build grid 3 x 2
        cx0, cy0 = SBX + 5 + (i % 3) * 68, 290 + (i // 3) * 50
        box = (cx0, cy0, cx0 + 66, cy0 + 48)
        cells.append(box)
        if i < len(C['cells']):
            hud.panel(box, 'inset', 'hi' if i == C['sel'] else 'line')
            hud.pic(cx0 + 2, cy0 + 2, item_pic(C['cells'][i][1], team, 62, 30, C, hr))
        else:
            hud.panel(box, 'inset', 'line')
            frame[cy0 + 1:cy0 + 47, cx0 + 1:cx0 + 65] *= 0.75
            hud.icon('lock', cx0 + 33, cy0 + 20, 0.8, T['dim'])
    hud.panel((SBX + 5, 394, W - 7, 440))                                   # build queue
    hud.pic(SBX + 9, 408, item_pic(C['queue'][2], team, 34, 28, C, hr))
    hud.boxes.append(([SBX + 9, 408, SBX + 43, 436], 'line'))
    for i in range(2):
        hud.panel((SBX + 160 + i * 23, 410, SBX + 180 + i * 23, 434))
    cmds = [(SBX + 5 + i * 51, 446, SBX + 53 + i * 51, 484) for i in range(4)]
    for i, b in enumerate(cmds):
        hud.panel(b, 'acc')
        hud.icon(('move', 'stop', 'shield', 'form')[i], (b[0] + b[2]) / 2, 465, 1.15)
    hud.panel((SBX + 5, 490, W - 7, 534))                                   # selection strip
    hud.pic(SBX + 9, 494, scene_pic(17, 18, C['uground'], [(f'infs_{team}', 7, 8, 13)], hr, 2))
    hud.boxes.append(([SBX + 9, 494, SBX + 43, 530], 'line'))

    im = to_img(frame)
    d = ImageDraw.Draw(im)
    d.fontmode = '1'
    hud.borders(d)
    tx, dim, sh, hi = T['text'], T['dim'], T['lo'], T['hi']
    d.line([SBX, 0, SBX, H], fill=T['lo'])
    d.line([SBX + 1, 0, SBX + 1, H], fill=T['line'])
    d.ellipse([BX1 - 24, 0, BX1 + 16, 40], fill=T['inset'][1], outline=T['lo'])
    d.ellipse([BX1 - 23, 1, BX1 + 15, 39], outline=T['line'])
    d.ellipse([BX1 - 20, 4, BX1 + 12, 36], outline=T['lo'])
    text(d, BX1 - 4, 14, '00:42' if theme == 'blue' else '00:17', F_B11, tx, sh, 'ma')
    text(d, BX0 + 44, 4, 'Objectives', F_S9, tx, sh, 'ma')
    text(d, BX0 + 126, 4, 'Menu  [Esc]', F_S9, tx, sh, 'ma')
    text(d, BX0 + 176, 4, 'THE FIRST CLAIM', F_C10, hi, sh)
    text(d, BX0 + 316, 4, '340', F_S10, tx, sh)
    text(d, BX0 + 364, 4, '14 / 20', F_S10, tx, sh)
    d.rectangle([9, 52, 48, 56], fill='#101410')                             # hero health and energy
    d.rectangle([10, 53, 40, 55], fill='#4f9a3c')
    d.rectangle([9, 59, 48, 63], fill='#101418')
    d.rectangle([10, 60, 32, 62], fill='#3f78c0')
    for k in range(1, 8):                                                    # power bar ticks
        d.line([SBX + 6, 152 - k * 18, SBX + 8, 152 - k * 18], fill=T['lo'])
    pv = C['preview']
    text(d, SBX + 9, 242, pv[0], F_B11, tx, sh)
    text(d, W - 11, 243, pv[1], F_S9, hi, sh, 'ra')
    d.line([SBX + 8, 256, W - 10, 256], fill=T['line'])
    text(d, SBX + 9, 258, pv[2], F_S9, dim)
    text(d, SBX + 9, 269, pv[3], F_S9, dim)
    for i, box in enumerate(cells):
        label = C['cells'][i][0] if i < len(C['cells']) else 'Locked'
        text(d, (box[0] + box[2]) // 2, box[1] + 35, label, F_S9, tx if i < len(C['cells']) else dim, sh, 'ma')
    text(d, SBX + 9, 396, 'Build Queue', F_S10, hi, sh)
    text(d, SBX + 49, 408, C['queue'][0], F_S9, tx, sh)
    d.rectangle([SBX + 49, 424, SBX + 153, 432], fill=T['lo'])
    d.rectangle([SBX + 50, 425, int(SBX + 50 + 102 * C['queue'][1]), 431], fill='#4f9a3c')
    d.line([SBX + 50, 425, int(SBX + 50 + 102 * C['queue'][1]), 425], fill='#7fc468')
    text(d, SBX + 49, 492, T['name'], F_B11, tx, sh)
    text(d, W - 11, 494, T['sub'], F_S9, dim, None, 'ra')
    d.rectangle([SBX + 49, 510, W - 11, 517], fill=T['lo'])
    d.rectangle([SBX + 50, 511, SBX + 50 + 112, 516], fill='#4f9a3c')
    text(d, SBX + 49, 520, 'Health  45 / 60', F_S9, dim)
    im.save(f'{OUT}/v8_{biome}_native.png')
    im.resize((W * 2, H * 2), Image.NEAREST).save(f'{OUT}/v8_{biome}.png')
    print('saved', biome)


if __name__ == '__main__':
    if 'forest' in WHICH:
        compose8('forest', 'blue', 11)
    if 'desert' in WHICH:
        compose8('desert', 'red', 23)
