# Renders Balance mock-up sprites (units in 16 directions, buildings) with Blender.
# Run: blender.exe -b --factory-startup -P blender_sprites.py -- <outdir> [name ...]
# Each sprite gets two PNGs: colour pass (<name>_<dir>.png) and shadow pass (<name>_<dir>_sh.png).
import bpy, sys, math, os
from mathutils import Vector

argv = sys.argv[sys.argv.index("--") + 1:]
OUT = argv[0]
ONLY = set(argv[1:])
os.makedirs(OUT, exist_ok=True)

TILE, SS = 32, 4                 # pixels per tile, supersampling factor
THETA = math.radians(35)         # camera tilt away from straight-down
pi = math.pi

bpy.ops.wm.read_factory_settings(use_empty=True)
scene = bpy.context.scene
scene.render.engine = 'CYCLES'
scene.cycles.samples = 24
scene.cycles.use_denoising = False
scene.cycles.max_bounces = 2
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


def mat(name, hexcol, metallic=0.0, rough=0.65, emit=None, estr=0.0):
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


HULL = mat('hull', '#b4bac2', 0.3, 0.55)
HULL2 = mat('hull2', '#868e99', 0.3, 0.6)
DARK = mat('dark', '#30343c', 0.4, 0.6)
TEAM = mat('team', '#ff00ff', 0.0, 0.8)
GLOW = mat('glow', '#30e8d0', 0.0, 0.4, '#30ffe0', 1.25)
GLOWDIM = mat('glowdim', '#1e8f88', 0.0, 0.3, '#30ffe0', 0.55)
WINDOW = mat('window', '#ffd890', 0.0, 0.4, '#ffd080', 2.5)
WALL = mat('wall', '#98a0ad', 0.1, 0.7)
WALL_D = mat('wall_d', '#667080', 0.1, 0.7)
ROOF = mat('roof', '#474e5b', 0.2, 0.6)
PLINTH = mat('plinth', '#565d6a', 0.1, 0.8)

# --- world, lights, camera -------------------------------------------------
world = bpy.data.worlds.new('w')
scene.world = world
try:
    world.use_nodes = True
except Exception:
    pass
bg = next(n for n in world.node_tree.nodes if n.type == 'BACKGROUND')
bg.inputs[0].default_value = (0.55, 0.62, 0.80, 1)
bg.inputs[1].default_value = 0.55


def add_sun(direction, energy, shadow=True, angle=0.06):
    l = bpy.data.lights.new('sun', 'SUN')
    l.energy = energy
    l.angle = angle
    l.use_shadow = shadow
    o = bpy.data.objects.new('sun', l)
    scene.collection.objects.link(o)
    o.rotation_euler = Vector(direction).normalized().to_track_quat('-Z', 'Y').to_euler()
    return o


add_sun((1.0, -0.45, -1.25), 3.6)            # key: from the west-north-west, shadows fall right/down
add_sun((-0.25, 1.0, -0.8), 1.1, False)      # fill from the camera side

camd = bpy.data.cameras.new('cam')
camd.type = 'ORTHO'
cam = bpy.data.objects.new('cam', camd)
scene.collection.objects.link(cam)
scene.camera = cam
D = 30
cam.location = (0, -D * math.sin(THETA), D * math.cos(THETA))
cam.rotation_euler = (THETA, 0, 0)
camd.clip_end = 200

bpy.ops.mesh.primitive_plane_add(size=40, location=(0, 0, 0))
catcher = bpy.context.active_object
catcher.is_shadow_catcher = True

root = bpy.data.objects.new('root', None)
pivot = bpy.data.objects.new('pivot', None)
scene.collection.objects.link(root)
scene.collection.objects.link(pivot)
pivot.parent = root
root.scale = (1, 1 / math.cos(THETA), 1)     # ground plane maps to square pixels

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


