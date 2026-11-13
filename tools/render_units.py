# Render the raw unit sprites for Balance with Blender.
#
# Run from the repo root (Blender 5.2):
#   C:\Blender\blender.exe -b --factory-startup -P tools/render_units.py -- tools/_raw
#
# For every unit, pose and facing this writes two images into the output folder:
#   <unit>_p<pose>_<dir>.png      colour pass
#   <unit>_p<pose>_<dir>_sh.png   ground shadow pass
# They are large (4x) renders. tools/make_units.py turns them into the small sprite sheets
# in assets/sprites/units/. The output folder is scratch space and is not kept in git.
#
# Facing 0 looks south (towards the camera), 2 west, 4 north, 6 east.
# Pose 0 stands; poses 1 and 2 are the two halves of a walking step.
#
# The models and the lighting are those of the approved style mockups (mockups/src/v5_units.py).
import bpy, sys, math, os
from mathutils import Vector

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
print('DONE')
