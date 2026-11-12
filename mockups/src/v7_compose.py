# Balance style test v7 -- grounding pass: units and buildings sit on the ground (contact shadow, soft outline),
# and buildings stand only on rock ground, on a flush foundation.
# Run: python v7_compose.py <raw_sprite_dir> <out_dir> [forest desert]
import os, sys
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from v6_compose import *          # noqa: F401,F403
import v3_compose as V3
import v4_compose as V4

_grit7 = np.random.default_rng(5)
_cache7 = {}


def unit_sprite7(u):
    """Grounded sprite: no opaque black ring, a half-transparent dark rim that blends into the terrain,
    and a tight contact shadow hugging the lower-right edge instead of a detached drop shadow."""
    key = (u[0], u[1])
    if key in _cache7:
        return _cache7[key]
    s = sprite(u[0], u[1], outline=None, colors=20, sat=0.95)
    solid = np.pad(s['a'], 2) > 0.5
    rgb = np.pad(s['rgb'], ((2, 2), (2, 2), (0, 0)))
    far = np.pad(s['sh'], 2)
    n = (_grit7.random(solid.shape).astype(np.float32) - 0.5) * 0.14
    rgb = np.clip(rgb * (1 + n[..., None]), 0, 1)
    edge = np.zeros_like(solid)
    for dy, dx in ((0, 1), (0, -1), (1, 0), (-1, 0)):
        edge |= np.roll(solid, (dy, dx), (0, 1))
    edge &= ~solid
    rgb[edge] = hexc('#15110d')
    alpha = solid.astype(np.float32) + 0.42 * edge
    contact = np.maximum(np.roll(solid, (1, 1), (0, 1)), 0.55 * np.roll(solid, (2, 2), (0, 1))).astype(np.float32)
    out = dict(rgb=rgb, a=alpha, sh=np.maximum(contact * 0.85, far * 0.22), ax=s['ax'] + 2, ay=s['ay'] + 2)
    _cache7[key] = out
    return out


V3.unit_sprite = unit_sprite7
V4.STONE_W = (160, 322, 1.3, 52)          # bigger rock patch on the Blue side to build on
FOUND = ['#4f5049', '#5a5b53', '#65665d', '#707167']


def foundation(rgb, x0, y0, tw, th, rng, plate=16):
    """Flush concrete plates set into the rock: no drop shadow, only thin seams."""
    w, h = tw * 32, th * 32
    base = ramp(np.clip(0.5 + speck(h, w, rng, 0.8), 0, 0.999), FOUND)
    yy, xx = np.mgrid[0:h, 0:w]
    base[(yy % plate == 0) | (xx % plate == 0)] = hexc('#7b7c71')
    base[(yy % plate == plate - 1) | (xx % plate == plate - 1)] = hexc('#3b3c36')
    rgb[y0:y0 + h, x0:x0 + w] = base


BLUE_R = (128, 288)
RED_R = (672, 96)


def forest7(rng):
    rgb, M = paint_forest4(rng)
    foundation(rgb, BLUE_R[0], BLUE_R[1], 2, 2, rng)
    return rgb, M


def desert7(rng):
    rgb, M = paint_desert4(rng)
    foundation(rgb, RED_R[0], RED_R[1], 2, 2, rng)
    return rgb, M


F7 = FOREST_UNITS + [('radar_blue', 0, BLUE_R[0] + 32, BLUE_R[1] + 32, '')]
D7 = DESERT_UNITS + [('radar_red', 0, RED_R[0] + 32, RED_R[1] + 32, ''), ('light_red', 2, 610, 208, ''),
                     ('infs_red', 1, 690, 206, ''), ('infs_red', 2, 704, 200, '')]
V3.paint_forest3 = forest7
V3.paint_desert3 = desert7
V3.forest_entities3 = lambda rng, M: ([], F7)
V3.desert_entities3 = lambda rng, M: ([], D7)

if __name__ == '__main__':
    crops = {'forest': (96, 262, 336, 422), 'desert': (552, 70, 746, 230)}
    for biome, theme, seed in (('forest', 'blue', 11), ('desert', 'red', 23)):
        if biome in WHICH:
            V3.compose3(biome, theme, seed)
            im = Image.open(f'{OUT}/v3_{biome}_native.png')
            c = crops[biome]
            im.crop((c[0], c[1] + TOP, c[2], c[3] + TOP)).resize(((c[2] - c[0]) * 4, (c[3] - c[1]) * 4),
                                                                 Image.NEAREST).save(f'{OUT}/v7_{biome}_closeup.png')
