# Balance style test v2 -- warm fantasy props (trees, rocks, Orichalcum, infantry).
# Run: blender.exe -b --factory-startup -P v2_sprites.py -- <outdir> [name ...]
# Each sprite: colour pass <name>_<dir>.png and ground-shadow pass <name>_<dir>_sh.png.
import bpy, sys, math, os, random
from mathutils import Vector, noise

argv = sys.argv[sys.argv.index("--") + 1:]
OUT = argv[0]
ONLY = set(argv[1:])
os.makedirs(OUT, exist_ok=True)

TILE, SS = 32, 4
THETA = math.radians(50)          # camera tilt away from straight-down (3/4 view)
pi = math.pi
cos, sin = math.cos, math.sin

bpy.ops.wm.read_factory_settings(use_empty=True)
scene = bpy.context.scene
scene.render.engine = 'CYCLES'
scene.cycles.samples = 32
scene.cycles.use_denoising = False
scene.cycles.max_bounces = 3
scene.render.film_transparent = True
scene.render.use_persistent_data = True
scene.render.image_settings.file_format = 'PNG'
scene.render.image_settings.color_mode = 'RGBA'
scene.view_settings.view_transform = 'Standard'
try:
    scene.view_settings.look = 'None'
except Exception:
    pass


def lin(hexcol):
    hexcol = hexcol.lstrip('#')
    out = []
    for i in (0, 2, 4):
        c = int(hexcol[i:i + 2], 16) / 255
        out.append(c / 12.92 if c <= 0.04045 else ((c + 0.055) / 1.055) ** 2.4)
    return tuple(out)


def _bsdf(m):
    try:
        m.use_nodes = True
    except Exception:
        pass
    nt = m.node_tree
    b = next((n for n in nt.nodes if n.type == 'BSDF_PRINCIPLED'), None)
    if b is None:
        b = nt.nodes.new('ShaderNodeBsdfPrincipled')
        o = nt.nodes.new('ShaderNodeOutputMaterial')
        nt.links.new(b.outputs[0], o.inputs[0])
    return nt, b


def mat(name, hexcol, metallic=0.0, rough=0.7, emit=None, estr=0.0):
    m = bpy.data.materials.new(name)
    nt, b = _bsdf(m)
    b.inputs['Base Color'].default_value = (*lin(hexcol), 1)
    b.inputs['Metallic'].default_value = metallic
    b.inputs['Roughness'].default_value = rough
    if emit:
        b.inputs['Emission Color'].default_value = (*lin(emit), 1)
        b.inputs['Emission Strength'].default_value = estr
    return m


def nmat(name, cols, nscale=3.0, stretch=(1, 1, 1), rough=0.85, detail=2.0, hard=True, lo=0.36, hi=0.64):
    """Material whose colour is a noise-driven ramp through `cols` (dappled leaves, strata, moss)."""
    m = mat(name, cols[0], 0.0, rough)
    nt, b = _bsdf(m)
    tc = nt.nodes.new('ShaderNodeTexCoord')
    mp = nt.nodes.new('ShaderNodeMapping')
    nz = nt.nodes.new('ShaderNodeTexNoise')
    cr = nt.nodes.new('ShaderNodeValToRGB')
    mp.inputs['Scale'].default_value = stretch
    nz.inputs['Scale'].default_value = nscale
    nz.inputs['Detail'].default_value = detail
    nt.links.new(tc.outputs['Object'], mp.inputs['Vector'])
    nt.links.new(mp.outputs['Vector'], nz.inputs['Vector'])
    nt.links.new(nz.outputs[0], cr.inputs[0])
    nt.links.new(cr.outputs[0], b.inputs['Base Color'])
    ramp = cr.color_ramp
    ramp.interpolation = 'CONSTANT' if hard else 'LINEAR'
    n = len(cols)
    els = ramp.elements
    els[0].position = 0.0 if hard else lo
    els[0].color = (*lin(cols[0]), 1)
    els[1].position = hi if not hard else lo + (hi - lo) * (n - 2) / max(1, n - 1)
    els[1].color = (*lin(cols[-1]), 1)
    for i in range(1, n - 1):
        pos = lo + (hi - lo) * (i - 1) / max(1, n - 1) if hard else lo + (hi - lo) * i / (n - 1)
        e = els.new(pos)
        e.color = (*lin(cols[i]), 1)
    return m


