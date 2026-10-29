"""Building blocks for code-built models, shared by every script in art/models/.

A model script defines build(kit) and makes its parts with the helpers here. Units are metres:
a person stands about 1.8 tall, the ground is z = 0, the model's middle (or feet) is the origin
and it faces +x. Keep parts low-poly and flat-shaded; colour comes from mat().

Walkers move by joints: a part made with on=<joint> swings with it. The renderer poses joints by
name for each animation frame (tools/render_art.py POSES): arm_l, arm_r, leg_l, leg_r for people
(humanoid() makes them), leg_fl, leg_fr, leg_bl, leg_br and head for beasts. A joint swings round
the model's left-right axis, so a limb swings forward and back.
"""
import math

import bpy
from mathutils import Matrix

_mats = {}


def mat(name, rgb, rough=0.9, noise=0.35, scale=18.0):
    """A matte material of colour rgb (0-1 sRGB) with a little noise in its colour, so flat faces don't look like plastic.
    Materials are shared by name within one model."""
    if name in _mats:
        return _mats[name]
    m = bpy.data.materials.new(name)
    m.use_nodes = True
    nt = m.node_tree
    bsdf = nt.nodes["Principled BSDF"]
    bsdf.inputs["Roughness"].default_value = rough
    # Colours are written as they look (sRGB, like a colour picker); Blender wants them linear.
    r, g, b = [c ** 2.2 for c in rgb]
    if noise > 0.0:
        tex = nt.nodes.new("ShaderNodeTexNoise")
        tex.inputs["Scale"].default_value = scale
        tex.inputs["Detail"].default_value = 6.0
        ramp = nt.nodes.new("ShaderNodeValToRGB")
        lo, hi = 1.0 - noise, 1.0 + noise * 0.5
        ramp.color_ramp.elements[0].color = (r * lo, g * lo, b * lo, 1)
        ramp.color_ramp.elements[1].color = (min(1, r * hi), min(1, g * hi), min(1, b * hi), 1)
        nt.links.new(tex.outputs["Fac"], ramp.inputs["Fac"])
        nt.links.new(ramp.outputs["Color"], bsdf.inputs["Base Color"])
    else:
        bsdf.inputs["Base Color"].default_value = (r, g, b, 1)
    _mats[name] = m
    return m


def _finish(m, loc, rot, scale, on=None):
    obj = bpy.context.object
    obj.data.materials.append(m)
    for p in obj.data.polygons:
        p.use_smooth = False
    obj.rotation_euler = rot
    obj.scale = scale
    _attach(obj, on)
    return obj


def _attach(obj, on):
    if on is not None:
        obj.parent = on
        obj.matrix_parent_inverse = Matrix.Translation(on.location).inverted()


def joint(name, loc):
    """A named pivot the renderer swings for animation (see the module note)."""
    j = bpy.data.objects.new(name, None)
    bpy.context.scene.collection.objects.link(j)
    j.location = loc
    return j


def box(m, loc, size, rot=(0, 0, 0), on=None):
    """A box of the given full size (x, y, z) centred on loc."""
    bpy.ops.mesh.primitive_cube_add(size=1, location=loc)
    return _finish(m, loc, rot, size, on)


def cylinder(m, loc, radius, depth, sides=8, rot=(0, 0, 0), scale=(1, 1, 1), on=None):
    bpy.ops.mesh.primitive_cylinder_add(vertices=sides, radius=radius, depth=depth, location=loc)
    return _finish(m, loc, rot, scale, on)


def cone(m, loc, r1, r2, depth, sides=8, rot=(0, 0, 0), scale=(1, 1, 1), on=None):
    bpy.ops.mesh.primitive_cone_add(vertices=sides, radius1=r1, radius2=r2, depth=depth, location=loc)
    return _finish(m, loc, rot, scale, on)


def ball(m, loc, radius, rot=(0, 0, 0), scale=(1, 1, 1), detail=1, on=None):
    bpy.ops.mesh.primitive_ico_sphere_add(subdivisions=detail, radius=radius, location=loc)
    return _finish(m, loc, rot, scale, on)


