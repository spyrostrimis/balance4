# Composes Balance mock-up screenshots from Blender-rendered sprites + procedural terrain/UI.
# Run: python compose.py <raw_sprite_dir> <out_dir> [scene ...]
import sys, os, math
import numpy as np
from PIL import Image, ImageDraw, ImageFont, ImageFilter

RAW, OUT = sys.argv[1], sys.argv[2]
WANT = set(sys.argv[3:])
os.makedirs(OUT, exist_ok=True)

T = 32                       # tile size in px
MW, MH = 60, 45              # map size in tiles
SW, SH = 640, 360            # native screen
VW, VH = 512, 342            # map viewport (top bar 18 px, sidebar 128 px)
SCALE = 3

FACTIONS = {                 # name: (hue deg, sat mul, val mul, ui rgb, title)
    'assembly': (44, 0.92, 1.00, (255, 196, 46), 'THE ASSEMBLY'),
    'drift': (268, 0.78, 1.00, (170, 104, 255), 'THE DRIFT'),
    'kiln': (6, 0.95, 0.96, (240, 62, 40), 'THE KILN'),
}
BSIZE = {'hq': (2, 2), 'refinery': (3, 2), 'reactor': (2, 2), 'barracks': (2, 2), 'factory': (3, 2),
         'silo': (2, 2), 'radar': (2, 2), 'turret': (1, 1)}

B4 = (np.array([[0, 8, 2, 10], [12, 4, 14, 6], [3, 11, 1, 9], [15, 7, 13, 5]], np.float32) + 0.5) / 16