# --- materials ---------------------------------------------------------------
BARK = nmat('bark', ['#4a2c17', '#6b4423', '#8a5c30'], 6, (1, 1, 0.25))
BARK_P = nmat('barkp', ['#7a5630', '#9a7444', '#b8915a'], 5, (0.2, 0.2, 4))
LEAF_A = nmat('leafA', ['#1f5a1c', '#2f7d22', '#4ea02c', '#7cc23a'], 4.5)
LEAF_B = nmat('leafB', ['#3a6b14', '#5c8f1c', '#86b428', '#b9d94a'], 4.5)
LEAF_C = nmat('leafC', ['#12523a', '#1c7350', '#2c9a66', '#58c486'], 4.5)
LEAF_AUT = nmat('leafAut', ['#a8380f', '#d6601a', '#f08a22', '#ffc040'], 4.5)
LEAF_PINK = nmat('leafPink', ['#b83a6a', '#e0608c', '#f593b0', '#ffd0dc'], 4.5)
PINE = nmat('pine', ['#0f4a44', '#17685a', '#22876c', '#3aa884'], 5, (1, 1, 0.5))
PINE2 = nmat('pine2', ['#17503a', '#216e3c', '#318a40', '#55ac4c'], 5, (1, 1, 0.5))
BERRY = mat('berry', '#e8262a', 0, 0.4)
BERRY_Y = mat('berryy', '#ffd23a', 0, 0.4)
CAP_R = mat('capr', '#d8281e', 0, 0.45)
CAP_V = mat('capv', '#8a3ad0', 0, 0.45)
CREAM = mat('cream', '#f2e2c0', 0, 0.8)
ROCK_F = nmat('rockF', ['#5a5148', '#7a6f62', '#998c7a', '#b5a892'], 2.2, hard=False)
MOSS = nmat('moss', ['#3c6a1c', '#5c8a26', '#84ac34'], 5)
ROCK_D = nmat('rockD', ['#7a2e18', '#a8482a', '#c8643a', '#e08a52', '#b85432'], 1.2, (0.25, 0.25, 7), hard=False,
              lo=0.3, hi=0.7)
ROCK_D2 = nmat('rockD2', ['#8a3a1e', '#b85a30', '#d87c44'], 2.5, hard=False)
PALM = nmat('palm', ['#2c7a22', '#48a02c', '#7cc43a'], 3, (1, 6, 1))
SUCC = nmat('succ', ['#1f7a5c', '#2ea078', '#62c896'], 3)
FLOWER_M = mat('flowerM', '#ff3aa0', 0, 0.5)
DRY = nmat('dry', ['#8a6a22', '#b8922e', '#dcb848'], 6)
BONE = mat('bone', '#efe2c4', 0, 0.6)
DEADWOOD = nmat('deadwood', ['#8a7458', '#b09a7a', '#cdbb9c'], 5, (1, 1, 0.3))
ORI = mat('ori', '#ff9a22', 0.5, 0.25, '#ff6a08', 0.45)
ORI_HOT = mat('orihot', '#ffc24a', 0.3, 0.2, '#ff9a20', 0.9)
ROCK_OD = nmat('rockOD', ['#3a2220', '#55322a', '#70463a', '#8a5a48'], 2.2, hard=False)
ROCK_OF = nmat('rockOF', ['#4a3c34', '#665448', '#84705e', '#a08a72'], 2.2, hard=False)
EYE = mat('eye', '#1a1210', 0, 0.5)

SKIN = mat('skin', '#e0a878', 0, 0.7)
LEATHER = mat('leather', '#4a2c18', 0, 0.8)
GOLD = mat('gold', '#f2c040', 0.9, 0.3)
STEEL = mat('steel', '#c8d4e4', 0.85, 0.3)
IRON = mat('iron', '#3a3238', 0.8, 0.4)
WOODS = mat('woods', '#7a5028', 0, 0.7)
B_CLOTH = mat('bcloth', '#1f55d8', 0, 0.8)
B_CLOTH2 = mat('bcloth2', '#163a94', 0, 0.8)
B_CREST = mat('bcrest', '#4aa8ff', 0, 0.7)
B_SHIELD = mat('bshield', '#2a6af0', 0.2, 0.4)
B_GLOW = mat('bglow', '#bfefff', 0, 0.3, '#7fdcff', 2.5)
R_CLOTH = mat('rcloth', '#d42a1e', 0, 0.8)
R_CLOTH2 = mat('rcloth2', '#8c1612', 0, 0.8)
R_CREST = mat('rcrest', '#ff5a2a', 0, 0.7)
R_GLOW = mat('rglow', '#ffe0a0', 0, 0.3, '#ff9a30', 2.5)

# --- world, lights, camera ---------------------------------------------------
world = bpy.data.worlds.new('w')
scene.world = world
try:
    world.use_nodes = True
except Exception:
    pass
