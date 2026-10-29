"""Renders the map art in art/manifest.json into sprites the game draws (game/sprite_book.gd).

Run it through tools/render_art.sh, which runs it in Blender's Python (the bpy package). For each id
it builds the model, points an orthographic camera at it from the map's own angle (the tilted view
in game/arena_view.gd: turned 45 degrees, looking down 30 degrees so the ground squashes 2:1), and
renders its frames into art/sprites/<id>.png: one row per facing, and along each row the
animations in ANIMS (walkers with a rig), one frame (buildings) or one per variant (props). art/sprites/index.json gets
what the game needs to place each frame: frame size, facings, where the feet are, pixels per model
unit and how tall the figure stands.

Coordinates: the sim's map has y pointing down the screen; Blender's ground has y pointing away. A
sim point (x, y) is Blender (x, -y), so the camera sits toward Blender (+x, -y) and a facing of
angle a in the sim (0 = +x, turning toward +y) is a turn of -a round Blender's z.
"""
import importlib.util
import json
import math
import os
import sys

import bpy
from bpy_extras.object_utils import world_to_camera_view
from mathutils import Vector
from PIL import Image

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
sys.path.insert(0, os.path.join(ROOT, "art", "lib"))
import kit  # noqa: E402

ELEVATION = math.radians(30.0)  # sin(30) = 0.5, ArenaView.ISO_SQUASH
SAMPLES = 24


def load_model(path):
    spec = importlib.util.spec_from_file_location("model", os.path.join(ROOT, path))
    mod = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(mod)
    return mod


def empty_scene():
    bpy.ops.wm.read_factory_settings(use_empty=True)
    kit.forget()


def light_and_camera(row):
    sc = bpy.context.scene
    sc.render.engine = "CYCLES"
    sc.cycles.samples = SAMPLES
    sc.cycles.device = "CPU"
    sc.cycles.seed = 1
    sc.render.resolution_x, sc.render.resolution_y = row["frame"]
    sc.render.film_transparent = True
    sc.render.image_settings.file_format = "PNG"
    sc.render.image_settings.color_mode = "RGBA"
    sc.view_settings.view_transform = "Standard"
    world = bpy.data.worlds.new("sky")
    sc.world = world
    world.use_nodes = True
    world.node_tree.nodes["Background"].inputs[0].default_value = (0.05, 0.055, 0.07, 1)
    world.node_tree.nodes["Background"].inputs[1].default_value = 1.0
    cam = bpy.data.cameras.new("cam")
    cam.type = "ORTHO"
    cam.ortho_scale = row["ortho"]
    cam.sensor_fit = "HORIZONTAL"  # ortho spans the frame's width, even for a tall frame
    co = bpy.data.objects.new("cam", cam)
    sc.collection.objects.link(co)
    sc.camera = co
    # Aim a little above the ground so tall things fit the frame with the feet low in it.
    w, h = row["frame"]
    aim = Vector((0, 0, row["ortho"] * h / w * 0.22))
    away = Vector((math.cos(ELEVATION) * math.cos(-math.pi / 4), math.cos(ELEVATION) * math.sin(-math.pi / 4), math.sin(ELEVATION)))
    co.location = aim + away * 30.0
    co.rotation_euler = (aim - co.location).to_track_quat("-Z", "Y").to_euler()
    # A warm low key light from the upper left of the screen and a cold rim from behind.
    key = bpy.data.lights.new("key", "SUN")
    key.energy = 6.5
    key.color = (1.0, 0.82, 0.62)
    key.angle = math.radians(8)
    ko = bpy.data.objects.new("key", key)
    sc.collection.objects.link(ko)
    ko.rotation_euler = (math.radians(50), 0, math.radians(-150))
    rim = bpy.data.lights.new("rim", "SUN")
    rim.energy = 1.2
    rim.color = (0.55, 0.65, 0.95)
    ro = bpy.data.objects.new("rim", rim)
    sc.collection.objects.link(ro)
    ro.rotation_euler = (math.radians(60), 0, math.radians(60))
    return sc, co