def limb(m, a, b, radius, sides=6, on=None):
    """A cylinder from point a to point b (a leg, an arm, a spear shaft)."""
    ax, ay, az = a
    bx, by, bz = b
    dx, dy, dz = bx - ax, by - ay, bz - az
    length = math.sqrt(dx * dx + dy * dy + dz * dz)
    tilt = math.acos(max(-1.0, min(1.0, dz / length))) if length > 0 else 0.0
    turn = math.atan2(dy, dx)
    bpy.ops.mesh.primitive_cylinder_add(vertices=sides, radius=radius, depth=length,
        location=((ax + bx) / 2, (ay + by) / 2, (az + bz) / 2))
    obj = bpy.context.object
    obj.rotation_euler = (0, tilt, turn)
    obj.data.materials.append(m)
    for p in obj.data.polygons:
        p.use_smooth = False
    _attach(obj, on)
    return obj


def humanoid(skin, top, legs, hair=None, cloak=None, boots=None, height=1.0, bulk=1.0, helm=None, skirt=True):
    """A standing person with swinging arms and legs, feet at the origin, facing +x. Materials:
    skin, top (tunic, mail), legs, and optional hair, cloak (over the shoulders), boots, helm.
    Returns the arm joints and where the hands and head are, for gear: {"arm_r", "arm_l",
    "hand_r", "hand_l", "head"} (the right hand holds the weapon, the left a shield)."""
    h, b = height, bulk
    for s, name in ((1, "leg_l"), (-1, "leg_r")):
        hip = (0, s * 0.11 * b, 0.82 * h)
        j = joint(name, hip)
        limb(legs, hip, (0.02, s * 0.10 * b, 0.06), 0.075 * b, on=j)
        box(boots or legs, (0.05, s * 0.11 * b, 0.04), (0.24, 0.12 * b, 0.09), on=j)
    if skirt:
        cone(top, (0, 0, 0.93 * h), 0.27 * b, 0.21 * b, 0.5 * h, sides=8)
    cylinder(top, (0, 0, 1.30 * h), 0.21 * b, 0.42 * h, sides=8, scale=(0.85, 1, 1))
    if cloak is not None:
        cone(cloak, (-0.03, 0, 1.43 * h), 0.31 * b, 0.15 * b, 0.22 * h, sides=8)
    shoulder = 1.45 * h
    out = {}
    for s, name in ((1, "arm_l"), (-1, "arm_r")):
        at = (0, s * 0.26 * b, shoulder)
        j = joint(name, at)
        hand = (0.04, s * 0.29 * b, shoulder - 0.48 * h)
        limb(top, at, (0.02, s * 0.27 * b, shoulder - 0.22 * h), 0.068 * b, on=j)
        limb(skin, (0.02, s * 0.27 * b, shoulder - 0.22 * h), hand, 0.058 * b, on=j)
        out[name] = j
        out["hand_l" if s > 0 else "hand_r"] = hand
    head = (0, 0, 1.68 * h)
    ball(skin, head, 0.14, scale=(1.0, 0.95, 1.1))
    if hair is not None:
        ball(hair, (head[0] - 0.04, 0, head[2] + 0.05), 0.145, scale=(1.0, 1.0, 0.9))
    if helm is not None:
        ball(helm, (head[0], 0, head[2] + 0.04), 0.155, scale=(1.05, 1.0, 0.85))
    out["head"] = head
    return out


def quadruped(fur, legs, length=1.0, height=1.0, girth=1.0, belly=None):
    """A four-legged beast with swinging legs, feet at the origin, facing +x: body, legs, neck and
    head. Returns where the head is ({"head": (x, y, z), "rump": (x, y, z)}) for ears, snout, horns."""
    L, H, G = length, height, girth
    ball(fur, (0.05 * L, 0, 0.62 * H), 0.32, scale=(1.55 * L, 0.72 * G, 0.78 * H))
    if belly is not None:
        ball(belly, (0.30 * L, 0, 0.52 * H), 0.2, scale=(1.0 * L, 0.8 * G, 0.9 * H))
    for x, front in ((0.34 * L, "f"), (-0.30 * L, "b")):
        for s, side in ((1, "l"), (-1, "r")):
            hip = (x, s * 0.12 * G, 0.58 * H)
            j = joint("leg_" + front + side, hip)
            limb(legs, hip, (x + 0.03, s * 0.12 * G, 0.02), 0.055 * G * (1.2 if H > 1.2 else 1.0), on=j)
    neck_a, head = (0.42 * L, 0, 0.70 * H), (0.74 * L, 0, 0.66 * H)
    limb(fur, neck_a, (0.66 * L, 0, 0.66 * H), 0.13 * G)
    ball(fur, head, 0.15 * G, scale=(1.2, 0.9, 0.9))
    return {"head": head, "rump": (-0.45 * L, 0, 0.70 * H)}