bg = next(n for n in world.node_tree.nodes if n.type == 'BACKGROUND')
bg.inputs[0].default_value = (0.50, 0.56, 0.90, 1)     # cool sky fill -> warm light / cool shadow
bg.inputs[1].default_value = 0.75


def add_sun(direction, energy, shadow=True, angle=0.05, color=(1, 1, 1)):
    l = bpy.data.lights.new('sun', 'SUN')
    l.energy = energy
    l.angle = angle
    l.color = color
    l.use_shadow = shadow
    o = bpy.data.objects.new('sun', l)
    scene.collection.objects.link(o)
    o.rotation_euler = Vector(direction).normalized().to_track_quat('-Z', 'Y').to_euler()
    return o


add_sun((1.0, 0.12, -1.0), 4.2, True, 0.05, (1.0, 0.90, 0.70))     # golden-hour key from the west
add_sun((-0.35, 1.0, -0.7), 1.3, False, 0.05, (1.0, 0.95, 0.88))   # soft fill from the camera side

camd = bpy.data.cameras.new('cam')
camd.type = 'ORTHO'
cam = bpy.data.objects.new('cam', camd)
scene.collection.objects.link(cam)
scene.camera = cam
D = 40
camd.clip_end = 300


def aim(theta, target=(0, 0, 0)):
    cam.location = (target[0], target[1] - D * sin(theta), target[2] + D * cos(theta))
    cam.rotation_euler = (theta, 0, 0)


bpy.ops.mesh.primitive_plane_add(size=60, location=(0, 0, 0))
catcher = bpy.context.active_object
catcher.is_shadow_catcher = True
bpy.ops.mesh.primitive_plane_add(size=60, location=(0, 0, 0))
ground = bpy.context.active_object          # hides anything below ground level in the colour pass
try:
    ground.is_holdout = True
except Exception:
    ground.hide_render = True

pivot = bpy.data.objects.new('pivot', None)
scene.collection.objects.link(pivot)
objs = []


def _finish(o, m, smooth=None):
    bpy.ops.object.transform_apply(location=False, rotation=False, scale=True)
    if m:
        o.data.materials.append(m)
    if smooth == 'all':
        for p in o.data.polygons:
            p.use_smooth = True
    elif smooth == 'sides':
        for p in o.data.polygons:
            p.use_smooth = len(p.vertices) == 4
    o.parent = pivot
    objs.append(o)
    return o


def box(sx, sy, sz, x=0.0, y=0.0, z=0.0, m=None, bevel=0.03, rot=(0, 0, 0)):
    bpy.ops.mesh.primitive_cube_add(size=1, location=(x, y, z + sz / 2), rotation=rot)
    o = bpy.context.active_object
    o.scale = (sx, sy, sz)
    _finish(o, m)
    if bevel:
        b = o.modifiers.new('b', 'BEVEL')
        b.width = bevel
        b.segments = 2
    return o


def cyl(r, h, x=0.0, y=0.0, z=0.0, m=None, verts=16, rot=(0, 0, 0), center=False, flat=False):
    loc = (x, y, z) if center else (x, y, z + h / 2)
    bpy.ops.mesh.primitive_cylinder_add(radius=r, depth=h, vertices=verts, location=loc, rotation=rot)
    return _finish(bpy.context.active_object, m, None if flat else 'sides')


def cone(r1, r2, h, x=0.0, y=0.0, z=0.0, m=None, rot=(0, 0, 0), verts=18, flat=False):
    bpy.ops.mesh.primitive_cone_add(radius1=r1, radius2=r2, depth=h, vertices=verts, location=(x, y, z),
                                    rotation=rot)
    return _finish(bpy.context.active_object, m, None if flat else 'sides')


def ell(rx, ry, rz, x=0.0, y=0.0, z=0.0, m=None, rot=(0, 0, 0)):
    bpy.ops.mesh.primitive_uv_sphere_add(radius=1, segments=20, ring_count=10, location=(x, y, z), rotation=rot)
    o = bpy.context.active_object
    o.scale = (rx, ry, rz)
    return _finish(o, m, 'all')


def torus(R, r, x=0.0, y=0.0, z=0.0, m=None, rot=(0, 0, 0)):
    bpy.ops.mesh.primitive_torus_add(major_radius=R, minor_radius=r, major_segments=28, minor_segments=10,
                                     location=(x, y, z), rotation=rot)
    return _finish(bpy.context.active_object, m, 'all')


def seg(p0, p1, r, m, verts=10, flat=False):
    p0, p1 = Vector(p0), Vector(p1)
    d = p1 - p0
    bpy.ops.mesh.primitive_cylinder_add(radius=r, depth=d.length, vertices=verts, location=(p0 + p1) / 2)
    o = bpy.context.active_object
    o.rotation_euler = d.normalized().to_track_quat('Z', 'Y').to_euler()
    return _finish(o, m, None if flat else 'sides')


