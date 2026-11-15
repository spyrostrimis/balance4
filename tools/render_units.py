# Render the raw unit and building sprites for Balance with Blender.
#
# Run from the repo root (Blender 5.2):
#   C:\Blender\blender.exe -b --factory-startup -P tools/render_units.py -- tools/_raw
#
# For every unit, pose and facing this writes two images into the output folder:
#   <unit>_p<pose>_<dir>.png      colour pass
#   <unit>_p<pose>_<dir>_sh.png   ground shadow pass
# They are large (4x) renders. tools/make_units.py turns them into the small sprite sheets
# in assets/sprites/units/, and tools/make_buildings.py into the building pictures in
# assets/sprites/buildings/. The output folder is scratch space and is not kept in git.
#
# Facing 0 looks south (towards the camera), 2 west, 4 north, 6 east.
# Troops: pose 0 stands; poses 1 and 2 are the two halves of a walking step.
# Harvesters: pose 0 is the empty truck, 1 the loaded truck, 2 halfway between truck and
# robot, 3 and 4 the two halves of the robot's swing, 5 the robot standing with its arms down.
# Trailers (the back of the truck, left standing when the robot steps off): pose 0 is empty,
# 1 loaded. A trailer is rendered where it sits in the truck, so the two pictures line up.
# Buildings have one pose and one facing.
#
# The models and the lighting are those of the approved style mockups (mockups/src/v5_units.py
# and v6_radar.py). The harvester's robot shape, its trailer and the buildings are new, in the
# same manner.
import bpy, sys, math, os
from mathutils import Vector, noise

argv = sys.argv[sys.argv.index("--") + 1:]
OUT = os.path.abspath(argv[0])     # Blender would otherwise resolve a relative path against the drive root
ONLY = set(argv[1:])
os.makedirs(OUT, exist_ok=True)

TILE, SS = 32, 4                  # pixels per cell, and how much larger than final size to render
pi = math.pi
cos, sin = math.cos, math.sin

bpy.ops.wm.read_factory_settings(use_empty=True)
scene = bpy.context.scene
scene.render.engine = 'CYCLES'
scene.cycles.samples = 32
scene.cycles.use_denoising = False
scene.cycles.max_bounces = 3
scene.cycles.seed = 0
scene.render.film_transparent = True
scene.render.use_persistent_data = True
scene.render.image_settings.file_format = 'PNG'
scene.render.image_settings.color_mode = 'RGBA'
scene.view_settings.view_transform = 'Standard'
try:
    scene.view_settings.look = 'None'
except Exception:
    pass


# --- materials ---------------------------------------------------------------------------
def lin(hexcol):
    hexcol = hexcol.lstrip('#')
    out = []
    for i in (0, 2, 4):
        c = int(hexcol[i:i + 2], 16) / 255
        out.append(c / 12.92 if c <= 0.04045 else ((c + 0.055) / 1.055) ** 2.4)
    return tuple(out)


def mat(name, hexcol, metallic=0.0, rough=0.7, emit=None, estr=0.0):
    m = bpy.data.materials.new(name)
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
    b.inputs['Base Color'].default_value = (*lin(hexcol), 1)
    b.inputs['Metallic'].default_value = metallic
    b.inputs['Roughness'].default_value = rough
    if emit:
        b.inputs['Emission Color'].default_value = (*lin(emit), 1)
        b.inputs['Emission Strength'].default_value = estr
    return m


EYE = mat('eye', '#1a1210', 0, 0.5)
SKIN = mat('skin', '#e0a878', 0, 0.7)
LEATHER = mat('leather', '#4a2c18', 0, 0.8)
GOLD = mat('gold', '#f2c040', 0.9, 0.3)
STEEL = mat('steel', '#c8d4e4', 0.85, 0.3)
IRON = mat('iron', '#3a3238', 0.8, 0.4)
WOODS = mat('woods', '#7a5028', 0, 0.7)
BONE = mat('bone', '#efe2c4', 0, 0.6)
B_CLOTH = mat('bcloth', '#1f55d8', 0, 0.8)
B_CLOTH2 = mat('bcloth2', '#163a94', 0, 0.8)
B_CREST = mat('bcrest', '#4aa8ff', 0, 0.7)
B_SHIELD = mat('bshield', '#2a6af0', 0.2, 0.4)
B_GLOW = mat('bglow', '#bfefff', 0, 0.3, '#7fdcff', 2.5)
R_CLOTH = mat('rcloth', '#d42a1e', 0, 0.8)
R_CLOTH2 = mat('rcloth2', '#8c1612', 0, 0.8)
R_CREST = mat('rcrest', '#ff5a2a', 0, 0.7)
R_GLOW = mat('rglow', '#ffe0a0', 0, 0.3, '#ff9a30', 2.5)