# --- Buildings -------------------------------------------------------------------------------
# A building fills a plot about 3.3 by 2.9 model metres (art/manifest.json world_per_unit 9), its
# middle at the origin on the ground; +x is the side facing the camera's right, -y its left.


def town_mats():
    """The town's everyday materials, so buildings share a look: daub, thatch, wood, dark_wood,
    hide, stone, dark_stone, straw, earth, iron, bronze, bone, cloth (red), cloth_blue, rope."""
    return {
        "daub": mat("daub", (0.46, 0.33, 0.20), noise=0.45),
        "thatch": mat("thatch", (0.62, 0.47, 0.22), noise=0.6, scale=30.0),
        "wood": mat("wood", (0.36, 0.24, 0.14), noise=0.45),
        "dark_wood": mat("dark_wood", (0.20, 0.13, 0.08), noise=0.4),
        "hide": mat("hide", (0.50, 0.36, 0.24), noise=0.3),
        "stone": mat("stone", (0.42, 0.40, 0.37), noise=0.4),
        "dark_stone": mat("dark_stone", (0.28, 0.27, 0.26), noise=0.4),
        "straw": mat("straw", (0.74, 0.62, 0.34), noise=0.5, scale=40.0),
        "earth": mat("earth", (0.30, 0.22, 0.15), noise=0.5),
        "iron": mat("iron", (0.30, 0.31, 0.33), rough=0.5, noise=0.25),
        "bronze": mat("bronze", (0.72, 0.48, 0.22), rough=0.4, noise=0.2),
        "bone": mat("bone", (0.85, 0.80, 0.68), noise=0.2),
        "cloth": mat("cloth", (0.55, 0.16, 0.12), noise=0.3),
        "cloth_blue": mat("cloth_blue", (0.20, 0.28, 0.50), noise=0.3),
        "rope": mat("rope", (0.58, 0.48, 0.30), noise=0.3),
    }


def glow(name, rgb, strength=6.0):
    """A material that gives off light (embers, a forge's mouth, a beacon)."""
    if name in _mats:
        return _mats[name]
    m = bpy.data.materials.new(name)
    m.use_nodes = True
    bsdf = m.node_tree.nodes["Principled BSDF"]
    r, g, b = [c ** 2.2 for c in rgb]
    bsdf.inputs["Base Color"].default_value = (r, g, b, 1)
    bsdf.inputs["Emission Color"].default_value = (r, g, b, 1)
    bsdf.inputs["Emission Strength"].default_value = strength
    _mats[name] = m
    return m


def mesh(m, verts, faces, loc=(0, 0, 0), rot=(0, 0, 0)):
    """A solid from its corner points and faces (lists of corner indices)."""
    data = bpy.data.meshes.new("mesh")
    data.from_pydata(verts, [], faces)
    data.update()
    obj = bpy.data.objects.new("mesh", data)
    bpy.context.scene.collection.objects.link(obj)
    obj.location = loc
    obj.rotation_euler = rot
    obj.data.materials.append(m)
    return obj


def gable(m, loc, length, width, height, turn=0.0, overhang=0.12):
    """A pitched roof (a long prism, ridge along x before it is turned `turn` radians round z), its
    eaves at loc's height."""
    x, y = length / 2 + overhang, width / 2 + overhang
    v = [(-x, -y, 0), (x, -y, 0), (x, y, 0), (-x, y, 0), (-x, 0, height), (x, 0, height)]
    f = [(0, 1, 5, 4), (2, 3, 4, 5), (0, 4, 3), (1, 2, 5), (0, 3, 2, 1)]
    return mesh(m, v, f, loc, (0, 0, turn))


def slope(m, loc, length, width, low, high, turn=0.0):
    """A lean-to roof: a slab rising from `low` at -y to `high` at +y (an awning, a shed roof)."""
    x, y, t = length / 2, width / 2, 0.05
    v = [(-x, -y, low), (x, -y, low), (x, y, high), (-x, y, high),
        (-x, -y, low + t), (x, -y, low + t), (x, y, high + t), (-x, y, high + t)]
    f = [(0, 1, 2, 3), (4, 7, 6, 5), (0, 4, 5, 1), (1, 5, 6, 2), (2, 6, 7, 3), (3, 7, 4, 0)]
    return mesh(m, v, f, loc, (0, 0, turn))