def blob(r, x, y, z, m, amp=0.2, freq=1.5, seed=0, sc=(1, 1, 1), sub=3):
    """Lumpy organic sphere (canopy clump, boulder)."""
    bpy.ops.mesh.primitive_ico_sphere_add(subdivisions=sub, radius=1.0, location=(x, y, z))
    o = bpy.context.active_object
    off = Vector((seed * 3.7 + 1, seed * 1.3 + 5, seed * 2.1 + 11))
    for v in o.data.vertices:
        p = v.co.copy()
        n = noise.noise(p * freq + off) + 0.5 * noise.noise(p * freq * 2.3 + off)
        v.co = p * (1 + amp * n)
    o.scale = (r * sc[0], r * sc[1], r * sc[2])
    return _finish(o, m, 'all')


def crystal(p, d, length, r, m=None):
    p, d = Vector(p), Vector(d).normalized()
    seg(p, p + d * length, r, m or ORI, verts=6, flat=True)
    tip = p + d * (length + r * 0.9)
    bpy.ops.mesh.primitive_cone_add(radius1=r, radius2=0, depth=r * 1.8, vertices=6, location=tip)
    o = bpy.context.active_object
    o.rotation_euler = d.to_track_quat('Z', 'Y').to_euler()
    _finish(o, m or ORI)


def clear():
    for o in objs:
        me = o.data
        bpy.data.objects.remove(o, do_unlink=True)
        if me and me.users == 0:
            bpy.data.meshes.remove(me)
    objs.clear()


def render(name, canvas, dirs=1, scale=1.0):
    aim(THETA)
    pivot.scale = (scale, scale, scale)
    res = canvas * TILE * SS
    scene.render.resolution_x = scene.render.resolution_y = res
    scene.render.resolution_percentage = 100
    camd.ortho_scale = canvas
    for k in range(dirs):
        pivot.rotation_euler = (0, 0, -2 * pi * k / dirs)
        catcher.hide_render = True
        ground.hide_render = False
        for o in objs:
            o.visible_camera = True
        scene.render.filepath = os.path.join(OUT, f"{name}_{k:02d}.png")
        bpy.ops.render.render(write_still=True)
        catcher.hide_render = False
        ground.hide_render = True
        for o in objs:
            o.visible_camera = False
        scene.render.filepath = os.path.join(OUT, f"{name}_{k:02d}_sh.png")
        bpy.ops.render.render(write_still=True)
    pivot.rotation_euler = (0, 0, 0)
    clear()


def portrait(name):
    """Bust shot for the sidebar card."""
    aim(math.radians(80), (0, 0, 1.0))
    pivot.scale = (1, 1, 1)
    pivot.rotation_euler = (0, 0, 0.35)
    scene.render.resolution_x = scene.render.resolution_y = 448
    camd.ortho_scale = 1.15
    catcher.hide_render = True
    ground.hide_render = True
    for o in objs:
        o.visible_camera = True
    scene.render.filepath = os.path.join(OUT, f"{name}_portrait.png")
    bpy.ops.render.render(write_still=True)
    pivot.rotation_euler = (0, 0, 0)
    clear()


# --- forest --------------------------------------------------------------------
def broadleaf(seed, h=1.1, R=0.8, leaf=None, fruit=None):
    rnd = random.Random(seed)
    leaf = leaf or LEAF_A
    cone(0.27, 0.13, 0.34, z=0.17, m=BARK)
    cone(0.14, 0.09, h, z=h / 2 + 0.15, m=BARK)
    top = h + 0.1
    pts = [(0, 0, top + R * 0.55, R)]
    for i in range(5):
        a = 2 * pi * i / 5 + rnd.uniform(-0.3, 0.3)
        d = R * rnd.uniform(0.55, 0.8)
        pts.append((d * cos(a), d * sin(a), top + R * rnd.uniform(0.15, 0.5), R * rnd.uniform(0.5, 0.68)))
    pts.append((rnd.uniform(-.2, .2), rnd.uniform(-.2, .2), top + R * 1.12, R * 0.55))
    for i, (x, y, z, r) in enumerate(pts):
        blob(r, x, y, z, leaf, seed=seed * 10 + i, sc=(1, 1, 0.85))
    if fruit:
        for k in range(16):
            x, y, z, r = rnd.choice(pts)
            a, e = rnd.uniform(0, 2 * pi), rnd.uniform(0.1, 1.2)
            ell(0.065, 0.065, 0.065, x + r * 1.0 * cos(a) * cos(e), y + r * 1.0 * sin(a) * cos(e),
                z + r * 0.85 * sin(e), fruit)


