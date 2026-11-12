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



# --- vehicles (front faces -Y at direction 0; sizes in tiles) --------------------------------------
HULL = mat('hull', '#7c8086', 0.3, 0.6)
HULL_D = mat('hull_d', '#50545a', 0.3, 0.65)
TRACK = mat('track', '#272522', 0.2, 0.8)
TREAD = mat('tread', '#4b4741', 0.2, 0.8)
TIRE = mat('tire', '#1d1b19', 0.0, 0.9)
GLASS = mat('glass', '#16222e', 0.2, 0.3)
ORE_L = mat('ore_l', '#e09a2c', 0.4, 0.3, '#c06a10', 0.25)
TEAM = {'blue': (mat('tb', '#2f5cc0', 0.1, 0.6), mat('tb2', '#213f88', 0.1, 0.6)),
        'red': (mat('tr', '#b8322a', 0.1, 0.6), mat('tr2', '#801f1a', 0.1, 0.6))}


def wheel(x, y, r=0.115, wd=0.1):
    cyl(r, wd, x=x, y=y, z=r, m=TIRE, rot=(0, pi / 2, 0), center=True, verts=12)
    cyl(r * 0.5, wd + 0.01, x=x, y=y, z=r, m=HULL_D, rot=(0, pi / 2, 0), center=True, verts=8)


def light(team):
    T, T2 = TEAM[team]
    for sx in (-1, 1):
        for y in (-0.2, 0.2):
            wheel(sx * 0.2, y)
    box(0.3, 0.6, 0.1, z=0.1, m=T)
    box(0.26, 0.2, 0.05, y=-0.19, z=0.2, m=T)
    box(0.26, 0.16, 0.1, y=0.0, z=0.2, m=GLASS)
    box(0.28, 0.2, 0.06, y=0.19, z=0.2, m=HULL_D)
    box(0.09, 0.09, 0.06, y=0.2, z=0.26, m=HULL)
    seg((0, 0.2, 0.31), (0, -0.14, 0.33), 0.02, HULL)
    box(0.34, 0.04, 0.05, y=-0.32, z=0.1, m=HULL_D)
    box(0.06, 0.18, 0.012, y=-0.19, z=0.25, m=T2, bevel=0)


def tank(team):
    T, T2 = TEAM[team]
    for sx in (-1, 1):
        box(0.15, 0.8, 0.15, x=sx * 0.24, z=0, m=TRACK, bevel=0.04)
        for i in range(7):
            box(0.16, 0.05, 0.02, x=sx * 0.24, y=-0.33 + i * 0.11, z=0.145, m=TREAD, bevel=0)
    box(0.36, 0.72, 0.14, z=0.06, m=HULL)
    box(0.3, 0.22, 0.04, y=-0.22, z=0.2, m=HULL_D)
    box(0.3, 0.2, 0.04, y=0.24, z=0.2, m=HULL_D)
    cyl(0.17, 0.1, z=0.2, m=T, verts=8, flat=True)
    box(0.2, 0.14, 0.08, y=0.12, z=0.21, m=T2)
    seg((0, -0.1, 0.26), (0, -0.56, 0.26), 0.03, HULL_D)
    seg((0, -0.5, 0.26), (0, -0.58, 0.26), 0.042, HULL)
    box(0.08, 0.08, 0.03, x=0.06, y=0.04, z=0.3, m=HULL_D)


def harvester(team):
    T, T2 = TEAM[team]
    for sx in (-1, 1):
        for y in (-0.34, 0.0, 0.34):
            wheel(sx * 0.26, y)
        box(0.06, 0.5, 0.06, x=sx * 0.29, y=0.14, z=0.3, m=T2)          # folded arms
    box(0.42, 0.98, 0.08, z=0.1, m=HULL_D)
    box(0.42, 0.26, 0.2, y=-0.34, z=0.18, m=T)
    box(0.38, 0.12, 0.03, y=-0.4, z=0.38, m=GLASS)
    box(0.46, 0.62, 0.04, y=0.14, z=0.18, m=HULL)
    for sx in (-1, 1):
        box(0.04, 0.62, 0.14, x=sx * 0.23, y=0.14, z=0.2, m=HULL)
    for y in (-0.17, 0.45):
        box(0.46, 0.04, 0.14, y=y, z=0.2, m=HULL)
    blob(0.2, 0, 0.14, 0.27, ORE_L, amp=0.3, freq=2.2, seed=4, sc=(0.95, 1.35, 0.5))
    blob(0.11, 0.06, 0.02, 0.33, ORE_L, amp=0.3, freq=2.2, seed=5, sc=(1, 1, 0.6))
    cyl(0.03, 0.1, x=0.15, y=-0.22, z=0.38, m=HULL_D, verts=8)


JOBS = []
for tm in ('blue', 'red'):
    JOBS += [(f'light_{tm}', (lambda t=tm: light(t)), 4, 8, 1.0, None),
             (f'tank_{tm}', (lambda t=tm: tank(t)), 4, 8, 1.0, None),
             (f'harv_{tm}', (lambda t=tm: harvester(t)), 4, 8, 1.0, None),
             (f'infs_{tm}', (lambda t=tm: infantry(t)), 4, 8, 0.33, math.radians(46))]
for name, fn, canvas, dirs, scale, th in JOBS:
    if ONLY and name not in ONLY:
        continue
    fn()
    render(name, canvas, dirs, scale, th)
print('DONE')