## Animations every walker gets, in the order they sit along each row of its sheet, and their frames.
ANIMS = [("idle", 1), ("walk", 6), ("attack", 4)]
## How an attack swings, frame by frame: the weapon arm (radians round the left-right axis: + is up and
## back, - forward), the other arm, and how far a beast lunges (model units along its facing).
ATTACK_ARM = [1.4, 2.5, -0.6, -1.0]
ATTACK_OFF_ARM = [-0.3, -0.4, 0.3, 0.2]
ATTACK_LUNGE = [0.0, -0.08, 0.22, 0.12]
STRIDE = 0.5  ## How far legs swing at mid-stride, radians.


def pose(rig, anim, t, n, joints, pivot, facing_angle):
    """Sets the joints (and the whole figure's lean) for frame t of n of an animation."""
    for j in joints.values():
        j.rotation_euler = (0, 0, 0)
    pivot.location = (0, 0, 0)
    swing = {}
    if anim == "walk":
        p = math.sin(2 * math.pi * t / n)
        if rig == "humanoid":
            swing = {"leg_l": STRIDE * p, "leg_r": -STRIDE * p, "arm_l": -0.7 * STRIDE * p, "arm_r": 0.7 * STRIDE * p}
        elif rig == "quadruped":
            swing = {"leg_fl": 0.9 * STRIDE * p, "leg_br": 0.9 * STRIDE * p, "leg_fr": -0.9 * STRIDE * p, "leg_bl": -0.9 * STRIDE * p}
        else:
            pivot.location = (0, 0, 0.03 * abs(p))
    elif anim == "attack":
        if rig == "humanoid":
            swing = {"arm_r": ATTACK_ARM[t], "arm_l": ATTACK_OFF_ARM[t]}
            if t >= 2:
                swing.update({"leg_l": -0.3, "leg_r": 0.25})
        else:
            lunge = ATTACK_LUNGE[t]
            pivot.location = (lunge * math.cos(-facing_angle), lunge * math.sin(-facing_angle), 0)
            if rig == "quadruped":
                swing = {"leg_fl": -2.0 * ATTACK_LUNGE[t], "leg_fr": -2.4 * ATTACK_LUNGE[t]}
    for name, angle in swing.items():
        if name in joints:
            joints[name].rotation_euler = (0, angle, 0)


def build_scene(row, variant):
    """Builds the model (variant `variant` for props that come in several looks) under one pivot to turn
    it by, and returns the pivot and the joints the renderer poses."""
    empty_scene()
    model = load_model(row["model"])
    if int(row.get("variants", 1)) > 1:
        model.build(kit, variant)
    else:
        model.build(kit)
    pivot = bpy.data.objects.new("pivot", None)
    bpy.context.scene.collection.objects.link(pivot)
    for obj in list(bpy.data.objects):
        if obj is not pivot and obj.parent is None:
            obj.parent = pivot
    joints = {o.name: o for o in bpy.data.objects if o.type == "EMPTY" and o is not pivot}
    return pivot, joints