def conifer(seed, h=3.0, leaf=None):
    leaf = leaf or PINE
    cyl(0.1, 0.6, m=BARK)
    tiers = 4
    step = (h - 0.5) / tiers
    for i in range(tiers):
        r = 0.82 * (1 - 0.68 * i / (tiers - 1))
        zc = 0.5 + i * step + step * 0.75
        cone(r, r * 0.12, step * 1.5, z=zc, m=leaf, verts=14)


def bush(seed, leaf=None, fruit=None):
    rnd = random.Random(seed)
    leaf = leaf or LEAF_B
    pts = [(rnd.uniform(-.3, .3), rnd.uniform(-.2, .2), rnd.uniform(.15, .3), rnd.uniform(.28, .4)) for _ in range(4)]
    for i, (x, y, z, r) in enumerate(pts):
        blob(r, x, y, z, leaf, seed=seed * 10 + i, sc=(1, 1, 0.8))
    if fruit:
        for k in range(9):
            x, y, z, r = rnd.choice(pts)
            a, e = rnd.uniform(0, 2 * pi), rnd.uniform(0.2, 1.2)
            ell(0.05, 0.05, 0.05, x + r * cos(a) * cos(e), y + r * sin(a) * cos(e), z + r * 0.8 * sin(e), fruit)


def mushroom(seed, cap=None, s=1.0):
    rnd = random.Random(seed)
    cap = cap or CAP_R
    for (x, y, k) in [(0, 0, 1.0), (0.42, -0.12, 0.6), (-0.3, -0.2, 0.45)]:
        k *= s
        cone(0.1 * k, 0.07 * k, 0.6 * k, x=x, y=y, z=0.3 * k, m=CREAM)
        ell(0.36 * k, 0.36 * k, 0.2 * k, x, y, 0.62 * k, cap)
        for j in range(7):
            a, e = rnd.uniform(0, 2 * pi), rnd.uniform(0.25, 1.4)
            ell(0.05 * k, 0.05 * k, 0.03 * k, x + 0.34 * k * cos(a) * cos(e), y + 0.34 * k * sin(a) * cos(e),
                0.62 * k + 0.2 * k * sin(e), CREAM)


def rock(seed, R=0.55, m=None, moss=False, tall=1.0):
    rnd = random.Random(seed)
    m = m or ROCK_F
    blob(R, 0, 0, R * 0.25 * tall, m, amp=0.28, freq=1.3, seed=seed, sc=(1.15, 0.9, 0.8 * tall))
    for i in range(2):
        a = rnd.uniform(0, 2 * pi)
        r = R * rnd.uniform(0.4, 0.6)
        blob(r, R * 0.9 * cos(a), R * 0.6 * sin(a), r * 0.2, m, amp=0.28, freq=1.3, seed=seed + i + 1,
             sc=(1.1, 0.9, 0.75))
    if moss:
        blob(R * 0.7, -0.05, 0.05, R * 0.62 * tall, MOSS, amp=0.25, seed=seed + 5, sc=(1.1, 0.85, 0.3))


# --- desert --------------------------------------------------------------------
def spire(seed, h=2.2):
    rnd = random.Random(seed)
    blob(0.6, 0, 0, h * 0.42, ROCK_D, amp=0.22, freq=1.2, seed=seed, sc=(1.0, 0.85, h / 1.2))
    blob(0.45, 0.6, 0.1, h * 0.2, ROCK_D, amp=0.25, freq=1.2, seed=seed + 1, sc=(1.0, 0.9, h / 2.2))
    blob(0.4, -0.55, -0.15, 0.1, ROCK_D2, amp=0.25, freq=1.3, seed=seed + 2, sc=(1.1, 0.9, 0.7))


def palm(seed, lean=1.0, h=6):
    rnd = random.Random(seed)
    pts = [Vector((0.02 * i * i * lean, 0, 0.37 * i)) for i in range(h + 1)]
    for i in range(h):
        seg(pts[i], pts[i + 1], 0.105 - 0.006 * i, BARK_P)
    top = pts[-1]
    for k in range(9):
        a = 2 * pi * k / 9 + rnd.uniform(-0.15, 0.15)
        t = rnd.uniform(0.4, 0.6)
        ell(0.62, 0.15, 0.035, top.x + 0.5 * cos(a), top.y + 0.5 * sin(a), top.z - 0.12, PALM, rot=(0, t, a))
    for k in range(5):
        a = 2 * pi * k / 5 + 0.3
        ell(0.45, 0.12, 0.035, top.x + 0.3 * cos(a), top.y + 0.3 * sin(a), top.z + 0.1, PALM, rot=(0, -0.25, a))
    for k in range(3):
        a = 2 * pi * k / 3
        ell(0.08, 0.08, 0.08, top.x + 0.1 * cos(a), top.y + 0.1 * sin(a), top.z - 0.1, BERRY_Y)