def turned(x, y, turn):
    """Point (x, y) turned `turn` radians round the origin."""
    c, s = math.cos(turn), math.sin(turn)
    return (x * c - y * s, x * s + y * c)


def hall(wall, roof, length, width, wall_h, roof_h, at=(0, 0), turn=0.0, door=None, beams=None):
    """A long rectangular building: walls, a pitched roof along its length, and a door on the long
    side facing -y before the turn, toward the camera (door = the door's material). beams = corner posts' material."""
    x, y = at
    box(wall, (x, y, wall_h / 2), (length, width, wall_h), rot=(0, 0, turn))
    gable(roof, (x, y, wall_h), length, width, roof_h, turn)
    if beams is not None:
        for sx in (-1, 1):
            for sy in (-1, 1):
                px, py = turned(sx * length / 2, sy * width / 2, turn)
                box(beams, (x + px, y + py, wall_h / 2), (0.1, 0.1, wall_h), rot=(0, 0, turn))
    if door is not None:
        dx, dy = turned(0, -width / 2 - 0.02, turn)
        box(door, (x + dx, y + dy, 0.4), (0.45, 0.06, 0.8), rot=(0, 0, turn))


def round_hut(wall, roof, r=1.0, wall_h=0.9, roof_h=1.25, at=(0, 0), door=None, sides=10):
    """A round hut with a cone roof, its door facing +x (toward the camera's right)."""
    x, y = at
    cylinder(wall, (x, y, wall_h / 2), r, wall_h, sides=sides)
    cone(roof, (x, y, wall_h + roof_h / 2), r * 1.35, 0.08, roof_h, sides=sides)
    if door is not None:
        box(door, (x + r * 0.97, y, 0.36), (0.1, 0.5, 0.72))


def post(m, x, y, h, r=0.06, lean=(0.0, 0.0)):
    """An upright pole from the ground to height h (leaning by `lean` at the top)."""
    return limb(m, (x, y, 0), (x + lean[0], y + lean[1], h), r, sides=6)


def fence(m, points, h=0.7, gap=0.32, r=0.045, rail=True, closed=False):
    """Stakes along a line through `points` (and back to the first if closed), with a rail."""
    pts = list(points) + ([points[0]] if closed else [])
    for (ax, ay), (bx, by) in zip(pts, pts[1:]):
        d = math.hypot(bx - ax, by - ay)
        n = max(1, int(d / gap))
        for i in range(n + (0 if closed else 1)):
            t = i / n
            post(m, ax + (bx - ax) * t, ay + (by - ay) * t, h * (0.9 + 0.2 * ((i * 7) % 3) / 2), r)
        if rail:
            limb(m, (ax, ay, h * 0.7), (bx, by, h * 0.7), r * 0.7, sides=5)


def stones(m, at, r, n=10, size=0.11, z=0.05):
    """A ring of stones round `at` (a hearth ring, a hut's foot)."""
    for i in range(n):
        a = i / n * 2 * math.pi
        ball(m, (at[0] + r * math.cos(a), at[1] + r * math.sin(a), z), size * (0.8 + 0.4 * ((i * 5) % 3) / 2),
            scale=(1.2, 1.0, 0.7))