def render(sprite_id, row, out_dir, tmp_dir):
    facings = int(row["facings"])
    rig = row.get("rig", "")
    variants = int(row.get("variants", 1))
    # Walkers get the animations along each row; props that come in several looks get one per column.
    anims = ANIMS if rig else [("idle", variants)]
    columns = sum(n for _, n in anims)
    w, h = row["frame"]
    sheet = Image.new("RGBA", (w * columns, h * facings))
    top = h
    for v in range(variants):
        pivot, joints = build_scene(row, v)
        sc, cam = light_and_camera(row)
        for i in range(facings):
            angle = math.radians(360.0 / facings * i)
            pivot.rotation_euler = (0, 0, -angle)
            col = 0
            for anim, n in anims:
                for t in range(n):
                    if variants > 1 and t != v:
                        col += 1
                        continue
                    pose(rig, anim, t, n, joints, pivot, angle)
                    path = os.path.join(tmp_dir, "%s_%d_%d.png" % (sprite_id, i, col))
                    sc.render.filepath = path
                    bpy.ops.render.render(write_still=True)
                    im = Image.open(path).convert("RGBA")
                    sheet.paste(im, (w * col, h * i))
                    if anim == "idle":
                        # How tall the figure stands above its feet: the tallest facing, standing still.
                        box = im.getchannel("A").point(lambda v: 255 if v > 40 else 0).getbbox()
                        if box:
                            top = min(top, box[1])
                    col += 1
    pivot.location = (0, 0, 0)
    sheet.save(os.path.join(out_dir, sprite_id + ".png"), optimize=True)
    feet = world_to_camera_view(sc, cam, Vector((0, 0, 0)))
    anchor = [round(feet.x * w, 2), round((1.0 - feet.y) * h, 2)]
    info = {
        "kind": row["kind"],
        "frame": [w, h],
        "facings": facings,
        "anims": {},
        "anchor": anchor,
        "px_per_unit": round(w / row["ortho"], 4),
        "figure_px": round(anchor[1] - top, 2),
    }
    col = 0
    for anim, n in anims:
        info["anims"][anim] = [col, n]
        col += n
    # Where each look sits in its frame as a card shows it (facing the viewer, standing still): [x, y, w, h] in
    # pixels of the frame, so a card can crop the picture to the figure.
    card_row = 1 if facings > 1 else 0
    info["card_boxes"] = []
    start, n = info["anims"]["idle"]
    for col in range(start, start + n):
        cell = sheet.crop((w * col, h * card_row, w * (col + 1), h * (card_row + 1)))
        box = cell.getchannel("A").point(lambda v: 255 if v > 24 else 0).getbbox() or (0, 0, w, h)
        info["card_boxes"].append([box[0], box[1], box[2] - box[0], box[3] - box[1]])
    for key in ("world_per_unit", "height_r", "variants"):
        if key in row:
            info[key] = row[key]
    return info


def main():
    args = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else []
    with open(os.path.join(ROOT, "art", "manifest.json")) as f:
        manifest = json.load(f)["sprites"]
    out_dir = os.path.join(ROOT, "art", "sprites")
    tmp_dir = os.environ.get("ART_TMP", "/tmp/render_art")
    os.makedirs(tmp_dir, exist_ok=True)
    index_path = os.path.join(out_dir, "index.json")
    index = {}
    if os.path.exists(index_path):
        with open(index_path) as f:
            index = json.load(f).get("sprites", {})
    wanted = args or list(manifest)
    for sprite_id in wanted:
        if sprite_id not in manifest:
            sys.exit("No manifest row for %s (art/manifest.json)" % sprite_id)
        index[sprite_id] = render(sprite_id, manifest[sprite_id], out_dir, tmp_dir)
        print("Rendered %s" % sprite_id)
    # Drop sprites whose manifest row is gone.
    for sprite_id in list(index):
        if sprite_id not in manifest:
            del index[sprite_id]
            png = os.path.join(out_dir, sprite_id + ".png")
            if os.path.exists(png):
                os.remove(png)
    with open(index_path, "w") as f:
        json.dump({"_note": "Written by tools/render_art.py from art/manifest.json; do not edit by hand.",
            "sprites": dict(sorted(index.items()))}, f, indent="\t")
        f.write("\n")
    contact_sheet(out_dir, index, os.path.join(tmp_dir, "sheet.png"))


def contact_sheet(out_dir, index, path):
    """Every sprite on dark ground for a quick look (an agent can open the file): for walkers the row
    facing the viewer (facing 1), every animation frame along it."""
    rows = []
    for i in index:
        im = Image.open(os.path.join(out_dir, i + ".png"))
        fh = index[i]["frame"][1]
        if index[i]["facings"] > 1:
            im = im.crop((0, fh, im.width, fh * 2))
        rows.append(im)
    if not rows:
        return
    pad = 8
    sheet = Image.new("RGBA", (max(r.width for r in rows) + pad * 2, sum(r.height + pad for r in rows) + pad), (30, 26, 22, 255))
    y = pad
    for r in rows:
        sheet.alpha_composite(r, (pad, y))
        y += r.height + pad
    sheet.save(path)
    print("Contact sheet: %s" % path)


main()