# --- world, lights, camera ---------------------------------------------------------------
world = bpy.data.worlds.new('w')
scene.world = world
try:
    world.use_nodes = True
except Exception:
    pass
bg = next(n for n in world.node_tree.nodes if n.type == 'BACKGROUND')
bg.inputs[0].default_value = (0.62, 0.66, 0.80, 1)     # cool sky fill: warm light, cool shadow
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


add_sun((0.5, -0.32, -1.0), 3.6, True, 0.05, (1.0, 0.96, 0.86))     # key light from the north-west
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


# --- primitives --------------------------------------------------------------------------
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
    """A rod from one point to another."""
    p0, p1 = Vector(p0), Vector(p1)
    d = p1 - p0
    bpy.ops.mesh.primitive_cylinder_add(radius=r, depth=d.length, vertices=verts, location=(p0 + p1) / 2)
    o = bpy.context.active_object
    o.rotation_euler = d.normalized().to_track_quat('Z', 'Y').to_euler()
    return _finish(o, m, None if flat else 'sides')


def blob(r, x, y, z, m, amp=0.2, freq=1.5, seed=0, sc=(1, 1, 1), sub=3):
    """A lumpy sphere (a heap of ore)."""
    bpy.ops.mesh.primitive_ico_sphere_add(subdivisions=sub, radius=1.0, location=(x, y, z))
    o = bpy.context.active_object
    off = Vector((seed * 3.7 + 1, seed * 1.3 + 5, seed * 2.1 + 11))
    for v in o.data.vertices:
        p = v.co.copy()
        n = noise.noise(p * freq + off) + 0.5 * noise.noise(p * freq * 2.3 + off)
        v.co = p * (1 + amp * n)
    o.scale = (r * sc[0], r * sc[1], r * sc[2])
    return _finish(o, m, 'all')


def clear():
    for o in objs:
        me = o.data
        bpy.data.objects.remove(o, do_unlink=True)
        if me and me.users == 0:
            bpy.data.meshes.remove(me)
    objs.clear()


def render(name, canvas, dirs, scale, theta):
    """Render the current model from `dirs` sides: a colour pass and a ground-shadow pass each."""
    aim(theta)
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


# --- infantry ----------------------------------------------------------------------------
STRIDE = 0.13     # how far a foot swings forward or back in a walking pose


