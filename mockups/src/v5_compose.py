# Balance style test v5 -- v4 terrain plus the first unit set: small infantry, light vehicle, tank, harvester.
# Run: python v5_compose.py <raw_sprite_dir> <out_dir> [forest desert]
import os, sys
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from v4_compose import *          # noqa: F401,F403
import v3_compose as V3

_grit = np.random.default_rng(5)
_done = set()


def unit_sprite(u):
    """Flat, gritty unit sprite: few colours, dark outline, per-pixel noise like the terrain."""
    s = sprite(u[0], u[1], outline='outer', colors=20, sat=0.95)
    if (u[0], u[1]) not in _done:
        _done.add((u[0], u[1]))
        n = (_grit.random(s['a'].shape).astype(np.float32) - 0.5) * 0.14
        s['rgb'] = np.clip(s['rgb'] * (1 + n[..., None]), 0, 1)
    return s


V3.unit_sprite = unit_sprite
V3.HP_DY, V3.SEL_RX, V3.SEL_RY = 19, 6, 3

# (sprite, direction 0..7, x, y, 'sel' or ''); direction 0 faces south, 2 west, 4 north, 6 east
FOREST_UNITS = [
    ('infs_blue', 7, 240, 350, 'sel'), ('infs_blue', 6, 256, 360, ''), ('infs_blue', 7, 228, 364, ''),
    ('infs_blue', 6, 246, 376, ''), ('infs_blue', 7, 266, 344, ''), ('infs_blue', 6, 218, 350, ''),
    ('tank_blue', 5, 306, 356, ''), ('light_blue', 5, 196, 404, ''), ('harv_blue', 6, 286, 262, ''),
    ('infs_red', 1, 560, 214, ''), ('infs_red', 2, 576, 206, ''), ('infs_red', 1, 580, 224, ''),
    ('infs_red', 2, 596, 214, ''), ('tank_red', 2, 650, 224, ''), ('light_red', 1, 520, 226, ''),
]
DESERT_UNITS = [
    ('infs_red', 1, 520, 372, 'sel'), ('infs_red', 2, 538, 362, ''), ('infs_red', 1, 540, 384, ''),
    ('infs_red', 2, 556, 374, ''), ('infs_red', 1, 502, 386, ''), ('infs_red', 2, 524, 394, ''),
    ('tank_red', 3, 606, 412, ''), ('light_red', 3, 498, 352, ''), ('harv_red', 2, 460, 268, ''),
    ('infs_blue', 7, 212, 186, ''), ('infs_blue', 6, 196, 178, ''), ('infs_blue', 7, 194, 196, ''),
    ('infs_blue', 6, 178, 188, ''), ('tank_blue', 6, 128, 160, ''), ('light_blue', 7, 256, 204, ''),
]
V3.forest_entities3 = lambda rng, M: ([], FOREST_UNITS)
V3.desert_entities3 = lambda rng, M: ([], DESERT_UNITS)

if __name__ == '__main__':
    if 'forest' in WHICH:
        V3.compose3('forest', 'blue', 11)
    if 'desert' in WHICH:
        V3.compose3('desert', 'red', 23)
    # contact sheet of the unit set at 4x, on neutral ground colours
    names = ['infs', 'light', 'tank', 'harv']
    sheet = np.zeros((2 * 56, 8 * 56 * 1, 3), np.float32)
    sheet[:56] = hexc('#4e6232')
    sheet[56:] = hexc('#cf9959')
    for r, tm in enumerate(('blue', 'red')):
        for c, nm in enumerate(names):
            for j, k in enumerate((7, 5)):
                s = unit_sprite((f'{nm}_{tm}', k))
                x, y = (c * 2 + j) * 56 + 28, r * 56 + 34
                put(sheet, x - s['ax'], y - s['ay'], np.zeros_like(s['rgb']), s['sh'] * 0.4)
                put(sheet, x - s['ax'], y - s['ay'], s['rgb'], s['a'])
    to_img(sheet).resize((sheet.shape[1] * 4, sheet.shape[0] * 4), Image.NEAREST).save(f'{OUT}/v5_units_sheet.png')
    print('saved sheet')
