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
THETA = math.radians(24)          # near top-down, Dune II style
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
LEAF_A = nmat('leafA', ['#234a1c', '#2f5f22', '#3f7529', '#538a33'], 4.5)
LEAF_B = nmat('leafB', ['#3a5a1c', '#4c7024', '#61872d', '#7a9c3a'], 4.5)
LEAF_C = nmat('leafC', ['#1c4a34', '#265f40', '#32754c', '#458a5c'], 4.5)
LEAF_AUT = nmat('leafAut', ['#7a4a1c', '#96602a', '#b07a34', '#c89644'], 4.5)
LEAF_PINK = nmat('leafPink', ['#b83a6a', '#e0608c', '#f593b0', '#ffd0dc'], 4.5)
PINE = nmat('pine', ['#173f38', '#1f5246', '#286654', '#357a64'], 5, (1, 1, 0.5))
PINE2 = nmat('pine2', ['#1f4530', '#2a5936', '#366d3e', '#46824a'], 5, (1, 1, 0.5))
BERRY = mat('berry', '#e8262a', 0, 0.4)
BERRY_Y = mat('berryy', '#ffd23a', 0, 0.4)
CAP_R = mat('capr', '#d8281e', 0, 0.45)
CAP_V = mat('capv', '#8a3ad0', 0, 0.45)
CREAM = mat('cream', '#f2e2c0', 0, 0.8)
ROCK_F = nmat('rockF', ['#4e483f', '#676054', '#80786a', '#989080'], 2.2, hard=False)
MOSS = nmat('moss', ['#3a5226', '#4a6630', '#5c7a3a'], 5)
ROCK_D = nmat('rockD', ['#5e4434', '#765642', '#8e6a50', '#a47e60'], 2.2, hard=False)
ROCK_D2 = nmat('rockD2', ['#6a4c3a', '#84624a', '#9e7a5c'], 2.5, hard=False)
PALM = nmat('palm', ['#2f5f22', '#427a2a', '#5c9436'], 3, (1, 6, 1))
SUCC = nmat('succ', ['#2a5f4a', '#3a7a5c', '#58966e'], 3)
FLOWER_M = mat('flowerM', '#d8607a', 0, 0.5)
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
bg.inputs[0].default_value = (0.62, 0.66, 0.80, 1)     # cool sky fill -> warm light / cool shadow
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


add_sun((0.5, -0.32, -1.0), 3.6, True, 0.05, (1.0, 0.96, 0.86))     # golden-hour key from the west
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


def render(name, canvas, dirs=1, scale=1.0, theta=None):
    aim(theta or THETA)
    pivot.scale = scale if isinstance(scale, tuple) else (scale, scale, scale)
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


# --- commander busts for the always-visible hero portrait ---------------------------------------------
add_sun((0.6, 1.0, -0.8), 2.4, True, 0.08, (1.0, 0.95, 0.88))
SK_B = mat('sk_b', '#c79a78', 0, 0.75)
SK_R = mat('sk_r', '#b48866', 0, 0.75)
HAIR = mat('hair', '#3a2a20', 0, 0.8)
HAIR_G = mat('hair_g', '#5a5650', 0, 0.8)
LIP = mat('lip', '#8a4a40', 0, 0.7)
SCAR = mat('scar', '#d8a898', 0, 0.7)
SCARF = mat('scarf', '#a88c60', 0, 0.9)
ARM_B = mat('arm_b', '#3a5a9a', 0.5, 0.5)
ARM_R = mat('arm_r', '#2c2628', 0.6, 0.45)
BRASS = mat('brass', '#b8963c', 0.8, 0.4)
CLOAK_R = mat('cloak_r', '#8c1f1a', 0, 0.85)
CREST_R = mat('crest_r', '#b8322a', 0, 0.8)
EYE2 = mat('eye2', '#1a1410', 0, 0.5)