def infantry(team, pose):
    """A foot soldier. The front faces -Y. pose 0 stands, 1 and 2 are the halves of a step."""
    B = team == 'blue'
    cloth, cloth2 = (B_CLOTH, B_CLOTH2) if B else (R_CLOTH, R_CLOTH2)
    armour = STEEL if B else IRON
    trim = GOLD
    lead = {0: 0, 1: -1, 2: 1}[pose]          # which leg is forward
    lift = 0.03 if pose else 0.0              # the body rises a little in mid-step
    for s in (-1, 1):
        fy = -STRIDE * s * lead
        box(0.15, 0.24, 0.14, x=s * 0.11, y=-0.03 + fy, z=0, m=LEATHER, bevel=0.04)
        cyl(0.085, 0.34, x=s * 0.11, y=fy * 0.6, z=0.1, m=cloth2)
    z0 = lift
    cone(0.27, 0.18, 0.32, z=0.52 + z0, m=cloth)                       # tunic
    ell(0.22, 0.17, 0.23, z=0.78 + z0, m=armour)                       # cuirass
    ell(0.12, 0.06, 0.13, y=-0.13, z=0.8 + z0, m=cloth)                # tabard on the chest
    torus(0.2, 0.04, z=0.62 + z0, m=trim)                              # belt
    ell(0.15, 0.15, 0.155, y=-0.015, z=1.1 + z0, m=SKIN)               # head
    for s in (-1, 1):
        ell(0.028, 0.02, 0.034, x=s * 0.06, y=-0.155, z=1.1 + z0, m=EYE)
        ell(0.05, 0.02, 0.014, x=s * 0.06, y=-0.15, z=1.145 + z0, m=LEATHER)
        ell(0.035, 0.05, 0.1, x=s * 0.14, y=-0.06, z=1.07 + z0, m=armour)     # cheek guards
    ell(0.028, 0.035, 0.035, y=-0.165, z=1.07 + z0, m=SKIN)
    ell(0.05, 0.015, 0.012, y=-0.155, z=1.02 + z0, m=LEATHER)
    ell(0.18, 0.18, 0.16, y=0.04, z=1.15 + z0, m=armour)               # helmet
    ell(0.19, 0.06, 0.035, y=-0.05, z=1.19 + z0, m=trim)               # brow band
    for s in (-1, 1):
        swing = 0.07 * s * lead               # arms swing against the legs
        ell(0.115, 0.115, 0.105, x=s * 0.27, z=0.93 + z0, m=trim if B else armour)
        cyl(0.065, 0.32, x=s * 0.3, y=-0.04 + swing, z=0.6 + z0, m=cloth)
        ell(0.065, 0.065, 0.065, x=s * 0.3, y=-0.06 + swing, z=0.58 + z0, m=SKIN)
    ell(0.23, 0.06, 0.38, y=0.19, z=0.66 + z0, m=cloth, rot=(-0.16, 0, 0))   # cape
    if B:
        ell(0.04, 0.22, 0.12, y=0.05, z=1.36 + z0, m=B_CREST)                  # helmet crest
        cyl(0.24, 0.035, x=-0.36, y=-0.17, z=0.72 + z0, m=trim, rot=(pi / 2, 0, 0), center=True, verts=22)
        cyl(0.2, 0.05, x=-0.36, y=-0.185, z=0.72 + z0, m=B_SHIELD, rot=(pi / 2, 0, 0), center=True, verts=22)
        ell(0.075, 0.04, 0.075, x=-0.36, y=-0.21, z=0.72 + z0, m=trim)
        cyl(0.024, 1.55, x=0.33, y=-0.09, z=0.08 + z0, m=WOODS)                # spear
        cone(0.055, 0.0, 0.24, x=0.33, y=-0.09, z=1.76 + z0, m=STEEL)
        ell(0.05, 0.05, 0.05, x=0.33, y=-0.09, z=1.6 + z0, m=B_GLOW)
    else:
        for s in (-1, 1):
            cone(0.05, 0.0, 0.3, x=s * 0.22, z=1.34 + z0, rot=(0, s * 0.55, 0), m=BONE)   # horns
            cone(0.045, 0.0, 0.2, x=s * 0.33, z=1.06 + z0, rot=(0, s * 0.6, 0), m=BONE)   # pauldron spikes
        ell(0.04, 0.2, 0.09, y=0.05, z=1.33 + z0, m=R_CREST)
        cyl(0.028, 1.5, x=0.33, y=-0.09, z=0.06 + z0, m=IRON)                  # glaive
        ell(0.07, 0.022, 0.27, x=0.42, y=-0.09, z=1.48 + z0, m=STEEL)
        ell(0.03, 0.024, 0.2, x=0.5, y=-0.09, z=1.48 + z0, m=R_GLOW)
        ell(0.05, 0.05, 0.05, x=0.33, y=-0.09, z=1.2 + z0, m=R_GLOW)