def box(sx, sy, sz, x=0.0, y=0.0, z=0.0, m=None, bevel=0.02, rot=(0, 0, 0)):
    bpy.ops.mesh.primitive_cube_add(size=1, location=(x, y, z + sz / 2), rotation=rot)
    o = bpy.context.active_object
    o.scale = (sx, sy, sz)
    _finish(o, m)
    if bevel:
        b = o.modifiers.new('b', 'BEVEL')
        b.width = bevel
        b.segments = 1
    return o


def cyl(r, h, x=0.0, y=0.0, z=0.0, m=None, verts=16, rot=(0, 0, 0), center=False):
    loc = (x, y, z) if center else (x, y, z + h / 2)
    bpy.ops.mesh.primitive_cylinder_add(radius=r, depth=h, vertices=verts, location=loc, rotation=rot)
    return _finish(bpy.context.active_object, m, 'sides' if verts > 8 else None)


def barrel(r, length, x=0.0, y=0.0, z=0.0, m=None, elev=0.0, yaw=0.0):
    """Cylinder starting at (x,y,z) pointing along +Y (rotated by yaw about Z, raised by elev)."""
    ax = Vector((math.sin(yaw) * math.cos(elev), math.cos(yaw) * math.cos(elev), math.sin(elev)))
    c = Vector((x, y, z)) + ax * (length / 2)
    bpy.ops.mesh.primitive_cylinder_add(radius=r, depth=length, vertices=10, location=c)
    o = bpy.context.active_object
    o.rotation_euler = ax.to_track_quat('Z', 'Y').to_euler()
    return _finish(o, m, 'sides')


def sphere(r, x=0.0, y=0.0, z=0.0, m=None, zs=1.0):
    bpy.ops.mesh.primitive_uv_sphere_add(radius=r, segments=20, ring_count=10, location=(x, y, z))
    o = bpy.context.active_object
    o.scale = (1, 1, zs)
    return _finish(o, m, 'all')


def torus(R, r, x=0.0, y=0.0, z=0.0, m=None):
    bpy.ops.mesh.primitive_torus_add(major_radius=R, minor_radius=r, major_segments=28, minor_segments=10,
                                     location=(x, y, z))
    return _finish(bpy.context.active_object, m, 'all')


def cone(r1, r2, h, x=0.0, y=0.0, z=0.0, m=None, rot=(0, 0, 0), verts=20):
    bpy.ops.mesh.primitive_cone_add(radius1=r1, radius2=r2, depth=h, vertices=verts, location=(x, y, z), rotation=rot)
    return _finish(bpy.context.active_object, m, 'sides')


def clear():
    for o in objs:
        me = o.data
        bpy.data.objects.remove(o, do_unlink=True)
        if me and me.users == 0:
            bpy.data.meshes.remove(me)
    objs.clear()


def render(name, canvas, dirs=1, scale=1.0):
    pivot.scale = (scale, scale, scale)
    res = canvas * TILE * SS
    scene.render.resolution_x = scene.render.resolution_y = res
    scene.render.resolution_percentage = 100
    camd.ortho_scale = canvas
    for k in range(dirs):
        pivot.rotation_euler = (0, 0, -2 * pi * k / dirs)
        catcher.hide_render = True
        for o in objs:
            o.visible_camera = True
        scene.render.filepath = os.path.join(OUT, f"{name}_{k:02d}.png")
        bpy.ops.render.render(write_still=True)
        catcher.hide_render = False
        for o in objs:
            o.visible_camera = False
        scene.render.filepath = os.path.join(OUT, f"{name}_{k:02d}_sh.png")
        bpy.ops.render.render(write_still=True)
    clear()


def tracks(half_w, length, w=0.16, h=0.14):
    for s in (-1, 1):
        box(w, length, h, x=s * half_w, m=DARK, bevel=0.04)
        box(w + 0.02, length * 0.7, 0.03, x=s * half_w, z=h - 0.01, m=HULL2, bevel=0.0)


