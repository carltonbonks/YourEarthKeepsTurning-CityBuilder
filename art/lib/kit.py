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


def forget():
    """Called by the renderer between models, after the scene is emptied."""
    _mats.clear()