# --- field commanders -----------------------------------------------------------------------
def commander(team, pose):
    """A field commander: the foot soldier's build, a little larger, with a gold helmet, a tall
    plume, a pale cape and a staff with a glowing head. Both sides share the model and differ
    only in colour. Red's is a placeholder until that character has been designed."""
    B = team == 'blue'
    cloth, cloth2 = (B_CLOTH, B_CLOTH2) if B else (R_CLOTH, R_CLOTH2)
    plume = B_CREST if B else R_CREST
    glow = B_GLOW if B else R_GLOW
    armour = STEEL if B else IRON
    lead = {0: 0, 1: -1, 2: 1}[pose]
    z0 = 0.03 if pose else 0.0
    for s in (-1, 1):
        fy = -STRIDE * s * lead
        box(0.16, 0.25, 0.14, x=s * 0.115, y=-0.03 + fy, z=0, m=LEATHER, bevel=0.04)
        cyl(0.09, 0.34, x=s * 0.115, y=fy * 0.6, z=0.1, m=cloth2)
    cone(0.29, 0.19, 0.34, z=0.52 + z0, m=cloth)                       # tunic
    ell(0.23, 0.18, 0.24, z=0.79 + z0, m=armour)                       # cuirass
    ell(0.13, 0.06, 0.14, y=-0.14, z=0.8 + z0, m=GOLD)                 # gold breastplate
    torus(0.21, 0.045, z=0.62 + z0, m=GOLD)                            # belt
    ell(0.15, 0.15, 0.155, y=-0.015, z=1.1 + z0, m=SKIN)               # head
    for s in (-1, 1):
        ell(0.028, 0.02, 0.034, x=s * 0.06, y=-0.155, z=1.1 + z0, m=EYE)
        ell(0.035, 0.05, 0.1, x=s * 0.14, y=-0.06, z=1.07 + z0, m=GOLD)       # cheek guards
    ell(0.028, 0.035, 0.035, y=-0.165, z=1.07 + z0, m=SKIN)
    ell(0.185, 0.185, 0.165, y=0.04, z=1.15 + z0, m=GOLD)              # gold helmet
    ell(0.195, 0.06, 0.035, y=-0.05, z=1.19 + z0, m=armour)            # brow band
    ell(0.055, 0.25, 0.2, y=0.07, z=1.42 + z0, m=plume)                # tall plume
    for s in (-1, 1):
        swing = 0.07 * s * lead
        ell(0.13, 0.13, 0.115, x=s * 0.28, z=0.94 + z0, m=GOLD)        # pauldrons
        cyl(0.068, 0.32, x=s * 0.31, y=-0.04 + swing, z=0.6 + z0, m=cloth)
        ell(0.068, 0.068, 0.068, x=s * 0.31, y=-0.06 + swing, z=0.58 + z0, m=SKIN)
    ell(0.28, 0.07, 0.46, y=0.2, z=0.62 + z0, m=BONE, rot=(-0.16, 0, 0))      # long pale cape
    cyl(0.026, 1.38, x=0.35, y=-0.09, z=0.06 + z0, m=WOODS)            # staff, short enough to fit the sprite
    torus(0.1, 0.028, x=0.35, y=-0.09, z=1.5 + z0, m=GOLD, rot=(pi / 2, 0, 0))
    ell(0.08, 0.08, 0.08, x=0.35, y=-0.09, z=1.5 + z0, m=glow)


# --- vehicles (the front faces -Y; sizes in cells) ------------------------------------------
HULL = mat('hull', '#7c8086', 0.3, 0.6)
HULL_D = mat('hull_d', '#50545a', 0.3, 0.65)
TIRE = mat('tire', '#1d1b19', 0.0, 0.9)
GLASS = mat('glass', '#16222e', 0.2, 0.3)
ORE_L = mat('ore_l', '#e09a2c', 0.4, 0.3, '#c06a10', 0.25)
TEAM = {'blue': (mat('tb', '#2f5cc0', 0.1, 0.6), mat('tb2', '#213f88', 0.1, 0.6)),
        'red': (mat('tr', '#b8322a', 0.1, 0.6), mat('tr2', '#801f1a', 0.1, 0.6))}


def wheel(x, y, z=0.0, r=0.115, wd=0.1):
    cyl(r, wd, x=x, y=y, z=z + r, m=TIRE, rot=(0, pi / 2, 0), center=True, verts=12)
    cyl(r * 0.5, wd + 0.01, x=x, y=y, z=z + r, m=HULL_D, rot=(0, pi / 2, 0), center=True, verts=8)


def hopper(team, loaded):
    """The open hopper that is the back of the truck and, unhitched, the trailer. It shows a
    heap of ore when it is loaded. Its end boards carry the team colour."""
    T, T2 = TEAM[team]
    box(0.46, 0.62, 0.04, y=0.14, z=0.18, m=HULL)
    for sx in (-1, 1):
        box(0.04, 0.62, 0.14, x=sx * 0.23, y=0.14, z=0.2, m=HULL)
    for y in (-0.17, 0.45):
        box(0.46, 0.04, 0.14, y=y, z=0.2, m=HULL)
        box(0.46, 0.05, 0.02, y=y, z=0.34, m=T2, bevel=0)               # team-coloured rim
    if loaded:
        blob(0.2, 0, 0.14, 0.27, ORE_L, amp=0.3, freq=2.2, seed=4, sc=(0.95, 1.35, 0.5))
        blob(0.11, 0.06, 0.02, 0.33, ORE_L, amp=0.3, freq=2.2, seed=5, sc=(1, 1, 0.6))
    else:
        box(0.38, 0.54, 0.02, y=0.14, z=0.22, m=HULL_D, bevel=0)        # the empty hopper floor