# --- units (facing +Y) -----------------------------------------------------
def tank():
    tracks(0.25, 0.80)
    box(0.40, 0.72, 0.13, z=0.07, m=HULL)
    box(0.30, 0.14, 0.05, y=-0.26, z=0.20, m=DARK)
    box(0.34, 0.10, 0.04, y=0.27, z=0.20, m=HULL2)
    box(0.32, 0.34, 0.11, y=-0.02, z=0.20, m=TEAM, bevel=0.04)
    cyl(0.07, 0.03, x=0.06, y=-0.06, z=0.31, m=DARK, verts=8)
    barrel(0.036, 0.40, y=0.12, z=0.255, m=DARK)
    barrel(0.05, 0.07, y=0.50, z=0.255, m=HULL2)


def heavy():
    tracks(0.33, 0.92, w=0.2, h=0.16)
    box(0.52, 0.84, 0.16, z=0.07, m=HULL)
    box(0.56, 0.2, 0.06, y=-0.3, z=0.23, m=DARK)
    box(0.46, 0.44, 0.14, y=-0.02, z=0.23, m=TEAM, bevel=0.05)
    box(0.24, 0.2, 0.05, y=-0.08, z=0.37, m=HULL2)
    for s in (-1, 1):
        barrel(0.04, 0.44, x=s * 0.1, y=0.18, z=0.30, m=DARK)
        barrel(0.055, 0.07, x=s * 0.1, y=0.58, z=0.30, m=HULL2)


def harvester():
    tracks(0.33, 0.92, w=0.2, h=0.17)
    box(0.52, 0.86, 0.2, z=0.08, m=HULL)
    box(0.44, 0.2, 0.15, y=0.27, z=0.28, m=TEAM, bevel=0.04)
    box(0.34, 0.03, 0.06, y=0.375, z=0.34, m=WINDOW, bevel=0)
    bpy.ops.mesh.primitive_cylinder_add(radius=0.2, depth=0.46, vertices=16, location=(0, -0.14, 0.40),
                                        rotation=(pi / 2, 0, 0))
    _finish(bpy.context.active_object, GLOWDIM, 'sides')
    for yy in (-0.36, -0.14, 0.08):
        bpy.ops.mesh.primitive_cylinder_add(radius=0.215, depth=0.04, vertices=16, location=(0, yy, 0.40),
                                            rotation=(pi / 2, 0, 0))
        _finish(bpy.context.active_object, DARK, 'sides')
    box(0.66, 0.1, 0.12, y=0.47, z=0.0, m=DARK, bevel=0.03)
    for xx in (-0.24, -0.08, 0.08, 0.24):
        box(0.06, 0.08, 0.05, x=xx, y=0.54, z=0.0, m=HULL2, bevel=0.0)


def scout():
    for sx in (-1, 1):
        for sy in (-1, 1):
            bpy.ops.mesh.primitive_cylinder_add(radius=0.095, depth=0.08, vertices=12,
                                                location=(sx * 0.2, sy * 0.2, 0.095), rotation=(0, pi / 2, 0))
            _finish(bpy.context.active_object, DARK, 'sides')
    box(0.28, 0.56, 0.09, z=0.08, m=HULL)
    box(0.2, 0.16, 0.07, y=0.26, z=0.1, m=TEAM, bevel=0.03)
    box(0.22, 0.2, 0.08, y=-0.06, z=0.17, m=TEAM, bevel=0.04)
    box(0.16, 0.03, 0.04, y=0.045, z=0.2, m=WINDOW, bevel=0)
    barrel(0.022, 0.26, y=0.02, z=0.27, m=DARK)


def siege():
    tracks(0.25, 0.86)
    box(0.40, 0.80, 0.12, z=0.07, m=HULL)
    box(0.36, 0.30, 0.14, y=-0.2, z=0.19, m=TEAM, bevel=0.04)
    box(0.2, 0.2, 0.06, y=0.22, z=0.19, m=HULL2)
    barrel(0.05, 0.74, y=-0.18, z=0.30, m=DARK, elev=math.radians(14))
    barrel(0.065, 0.1, y=0.42, z=0.45, m=HULL2, elev=math.radians(14))


