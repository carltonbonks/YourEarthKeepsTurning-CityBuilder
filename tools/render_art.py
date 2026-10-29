"""Renders the map art in art/manifest.json into sprites the game draws (game/sprite_book.gd).

Run it through tools/render_art.sh, which runs it in Blender's Python (the bpy package). For each id
it builds the model, points an orthographic camera at it from the map's own angle (the tilted view
in game/arena_view.gd: turned 45 degrees, looking down 30 degrees so the ground squashes 2:1), and
renders one frame per facing into art/sprites/<id>.png, left to right. art/sprites/index.json gets
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
SAMPLES = 32


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


def render(sprite_id, row, out_dir, tmp_dir):
    empty_scene()
    load_model(row["model"]).build(kit)
    pivot = bpy.data.objects.new("pivot", None)
    bpy.context.scene.collection.objects.link(pivot)
    for obj in list(bpy.data.objects):
        if obj is not pivot and obj.parent is None:
            obj.parent = pivot
    sc, cam = light_and_camera(row)
    facings = int(row["facings"])
    w, h = row["frame"]
    frames = []
    for i in range(facings):
        pivot.rotation_euler = (0, 0, -math.radians(360.0 / facings * i))
        path = os.path.join(tmp_dir, "%s_%d.png" % (sprite_id, i))
        sc.render.filepath = path
        bpy.ops.render.render(write_still=True)
        frames.append(Image.open(path).convert("RGBA"))
    sheet = Image.new("RGBA", (w * facings, h))
    for i, im in enumerate(frames):
        sheet.paste(im, (w * i, 0))
    sheet.save(os.path.join(out_dir, sprite_id + ".png"), optimize=True)
    feet = world_to_camera_view(sc, cam, Vector((0, 0, 0)))
    anchor = [round(feet.x * w, 2), round((1.0 - feet.y) * h, 2)]
    # How tall the figure stands above its feet, in pixels, the tallest of its facings.
    top = h
    for im in frames:
        box = im.getchannel("A").point(lambda v: 255 if v > 40 else 0).getbbox()
        if box:
            top = min(top, box[1])
    info = {
        "kind": row["kind"],
        "frame": [w, h],
        "facings": facings,
        "anchor": anchor,
        "px_per_unit": round(w / row["ortho"], 4),
        "figure_px": round(anchor[1] - top, 2),
    }
    for key in ("world_per_unit", "height_r"):
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
    """Every sprite on dark ground, all facings, for a quick look (an agent can open the file)."""
    rows = [Image.open(os.path.join(out_dir, i + ".png")) for i in index]
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