def harvester_truck(team, loaded):
    """The harvester as a truck: a cab in front and an open hopper (its trailer) behind it,
    after the approved mockup."""
    T, T2 = TEAM[team]
    for sx in (-1, 1):
        for y in (-0.34, 0.0, 0.34):
            wheel(sx * 0.26, y)
        box(0.06, 0.5, 0.06, x=sx * 0.29, y=0.14, z=0.3, m=T2)          # folded arms
    box(0.42, 0.98, 0.08, z=0.1, m=HULL_D)
    box(0.42, 0.26, 0.2, y=-0.34, z=0.18, m=T)
    box(0.38, 0.12, 0.03, y=-0.4, z=0.38, m=GLASS)
    hopper(team, loaded)
    cyl(0.03, 0.1, x=0.15, y=-0.22, z=0.38, m=HULL_D, verts=8)


def harvester_trailer(team, loaded):
    """The trailer on its own: the hopper on its four wheels, where it sits in the truck, with
    a drawbar and a leg in front where the cab was."""
    for sx in (-1, 1):
        for y in (0.0, 0.34):
            wheel(sx * 0.26, y)
    box(0.42, 0.66, 0.08, y=0.14, z=0.1, m=HULL_D)                      # chassis
    box(0.1, 0.16, 0.05, y=-0.26, z=0.11, m=HULL_D)                     # drawbar
    cyl(0.035, 0.11, y=-0.31, z=0.0, m=HULL_D, verts=8)                 # the leg it rests on
    cyl(0.06, 0.02, y=-0.31, z=0.0, m=IRON, verts=8)
    hopper(team, loaded)


def harvester_robot(team, pose):
    """The harvester's cab standing up as a squat robot: its wheels become its feet, the cab
    its head, the folded arms unfold and it carries a pack for ore on its back. pose 0 is
    halfway there; poses 1 and 2 are the two halves of its swing (at the rock, or at an
    enemy), one arm up while the other is down; pose 3 stands with both arms lowered."""
    T, T2 = TEAM[team]
    up = 0.5 if pose == 0 else 1.0                 # how far it has risen
    lean = (1 - up) * 0.5
    for sx in (-1, 1):
        wheel(sx * 0.2, -0.1)
        wheel(sx * 0.2, 0.14)
        box(0.14, 0.42, 0.08, x=sx * 0.2, y=0.02, z=0.06, m=HULL_D)                 # feet
        box(0.12, 0.14, 0.1 + 0.14 * up, x=sx * 0.17, y=0.04, z=0.12, m=HULL_D)     # legs
    z0 = 0.2 + 0.14 * up
    box(0.44, 0.3, 0.08, y=0.04, z=z0, m=HULL_D)                                     # hips
    box(0.46, 0.34, 0.22, y=0.03 + lean * 0.2, z=z0 + 0.07, m=HULL, rot=(-lean, 0, 0))    # body
    box(0.3, 0.04, 0.14, y=-0.15 + lean * 0.2, z=z0 + 0.11, m=T, bevel=0.01)         # chest plate
    box(0.4, 0.16, 0.24, y=0.26 + lean * 0.3, z=z0 + 0.02, m=HULL, rot=(-lean, 0, 0))     # hopper on its back
    blob(0.12, 0, 0.26 + lean * 0.3, z0 + 0.27, ORE_L, amp=0.3, freq=2.2, seed=4, sc=(1.3, 0.5, 0.5))
    zh = z0 + 0.3
    box(0.26, 0.24, 0.13, y=-0.02 + lean * 0.3, z=zh, m=T)                           # head (the cab)
    box(0.22, 0.04, 0.06, y=-0.14 + lean * 0.3, z=zh + 0.04, m=GLASS, bevel=0.01)
    for sx in (-1, 1):
        sh = Vector((sx * 0.31, 0.02, z0 + 0.22))
        box(0.13, 0.16, 0.12, x=sh.x, y=sh.y, z=sh.z - 0.06, m=T2)                   # shoulders
        if pose == 0:
            hand = sh + Vector((0, -0.18, -0.14))
        elif pose == 3:
            hand = sh + Vector((0, -0.14, -0.2))   # at rest
        elif (pose == 1) == (sx == 1):
            hand = sh + Vector((0, -0.3, 0.2))     # raised
        else:
            hand = sh + Vector((0, -0.4, -0.2))    # struck
        seg(sh, hand, 0.05, T2, verts=8)
        tip = hand + (hand - sh).normalized() * 0.07
        seg(hand, tip, 0.07, HULL_D, verts=6, flat=True)                             # the pick
        ell(0.05, 0.05, 0.05, x=tip.x, y=tip.y, z=tip.z, m=STEEL)