def launcher():
    tracks(0.25, 0.80)
    box(0.40, 0.74, 0.12, z=0.07, m=HULL)
    box(0.3, 0.16, 0.1, y=0.24, z=0.19, m=HULL2)
    box(0.40, 0.42, 0.16, y=-0.1, z=0.24, m=TEAM, bevel=0.03, rot=(math.radians(12), 0, 0))
    for xx in (-0.12, 0, 0.12):
        barrel(0.04, 0.06, x=xx, y=0.09, z=0.375, m=DARK, elev=math.radians(12))


def turret():
    cyl(0.40, 0.16, m=WALL_D, verts=8, rot=(0, 0, pi / 8))
    cyl(0.31, 0.07, z=0.16, m=TEAM, verts=8, rot=(0, 0, pi / 8))
    box(0.32, 0.38, 0.15, y=-0.02, z=0.23, m=HULL, bevel=0.04)
    barrel(0.045, 0.40, y=0.15, z=0.305, m=DARK)
    barrel(0.06, 0.07, y=0.52, z=0.305, m=HULL2)


# --- buildings (north = +Y, door faces south towards the camera) ------------
def hq():
    box(1.9, 1.9, 0.1, m=PLINTH, bevel=0.03)
    box(1.25, 1.2, 0.5, y=0.12, z=0.1, m=WALL, bevel=0.04)
    box(1.0, 0.95, 0.08, y=0.12, z=0.6, m=TEAM, bevel=0.02)
    box(0.8, 0.78, 0.3, y=0.12, z=0.68, m=WALL, bevel=0.04)
    cyl(0.26, 0.1, y=0.12, z=0.98, m=ROOF)
    sphere(0.19, y=0.12, z=1.13, m=GLOW)
    for sx in (-1, 1):
        for sy in (-1, 1):
            box(0.2, 0.2, 0.62, x=sx * 0.78, y=sy * 0.78, z=0.1, m=WALL_D, bevel=0.03)
            box(0.23, 0.23, 0.06, x=sx * 0.78, y=sy * 0.78, z=0.72, m=TEAM, bevel=0.01)
    box(0.42, 0.06, 0.3, y=-0.49, z=0.1, m=DARK, bevel=0.01)
    box(1.0, 0.03, 0.07, y=-0.49, z=0.46, m=WINDOW, bevel=0)
    box(0.6, 0.03, 0.06, y=-0.275, z=0.82, m=WINDOW, bevel=0)
    cyl(0.015, 0.55, x=0.28, y=0.38, z=0.98, m=DARK, verts=6)


def refinery():
    box(2.9, 1.9, 0.08, m=PLINTH, bevel=0.03)
    box(1.15, 1.2, 0.55, x=-0.8, y=0.2, z=0.08, m=WALL, bevel=0.04)
    box(1.19, 0.3, 0.06, x=-0.8, y=0.2, z=0.63, m=TEAM, bevel=0.01)
    box(0.8, 0.03, 0.07, x=-0.8, y=-0.41, z=0.42, m=WINDOW, bevel=0)
    for xx in (0.32, 1.05):
        cyl(0.34, 0.66, x=xx, y=0.45, z=0.08, m=HULL, verts=20)
        cyl(0.347, 0.1, x=xx, y=0.45, z=0.46, m=GLOW, verts=20)
        sphere(0.34, x=xx, y=0.45, z=0.74, m=HULL2, zs=0.35)
    cyl(0.09, 1.0, x=-1.22, y=0.72, z=0.08, m=WALL_D, verts=12)
    cyl(0.1, 0.08, x=-1.22, y=0.72, z=0.9, m=TEAM, verts=12)
    box(0.5, 0.09, 0.09, x=-0.1, y=0.45, z=0.3, m=HULL2, bevel=0.02)
    box(0.09, 0.5, 0.09, x=0.68, y=0.1, z=0.2, m=HULL2, bevel=0.02)
    # docking pad
    box(1.5, 0.82, 0.03, x=0.62, y=-0.5, z=0.08, m=DARK, bevel=0.0)
    for yy in (-0.89, -0.11):
        box(1.5, 0.04, 0.035, x=0.62, y=yy, z=0.08, m=GLOW, bevel=0)
    for xx in (-0.1, 1.34):
        box(0.08, 0.5, 0.035, x=xx, y=-0.5, z=0.08, m=TEAM, bevel=0)
    box(0.3, 0.3, 0.46, x=-0.42, y=-0.62, z=0.08, m=WALL_D, bevel=0.03)
    box(0.31, 0.31, 0.06, x=-0.42, y=-0.62, z=0.4, m=WINDOW, bevel=0)