def pile(m, at, n=6, size=0.14, spread=0.25, seed=1):
    """A heap of lumps (rocks, sacks, ore) round `at`."""
    rnd = _rand(seed)
    for i in range(n):
        x = at[0] + (rnd() - 0.5) * spread * 2
        y = at[1] + (rnd() - 0.5) * spread * 2
        z = size * 0.6 + (size * 0.9 if i >= n * 2 // 3 else 0.0)
        ball(m, (x, y, z), size * (0.7 + 0.6 * rnd()), scale=(1.2, 1.0, 0.8), rot=(0, 0, rnd() * 3))


def logs(m, at, n=4, length=0.9, r=0.08, turn=0.0):
    """Logs stacked side by side and on top of each other, lying along x before the turn."""
    k = 0
    row = 0
    while k < n:
        across = n - k if row == 0 else max(1, min(n - k, 3 - row))
        for i in range(across):
            off = (i - (across - 1) / 2) * r * 2.1
            dx, dy = turned(0, off, turn)
            ax, ay = turned(-length / 2, 0, turn)
            bx, by = turned(length / 2, 0, turn)
            z = r + row * r * 1.8
            limb(m, (at[0] + dx + ax, at[1] + dy + ay, z), (at[0] + dx + bx, at[1] + dy + by, z), r, sides=7)
            k += 1
        row += 1


def fire(at, size=0.25, logs_m=None, z=0.0):
    """A small fire: glowing embers and a flame, on crossed logs, standing at height z."""
    if logs_m is not None:
        for a in (0.4, 2.0):
            dx, dy = math.cos(a) * size * 1.4, math.sin(a) * size * 1.4
            limb(logs_m, (at[0] - dx, at[1] - dy, z + 0.05), (at[0] + dx, at[1] + dy, z + 0.05), size * 0.22, sides=6)
    ball(glow("ember", (1.0, 0.45, 0.12), 5.0), (at[0], at[1], z + 0.06), size * 0.7, scale=(1, 1, 0.4))
    cone(glow("flame", (1.0, 0.7, 0.25), 9.0), (at[0], at[1], z + size * 0.9), size * 0.45, 0.0, size * 1.6, sides=5)


def barrel(m, at, r=0.17, h=0.42, band=None):
    cylinder(m, (at[0], at[1], h / 2), r, h, sides=8, scale=(1, 1, 1))
    if band is not None:
        for z in (0.2 * h, 0.8 * h):
            cylinder(band, (at[0], at[1], z), r * 1.04, 0.03, sides=8)


def banner(pole, cloth, at, h=1.9, width=0.38, drop=0.6, turn=0.0):
    """A pole with a cloth hung from a crossbar near its top."""
    post(pole, at[0], at[1], h, 0.035)
    dx, dy = turned(width / 2, 0, turn)
    limb(pole, (at[0] - dx, at[1] - dy, h - 0.05), (at[0] + dx, at[1] + dy, h - 0.05), 0.02, sides=5)
    box(cloth, (at[0], at[1], h - 0.07 - drop / 2), (width * 0.9, 0.03, drop), rot=(0, 0, turn))


def stall(awning, counter, poles, at=(0, 0), length=2.2, depth=1.2, turn=0.0):
    """A market stall: a counter under a sloping cloth awning on four poles, open toward the camera
    (-y). Returns the counter top's middle (x, y, z) for the goods."""
    x, y = at
    for sx in (-1, 1):
        for sy, h in ((-1, 1.45), (1, 1.75)):
            px, py = turned(sx * length / 2, sy * depth / 2, turn)
            post(poles, x + px, y + py, h, 0.045)
    slope(awning, (x, y, 0), length + 0.2, depth + 0.3, 1.4, 1.75, turn)
    cx, cy = turned(0, -depth / 2 + 0.25, turn)
    box(counter, (x + cx, y + cy, 0.38), (length * 0.92, 0.42, 0.76), rot=(0, 0, turn))
    bx, by = turned(0, depth / 2 - 0.15, turn)
    box(counter, (x + bx, y + by, 0.55), (length * 0.9, 0.12, 1.1), rot=(0, 0, turn))
    return (x + cx, y + cy, 0.77)


def tent(hide, poles, at=(0, 0), r=0.8, h=1.5, sides=7):
    """A cone tent of hides with poles poking out of its top."""
    cone(hide, (at[0], at[1], h / 2), r, 0.06, h, sides=sides)
    for i in range(4):
        a = i * 1.6
        limb(poles, (at[0] + 0.05 * math.cos(a), at[1] + 0.05 * math.sin(a), h * 0.9),
            (at[0] + 0.25 * math.cos(a), at[1] + 0.25 * math.sin(a), h + 0.35), 0.025, sides=5)
    box(poles, (at[0] + r * 0.6, at[1] - r * 0.55, 0.3), (0.04, 0.3, 0.6), rot=(0, 0, -0.8))


def _rand(seed):
    state = [seed * 2654435761 % 4294967296 or 1]

    def nxt():
        state[0] = (1103515245 * state[0] + 12345) % 2147483648
        return state[0] / 2147483648
    return nxt


def forget():
    """Called by the renderer between models, after the scene is emptied."""
    _mats.clear()