def bayer(h, w):
    return np.tile(B4, (h // 4 + 1, w // 4 + 1))[:h, :w]


def hexc(s):
    return np.array([int(s[i:i + 2], 16) for i in (1, 3, 5)], np.float32) / 255


def hex8(s):
    return tuple(int(s[i:i + 2], 16) for i in (1, 3, 5))


def smooth(a, e0, e1):
    t = np.clip((a - e0) / (e1 - e0), 0, 1)
    return t * t * (3 - 2 * t)


def blur(a, r):
    im = Image.fromarray((np.clip(a, 0, 1) * 255).astype(np.uint8))
    return np.asarray(im.filter(ImageFilter.GaussianBlur(r)), np.float32) / 255


def shift(m, dy, dx):
    """Move content down by dy and right by dx (zero fill)."""
    out = np.zeros_like(m)
    h, w = m.shape
    ys, yd = (slice(0, h - dy), slice(dy, h)) if dy >= 0 else (slice(-dy, h), slice(0, h + dy))
    xs, xd = (slice(0, w - dx), slice(dx, w)) if dx >= 0 else (slice(-dx, w), slice(0, w + dx))
    out[yd, xd] = m[ys, xs]
    return out


def vnoise(h, w, cell, rng, octaves=1, cx=None):
    out = np.zeros((h, w), np.float32)
    amp, tot = 1.0, 0.0
    for o in range(octaves):
        cy_ = max(1, int(cell / 2 ** o))
        cx_ = max(1, int((cx or cell) / 2 ** o))
        gh, gw = h // cy_ + 3, w // cx_ + 3
        g = rng.random((gh, gw)).astype(np.float32)
        im = Image.fromarray(g).resize((gw * cx_, gh * cy_), Image.BICUBIC)
        out += np.asarray(im)[cy_:cy_ + h, cx_:cx_ + w] * amp
        tot += amp
        amp *= 0.5
    return np.clip(out / tot, 0, 1)


def voronoi(h, w, cell, rng):
    gh, gw = h // cell + 3, w // cell + 3
    px = ((np.arange(gw)[None, :] + rng.random((gh, gw))) * cell - cell).astype(np.float32)
    py = ((np.arange(gh)[:, None] + rng.random((gh, gw))) * cell - cell).astype(np.float32)
    yy, xx = np.mgrid[0:h, 0:w].astype(np.float32)
    iy = (yy // cell).astype(np.int32) + 1
    ix = (xx // cell).astype(np.int32) + 1
    pv = rng.random((gh, gw)).astype(np.float32)
    f1 = np.full((h, w), 1e9, np.float32)
    f2 = f1.copy()
    val = np.zeros((h, w), np.float32)
    for oy in (-1, 0, 1):
        for ox in (-1, 0, 1):
            d = np.hypot(px[iy + oy, ix + ox] - xx, py[iy + oy, ix + ox] - yy)
            f2 = np.minimum(f2, np.maximum(f1, d))
            val = np.where(d < f1, pv[iy + oy, ix + ox], val)
            f1 = np.minimum(f1, d)
    return f1, f2, val


def ramp(v, cols):
    cols = np.array([hexc(c) for c in cols])
    n = len(cols) - 1
    t = np.clip(v, 0, 1) * n
    i = np.minimum(t.astype(np.int32), n - 1)
    f = (t - i)[..., None]
    return cols[i] * (1 - f) + cols[i + 1] * f


def quant(v, levels, by):
    return np.floor(np.clip(v, 0, 1) * levels + by) / levels


# ---------------------------------------------------------------- sprites ---
_cache = {}


def sprite(name, d=0, faction='assembly'):
    key = (name, d, faction)
    if key in _cache:
        return _cache[key]
    raw = Image.open(os.path.join(RAW, f"{name}_{d:02d}.png")).convert('RGBA')
    n = raw.width // 4
    a = np.asarray(raw.resize((n, n), Image.LANCZOS)).copy()
    alpha = np.where(a[..., 3] >= 100, 255, 0).astype(np.uint8)
    rgb = Image.fromarray(a[..., :3])
    hsv = np.asarray(rgb.convert('HSV')).astype(np.float32)
    Hh, S, V = hsv[..., 0], hsv[..., 1], hsv[..., 2]
    em = ((Hh > 108) & (Hh < 142) & (S > 70) & (V > 135)) | ((Hh > 12) & (Hh < 42) & (V > 185) & (S > 45))
    key_m = (np.abs(Hh - 212.5) < 28) & (S > 36)
    fh, sm, vm = FACTIONS[faction][:3]
    h2 = np.where(key_m, fh / 360 * 255, Hh)
    s2 = np.where(key_m, np.clip(S * sm, 0, 255), S)
    v2 = np.where(key_m, np.clip(V * vm, 0, 255), V)
    out = Image.merge('HSV', [Image.fromarray(c.astype(np.uint8)) for c in (h2, s2, v2)]).convert('RGB')
    out = out.filter(ImageFilter.UnsharpMask(radius=1, percent=60, threshold=0))
    o = np.dstack([np.asarray(out), alpha])
    if name not in BSIZE or name == 'turret':
        grown = np.asarray(Image.fromarray(alpha).filter(ImageFilter.MaxFilter(3)))
        edge = (grown > 0) & (alpha == 0)
        o[edge] = (9, 11, 17, 255)
    emis = np.asarray(out).astype(np.float32) * (em & (alpha > 0))[..., None]
    sh = Image.open(os.path.join(RAW, f"{name}_{d:02d}_sh.png")).convert('RGBA').resize((n, n), Image.LANCZOS)
    sh = sh.getchannel('A').point(lambda v: int(v * 0.62))
    res = (Image.fromarray(o, 'RGBA'), Image.fromarray(emis.astype(np.uint8)), sh)
    _cache[key] = res
    return res


# ---------------------------------------------------------------- world -----
class World:
    def __init__(self, seed):
        self.rng = np.random.default_rng(seed)
        self.stone = np.zeros((MH, MW), np.float32)
        self.lumen = np.zeros((MH, MW), np.float32)
        self.expl = np.zeros((MH, MW), np.float32)
        self.blips = []          # (tx, ty, w, h, faction) extra minimap marks

    def _ell(self, arr, cx, cy, rx, ry, val):
        yy, xx = np.mgrid[0:MH, 0:MW]
        m = ((xx + 0.5 - cx) / rx) ** 2 + ((yy + 0.5 - cy) / ry) ** 2 <= 1
        arr[m] = val

    def mesa(self, cx, cy, rx, ry, val=1.0):
        self._ell(self.stone, cx, cy, rx, ry, val)

    def rect(self, x, y, w, h, val=1.0):
        self.stone[max(0, int(y)):int(y + h), max(0, int(x)):int(x + w)] = val

    def field(self, cx, cy, rx, ry, val=1.0):
        self._ell(self.lumen, cx, cy, rx, ry, val)

    def explore(self, cx, cy, rx, ry):
        self._ell(self.expl, cx, cy, rx, ry, 1.0)

    def scatter(self, keep):
        """Random mesas / fields outside the keep-out rect (x0,y0,x1,y1), for minimap variety."""
        x0, y0, x1, y1 = keep
        n = vnoise(MH, MW, 7, self.rng, 2)
        l = vnoise(MH, MW, 6, self.rng, 2)
        out = np.ones((MH, MW), bool)
        out[max(0, y0):y1, max(0, x0):x1] = False
        self.stone[out & (n > 0.6)] = 1
        self.lumen[out & (l > 0.66) & (n <= 0.6)] = 1

    def build(self):
        rng = self.rng
        H, W = MH * T, MW * T
        by = bayer(H, W)
        up = lambda a: np.kron(a, np.ones((T, T), np.float32))
        # --- masks
        sf = blur(up(self.stone), 9) + (vnoise(H, W, 14, rng, 2) - 0.5) * 0.42
        stone = sf > 0.5
        # --- glass
        g = 0.18 + 0.62 * vnoise(H, W, 170, rng, 3) + (rng.random((H, W)).astype(np.float32) - 0.5) * 0.05
        big = max(H, W) * 2
        st = Image.fromarray(vnoise(big, big, 5, rng, 1, cx=260)).rotate(-27, Image.BILINEAR)
        st = np.asarray(st)[big // 2 - H // 2: big // 2 - H // 2 + H, big // 2 - W // 2: big // 2 - W // 2 + W]
        g += 0.22 * smooth(st, 0.6, 0.85)
        f1, f2, fv = voronoi(H, W, 46, rng)
        crack = (f2 - f1) < 1.3
        g = g * 0.8 + (fv - 0.5) * 0.24
        g = g - 0.25 * crack + 0.2 * shift(crack, 1, 1)
        glass = ramp(quant(g, 14, by), ['#04050a', '#090c17', '#0f1526', '#17213a', '#213152', '#2e456e'])
        # --- lumen
        L = np.clip(blur(up(self.lumen), 13) * (0.45 + 1.1 * vnoise(H, W, 44, rng, 2)), 0, 1) * (~stone)
        f1, f2, _ = voronoi(H, W, 17, rng)
        e = f2 - f1
        patch = vnoise(H, W, 26, rng, 2)
        vein = (e < 0.55 + 1.0 * L) & (L > 0.16) & (patch < 0.12 + 0.62 * L)
        core = (e < 0.8 * L) & (L > 0.5) & (patch < 0.05 + 0.5 * L)
        tint = (0.5 * smooth(L, 0.1, 0.8))[..., None]
        glass = glass * (1 - tint) + hexc('#0b3f44') * tint
        glass[vein] = hexc('#1fcdb8')
        glass[core] = hexc('#c4fff2')
        emis = np.zeros((H, W, 3), np.float32)
        emis += (L * 0.05)[..., None] * hexc('#30ffe0')
        emis[vein] = hexc('#1fcdb8') * 0.5
        emis[core] = hexc('#c4fff2')
        # crystals
        ys, xs = np.nonzero((L > 0.4) & (rng.random((H, W)) < 0.0022))
        self.crystals = list(zip(xs.tolist(), ys.tolist()))
        # --- stone
        s = 0.34 + 0.5 * vnoise(H, W, 90, rng, 4) + (rng.random((H, W)).astype(np.float32) - 0.5) * 0.10
        f1, f2, fv = voronoi(H, W, 52, rng)
        scr = (f2 - f1) < 1.2
        s = s + (fv - 0.5) * 0.2
        s = s - 0.24 * scr + 0.12 * shift(scr, 1, 1)
        strata = vnoise(H, W, 9, rng, 2, cx=140)
        s = s - 0.10 * (strata > 0.62)
        peb = rng.random((H, W)) < 0.004
        s = s - 0.25 * peb + 0.2 * shift(peb, -1, -1)
        rock = ramp(quant(s, 9, by), ['#55514f', '#726d6a', '#8f8984', '#aaa39d', '#c6bfb7'])
        rgb = np.where(stone[..., None], rock, glass)
        # rims and cliffs (light from the west-north-west)
        hi = stone & (~shift(stone, 2, 0) | ~shift(stone, 0, 2))
        rgb[hi] = rgb[hi] * 0.35 + hexc('#e9e3d8') * 0.65
        col_n = (rng.random(W).astype(np.float32) - 0.5)[None, :] * 0.12
        for k in range(8, 0, -1):
            band = stone & ~shift(stone, -k, 0)
            v = 0.16 + 0.05 * k + col_n
            rgb[band] = (ramp(np.broadcast_to(v, (H, W)), ['#1b1917', '#4a443f', '#6d655d']))[band]
        east = stone & ~shift(stone, 0, -4) & shift(stone, -8, 0)
        rgb[east] = rgb[east] * 0.3 + hexc('#3a3531') * 0.7
        cast = blur((shift(stone, 9, 11) & ~stone).astype(np.float32), 2.0)
        rgb *= (1 - 0.6 * cast * (~stone))[..., None]
        emis *= (1 - 0.6 * cast)[..., None]
        emis[stone] = 0
        self.stone_px = stone
        self.ground = Image.fromarray((np.clip(rgb, 0, 1) * 255).astype(np.uint8))
        self.gemis = Image.fromarray((np.clip(emis, 0, 1) * 255).astype(np.uint8))
        self.shroud = 1 - smooth(blur(up(self.expl), 13), 0.3, 0.7)
        d = ImageDraw.Draw(self.ground)
        de = ImageDraw.Draw(self.gemis)
        for (x, y) in self.crystals:
            r = int(rng.integers(2, 5))
            pts = [(x, y - r - 1), (x + r - 1, y), (x, y + r), (x - r + 1, y)]
            d.polygon(pts, fill=hex8('#35e6cf'))
            d.polygon([(x, y - r - 1), (x, y + r), (x - r + 1, y)], fill=hex8('#d6fff6'))
            de.polygon(pts, fill=hex8('#35e6cf'))


# ---------------------------------------------------------------- view ------
def slab_tile(rng):
    a = np.full((T, T, 3), hexc('#4a5361'), np.float32) + (rng.random((T, T, 1)).astype(np.float32) - 0.5) * 0.05
    a[0, :] = a[:, 0] = hexc('#6f7b8d')
    a[-1, :] = a[:, -1] = hexc('#262b34')
    a[1, 1:-1] = a[1:-1, 1] = hexc('#596373')
    a[15:17, 2:-2] *= 0.82
    a[2:-2, 15:17] *= 0.82
    for (y, x) in ((4, 4), (4, 27), (27, 4), (27, 27)):
        a[y, x] = hexc('#8d99ab')
        a[y + 1, x + 1] = hexc('#20242c')
    return Image.fromarray((np.clip(a, 0, 1) * 255).astype(np.uint8))


class View:
    def __init__(self, world, cam_tx, cam_ty, seed=1):
        self.w = world
        self.cx, self.cy = int(cam_tx * T), int(cam_ty * T)
        box = (self.cx, self.cy, self.cx + VW, self.cy + VH)
        self.img = world.ground.crop(box)
        self.emis = world.gemis.crop(box)
        self.rng = np.random.default_rng(seed)
        self.overlay = []        # deferred draw calls (after shroud)
        self.shadows = Image.new('L', (VW, VH), 0)

    def p(self, tx, ty):
        return tx * T - self.cx, ty * T - self.cy

    def slab(self, tx, ty, w=1, h=1):
        for j in range(h):
            for i in range(w):
                x, y = self.p(tx + i, ty + j)
                self.img.paste(slab_tile(self.rng), (int(x), int(y)))
                self.emis.paste((0, 0, 0), (int(x), int(y), int(x) + T, int(y) + T))

    def _paste(self, im, em, x, y, alpha=None):
        pos = (int(round(x - im.width / 2)), int(round(y - im.height / 2)))
        mask = im.getchannel('A') if alpha is None else im.getchannel('A').point(lambda v: int(v * alpha))
        self.img.paste(im.convert('RGB'), pos, mask)
        if em is not None:
            self.emis.paste(em, pos, mask)

    def shadow(self, name, d, x, y):
        sh = sprite(name, d)[2]
        pos = (int(round(x - sh.width / 2)), int(round(y - sh.height / 2)))
        tmp = Image.new('L', (VW, VH), 0)
        tmp.paste(sh, pos)
        self.shadows = Image.fromarray(np.maximum(np.asarray(self.shadows), np.asarray(tmp)))

    def apply_shadows(self):
        self.img.paste((4, 5, 10), (0, 0), self.shadows)
        self.emis.paste((0, 0, 0), (0, 0), self.shadows.point(lambda v: int(v * 0.7)))

    def draw(self, ents):
        """ents: dicts with s(prite), f(action), x,y (tile centre) or tx,ty for buildings, d, hp, sel, wreck."""
        for e in ents:
            if e['s'] in BSIZE and 'tx' in e:
                w, h = BSIZE[e['s']]
                e['x'], e['y'] = e['tx'] + w / 2, e['ty'] + h / 2
                if not e.get('ghost'):
                    self.slab(e['tx'], e['ty'], w, h)
        for e in ents:
            if not e.get('ghost'):
                self.shadow(e['s'], e.get('d', 0), *self.p(e['x'], e['y']))
        self.apply_shadows()
        for e in sorted(ents, key=lambda e: (e['s'] not in BSIZE, e['y'])):
            im, em, _ = sprite(e['s'], e.get('d', 0), e['f'])
            x, y = self.p(e['x'], e['y'])
            if e.get('ghost'):
                w, h = BSIZE[e['s']]
                gx, gy = self.p(e['tx'], e['ty'])
                ov = Image.new('RGBA', (w * T, h * T), (60, 255, 150, 70))
                ImageDraw.Draw(ov).rectangle((0, 0, w * T - 1, h * T - 1), outline=(120, 255, 190, 220))
                for i in range(1, w):
                    ImageDraw.Draw(ov).line((i * T, 0, i * T, h * T), fill=(120, 255, 190, 110))
                for j in range(1, h):
                    ImageDraw.Draw(ov).line((0, j * T, w * T, j * T), fill=(120, 255, 190, 110))
                self.img.paste(ov.convert('RGB'), (int(gx), int(gy)), ov.getchannel('A'))
                self._paste(im, None, x, y, alpha=0.6)
                continue
            if e.get('wreck'):
                a = np.asarray(im).astype(np.float32)
                gr = a[..., :3].mean(axis=2, keepdims=True)
                a[..., :3] = gr * 0.28 + 8
                im = Image.fromarray(a.astype(np.uint8), 'RGBA')
                em = Image.new('RGB', im.size, 0)
            self._paste(im, em, x, y)
            if e.get('sel') or e.get('hp') is not None:
                self.overlay.append(('bar', x, y, e.get('hp', 1.0), e.get('sel', False), e['s']))

    # ---- effects
    def _blob(self, r, rough=0.8):
        size = int(r * 2.8) + 6
        c = size / 2
        yy, xx = np.mgrid[0:size, 0:size]
        d = np.hypot(xx - c + .5, yy - c + .5)
        n = vnoise(size, size, max(2, int(r / 2.2)), self.rng, 2)
        return d + (n - 0.5) * r * rough * 2, size

    def explosion(self, tx, ty, r):
        x, y = self.p(tx, ty)
        rad, size = self._blob(r)
        arr = np.zeros((size, size, 4), np.uint8)
        for frac, col in [(1.0, '#4a1a10'), (0.88, '#b83414'), (0.72, '#ee7016'), (0.54, '#ffae2a'),
                          (0.36, '#ffe27a'), (0.18, '#fffbe6')]:
            m = rad < r * frac
            arr[m, :3] = hex8(col)
            arr[m, 3] = 255
        im = Image.fromarray(arr, 'RGBA')
        self._paste(im, im.convert('RGB'), x, y)
        for _ in range(int(r)):
            a, dd = self.rng.random() * 6.28, r * (0.9 + self.rng.random() * 0.9)
            sx, sy = int(x + math.cos(a) * dd), int(y + math.sin(a) * dd)
            if 0 <= sx < VW and 0 <= sy < VH:
                self.img.putpixel((sx, sy), hex8('#ffd45e'))
                self.emis.putpixel((sx, sy), hex8('#ffd45e'))

    def smoke(self, tx, ty, r, n=4, drift=(5, -8), dark=True):
        x, y = self.p(tx, ty)
        for i in range(n):
            rr = r * (0.7 + 0.25 * i)
            rad, size = self._blob(rr, 0.6)
            arr = np.zeros((size, size, 4), np.uint8)
            by = bayer(size, size)
            dens = 0.92 - 0.17 * i
            for frac, col in [(1.0, '#22242a' if dark else '#555a66'), (0.62, '#3b3e47' if dark else '#7a808e')]:
                m = (rad < rr * frac) & (by < dens)
                arr[m, :3] = hex8(col)
                arr[m, 3] = 255
            im = Image.fromarray(arr, 'RGBA')
            self._paste(im, Image.new('RGB', im.size, 0), x + drift[0] * i, y + drift[1] * i)

    def scorch(self, tx, ty, r, crater=False):
        x, y = self.p(tx, ty)
        rad, size = self._blob(r, 0.7)
        by = bayer(size, size)
        a = np.clip(1.25 - rad / r, 0, 1)
        m = (a > by * 0.9)
        arr = np.zeros((size, size, 4), np.uint8)
        arr[m, 3] = 150
        im = Image.fromarray(arr, 'RGBA')
        self._paste(im, Image.new('RGB', im.size, 0), x, y)
        if crater:
            d = ImageDraw.Draw(self.img)
            rr = r * 0.42
            d.ellipse((x - rr, y - rr * 0.8, x + rr, y + rr * 0.8), fill=(10, 10, 14))
            d.arc((x - rr, y - rr * 0.8, x + rr, y + rr * 0.8), 10, 130, fill=(118, 112, 104))
            d.arc((x - rr, y - rr * 0.8, x + rr, y + rr * 0.8), 200, 300, fill=(0, 0, 0))

    def tip(self, tx, ty, d, length=17, up=6):
        a = d * math.pi / 8
        x, y = self.p(tx, ty)
        return x + math.sin(a) * length, y - math.cos(a) * length - up

    def flash(self, x, y, r=4):
        for dr, col in ((r, '#ff9a2a'), (r - 1.5, '#ffe27a'), (r - 3, '#ffffff')):
            if dr > 0:
                for dd in (ImageDraw.Draw(self.img), ImageDraw.Draw(self.emis)):
                    dd.polygon([(x, y - dr - 1), (x + dr * 0.5, y - dr * 0.5), (x + dr + 1, y), (x + dr * 0.5, y + dr * 0.5),
                                (x, y + dr + 1), (x - dr * 0.5, y + dr * 0.5), (x - dr - 1, y), (x - dr * 0.5, y - dr * 0.5)],
                               fill=hex8(col))

    def line(self, p0, p1, col, width=1, emis=True):
        ImageDraw.Draw(self.img).line((*p0, *p1), fill=hex8(col), width=width)
        if emis:
            ImageDraw.Draw(self.emis).line((*p0, *p1), fill=hex8(col), width=width)

    def tracer(self, p0, p1, t=0.6, n=7):
        x = p0[0] + (p1[0] - p0[0]) * t
        y = p0[1] + (p1[1] - p0[1]) * t
        L = math.hypot(p1[0] - p0[0], p1[1] - p0[1])
        ux, uy = (p1[0] - p0[0]) / L, (p1[1] - p0[1]) / L
        self.line((x - ux * n, y - uy * n), (x, y), '#ffb030', 1)
        self.line((x - ux * 2, y - uy * 2), (x, y), '#fff6c8', 2)

    def beam(self, p0, p1, col='#30f0d8'):
        self.line(p0, p1, col, 3)
        self.line(p0, p1, '#eafffb', 1)
        self.flash(p1[0], p1[1], 5)
        ImageDraw.Draw(self.emis).ellipse((p1[0] - 6, p1[1] - 6, p1[0] + 6, p1[1] + 6), fill=hex8(col))

    def missile(self, p0, p1, t=0.7):
        x = p0[0] + (p1[0] - p0[0]) * t
        y = p0[1] + (p1[1] - p0[1]) * t - math.sin(t * math.pi) * 14
        d = ImageDraw.Draw(self.img)
        steps = max(4, int(t * 40))
        prev = None
        for i in range(steps + 1):
            tt = t * i / steps
            sx = p0[0] + (p1[0] - p0[0]) * tt
            sy = p0[1] + (p1[1] - p0[1]) * tt - math.sin(tt * math.pi) * 14
            if prev and i > steps * 0.25:
                c = int(60 + 150 * (i / steps) ** 2)
                d.line((*prev, sx, sy), fill=(c, c, c + 10), width=2 if i > steps * 0.6 else 1)
            prev = (sx, sy)
        self.line((x - 3, y + 1), (x, y), '#ffcc55', 2)
        d.rectangle((x, y - 1, x + 2, y), fill=(240, 240, 240))

    def lightning(self, tx, ty, height=150, lean=30, col='#d9d0ff'):
        x1, y1 = self.p(tx, ty)
        pts = [(x1 + lean, y1 - height)]
        n = 9
        for i in range(1, n):
            t = i / n
            pts.append((x1 + lean * (1 - t) + self.rng.normal() * 9, y1 - height * (1 - t)))
        pts.append((x1, y1))
        for dd in (ImageDraw.Draw(self.img), ImageDraw.Draw(self.emis)):
            dd.line(pts, fill=hex8('#7f6cff'), width=3)
            dd.line(pts, fill=hex8(col), width=1)
        b = pts[4]
        br = [b, (b[0] - 14, b[1] + 16), (b[0] - 18, b[1] + 34), (b[0] - 30, b[1] + 44)]
        self.line(br[0], br[1], col)
        self.line(br[1], br[2], col)
        self.line(br[2], br[3], '#7f6cff')
        self.flash(x1, y1, 6)
        ImageDraw.Draw(self.emis).ellipse((x1 - 12, y1 - 8, x1 + 12, y1 + 8), fill=hex8('#8f7cff'))

    def soldiers(self, tx, ty, faction, n=3):
        x, y = self.p(tx, ty)
        col = FACTIONS[faction][3]
        d = ImageDraw.Draw(self.img)
        offs = [(0, 0), (7, 3), (-6, 4), (3, 9), (-3, -6)][:n]
        for ox, oy in offs:
            px, py = int(x + ox), int(y + oy)
            d.rectangle((px - 1, py + 1, px + 3, py + 1), fill=(8, 9, 14))
            d.rectangle((px, py - 2, px, py), fill=(28, 30, 36))
            d.rectangle((px + 2, py - 2, px + 2, py), fill=(28, 30, 36))
            d.rectangle((px - 1, py - 6, px + 2, py - 3), fill=col)
            d.rectangle((px - 1, py - 6, px - 1, py - 3), fill=tuple(min(255, int(c * 1.25) + 20) for c in col))
            d.rectangle((px, py - 8, px + 1, py - 7), fill=(232, 196, 160))
            d.line((px + 3, py - 6, px + 5, py - 8), fill=(20, 20, 24))

    def tint(self, color, strength, cx, cy, rx, ry):
        """Darken/tint an elliptical region (storm front)."""
        yy, xx = np.mgrid[0:VH, 0:VW]
        x, y = self.p(cx, cy)
        m = np.clip(1.3 - np.sqrt(((xx - x) / (rx * T)) ** 2 + ((yy - y) / (ry * T)) ** 2), 0, 1)[..., None] * strength
        a = np.asarray(self.img).astype(np.float32)
        a = a * (1 - m) + np.array(color, np.float32) * m
        self.img = Image.fromarray(a.astype(np.uint8))

    def rain(self, cx, cy, rx, ry, n=260):
        x0, y0 = self.p(cx, cy)
        d = ImageDraw.Draw(self.img)
        de = ImageDraw.Draw(self.emis)
        for _ in range(n):
            a, r = self.rng.random() * 6.28, math.sqrt(self.rng.random())
            x, y = x0 + math.cos(a) * r * rx * T, y0 + math.sin(a) * r * ry * T
            L = 3 + self.rng.random() * 5
            c = (150, 170, 230) if self.rng.random() < 0.7 else (220, 235, 255)
            d.line((x, y, x - L * 0.45, y + L), fill=c)
            if c[0] > 200:
                de.line((x, y, x - L * 0.45, y + L), fill=(90, 100, 160))

    # ---- finish
    def finish(self):
        sh = self.w.shroud[self.cy:self.cy + VH, self.cx:self.cx + VW]
        by = bayer(VH, VW)
        m = (sh > by * 0.98) | (sh > 0.97)
        a = np.asarray(self.img).copy()
        e = np.asarray(self.emis).copy()
        a[m] = (2, 3, 8)
        e[m] = 0
        self.img = Image.fromarray(a)
        d = ImageDraw.Draw(self.img)
        for kind, x, y, hp, sel, s in self.overlay:
            big = s in BSIZE and s != 'turret'
            hw = (BSIZE[s][0] * T // 2 - 2) if big else 13
            hh = (BSIZE[s][1] * T // 2 - 2) if big else 13
            x, y = int(x), int(y)
            if sel:
                c = (255, 255, 255)
                for sx in (-1, 1):
                    for sy in (-1, 1):
                        cx_, cy_ = x + sx * hw, y + sy * hh
                        d.line((cx_, cy_, cx_ - sx * 5, cy_), fill=c)
                        d.line((cx_, cy_, cx_, cy_ - sy * 5), fill=c)
            bw = 2 * hw - 4 if big else 18
            bx, byy = x - bw // 2, y - hh - 5
            d.rectangle((bx - 1, byy - 1, bx + bw, byy + 3), fill=(0, 0, 0))
            col = (70, 230, 90) if hp > 0.6 else (245, 200, 50) if hp > 0.3 else (240, 60, 40)
            d.rectangle((bx, byy, bx + max(1, int(bw * hp)) - 1, byy + 2), fill=col)
        em = Image.fromarray(e)
        b = (np.asarray(em.filter(ImageFilter.GaussianBlur(2.5))).astype(np.float32) * 0.42 +
             np.asarray(em.filter(ImageFilter.GaussianBlur(8))).astype(np.float32) * 0.38)
        out = np.clip(np.asarray(self.img).astype(np.float32) + b, 0, 255).astype(np.uint8)
        return Image.fromarray(out)


# ---------------------------------------------------------------- UI --------
F8 = ImageFont.truetype(r"C:\Windows\Fonts\tahoma.ttf", 9)
F8B = ImageFont.truetype(r"C:\Windows\Fonts\tahomabd.ttf", 9)
F7 = ImageFont.truetype(r"C:\Windows\Fonts\tahoma.ttf", 8)
F10B = ImageFont.truetype(r"C:\Windows\Fonts\tahomabd.ttf", 11)
PANEL, PANEL_HI, PANEL_LO, INSET = (26, 31, 41), (62, 74, 96), (7, 9, 13), (10, 13, 19)
TEXT, DIM, CYAN = (206, 214, 226), (118, 130, 148), (53, 226, 204)


def panel(d, x, y, w, h, fill=PANEL):
    d.rectangle((x, y, x + w - 1, y + h - 1), fill=fill)
    d.line((x, y, x + w - 1, y), fill=PANEL_HI)
    d.line((x, y, x, y + h - 1), fill=PANEL_HI)
    d.line((x, y + h - 1, x + w - 1, y + h - 1), fill=PANEL_LO)
    d.line((x + w - 1, y, x + w - 1, y + h - 1), fill=PANEL_LO)


def inset(d, x, y, w, h, fill=INSET):
    d.rectangle((x, y, x + w - 1, y + h - 1), fill=fill)
    d.line((x, y, x + w - 1, y), fill=PANEL_LO)
    d.line((x, y, x, y + h - 1), fill=PANEL_LO)
    d.line((x, y + h - 1, x + w - 1, y + h - 1), fill=PANEL_HI)
    d.line((x + w - 1, y, x + w - 1, y + h - 1), fill=PANEL_HI)


def ctext(d, cx, y, s, font, fill):
    d.text((cx - d.textlength(s, font=font) / 2, y), s, font=font, fill=fill)


def rtext(d, rx, y, s, font, fill):
    d.text((rx - d.textlength(s, font=font), y), s, font=font, fill=fill)


def thumb(name, faction, w, h):
    im = sprite(name, 2 if name not in BSIZE or name == 'turret' else 0, faction)[0]
    im = im.crop(im.getbbox())
    k = min(w / im.width, h / im.height)
    return im.resize((max(1, int(im.width * k)), max(1, int(im.height * k))), Image.LANCZOS)


def minimap(world, view, ents, player):
    mm = np.zeros((MH, MW, 3), np.float32)
    mm[:] = hexc('#141a2b')
    mm[world.lumen > 0.5] = hexc('#1fae9e')
    mm[world.stone > 0.5] = hexc('#8a8177')
    im = Image.fromarray((mm * 255).astype(np.uint8)).resize((MW * 2, MH * 2), Image.NEAREST)
    d = ImageDraw.Draw(im)
    for (tx, ty, w, h, f) in world.blips:
        d.rectangle((tx * 2, ty * 2, (tx + w) * 2 - 1, (ty + h) * 2 - 1), fill=FACTIONS[f][3])
    for e in ents:
        col = FACTIONS[e['f']][3]
        if e['s'] in BSIZE and 'tx' in e:
            w, h = BSIZE[e['s']]
            d.rectangle((e['tx'] * 2, e['ty'] * 2, (e['tx'] + w) * 2 - 1, (e['ty'] + h) * 2 - 1), fill=col)
        else:
            d.rectangle((int(e['x'] * 2) - 1, int(e['y'] * 2) - 1, int(e['x'] * 2), int(e['y'] * 2)), fill=col)
    a = np.asarray(im).copy()
    ex = np.kron(world.expl, np.ones((2, 2))) < 0.5
    a[ex] = (3, 4, 8)
    im = Image.fromarray(a)
    d = ImageDraw.Draw(im)
    x0, y0 = view.cx / T * 2, view.cy / T * 2
    d.rectangle((x0, y0, x0 + VW / T * 2, y0 + VH / T * 2), outline=(255, 255, 255))
    return im


def compose(view_img, world, view, ents, ui):
    player = ui['player']
    acc = FACTIONS[player][3]
    img = Image.new('RGB', (SW, SH), PANEL)
    img.paste(view_img, (0, 18))
    d = ImageDraw.Draw(img)
    d.fontmode = '1'
    # top bar
    panel(d, 0, 0, 512, 18)
    for x, w, s in ((3, 40, 'MENU'), (45, 56, 'COUNSEL')):
        panel(d, x, 2, w, 14, (38, 46, 60))
        ctext(d, x + w / 2, 3, s, F8B, TEXT)
    inset(d, 104, 2, 288, 14)
    d.text((109, 3), ui['msg'], font=F8, fill=ui.get('msgcol', TEXT))
    d.text((398, 3), 'LUMEN', font=F8B, fill=CYAN)
    inset(d, 438, 2, 70, 14)
    rtext(d, 503, 3, ui['credits'], F8B, (232, 255, 250))
    d.line((0, 18, 511, 18), fill=PANEL_LO)
    # sidebar
    panel(d, 512, 0, 128, 360)
    d.rectangle((514, 2, 637, 15), fill=tuple(int(c * 0.28) for c in acc))
    d.line((514, 15, 637, 15), fill=acc)
    ctext(d, 576, 3, FACTIONS[player][4], F8B, acc)
    inset(d, 515, 19, 122, 92)
    img.paste(minimap(world, view, ents, player), (516, 20))
    # the Scales
    d.text((516, 114), 'SCALES', font=F8, fill=DIM)
    inset(d, 557, 115, 80, 9)
    x = 558
    for f, share in ui['scales']:
        w = int(round(78 * share))
        d.rectangle((x, 116, x + w - 1, 122), fill=FACTIONS[f][3])
        x += w
    for t in (1 / 3, 2 / 3):
        d.line((558 + int(78 * t), 115, 558 + int(78 * t), 123), fill=(255, 255, 255))
    # power
    d.text((516, 126), 'POWER', font=F8, fill=DIM)
    inset(d, 557, 127, 80, 9)
    use, cap = ui['power']
    d.rectangle((558, 128, 558 + int(78 * min(1, use / max(cap, use))) - 1, 134),
                fill=(70, 220, 100) if use <= cap else (240, 70, 50))
    d.line((558 + int(78 * cap / max(cap, use)) - 1, 127, 558 + int(78 * cap / max(cap, use)) - 1, 135), fill=TEXT)
    # tabs
    for i, s in enumerate(('BUILD', 'UNITS')):
        on = i == ui.get('tab', 0)
        panel(d, 515 + i * 61, 139, 61, 13, (44, 54, 72) if on else (20, 24, 32))
        ctext(d, 515 + i * 61 + 30, 140, s, F8B if on else F8, acc if on else DIM)
    # build grid
    for i, it in enumerate(ui['build']):
        bx, by_ = 515 + (i % 2) * 61, 154 + (i // 2) * 47
        panel(d, bx, by_, 61, 46, (32, 38, 50))
        inset(d, bx + 2, by_ + 2, 57, 31, (14, 18, 27))
        th = thumb(it['s'], player, 52, 28)
        img.paste(th.convert('RGB'), (bx + 30 - th.width // 2, by_ + 17 - th.height // 2), th.getchannel('A'))
        st = it.get('state')
        if st == 'locked':
            ov = Image.new('RGB', (57, 31), (8, 10, 14))
            img.paste(ov, (bx + 2, by_ + 2), Image.new('L', (57, 31), 170))
        if isinstance(st, float):
            d.rectangle((bx + 3, by_ + 28, bx + 57, by_ + 31), fill=(8, 10, 14))
            d.rectangle((bx + 3, by_ + 28, bx + 3 + int(54 * st), by_ + 31), fill=CYAN)
            ctext(d, bx + 30, by_ + 17, f"{int(st * 100)}%", F8B, (255, 255, 255))
        if st == 'ready':
            d.rectangle((bx + 2, by_ + 2, bx + 58, by_ + 32), outline=CYAN)
            ctext(d, bx + 30, by_ + 21, 'READY', F8B, (255, 255, 255))
        if it.get('n'):
            d.text((bx + 5, by_ + 3), str(it['n']), font=F8B, fill=(255, 255, 255))
        ctext(d, bx + 30, by_ + 35, it['name'], F7, TEXT if st != 'locked' else DIM)
        if st != 'ready' and not isinstance(st, float):
            rtext(d, bx + 57, by_ + 3, str(it['cost']), F8, CYAN if st != 'locked' else DIM)
    # selection panel
    inset(d, 515, 297, 122, 60)
    sel = ui['sel']
    th = thumb(sel['s'], sel.get('f', player), 34, 30)
    inset(d, 518, 300, 40, 34, (20, 25, 36))
    img.paste(th.convert('RGB'), (538 - th.width // 2, 317 - th.height // 2), th.getchannel('A'))
    d.text((562, 300), sel['name'], font=F8B, fill=TEXT)
    d.rectangle((562, 313, 632, 318), fill=(0, 0, 0))
    hp = sel.get('hp', 1.0)
    d.rectangle((563, 314, 563 + int(68 * hp), 317), fill=(70, 230, 90) if hp > 0.6 else (245, 200, 50))
    d.text((562, 321), sel['l1'], font=F8, fill=DIM)
    for i, s in enumerate(sel.get('btns', ())):
        panel(d, 518 + i * 59, 339, 57, 14, (38, 46, 60))
        ctext(d, 518 + i * 59 + 28, 340, s, F8, TEXT)
    # cursor
    cx, cy = ui.get('cursor', (300, 200))
    pts = [(cx, cy), (cx, cy + 11), (cx + 3, cy + 8), (cx + 6, cy + 13), (cx + 8, cy + 12), (cx + 5, cy + 7), (cx + 9, cy + 7)]
    d.polygon(pts, fill=(255, 255, 255), outline=(0, 0, 0))
    return img


def save(img, name):
    img.save(os.path.join(OUT, name + '_native.png'))
    img.resize((SW * SCALE, SH * SCALE), Image.NEAREST).save(os.path.join(OUT, name + '.png'))
    print('saved', name)


def B(s, f, tx, ty, **k):
    return dict(s=s, f=f, tx=tx, ty=ty, **k)


def U(s, f, x, y, d=0, **k):
    return dict(s=s, f=f, x=x, y=y, d=d, **k)


# ---------------------------------------------------------------- scenes ----
def scene_base():
    ox, oy = 20, 15
    w = World(11)
    w.scatter((ox - 4, oy - 4, ox + 21, oy + 16))
    w.rect(ox - 3, oy - 3, 14, 12)
    w.mesa(ox + 11, oy + 1.5, 2.2, 3)
    w.mesa(ox + 3, oy + 9.5, 5, 2.2)
    w.field(ox + 14, oy + 8, 4.2, 3.6)
    w.field(ox + 16.5, oy + 3.5, 2.2, 2.0)
    w.explore(ox + 6, oy + 5, 10.5, 8.5)
    w.explore(ox - 6, oy + 3, 9, 9)
    w.explore(ox + 6, oy + 14, 12, 7)
    w.explore(47, 32, 8, 7)
    w.blips += [(46, 31, 2, 2, 'kiln'), (48, 30, 3, 2, 'kiln'), (45, 33, 2, 2, 'kiln')]
    w.build()
    v = View(w, ox, oy, 3)
    a = 'assembly'
    for (tx, ty, ww, hh) in ((3, 3, 1, 1), (4, 3, 2, 1), (0, 6, 1, 2), (4, 6, 3, 1), (9, 7, 1, 1), (10, 2, 1, 2)):
        v.slab(ox + tx, oy + ty, ww, hh)
    ents = [
        B('hq', a, ox + 1, oy + 1), B('reactor', a, ox + 4, oy + 1), B('reactor', a, ox + 6, oy + 1),
        B('radar', a, ox + 8, oy + 0), B('factory', a, ox + 1, oy + 4), B('barracks', a, ox + 4, oy + 4),
        B('refinery', a, ox + 7, oy + 4), B('silo', a, ox + 1, oy + 7), B('silo', a, ox + 5, oy + 7, ghost=True),
        U('turret', a, ox + 10.5, oy + 2.5, 5), U('turret', a, ox + 9.5, oy + 7.5, 6),
        U('harvester', a, ox + 9.1, oy + 5.55, 12),
        U('harvester', a, ox + 13.3, oy + 7.6, 3, sel=True, hp=0.85),
        U('tank', a, ox + 11.7, oy + 4.2, 4), U('tank', a, ox + 12.4, oy + 5.4, 5),
        U('heavy', a, ox + 11.4, oy + 9.3, 5), U('scout', a, ox + 14.6, oy + 1.6, 2),
        U('siege', a, ox + 3.6, oy + 8.9, 4), U('launcher', a, ox + 4.6, oy + 9.6, 3),
    ]
    v.draw(ents)
    v.soldiers(ox + 4.9, oy + 6.5, a, 4)
    v.soldiers(ox + 8.6, oy + 8.6, a, 3)
    for i in range(5):
        x, y = v.p(ox + 13.3 + v.rng.normal() * 0.35, oy + 7.4 + v.rng.normal() * 0.3)
        v.flash(x, y, 2)
    img = v.finish()
    ui = dict(player=a, msg='Harvester is 62 percent full and harvesting.', credits='1,252',
              scales=(('assembly', 0.36), ('drift', 0.30), ('kiln', 0.34)), power=(110, 150), tab=0,
              build=[dict(s='reactor', name='REACTOR', cost=300), dict(s='refinery', name='REFINERY', cost=400),
                     dict(s='silo', name='SILO', cost=150, state='ready'), dict(s='barracks', name='BARRACKS', cost=300),
                     dict(s='radar', name='RADAR', cost=400), dict(s='turret', name='TURRET', cost=250, state='locked')],
              sel=dict(s='harvester', name='HARVESTER', hp=0.85, l1='Cargo 62%', btns=('HARVEST', 'RETURN')),
              cursor=(207, 268))
    save(compose(img, w, v, ents, ui), 'balance_mock_1_base')


def scene_battle():
    ox, oy = 18, 12
    w = World(23)
    w.scatter((ox - 4, oy - 4, ox + 21, oy + 16))
    w.rect(ox - 3, oy - 3, 12, 9)
    w.mesa(ox + 3, oy + 6.5, 4.5, 1.6)
    w.mesa(ox + 14.5, oy + 10.5, 3, 2.2)
    w.field(ox + 13.5, oy + 1.5, 2.6, 2.2)
    w.explore(ox + 9.5, oy + 6, 11, 8.5)
    w.explore(8, 34, 7, 6)
    w.explore(ox + 4, oy + 17, 14, 8)
    w.explore(ox + 22, oy + 12, 8, 9)
    w.blips += [(6, 33, 2, 2, 'kiln'), (8, 34, 3, 2, 'kiln'), (9, 32, 2, 2, 'kiln'), (ox - 2, oy - 2, 2, 2, 'drift')]
    w.build()
    v = View(w, ox, oy, 5)
    dr, k = 'drift', 'kiln'
    for (tx, ty, ww, hh) in ((3, 2, 1, 2), (4, 3, 1, 1), (7, 2, 1, 1), (3, 5, 2, 1), (8, 5, 1, 1)):
        v.slab(ox + tx, oy + ty, ww, hh)
    for (x, y, r, c) in ((9.8, 3.6, 16, True), (10.9, 6.4, 13, True), (8.9, 6.9, 12, False), (12.2, 4.3, 12, True),
                         (7.6, 5.6, 11, False), (11.6, 8.4, 10, True), (9.6, 5.2, 9, False), (6.2, 2.6, 12, False)):
        v.scorch(ox + x, oy + y, r, c)
    ents = [
        B('barracks', dr, ox + 1, oy + 0), B('reactor', dr, ox + 4, oy + 0), B('reactor', dr, ox + 6, oy + 0),
        B('factory', dr, ox + 5, oy + 3, hp=0.35), B('silo', dr, ox + 1, oy + 3), B('radar', dr, ox + 0, oy + 6),
        U('turret', dr, ox + 8.5, oy + 2.5, 6, hp=0.5), U('turret', dr, ox + 4.5, oy + 5.5, 5),
        U('tank', dr, ox + 8.6, oy + 5.0, 5, hp=0.4), U('tank', dr, ox + 6.4, oy + 6.9, 4),
        U('scout', dr, ox + 9.6, oy + 1.2, 6),
        U('tank', k, ox + 10.7, oy + 5.6, 14, sel=True, hp=0.7), U('tank', k, ox + 11.7, oy + 7.3, 14, sel=True, hp=1.0),
        U('tank', k, ox + 9.9, oy + 8.2, 15, sel=True, hp=0.45), U('heavy', k, ox + 12.8, oy + 5.5, 13, sel=True, hp=0.9),
        U('launcher', k, ox + 13.7, oy + 8.4, 14), U('siege', k, ox + 14.6, oy + 6.6, 13),
        U('scout', k, ox + 12.6, oy + 2.6, 13),
        U('tank', k, ox + 10.3, oy + 3.7, 2, wreck=True), U('tank', dr, ox + 7.5, oy + 8.3, 9, wreck=True),
    ]
    v.draw(ents)
    v.soldiers(ox + 3.3, oy + 2.6, dr, 3)
    v.soldiers(ox + 11.0, oy + 9.5, k, 4)
    # fire & smoke on the factory and wrecks
    v.smoke(ox + 6.0, oy + 3.4, 9, 5)
    v.explosion(ox + 6.1, oy + 3.9, 9)
    v.explosion(ox + 7.2, oy + 4.5, 6)
    v.smoke(ox + 10.3, oy + 3.5, 6, 4)
    v.explosion(ox + 10.3, oy + 3.75, 4)
    v.smoke(ox + 7.5, oy + 8.1, 5, 3)
    # turret beam on the lead tank
    t0 = v.tip(ox + 8.5, oy + 2.5, 6, 18, 8)
    v.beam(t0, v.p(ox + 10.55, oy + 5.35))
    v.flash(*t0, 3)
    # shells
    for (sx, sy, d, tx, ty, t) in ((11.7, 7.3, 14, 8.6, 5.0, 0.55), (12.8, 5.5, 13, 8.5, 2.6, 0.7),
                                   (9.9, 8.2, 15, 6.5, 4.6, 0.35)):
        p0 = v.tip(ox + sx, oy + sy, d)
        v.tracer(p0, v.p(ox + tx, oy + ty), t)
    v.flash(*v.tip(ox + 11.7, oy + 7.3, 14), 4)
    v.flash(*v.tip(ox + 8.6, oy + 5.0, 5), 4)
    v.tracer(v.tip(ox + 8.6, oy + 5.0, 5), v.p(ox + 11.7, oy + 7.3), 0.5)
    v.explosion(ox + 8.75, oy + 4.8, 7)
    v.explosion(ox + 4.6, oy + 5.3, 5)
    # missiles and the siege shell landing
    m0 = v.p(ox + 13.6, oy + 8.1)
    v.missile(m0, v.p(ox + 4.6, oy + 5.4), 0.8)
    v.missile((m0[0] + 4, m0[1] - 3), v.p(ox + 8.5, oy + 2.5), 0.45)
    v.explosion(ox + 3.2, oy + 4.2, 10)
    v.smoke(ox + 3.2, oy + 3.9, 7, 3)
    img = v.finish()
    ui = dict(player=k, msg='Enemy factory under attack.', credits='3,410',
              scales=(('assembly', 0.24), ('drift', 0.31), ('kiln', 0.45)), power=(170, 160), tab=1,
              build=[dict(s='tank', name='TANK', cost=350, state=0.62, n=2), dict(s='heavy', name='BULWARK', cost=600),
                     dict(s='scout', name='SCOUT', cost=150), dict(s='siege', name='SIEGE GUN', cost=550),
                     dict(s='launcher', name='LAUNCHER', cost=450), dict(s='harvester', name='HARVESTER', cost=400)],
              sel=dict(s='tank', name='4 UNITS', hp=0.76, l1='Tank x3, Bulwark', btns=('ATTACK', 'GUARD')),
              cursor=(232, 152), msgcol=(255, 190, 120))
    save(compose(img, w, v, ents, ui), 'balance_mock_2_battle')


def scene_storm():
    ox, oy = 30, 20
    w = World(37)
    w.scatter((ox - 4, oy - 4, ox + 21, oy + 16))
    w.mesa(ox + 1.5, oy + 8.5, 3.0, 2.4)
    w.mesa(ox + 14, oy + 0.3, 2.6, 1.7)
    w.field(ox + 7.5, oy + 5, 6.5, 4.2)
    w.field(ox + 13, oy + 8.5, 3, 2.5)
    w.explore(ox + 7.5, oy + 5.5, 10, 7.2)
    w.explore(ox + 1, oy + 9, 5, 4)
    w.explore(12, 10, 8, 6)
    w.explore(22, 16, 9, 7)
    w.explore(ox + 4, oy + 16, 12, 6)
    w.blips += [(10, 8, 2, 2, 'drift'), (12, 9, 3, 2, 'drift'), (11, 11, 2, 2, 'drift'), (14, 11, 2, 2, 'drift')]
    w.build()
    v = View(w, ox, oy, 9)
    dr, a = 'drift', 'assembly'
    v.tint((34, 22, 80), 0.5, ox + 12.5, oy + 4.5, 5.0, 4.6)
    v.scorch(ox + 11.2, oy + 6.4, 13, True)
    v.scorch(ox + 13.4, oy + 3.4, 11, True)
    ents = [
        U('turret', dr, ox + 1.5, oy + 8.5, 3),
        U('harvester', dr, ox + 5.2, oy + 4.3, 5, sel=True, hp=0.95),
        U('harvester', dr, ox + 10.4, oy + 5.3, 10, hp=0.4),
        U('harvester', dr, ox + 7.4, oy + 7.7, 13),
        U('scout', dr, ox + 3.4, oy + 2.4, 14), U('scout', dr, ox + 8.2, oy + 2.2, 3),
        U('tank', dr, ox + 4.2, oy + 6.6, 12), U('tank', dr, ox + 2.8, oy + 5.4, 13), U('launcher', dr, ox + 3.2, oy + 7.6, 12),
        U('scout', a, ox + 0.5, oy + 3.6, 4), U('scout', a, ox + 0.9, oy + 5.0, 4), U('tank', a, ox + 0.2, oy + 4.3, 4),
    ]
    w_slab = [(1, 8)]
    for (tx, ty) in w_slab:
        v.slab(ox + tx, oy + ty)
    v.draw(ents)
    v.smoke(ox + 10.4, oy + 5.0, 5, 4)
    v.rain(ox + 12.5, oy + 4.5, 4.6, 4.2)
    v.lightning(ox + 11.2, oy + 6.4, 190, 46)
    v.lightning(ox + 13.4, oy + 3.4, 120, -30)
    v.lightning(ox + 14.8, oy + 7.2, 150, 24)
    for (x, y) in ((5.3, 4.5), (7.3, 7.9)):
        for i in range(4):
            px, py = v.p(ox + x + v.rng.normal() * 0.3, oy + y + v.rng.normal() * 0.3)
            v.flash(px, py, 2)
    p0 = v.tip(ox + 2.8, oy + 5.4, 13)
    v.tracer(p0, v.p(ox + 0.9, oy + 5.0), 0.6)
    v.flash(*p0, 3)
    img = v.finish()
    ui = dict(player=dr, msg='Warning: glass storm over the eastern field.', credits='842',
              scales=(('assembly', 0.41), ('drift', 0.25), ('kiln', 0.34)), power=(90, 120), tab=1,
              build=[dict(s='harvester', name='HARVESTER', cost=400, state=0.3), dict(s='scout', name='SCOUT', cost=150, n=3),
                     dict(s='tank', name='TANK', cost=350), dict(s='launcher', name='LAUNCHER', cost=450),
                     dict(s='siege', name='SIEGE GUN', cost=550, state='locked'),
                     dict(s='heavy', name='BULWARK', cost=600, state='locked')],
              sel=dict(s='harvester', name='HARVESTER', hp=0.95, l1='Cargo 34%', btns=('HARVEST', 'RETURN')),
              cursor=(318, 190), msgcol=(200, 180, 255))
    save(compose(img, w, v, ents, ui), 'balance_mock_3_storm')


def sheet():
    names = ['tank', 'heavy', 'harvester', 'scout', 'siege', 'launcher', 'turret']
    im = Image.new('RGB', (16 * 64, len(names) * 64 + 160), (60, 62, 70))
    for j, n in enumerate(names):
        for d in range(16):
            s = sprite(n, d, ('assembly', 'drift', 'kiln')[d % 3])[0]
            im.paste(s, (d * 64, j * 64), s)
    x = 0
    for n in ('hq', 'refinery', 'reactor', 'barracks', 'factory', 'silo', 'radar'):
        s = sprite(n, 0, 'assembly')[0]
        im.paste(s, (x, len(names) * 64), s)
        x += s.width - 8
    im.resize((im.width * 2, im.height * 2), Image.NEAREST).save(os.path.join(OUT, 'sheet.png'))


SCENES = {'base': scene_base, 'battle': scene_battle, 'storm': scene_storm, 'sheet': sheet}
for name, fn in SCENES.items():
    if not WANT or name in WANT:
        fn()