# --- buildings (footprint centred on the origin; sizes in cells) ----------------------------
WALL = mat('wall', '#8c8e86', 0.1, 0.8)
WALL_D = mat('wall_d', '#62645e', 0.1, 0.8)
ROOF = mat('roof', '#44474a', 0.2, 0.7)
TANK = mat('tank', '#b9bbb4', 0.2, 0.5)


def refinery(team):
    """The refinery, 3 by 2 cells and low: a hall, a storage tank, a stack and, in front on the
    right, the bay where harvesters tip their load."""
    T, T2 = TEAM[team]
    box(1.5, 1.05, 0.22, x=-0.62, y=0.3, z=0, m=WALL, bevel=0.03)                    # hall
    box(1.3, 0.85, 0.03, x=-0.62, y=0.3, z=0.22, m=ROOF, bevel=0)
    for i in range(5):                                                               # roof ribs
        box(0.16, 0.66, 0.02, x=-1.1 + i * 0.24, y=0.3, z=0.25, m=T if i % 2 == 0 else HULL_D, bevel=0)
    box(0.7, 0.42, 0.15, x=-0.98, y=-0.62, z=0, m=WALL_D)                            # annex
    box(0.58, 0.3, 0.02, x=-0.98, y=-0.62, z=0.15, m=T)
    box(0.14, 0.04, 0.1, x=-0.98, y=-0.84, z=0, m=GLASS)
    cyl(0.1, 0.36, x=-1.2, y=0.62, z=0.22, m=WALL_D, verts=10)                       # stack
    cyl(0.07, 0.03, x=-1.2, y=0.62, z=0.58, m=TIRE, verts=10)
    cyl(0.46, 0.26, x=0.86, y=0.4, z=0, m=TANK, verts=20)                            # storage tank
    cyl(0.47, 0.05, x=0.86, y=0.4, z=0.1, m=T, verts=20)
    cyl(0.36, 0.03, x=0.86, y=0.4, z=0.26, m=WALL_D, verts=20)
    cyl(0.1, 0.03, x=0.86, y=0.4, z=0.29, m=T2, verts=10)
    seg((0.1, 0.3, 0.14), (0.42, 0.38, 0.14), 0.05, HULL)                            # pipe from hall to tank
    box(1.0, 0.56, 0.04, x=0.8, y=-0.6, z=0, m=HULL_D, bevel=0.01)                   # tipping bay
    for sx in (-1, 1):
        box(0.05, 0.56, 0.08, x=0.8 + sx * 0.5, y=-0.6, z=0, m=T2, bevel=0.01)
    box(0.6, 0.3, 0.02, x=0.8, y=-0.56, z=0.04, m=TIRE, bevel=0)                     # the grate
    blob(0.13, 0.62, -0.5, 0.07, ORE_L, amp=0.3, freq=2.2, seed=7, sc=(1.2, 0.9, 0.5))
    seg((0.8, -0.3, 0.1), (0.84, 0.0, 0.2), 0.06, HULL)                              # chute up to the tank
    box(0.3, 0.2, 0.12, x=-0.1, y=-0.4, z=0, m=WALL_D)                               # pump house
    box(0.22, 0.12, 0.02, x=-0.1, y=-0.4, z=0.12, m=T2)


def headquarters(team):
    """The headquarters, 2 by 2 cells: a square keep with a low turret at each corner, a taller
    block in the middle that carries the team colour, and a flag."""
    T, T2 = TEAM[team]
    box(1.5, 1.5, 0.2, z=0, m=WALL, bevel=0.03)                                      # the keep
    box(1.3, 1.3, 0.03, z=0.2, m=ROOF, bevel=0)
    for sx in (-1, 1):
        for sy in (-1, 1):
            cyl(0.2, 0.3, x=sx * 0.7, y=sy * 0.7, z=0, m=WALL_D, verts=10)           # corner turrets
            cyl(0.15, 0.03, x=sx * 0.7, y=sy * 0.7, z=0.3, m=T2, verts=10)
    box(0.8, 0.8, 0.2, z=0.2, m=WALL_D, bevel=0.03)                                  # the middle block
    box(0.66, 0.66, 0.03, z=0.4, m=T, bevel=0)
    box(0.3, 0.3, 0.06, z=0.43, m=T2, bevel=0.01)
    cyl(0.02, 0.4, x=0.22, y=0.22, z=0.43, m=IRON, verts=6)                          # flag pole
    box(0.22, 0.02, 0.12, x=0.34, y=0.22, z=0.7, m=T, bevel=0)                       # flag
    box(0.34, 0.04, 0.14, y=-0.76, z=0, m=GLASS, bevel=0.01)                         # gate
    box(0.5, 0.05, 0.03, y=-0.77, z=0.16, m=T2, bevel=0)
    for sx in (-1, 1):
        box(0.1, 0.5, 0.02, x=sx * 0.42, y=0.0, z=0.23, m=HULL_D, bevel=0)           # roof ribs