def succulent(seed):
    rnd = random.Random(seed)
    for i in range(6):
        a = 2 * pi * i / 6 + rnd.uniform(-0.3, 0.3)
        d = rnd.uniform(0.0, 0.3) if i else 0
        hh = rnd.uniform(0.3, 0.6) if i else 0.7
        blob(0.15, d * cos(a), d * sin(a), hh * 0.5, SUCC, amp=0.12, seed=seed * 7 + i, sc=(1, 1, hh / 0.3))
        ell(0.07, 0.07, 0.06, d * cos(a), d * sin(a), hh + 0.02, FLOWER_M)


def drybush(seed):
    for i in range(3):
        blob(0.24, (i - 1) * 0.22, 0.05 * (i % 2), 0.14, DRY, amp=0.45, freq=3.5, seed=seed + i, sc=(1, 1, 0.75))


def ribs():
    for i in range(5):
        R = 0.52 - 0.06 * abs(i - 1.5)
        torus(R, 0.045, y=(i - 2) * 0.33, z=-0.05, m=BONE, rot=(pi / 2, 0, 0.12 * (i - 2)))
    seg((0, -0.9, 0.04), (0, 0.9, 0.04), 0.06, BONE)
    blob(0.2, 0.05, -1.15, 0.12, BONE, amp=0.15, seed=3, sc=(0.9, 1.4, 0.8))


def deadtree(seed):
    rnd = random.Random(seed)
    seg((0, 0, 0), (0.1, 0, 1.0), 0.1, DEADWOOD)
    seg((0.1, 0, 1.0), (0.5, 0.1, 1.6), 0.06, DEADWOOD)
    seg((0.1, 0, 0.9), (-0.45, -0.1, 1.5), 0.055, DEADWOOD)
    seg((0.5, 0.1, 1.6), (0.55, 0, 2.0), 0.035, DEADWOOD)
    seg((0.5, 0.1, 1.6), (0.95, 0.1, 1.75), 0.03, DEADWOOD)
    seg((-0.45, -0.1, 1.5), (-0.8, 0, 1.6), 0.03, DEADWOOD)
    seg((-0.45, -0.1, 1.5), (-0.4, 0, 1.95), 0.03, DEADWOOD)


# --- Orichalcum ------------------------------------------------------------------
def orichalcum(biome, seed=1):
    rnd = random.Random(seed)
    R = ROCK_OF if biome == 'forest' else ROCK_OD
    lumps = [(0.95, 0.0, 0.1, 0.3, 1.05), (0.7, -0.95, 0.05, 0.1, 0.85), (0.66, 0.9, -0.1, 0.1, 0.95),
             (0.55, 0.25, -0.6, 0.05, 0.8), (0.5, -0.45, 0.55, 0.35, 1.2), (0.42, -0.5, -0.5, 0.05, 0.7)]
    for i, (r, x, y, z, sz) in enumerate(lumps):
        blob(r, x, y, z, R, amp=0.26, freq=1.3, seed=seed * 5 + i, sc=(1.1, 0.95, sz))
    if biome == 'forest':
        blob(0.6, -0.9, 0.1, 0.55, MOSS, amp=0.25, seed=9, sc=(1.1, 0.9, 0.25))
        blob(0.45, 0.75, 0.2, 0.72, MOSS, amp=0.25, seed=11, sc=(1.1, 0.9, 0.25))
    cr = [((0.1, -0.15, 0.9), (0.15, -0.2, 1), 1.0, 0.17), ((-0.25, -0.1, 0.95), (-0.45, -0.25, 1), 0.75, 0.13),
          ((0.45, -0.05, 0.85), (0.6, -0.1, 1), 0.7, 0.12), ((0.0, 0.2, 1.0), (-0.1, 0.3, 1), 0.85, 0.14),
          ((-0.95, -0.25, 0.45), (-0.6, -0.5, 1), 0.55, 0.1), ((0.95, -0.4, 0.45), (0.5, -0.5, 1), 0.6, 0.11),
          ((0.3, -0.85, 0.3), (0.2, -0.8, 1), 0.5, 0.1), ((-0.5, -0.75, 0.25), (-0.3, -0.7, 1), 0.42, 0.085),
          ((1.3, 0.0, 0.2), (0.8, -0.2, 1), 0.4, 0.08), ((-1.35, -0.1, 0.2), (-0.8, -0.3, 1), 0.38, 0.08),
          ((0.7, -0.75, 0.15), (0.5, -0.6, 0.8), 0.3, 0.07), ((-0.05, -1.05, 0.1), (0, -0.7, 1), 0.3, 0.07)]
    for i, (p, d, ln, r) in enumerate(cr):
        crystal(p, d, ln, r, ORI_HOT if i % 4 == 0 else ORI)
    for i in range(10):                                   # ore veins on the rock face
        a = rnd.uniform(pi, 2 * pi)
        ell(0.14, 0.06, 0.07, 1.0 * cos(a) * rnd.uniform(0.5, 1.2), 0.75 * sin(a) - 0.1, rnd.uniform(0.25, 0.7), ORI,
            rot=(0, rnd.uniform(-1, 1), rnd.uniform(0, 3)))