def reactor():
    box(1.9, 1.9, 0.08, m=PLINTH, bevel=0.03)
    cyl(0.62, 0.14, z=0.08, m=WALL_D, verts=24)
    torus(0.56, 0.16, z=0.34, m=WALL)
    sphere(0.26, z=0.40, m=GLOW)
    cyl(0.40, 0.05, z=0.22, m=TEAM, verts=24)
    cyl(0.33, 0.06, z=0.23, m=DARK, verts=24)
    for i in range(4):
        a = pi / 4 + i * pi / 2
        x, y = 0.80 * math.cos(a), 0.80 * math.sin(a)
        box(0.26, 0.26, 0.5, x=x, y=y, z=0.08, m=WALL_D, bevel=0.03)
        box(0.29, 0.29, 0.06, x=x, y=y, z=0.58, m=TEAM, bevel=0.01)
        box(0.1, 0.1, 0.05, x=x, y=y, z=0.64, m=GLOW, bevel=0)


def barracks():
    box(1.9, 1.9, 0.08, m=PLINTH, bevel=0.03)
    box(1.5, 1.05, 0.4, y=0.3, z=0.08, m=WALL, bevel=0.04)
    box(1.6, 1.15, 0.07, y=0.3, z=0.48, m=ROOF, bevel=0.02)
    box(0.34, 1.17, 0.08, y=0.3, z=0.48, m=TEAM, bevel=0.01)
    for xx in (-0.5, 0.5):
        cyl(0.11, 0.08, x=xx, y=0.45, z=0.55, m=WALL_D, verts=12)
    box(0.3, 0.05, 0.28, y=-0.235, z=0.08, m=DARK, bevel=0.01)
    for xx in (-0.5, 0.5):
        box(0.3, 0.03, 0.07, x=xx, y=-0.235, z=0.3, m=WINDOW, bevel=0)
    for xx in (-0.62, 0.62):
        box(0.5, 0.12, 0.13, x=xx, y=-0.72, z=0.08, m=WALL_D, bevel=0.03)
    cyl(0.015, 0.7, x=0.8, y=-0.35, z=0.08, m=DARK, verts=6)
    box(0.22, 0.02, 0.13, x=0.68, y=-0.35, z=0.62, m=TEAM, bevel=0)


