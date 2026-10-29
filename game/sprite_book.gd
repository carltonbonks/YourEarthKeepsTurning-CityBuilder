class_name SpriteBook
extends RefCounted
## The map's rendered art (Yusuf, 2026-10-29): sprites made from 3D models by tools/render_art.sh,
## listed in art/sprites/index.json. ArenaView asks for a content id's sprite and draws its
## placeholder shape when there is none, so art can be added one id at a time. View only: no rule
## reads art. How the art is made and what bought art must match: docs/ART_SPEC.md.

const INDEX := "res://art/sprites/index.json"

## id -> what index.json says about it, plus "texture".
var _sprites := {}


func _init() -> void:
	if not FileAccess.file_exists(INDEX):
		return
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(INDEX))
	if not (parsed is Dictionary):
		return
	var sprites: Dictionary = parsed.get("sprites", {})
	for id: String in sprites:
		var tex := load("res://art/sprites/%s.png" % id) as Texture2D
		if tex == null:
			continue
		var info: Dictionary = sprites[id].duplicate()
		info["texture"] = tex
		_sprites[id] = info


func has(id: String) -> bool:
	return _sprites.has(id)


func ids() -> Array:
	return _sprites.keys()


func info(id: String) -> Dictionary:
	return _sprites.get(id, {})


## Which of `facings` frames looks most along `dir` (a direction on the sim's map).
static func facing_of(dir: Vector2, facings: int) -> int:
	if facings <= 1 or dir == Vector2.ZERO:
		return 0
	return posmod(roundi(dir.angle() / TAU * facings), facings)


## How many screen pixels one sprite pixel covers for a building drawn at the map's scale `map_scale`
## (screen pixels per world unit).
func building_scale(id: String, map_scale: float) -> float:
	var s: Dictionary = _sprites[id]
	return map_scale * float(s.get("world_per_unit", 1.0)) / float(s["px_per_unit"])


## How many screen pixels one sprite pixel covers for a walker that replaces a circle of screen radius r.
func walker_scale(id: String, r: float) -> float:
	var s: Dictionary = _sprites[id]
	return r * float(s.get("height_r", 3.0)) / maxf(1.0, float(s["figure_px"]))


## How tall the sprite stands above its feet on screen at `scale`.
func height_at(id: String, scale: float) -> float:
	return float(_sprites[id]["figure_px"]) * scale


## Draws `id`'s frame `facing` with its feet on `feet`, each sprite pixel `scale` screen pixels.
func draw(canvas: CanvasItem, id: String, feet: Vector2, scale: float, facing := 0, tint := Color.WHITE) -> void:
	var s: Dictionary = _sprites[id]
	var frame := Vector2(s["frame"][0], s["frame"][1])
	var anchor := Vector2(s["anchor"][0], s["anchor"][1])
	var src := Rect2(Vector2(frame.x * clampi(facing, 0, int(s["facings"]) - 1), 0.0), frame)
	canvas.draw_texture_rect_region(s["texture"], Rect2(feet - anchor * scale, frame * scale), src, tint)