def shard(seed):
    rnd = random.Random(seed)
    blob(0.22, 0, 0.05, 0.03, ROCK_F if seed % 2 else ROCK_D2, amp=0.25, seed=seed, sc=(1.2, 0.9, 0.6))
    for i in range(3):
        a = rnd.uniform(0, 2 * pi)
        crystal((0.1 * cos(a), 0.08 * sin(a), 0.05), (0.5 * cos(a), 0.4 * sin(a) - 0.2, 1), rnd.uniform(0.22, 0.4),
                0.055, ORI_HOT if i == 0 else ORI)


# --- infantry ------------------------------------------------------------------------
def infantry(team):
    B = team == 'blue'
    cloth, cloth2 = (B_CLOTH, B_CLOTH2) if B else (R_CLOTH, R_CLOTH2)
    armour = STEEL if B else IRON
    trim = GOLD
    for s in (-1, 1):
        box(0.15, 0.24, 0.14, x=s * 0.11, y=-0.03, z=0, m=LEATHER, bevel=0.04)
        cyl(0.085, 0.34, x=s * 0.11, z=0.1, m=cloth2)
    cone(0.27, 0.18, 0.32, z=0.52, m=cloth)                       # tunic
    ell(0.22, 0.17, 0.23, z=0.78, m=armour)                       # cuirass
    ell(0.12, 0.06, 0.13, y=-0.13, z=0.8, m=cloth)                # tabard on the chest
    torus(0.2, 0.04, z=0.62, m=trim)                              # belt
    ell(0.15, 0.15, 0.155, y=-0.015, z=1.1, m=SKIN)               # head
    for s in (-1, 1):
        ell(0.028, 0.02, 0.034, x=s * 0.06, y=-0.155, z=1.1, m=EYE)
        ell(0.05, 0.02, 0.014, x=s * 0.06, y=-0.15, z=1.145, m=LEATHER)
        ell(0.035, 0.05, 0.1, x=s * 0.14, y=-0.06, z=1.07, m=armour)     # cheek guards
    ell(0.028, 0.035, 0.035, y=-0.165, z=1.07, m=SKIN)
    ell(0.05, 0.015, 0.012, y=-0.155, z=1.02, m=LEATHER)
    ell(0.18, 0.18, 0.16, y=0.04, z=1.15, m=armour)               # helmet
    ell(0.19, 0.06, 0.035, y=-0.05, z=1.19, m=trim)               # brow band
    for s in (-1, 1):
        ell(0.115, 0.115, 0.105, x=s * 0.27, z=0.93, m=trim if B else armour)
        cyl(0.065, 0.32, x=s * 0.3, y=-0.04, z=0.6, m=cloth)
        ell(0.065, 0.065, 0.065, x=s * 0.3, y=-0.06, z=0.58, m=SKIN)
    ell(0.23, 0.06, 0.38, y=0.19, z=0.66, m=cloth, rot=(-0.16, 0, 0))   # cape
    if B:
        ell(0.04, 0.22, 0.12, y=0.05, z=1.36, m=B_CREST)                  # helmet crest
        cyl(0.24, 0.035, x=-0.36, y=-0.17, z=0.72, m=trim, rot=(pi / 2, 0, 0), center=True, verts=22)
        cyl(0.2, 0.05, x=-0.36, y=-0.185, z=0.72, m=B_SHIELD, rot=(pi / 2, 0, 0), center=True, verts=22)
        ell(0.075, 0.04, 0.075, x=-0.36, y=-0.21, z=0.72, m=trim)
        cyl(0.024, 1.55, x=0.33, y=-0.09, z=0.08, m=WOODS)                # spear
        cone(0.055, 0.0, 0.24, x=0.33, y=-0.09, z=1.76, m=STEEL)
        ell(0.05, 0.05, 0.05, x=0.33, y=-0.09, z=1.6, m=B_GLOW)
    else:
        for s in (-1, 1):
            cone(0.05, 0.0, 0.3, x=s * 0.22, z=1.34, rot=(0, s * 0.55, 0), m=BONE)   # horns
            cone(0.045, 0.0, 0.2, x=s * 0.33, z=1.06, rot=(0, s * 0.6, 0), m=BONE)   # pauldron spikes
        ell(0.04, 0.2, 0.09, y=0.05, z=1.33, m=R_CREST)
        cyl(0.028, 1.5, x=0.33, y=-0.09, z=0.06, m=IRON)                  # glaive
        ell(0.07, 0.022, 0.27, x=0.42, y=-0.09, z=1.48, m=STEEL)
        ell(0.03, 0.024, 0.2, x=0.5, y=-0.09, z=1.48, m=R_GLOW)
        ell(0.05, 0.05, 0.05, x=0.33, y=-0.09, z=1.2, m=R_GLOW)