def face(sk, brow):
    cyl(0.055, 0.16, z=0.84, m=sk)
    ell(0.115, 0.13, 0.15, z=1.1, m=sk)
    ell(0.092, 0.105, 0.09, y=-0.012, z=1.01, m=sk)
    for sx in (-1, 1):
        ell(0.02, 0.012, 0.011, x=sx * 0.046, y=-0.117, z=1.115, m=EYE2)
        ell(0.032, 0.012, 0.007, x=sx * 0.046, y=-0.119, z=1.14, m=brow)
        ell(0.02, 0.03, 0.035, x=sx * 0.118, y=0.0, z=1.1, m=sk)
    ell(0.016, 0.026, 0.036, y=-0.128, z=1.08, m=sk)
    ell(0.03, 0.01, 0.006, y=-0.116, z=1.032, m=LIP)


def hero_blue():
    face(SK_B, HAIR)
    ell(0.125, 0.14, 0.12, y=0.035, z=1.17, m=HAIR)                       # hair
    ell(0.1, 0.05, 0.05, x=0.03, y=-0.085, z=1.225, m=HAIR, rot=(0, 0.3, 0))
    ell(0.04, 0.09, 0.13, x=-0.115, y=0.03, z=1.08, m=HAIR)
    ell(0.04, 0.09, 0.13, x=0.115, y=0.03, z=1.08, m=HAIR)
    ell(0.07, 0.07, 0.09, y=0.16, z=1.16, m=HAIR)                         # bun
    box(0.006, 0.004, 0.075, x=0.062, y=-0.108, z=1.03, m=SCAR, bevel=0, rot=(0, 0.35, 0))
    torus(0.105, 0.05, z=0.9, m=SCARF)                                    # scarf
    ell(0.13, 0.08, 0.07, y=-0.05, z=0.85, m=SCARF)
    ell(0.25, 0.15, 0.2, z=0.66, m=ARM_B)                                 # cuirass
    for sx in (-1, 1):
        ell(0.12, 0.12, 0.085, x=sx * 0.28, z=0.8, m=ARM_B)
        torus(0.115, 0.016, x=sx * 0.28, z=0.775, m=BRASS)
    ell(0.05, 0.02, 0.05, y=-0.15, z=0.7, m=BRASS)


def hero_red():
    face(SK_R, HAIR_G)
    ell(0.13, 0.145, 0.12, y=0.03, z=1.18, m=ARM_R)                       # helmet
    ell(0.135, 0.06, 0.025, y=-0.07, z=1.185, m=BRASS)                    # brow band
    box(0.02, 0.02, 0.1, y=-0.135, z=1.09, m=ARM_R, bevel=0.005)          # nasal guard
    for sx in (-1, 1):
        ell(0.03, 0.07, 0.11, x=sx * 0.118, y=-0.03, z=1.07, m=ARM_R)     # cheek plates
    ell(0.03, 0.17, 0.09, y=0.04, z=1.31, m=CREST_R)                      # crest
    ell(0.085, 0.07, 0.06, y=-0.045, z=0.99, m=HAIR_G)                    # beard
    torus(0.12, 0.055, z=0.9, m=CLOAK_R)                                  # cloak collar
    ell(0.26, 0.16, 0.2, z=0.66, m=ARM_R)
    for sx in (-1, 1):
        ell(0.125, 0.125, 0.09, x=sx * 0.29, z=0.8, m=ARM_R)
        torus(0.12, 0.016, x=sx * 0.29, z=0.775, m=BRASS)
        cone(0.04, 0.0, 0.16, x=sx * 0.33, z=0.9, rot=(0, sx * 0.6, 0), m=BRASS)
    ell(0.3, 0.1, 0.22, y=0.14, z=0.62, m=CLOAK_R)


for name, fn in (('hero_blue', hero_blue), ('hero_red', hero_red)):
    fn()
    aim(math.radians(84), (0, 0, 1.02))
    pivot.scale = (1, 1, 1)
    pivot.rotation_euler = (0, 0, 0.3)
    scene.render.resolution_x = scene.render.resolution_y = 320
    camd.ortho_scale = 0.82
    catcher.hide_render = True
    ground.hide_render = True
    scene.render.filepath = os.path.join(OUT, name + '.png')
    bpy.ops.render.render(write_still=True)
    pivot.rotation_euler = (0, 0, 0)
    clear()
print('DONE')