def generator(team):
    """The generator, 2 by 2 cells: a round furnace that burns Orichalcum (its top glows), a
    stack, a small control house and the pipe between them."""
    T, T2 = TEAM[team]
    box(1.6, 1.6, 0.05, z=0, m=WALL_D, bevel=0.02)                                   # slab
    cyl(0.56, 0.26, x=-0.2, y=0.15, z=0.05, m=TANK, verts=22)                        # furnace
    cyl(0.57, 0.06, x=-0.2, y=0.15, z=0.13, m=T, verts=22)                           # team band
    cyl(0.42, 0.03, x=-0.2, y=0.15, z=0.31, m=WALL_D, verts=22)
    cyl(0.24, 0.03, x=-0.2, y=0.15, z=0.34, m=ORE_L, verts=16)                       # the glowing core
    torus(0.24, 0.035, x=-0.2, y=0.15, z=0.36, m=IRON)
    cyl(0.11, 0.42, x=0.56, y=0.56, z=0.05, m=WALL, verts=10)                        # stack
    cyl(0.08, 0.03, x=0.56, y=0.56, z=0.47, m=TIRE, verts=10)
    box(0.42, 0.5, 0.2, x=0.52, y=-0.48, z=0.05, m=WALL, bevel=0.02)                 # control house
    box(0.34, 0.42, 0.03, x=0.52, y=-0.48, z=0.25, m=T2, bevel=0)
    box(0.14, 0.03, 0.1, x=0.52, y=-0.74, z=0.05, m=GLASS, bevel=0)
    seg((0.3, 0.0, 0.16), (0.52, -0.25, 0.16), 0.05, HULL)                           # pipe
    seg((0.2, 0.45, 0.2), (0.5, 0.56, 0.2), 0.05, HULL)
    for a in range(4):                                                               # bolts round the furnace
        an = a * pi / 2 + pi / 4
        box(0.1, 0.1, 0.1, x=-0.2 + 0.6 * cos(an), y=0.15 + 0.6 * sin(an), z=0.05, m=HULL_D, bevel=0.01)


def barracks(team):
    """The barracks, 2 by 2 cells: a long hall with a ribbed roof in the team colour at the
    back and a drill yard with practice posts in front."""
    T, T2 = TEAM[team]
    box(1.6, 0.8, 0.22, y=0.38, z=0, m=WALL, bevel=0.03)                             # hall
    box(1.46, 0.66, 0.03, y=0.38, z=0.22, m=ROOF, bevel=0)
    for i in range(6):                                                               # roof ribs
        box(0.14, 0.6, 0.025, x=-0.6 + i * 0.24, y=0.38, z=0.25, m=T if i % 2 == 0 else T2, bevel=0)
    box(0.26, 0.04, 0.14, x=-0.3, y=-0.03, z=0, m=GLASS, bevel=0.01)                 # door
    box(0.4, 0.05, 0.03, x=-0.3, y=-0.04, z=0.15, m=T2, bevel=0)
    box(1.6, 0.74, 0.03, y=-0.42, z=0, m=WALL_D, bevel=0.01)                         # yard
    for sx in (-1, 1):
        box(0.05, 0.74, 0.07, x=sx * 0.78, y=-0.42, z=0, m=WALL, bevel=0.01)         # yard walls
    for x in (0.2, 0.45, 0.7):                                                       # practice posts
        cyl(0.03, 0.2, x=x, y=-0.5, z=0.03, m=WOODS, verts=6)
        ell(0.06, 0.06, 0.07, x=x, y=-0.5, z=0.25, m=LEATHER)
    box(0.3, 0.2, 0.08, x=-0.5, y=-0.55, z=0.03, m=WOODS, bevel=0.01)                # rack
    box(0.26, 0.03, 0.06, x=-0.5, y=-0.55, z=0.11, m=STEEL, bevel=0)
    cyl(0.02, 0.34, x=0.7, y=0.7, z=0.22, m=IRON, verts=6)                           # flag
    box(0.2, 0.02, 0.1, x=0.59, y=0.7, z=0.44, m=T, bevel=0)