JOBS = [
    ('tree_a', lambda: broadleaf(1, 1.1, 0.82, LEAF_A), 9, 1, 1.0),
    ('tree_b', lambda: broadleaf(2, 1.3, 0.9, LEAF_B), 9, 1, 1.0),
    ('tree_c', lambda: broadleaf(3, 0.9, 0.7, LEAF_C), 9, 1, 1.0),
    ('tree_d', lambda: broadleaf(4, 1.2, 0.85, LEAF_A, BERRY), 9, 1, 1.0),
    ('tree_aut', lambda: broadleaf(5, 1.0, 0.75, LEAF_AUT), 9, 1, 1.0),
    ('tree_pink', lambda: broadleaf(6, 0.9, 0.68, LEAF_PINK), 9, 1, 1.0),
    ('pine_a', lambda: conifer(1, 3.1, PINE), 9, 1, 1.0),
    ('pine_b', lambda: conifer(2, 2.5, PINE2), 9, 1, 1.0),
    ('bush_a', lambda: bush(1, LEAF_B, BERRY), 4, 1, 1.0),
    ('bush_b', lambda: bush(2, LEAF_C, BERRY_Y), 4, 1, 1.0),
    ('shroom_r', lambda: mushroom(1, CAP_R, 1.0), 4, 1, 1.0),
    ('shroom_v', lambda: mushroom(2, CAP_V, 0.8), 4, 1, 1.0),
    ('rockf_a', lambda: rock(1, 0.55, ROCK_F, True), 5, 1, 1.0),
    ('rockf_b', lambda: rock(2, 0.4, ROCK_F, False), 5, 1, 1.0),
    ('rockf_c', lambda: rock(3, 0.7, ROCK_F, True, 1.3), 5, 1, 1.0),
    ('rockd_a', lambda: rock(4, 0.55, ROCK_D2), 5, 1, 1.0),
    ('rockd_b', lambda: rock(5, 0.38, ROCK_D), 5, 1, 1.0),
    ('rockd_c', lambda: rock(6, 0.75, ROCK_D, False, 1.4), 5, 1, 1.0),
    ('spire_a', lambda: spire(1, 2.4), 9, 1, 1.0),
    ('spire_b', lambda: spire(2, 1.7), 9, 1, 1.0),
    ('palm_a', lambda: palm(1, 1.0, 6), 9, 1, 1.0),
    ('palm_b', lambda: palm(2, -0.7, 5), 9, 1, 1.0),
    ('succ_a', lambda: succulent(1), 4, 1, 1.0),
    ('succ_b', lambda: succulent(2), 4, 1, 0.8),
    ('drybush', lambda: drybush(1), 4, 1, 1.0),
    ('ribs', ribs, 6, 1, 1.0),
    ('deadtree', lambda: deadtree(1), 7, 1, 1.0),
    ('ori_forest', lambda: orichalcum('forest'), 9, 1, 1.0),
    ('ori_desert', lambda: orichalcum('desert'), 9, 1, 1.0),
    ('shard_a', lambda: shard(1), 4, 1, 1.0),
    ('shard_b', lambda: shard(2), 4, 1, 1.0),
    ('inf_blue', lambda: infantry('blue'), 6, 8, 1.2),
    ('inf_red', lambda: infantry('red'), 6, 8, 1.2),
]
for name, fn, canvas, dirs, scale in JOBS:
    if ONLY and name not in ONLY:
        continue
    fn()
    render(name, canvas, dirs, scale)
for team in ('blue', 'red'):
    if ONLY and f'inf_{team}' not in ONLY and 'portraits' not in ONLY:
        continue
    infantry(team)
    portrait(f'inf_{team}')
print('DONE')
