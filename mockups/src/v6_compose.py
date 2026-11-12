# Balance style test v6 -- v5 plus one Radar building per side (on a slab) and HUD cards in the sprite style.
# Run: python v6_compose.py <raw_sprite_dir> <out_dir> [forest desert]
import os, sys
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from v5_compose import *          # noqa: F401,F403
import v3_compose as V3

SLAB = ['#555950', '#61655a', '#6d7165', '#797d70']


def slab(rgb, x0, y0, tw, th, rng, plate=16):
    """Foundation of small concrete plates, each with a lit north-west and dark south-east edge."""
    w, h = tw * 32, th * 32
    rgb[y0 + 3:y0 + h + 3, x0 + 3:x0 + w + 3] *= 0.62
    base = ramp(np.clip(0.5 + speck(h, w, rng, 0.8), 0, 0.999), SLAB)
    yy, xx = np.mgrid[0:h, 0:w]
    base[(yy % plate == 0) | (xx % plate == 0)] = hexc('#8d9184')
    base[(yy % plate == plate - 1) | (xx % plate == plate - 1)] = hexc('#3a3d36')
    rgb[y0:y0 + h, x0:x0 + w] = base


BLUE_RADAR = (128, 304)       # top-left pixel of the 2x2 footprint (tile aligned)
RED_RADAR = (640, 320)


def forest6(rng):
    rgb, M = paint_forest4(rng)
    slab(rgb, BLUE_RADAR[0], BLUE_RADAR[1], 2, 2, rng)
    return rgb, M


def desert6(rng):
    rgb, M = paint_desert4(rng)
    slab(rgb, RED_RADAR[0], RED_RADAR[1], 2, 2, rng)
    return rgb, M


F6 = FOREST_UNITS + [('radar_blue', 0, BLUE_RADAR[0] + 32, BLUE_RADAR[1] + 32, '')]
D6 = DESERT_UNITS + [('radar_red', 0, RED_RADAR[0] + 32, RED_RADAR[1] + 32, '')]
V3.paint_forest3 = forest6
V3.paint_desert3 = desert6
V3.forest_entities3 = lambda rng, M: ([], F6)
V3.desert_entities3 = lambda rng, M: ([], D6)


def _ground(team, h, w, seed):
    rng = np.random.default_rng(seed)
    return ramp(np.clip(0.5 + speck(h, w, rng, 0.8), 0, 0.999), GRASS4 if team == 'blue' else SAND3)


def _figure(team, h, w, ax, ay, seed):
    s = unit_sprite((f'infs_{team}', 7))
    c = _ground(team, h, w, seed)
    put(c, ax - s['ax'], ay - s['ay'], np.zeros_like(s['rgb']), s['sh'] * 0.4)
    put(c, ax - s['ax'], ay - s['ay'], s['rgb'], s['a'])
    return c


def card_portrait(team, T, pw, ph):
    """Unit picture: the in-game sprite at 4x on its home ground, so the card matches the map."""
    k = 4
    small = _figure(team, ph // k + 1, pw // k + 1, (pw // k) // 2, ph // k - 3, 3)
    big = np.repeat(np.repeat(small, k, 0), k, 1)
    return big[:ph, :pw]


def card_pip(team, T):
    return _figure(team, 18, 18, 9, 15, 4)


V3.card_portrait = card_portrait
V3.card_pip = card_pip

if __name__ == '__main__':
    if 'forest' in WHICH:
        V3.compose3('forest', 'blue', 11)
    if 'desert' in WHICH:
        V3.compose3('desert', 'red', 23)
    rng = np.random.default_rng(9)
    sheet = np.zeros((112, 224, 3), np.float32)
    sheet[:, :112] = ramp(np.clip(0.5 + speck(112, 112, rng, 0.8), 0, 0.999), GRASS4)
    sheet[:, 112:] = ramp(np.clip(0.5 + speck(112, 112, rng, 0.8), 0, 0.999), SAND3)
    for i, tm in enumerate(('blue', 'red')):
        x0 = i * 112 + 24
        slab(sheet, x0, 26, 2, 2, rng)
        s = unit_sprite((f'radar_{tm}', 0))
        put(sheet, x0 + 32 - s['ax'], 58 - s['ay'], np.zeros_like(s['rgb']), s['sh'] * 0.42)
        put(sheet, x0 + 32 - s['ax'], 58 - s['ay'], s['rgb'], s['a'])
        for j, nm in enumerate(('infs', 'tank')):                       # scale references
            u = unit_sprite((f'{nm}_{tm}', 7))
            put(sheet, i * 112 + 14 + j * 84 - u['ax'], 100 - u['ay'], u['rgb'], u['a'])
    to_img(sheet).resize((224 * 4, 112 * 4), Image.NEAREST).save(f'{OUT}/v6_radar_sheet.png')
    print('saved sheet')
