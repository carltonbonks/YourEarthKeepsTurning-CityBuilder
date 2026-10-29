"""Building blocks for code-built models, shared by every script in art/models/.

A model script defines build(kit) and makes its parts with the helpers here. Units are metres:
a person stands about 1.8 tall, the ground is z = 0, the model's middle (or feet) is the origin
and it faces +x. Keep parts low-poly and flat-shaded; colour comes from mat().
"""
import math

import bpy

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


def _finish(m, loc, rot, scale):
    obj = bpy.context.object
    obj.data.materials.append(m)
    for p in obj.data.polygons:
        p.use_smooth = False
    obj.rotation_euler = rot
    obj.scale = scale
    return obj


def box(m, loc, size, rot=(0, 0, 0)):
    """A box of the given full size (x, y, z) centred on loc."""
    bpy.ops.mesh.primitive_cube_add(size=1, location=loc)
    return _finish(m, loc, rot, size)


def cylinder(m, loc, radius, depth, sides=8, rot=(0, 0, 0), scale=(1, 1, 1)):
    bpy.ops.mesh.primitive_cylinder_add(vertices=sides, radius=radius, depth=depth, location=loc)
    return _finish(m, loc, rot, scale)


def cone(m, loc, r1, r2, depth, sides=8, rot=(0, 0, 0), scale=(1, 1, 1)):
    bpy.ops.mesh.primitive_cone_add(vertices=sides, radius1=r1, radius2=r2, depth=depth, location=loc)
    return _finish(m, loc, rot, scale)


def ball(m, loc, radius, rot=(0, 0, 0), scale=(1, 1, 1), detail=1):
    bpy.ops.mesh.primitive_ico_sphere_add(subdivisions=detail, radius=radius, location=loc)
    return _finish(m, loc, rot, scale)


def limb(m, a, b, radius, sides=6):
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
    return obj


def forget():
    """Called by the renderer between models, after the scene is emptied."""
    _mats.clear()
