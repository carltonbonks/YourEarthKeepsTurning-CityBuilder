class_name SpriteBook
extends RefCounted
## The map's rendered art (Yusuf, 2026-10-29): sprites made from 3D models by tools/render_art.sh,
## listed in art/sprites/index.json. ArenaView asks for a content id's sprite and draws its
## placeholder shape when there is none, so art can be added one id at a time. View only: no rule
## reads art. How the art is made and what bought art must match: docs/ART_SPEC.md.

const INDEX := "res://art/sprites/index.json"

const CARD_ART := "res://art/card_art.json"

## id -> what index.json says about it, plus "texture".
var _sprites := {}
## art/card_art.json: which column of the icon sheets each item base and relic shows.
var _card_art := {}
static var _shared: SpriteBook = null


## One book for the whole game (cards ask for pictures often; the sheets load once).
static func shared() -> SpriteBook:
	if _shared == null:
		_shared = SpriteBook.new()
	return _shared


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
	if FileAccess.file_exists(CARD_ART):
		var art: Variant = JSON.parse_string(FileAccess.get_file_as_string(CARD_ART))
		if art is Dictionary:
			_card_art = art


func has(id: String) -> bool:
	return _sprites.has(id)


func ids() -> Array:
	return _sprites.keys()


func info(id: String) -> Dictionary:
	return _sprites.get(id, {})


## Which of `facings` sheet rows looks most along `dir` (a direction on the sim's map).
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


## Which frame of `anim` (idle, walk, attack, cheer: see tools/render_art.py ANIMS) a walker shows: {"anim", "frame"}.
## The walk steps with the ground walked, so legs keep pace at any speed; a blow plays through once; a walker
## told to cheer (look["cheer"], the frame) does so when standing still.
func walker_frame(id: String, look: Dictionary) -> Dictionary:
	var anims: Dictionary = _sprites[id].get("anims", {})
	if look.has("cheer") and anims.has("cheer") and float(look.get("attack", -1.0)) < 0.0 and not look.get("walking", false):
		return {"anim": "cheer", "frame": int(look["cheer"])}
	if float(look.get("attack", -1.0)) >= 0.0 and anims.has("attack"):
		return {"anim": "attack", "frame": int(float(look["attack"]) * int(anims["attack"][1]))}
	if look.get("walking", false) and anims.has("walk"):
		return {"anim": "walk", "frame": int(float(look["walked"]) / WalkerMotion.STRIDE)}
	return {"anim": "idle", "frame": 0}


## Draws `id` with its feet on `feet`, each sprite pixel `scale` screen pixels: the frame of `anim` (wrapping
## round its frames) seen from `facing`.
func draw(canvas: CanvasItem, id: String, feet: Vector2, scale: float, facing := 0, tint := Color.WHITE,
		anim := "idle", frame_index := 0) -> void:
	var s: Dictionary = _sprites[id]
	var frame := Vector2(s["frame"][0], s["frame"][1])
	var anchor := Vector2(s["anchor"][0], s["anchor"][1])
	var span: Array = s.get("anims", {}).get(anim, [0, 1])
	var col := int(span[0]) + posmod(frame_index, int(span[1]))
	var row := clampi(facing, 0, int(s["facings"]) - 1)
	var src := Rect2(Vector2(frame.x * col, frame.y * row), frame)
	canvas.draw_texture_rect_region(s["texture"], Rect2(feet - anchor * scale, frame * scale), src, tint)


## Draws a walker as WalkerMotion.look sees it.
func draw_walker(canvas: CanvasItem, id: String, feet: Vector2, scale: float, look: Dictionary, tint := Color.WHITE) -> void:
	var f := walker_frame(id, look)
	draw(canvas, id, feet, scale, int(look["facing"]), tint * Color(look["tint"]), f["anim"], f["frame"])


## A card's picture of `id` (rendered art slice 4): look `look` (a column of its idle frames) seen as a card shows
## it, cropped to the figure with a little room round it. Null when `id` has no art.
func card_texture(id: String, look := 0) -> Texture2D:
	if not _sprites.has(id):
		return null
	var s: Dictionary = _sprites[id]
	var frame := Vector2(s["frame"][0], s["frame"][1])
	var span: Array = s["anims"]["idle"]
	var col := int(span[0]) + clampi(look, 0, int(span[1]) - 1)
	var row := 1 if int(s["facings"]) > 1 else 0
	var boxes: Array = s.get("card_boxes", [])
	var box := Rect2(Vector2.ZERO, frame)
	if look < boxes.size():
		var b: Array = boxes[look]
		box = Rect2(b[0], b[1], b[2], b[3]).grow(maxf(2.0, 0.06 * maxf(b[2], b[3]))).intersection(Rect2(Vector2.ZERO, frame))
	var tex := AtlasTexture.new()
	tex.atlas = s["texture"]
	tex.region = Rect2(Vector2(frame.x * col, frame.y * row) + box.position, box.size)
	return tex


## The picture for an item base (data/items.json), or null.
func item_texture(base: String) -> Texture2D:
	var at: int = _card_art.get("items", []).find(base)
	return card_texture("item_icons", at) if at >= 0 else null


## The picture for a relic (data/relics.json): the look art/card_art.json gives it, or null.
func relic_texture(relic_id: String) -> Texture2D:
	var look: String = _card_art.get("relics", {}).get(relic_id, "")
	var at: int = _card_art.get("relic_looks", []).find(look)
	return card_texture("relic_icons", at) if at >= 0 else null