def workshop(team):
    """The workshop, 3 by 2 cells: a large hall with a wide door, skylights and vents, and in
    front of the door the apron where finished vehicles roll out, with a crane beside it."""
    T, T2 = TEAM[team]
    box(2.5, 1.0, 0.3, x=0.0, y=0.4, z=0, m=WALL, bevel=0.03)                        # hall
    box(2.34, 0.86, 0.03, x=0.0, y=0.4, z=0.3, m=ROOF, bevel=0)
    for i in range(4):                                                               # skylights
        box(0.34, 0.24, 0.02, x=-0.9 + i * 0.6, y=0.56, z=0.33, m=GLASS, bevel=0)
    box(2.34, 0.08, 0.025, x=0.0, y=0.12, z=0.33, m=T, bevel=0)                      # team stripe along the front
    for x in (-1.0, 1.0):
        cyl(0.07, 0.08, x=x, y=0.3, z=0.33, m=HULL_D, verts=8)                       # vents
    box(0.9, 0.05, 0.24, x=0.5, y=-0.1, z=0, m=TIRE, bevel=0)                        # the door
    box(1.0, 0.06, 0.03, x=0.5, y=-0.11, z=0.25, m=T2, bevel=0)
    box(1.1, 0.7, 0.03, x=0.5, y=-0.5, z=0, m=HULL_D, bevel=0.01)                    # apron
    for sx in (-1, 1):
        box(0.05, 0.7, 0.06, x=0.5 + sx * 0.55, y=-0.5, z=0, m=T2, bevel=0.01)
    box(0.5, 0.02, 0.01, x=0.5, y=-0.5, z=0.035, m=GOLD, bevel=0)                    # marking
    cyl(0.07, 0.36, x=-0.5, y=-0.5, z=0, m=HULL, verts=8)                            # crane post
    seg((-0.5, -0.5, 0.36), (-0.05, -0.62, 0.36), 0.035, T2)                         # crane arm
    seg((-0.05, -0.62, 0.36), (-0.05, -0.62, 0.2), 0.012, IRON, verts=6)
    box(0.24, 0.24, 0.14, x=-1.0, y=-0.5, z=0, m=WOODS, bevel=0.01)                  # crates
    box(0.2, 0.2, 0.12, x=-0.95, y=-0.5, z=0.14, m=WOODS, bevel=0.01)
    box(0.22, 0.22, 0.12, x=-0.72, y=-0.72, z=0, m=HULL, bevel=0.01)
    wheel(-0.95, -0.2, 0.0)                                                          # a spare wheel


# Infantry are a third of a cell tall and are seen from a little lower than vehicles so they stay
# readable. Commanders are a little larger so they stand out in a squad.
MODELS = [('infantry_blue', infantry, 'blue', 0.33), ('infantry_red', infantry, 'red', 0.33),
          ('commander_blue', commander, 'blue', 0.38), ('commander_red', commander, 'red', 0.38)]
for unit, model, team, scale in MODELS:
    if ONLY and unit not in ONLY:
        continue
    for pose in range(3):
        model(team, pose)
        render(f'{unit}_p{pose}', 2, 8, scale, math.radians(46))

# Vehicles and buildings are seen from almost straight above, as in the mockups.
STEEP = math.radians(24)
for team in ('blue', 'red'):
    unit = f'harvester_{team}'
    if not ONLY or unit in ONLY:
        for pose in range(6):
            if pose < 2:
                harvester_truck(team, pose == 1)
            else:
                harvester_robot(team, pose - 2)
            render(f'{unit}_p{pose}', 2, 8, 1.0, STEEP)
    trailer = f'trailer_{team}'
    if not ONLY or trailer in ONLY:
        for pose in range(2):
            harvester_trailer(team, pose == 1)
            render(f'{trailer}_p{pose}', 2, 8, 1.0, STEEP)
    for kind, model in (('refinery', refinery), ('headquarters', headquarters), ('generator', generator),
                        ('barracks', barracks), ('workshop', workshop)):
        building = f'{kind}_{team}'
        if not ONLY or building in ONLY:
            model(team)
            render(f'{building}_p0', 4, 1, 1.0, STEEP)
print('DONE')