def factory():
    box(2.9, 1.9, 0.08, m=PLINTH, bevel=0.03)
    box(1.9, 1.45, 0.58, x=-0.42, y=0.18, z=0.08, m=WALL, bevel=0.04)
    box(1.6, 1.45, 0.1, x=-0.42, y=0.18, z=0.66, m=ROOF, bevel=0.03)
    box(1.0, 1.45, 0.09, x=-0.42, y=0.18, z=0.76, m=WALL_D, bevel=0.03)
    box(1.0, 0.05, 0.42, x=-0.42, y=-0.55, z=0.08, m=DARK, bevel=0.0)
    box(1.25, 0.06, 0.08, x=-0.42, y=-0.555, z=0.52, m=TEAM, bevel=0.01)
    box(1.0, 0.36, 0.02, x=-0.42, y=-0.76, z=0.08, m=ROOF, bevel=0.0)
    for xx in (-0.9, 0.06):
        box(0.05, 0.36, 0.025, x=xx, y=-0.76, z=0.08, m=WINDOW, bevel=0)
    box(0.72, 1.0, 0.38, x=1.02, y=0.35, z=0.08, m=WALL_D, bevel=0.04)
    box(0.5, 0.03, 0.07, x=1.02, y=-0.155, z=0.3, m=WINDOW, bevel=0)
    box(0.76, 0.3, 0.05, x=1.02, y=0.35, z=0.46, m=TEAM, bevel=0.01)
    cyl(0.12, 0.3, x=1.2, y=0.65, z=0.46, m=HULL2, verts=12)
    box(0.5, 0.5, 0.03, x=1.02, y=-0.6, z=0.08, m=DARK, bevel=0)
    for yy in (-0.3, 0.18, 0.66):
        box(0.5, 0.16, 0.06, x=-0.42, y=yy, z=0.85, m=DARK, bevel=0.02)
    for xx in (-1.42, 0.58):
        box(0.12, 1.3, 0.3, x=xx, y=0.18, z=0.08, m=WALL_D, bevel=0.03)
    for xx in (-0.8, -0.42, -0.04):
        box(0.06, 0.02, 0.36, x=xx, y=-0.58, z=0.1, m=HULL2, bevel=0)
    box(0.3, 0.3, 0.14, x=1.02, y=-0.6, z=0.11, m=HULL2, bevel=0.03)


def silo():
    box(1.9, 1.9, 0.08, m=PLINTH, bevel=0.03)
    for sx in (-1, 1):
        for sy in (-1, 1):
            cyl(0.36, 0.16, x=sx * 0.45, y=sy * 0.45, z=0.08, m=WALL_D, verts=20)
            sphere(0.33, x=sx * 0.45, y=sy * 0.45, z=0.26, m=GLOWDIM, zs=0.8)
            cyl(0.1, 0.05, x=sx * 0.45, y=sy * 0.45, z=0.5, m=DARK, verts=10)
    cyl(0.2, 0.42, z=0.08, m=WALL, verts=12)
    cyl(0.22, 0.06, z=0.5, m=TEAM, verts=12)


def radar():
    box(1.9, 1.9, 0.08, m=PLINTH, bevel=0.03)
    box(1.2, 1.1, 0.3, y=0.2, z=0.08, m=WALL, bevel=0.04)
    box(1.24, 0.25, 0.06, y=0.2, z=0.38, m=TEAM, bevel=0.01)
    box(0.8, 0.03, 0.07, y=-0.355, z=0.22, m=WINDOW, bevel=0)
    cyl(0.12, 0.5, y=0.2, z=0.38, m=WALL_D, verts=10)
    cone(0.62, 0.12, 0.22, x=0.0, y=0.2, z=1.05, m=HULL, rot=(math.radians(-150), math.radians(25), 0))
    sphere(0.07, x=-0.14, y=-0.04, z=1.25, m=GLOW)
    box(0.4, 0.4, 0.2, x=-0.6, y=-0.65, z=0.08, m=WALL_D, bevel=0.03)
    box(0.2, 0.2, 0.05, x=-0.6, y=-0.65, z=0.28, m=GLOW, bevel=0)


JOBS = [
    ('tank', tank, 2, 16, 1.12), ('heavy', heavy, 2, 16, 1.08), ('harvester', harvester, 2, 16, 1.05),
    ('scout', scout, 2, 16, 1.35), ('siege', siege, 2, 16, 1.12), ('launcher', launcher, 2, 16, 1.12),
    ('turret', turret, 2, 16),
    ('hq', hq, 4, 1), ('refinery', refinery, 5, 1), ('reactor', reactor, 4, 1),
    ('barracks', barracks, 4, 1), ('factory', factory, 5, 1), ('silo', silo, 4, 1), ('radar', radar, 4, 1),
]
for name, fn, canvas, dirs, *rest in JOBS:
    if ONLY and name not in ONLY:
        continue
    fn()
    render(name, canvas, dirs, rest[0] if rest else 1.0)
print("SPRITES DONE")
