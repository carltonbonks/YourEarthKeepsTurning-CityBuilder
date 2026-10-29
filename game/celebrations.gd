class_name Celebrations
extends RefCounted
## Marks the town's big moments on the map. View only: it compares the run with what it saw last frame.
## - A new age (the moot or the keep raised): a title card over the map, the raised building glowing and
##   ringed, and the resource nodes the age brings pulsing (with markers at the map's edge for those out
##   of view). The ground the age lays round the hearth glows by itself (ArenaView._draw_ground).
## - A hero levelling up: a halo of light round them and "Level N" rising over their head.
## Timings are in real milliseconds, so the moments read the same at 8x speed.

const CARD_MS := 6500.0
const CARD_FADE_MS := 600.0
## How long the raised building and the new resources stay highlighted.
const HIGHLIGHT_MS := 14000.0
const HALO_MS := 2600.0
const GOLD := Color("#ffd870")

var _world: World
var _age := ""
var _levels := {}  ## Hero id -> level last seen.
## The age-up being celebrated: {age, title, subtitle, lines, building (index or -1), nodes: [index], born: ms}.
var age_up := {}
## Heroes levelling up: hero id -> {level, born: ms}.
var halos := {}


## Call every frame. A new world (a new run) starts afresh rather than celebrating what it already has.
func update(run: RunState, now_ms: float) -> void:
	var w := run.world
	if w != _world:
		_world = w
		_age = run.age
		_levels.clear()
		halos.clear()
		age_up = {}
		for hero in run.heroes:
			_levels[hero.id] = hero.level
		return
	if run.age != _age:
		_age = run.age
		age_up = card(run, run.age)
		age_up["born"] = now_ms
	if not age_up.is_empty() and now_ms - float(age_up["born"]) >= HIGHLIGHT_MS:
		age_up = {}
	for hero in run.heroes:
		var was := int(_levels.get(hero.id, hero.level))
		if hero.level > was and hero.alive:
			halos[hero.id] = {"level": hero.level, "born": now_ms}
		_levels[hero.id] = hero.level
	for id: int in halos.keys():
		if now_ms - float(halos[id]["born"]) >= HALO_MS:
			halos.erase(id)


## What the age-up card says and what it highlights.
static func card(run: RunState, age_id: String) -> Dictionary:
	var content := run.content
	var building := raised_building(run, age_id)
	var nodes := new_nodes(run, age_id)
	var counts := {}
	for i in nodes:
		var name: String = content.world["nodes"][run.world.nodes[i]["type"]]["name"]
		counts[name] = int(counts.get(name, 0)) + 1
	var found: Array[String] = []
	for name: String in counts:
		found.append("%s ×%d" % [name, counts[name]] if int(counts[name]) > 1 else name)
	var lines: Array[String] = []
	var begins: String = content.ages["ages"][age_id].get("begins", "")
	if begins != "":
		lines.append(begins.left(1).to_upper() + begins.substr(1) + ".")
	if not found.is_empty():
		lines.append("New on the map: " + ", ".join(found))
	var ground: String = content.ages["ages"][age_id].get("hearth_ground", "")
	if ground != "":
		var gdef: Dictionary = content.town["roads"].get(ground, content.town.get(ground, {}))
		lines.append("Round the hearth, the ground is now a %s." % String(gdef.get("name", ground)).to_lower())
	var raised := "" if building < 0 else "The %s is raised" % content.buildings[run.world.buildings[building]["type"]]["name"]
	return {"age": age_id, "title": "The %s begins" % content.age_name(age_id), "subtitle": raised,
		"lines": lines, "building": building, "nodes": nodes}


## The standing building that brought this age (its "ages_up"), or -1.
static func raised_building(run: RunState, age_id: String) -> int:
	var w := run.world
	for bi in range(w.buildings.size() - 1, -1, -1):
		var b: Dictionary = w.buildings[bi]
		if run.content.buildings[b["type"]].get("ages_up", "") == age_id and float(b["work_left"]) <= 0.0:
			return bi
	return -1


## Indices of the map's resource nodes that this age brought into view.
static func new_nodes(run: RunState, age_id: String) -> Array[int]:
	var out: Array[int] = []
	var w := run.world
	for i in w.nodes.size():
		if w.nodes[i].get("age", "") == age_id and w.node_active(w.nodes[i]):
			out.append(i)
	return out


## Share of the age-up still showing: 1 at full strength, 0 once it is over. `fade_ms` is the closing fade.
func _strength(span_ms: float, now_ms: float, fade_ms := 2000.0) -> float:
	if age_up.is_empty():
		return 0.0
	var t := now_ms - float(age_up["born"])
	if t >= span_ms:
		return 0.0
	return clampf((span_ms - t) / fade_ms, 0.0, 1.0)


## Rings round the raised building and the new resources, on the map layer. `to_screen` maps a world point.
## Nodes out of view get a small arrow at the map's edge pointing to them.
func draw_highlights(view: CanvasItem, size: Vector2, now_ms: float, to_screen: Callable, color_of: Callable) -> void:
	var k := _strength(HIGHLIGHT_MS, now_ms)
	if k <= 0.0:
		return
	var phase := fmod(now_ms - float(age_up["born"]), 1400.0) / 1400.0
	var bi: int = age_up["building"]
	if bi >= 0 and bi < _world.buildings.size():
		var p: Vector2 = to_screen.call(_world.buildings[bi]["pos"])
		for j in 2:
			var f := fmod(phase + j * 0.5, 1.0)
			view.draw_arc(p, 18.0 + f * 46.0, 0, TAU, 40, Color(GOLD, k * (1.0 - f)), 3.0)
	var margin := 18.0
	var rect := Rect2(Vector2(margin, margin), size - Vector2(margin, margin) * 2.0)
	for i: int in age_up["nodes"]:
		if i >= _world.nodes.size():
			continue
		var node: Dictionary = _world.nodes[i]
		var col := Color(color_of.call(node["gives"]))
		var p: Vector2 = to_screen.call(node["pos"])
		if rect.has_point(p):
			view.draw_arc(p, 10.0 + phase * 26.0, 0, TAU, 28, Color(col.lightened(0.4), k * (1.0 - phase)), 2.5)
			view.draw_arc(p, 14.0, 0, TAU, 28, Color(GOLD, k * 0.8), 1.5)
		else:
			# An arrow at the edge of the map, pointing at the node.
			var c := size / 2.0
			var dir := (p - c).normalized()
			var reach := minf(absf((rect.size.x / 2.0) / dir.x) if dir.x != 0.0 else INF, absf((rect.size.y / 2.0) / dir.y) if dir.y != 0.0 else INF)
			var tip := c + dir * reach
			var side := dir.orthogonal() * 7.0
			view.draw_colored_polygon(PackedVector2Array([tip, tip - dir * 14.0 + side, tip - dir * 14.0 - side]), Color(col.lightened(0.4), k))
			view.draw_polyline(PackedVector2Array([tip, tip - dir * 14.0 + side, tip - dir * 14.0 - side, tip]), Color(GOLD, k), 1.5)


## Light on the adding layer: a warm glow over the raised building, and halos round heroes levelling up.
func draw_lights(view: CanvasItem, light: Lighting, now_ms: float, to_screen: Callable, heroes: Array[Unit], hero_r: float) -> void:
	var k := _strength(HIGHLIGHT_MS, now_ms)
	if k > 0.0:
		var bi: int = age_up["building"]
		if bi >= 0 and bi < _world.buildings.size():
			var p: Vector2 = to_screen.call(_world.buildings[bi]["pos"])
			var pulse := 0.8 + 0.2 * sin(now_ms * 0.004)
			light.draw_glow(view, p, 70.0, 70.0, Lighting.dim(GOLD, 0.45 * k * pulse))
	for hero in heroes:
		var h := halo_share(hero, now_ms)
		if h > 0.0:
			var r := hero_r * (2.5 + 2.0 * (1.0 - h))
			light.draw_glow(view, to_screen.call(hero.pos) - Vector2(0, hero_r), r, r, Lighting.dim(GOLD, 0.8 * h))


## How strongly a hero's level-up halo shows: 1 as it starts, fading to 0.
func halo_share(hero: Unit, now_ms: float) -> float:
	if not halos.has(hero.id):
		return 0.0
	return clampf(1.0 - (now_ms - float(halos[hero.id]["born"])) / HALO_MS, 0.0, 1.0)


## Over the light: a ring and "Level N" rising over each hero levelling up, then the age-up title card.
func draw_top(view: CanvasItem, size: Vector2, font: Font, now_ms: float, to_screen: Callable, heroes: Array[Unit], hero_r: float) -> void:
	for hero in heroes:
		var h := halo_share(hero, now_ms)
		if h <= 0.0 or not hero.alive:
			continue
		var p: Vector2 = to_screen.call(hero.pos) - Vector2(0, hero_r)
		view.draw_arc(p, hero_r * (1.3 + 1.2 * (1.0 - h)), 0, TAU, 32, Color(GOLD, h), 2.5)
		var text := "Level %d" % int(halos[hero.id]["level"])
		var width := font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, 15).x
		var at := p - Vector2(width / 2.0, hero_r * 2.2 + 26.0 * (1.0 - h))
		view.draw_string_outline(font, at, text, HORIZONTAL_ALIGNMENT_LEFT, -1, 15, 3, Color(0, 0, 0, 0.8 * h))
		view.draw_string(font, at, text, HORIZONTAL_ALIGNMENT_LEFT, -1, 15, Color(GOLD, h))
	if age_up.is_empty():
		return
	var t := now_ms - float(age_up["born"])
	if t >= CARD_MS:
		return
	var a := minf(clampf(t / 300.0, 0.0, 1.0), clampf((CARD_MS - t) / CARD_FADE_MS, 0.0, 1.0))
	var lines: Array = age_up["lines"]
	var band_h := 92.0 + 20.0 * lines.size()
	var top := size.y * 0.16
	var band := Rect2(0.0, top, size.x, band_h)
	view.draw_rect(band, Color(0.05, 0.04, 0.02, 0.72 * a))
	view.draw_line(band.position, band.position + Vector2(size.x, 0), Color(GOLD, 0.8 * a), 2.0)
	view.draw_line(band.end - Vector2(size.x, 0), band.end, Color(GOLD, 0.8 * a), 2.0)
	var y := top + 46.0
	_centred(view, font, str(age_up["title"]), y, 34, Color(GOLD, a), size.x, a)
	y += 28.0
	if str(age_up["subtitle"]) != "":
		_centred(view, font, str(age_up["subtitle"]), y, 17, Color(0.95, 0.92, 0.84, a), size.x, a)
	for line: String in lines:
		y += 20.0
		_centred(view, font, line, y, 14, Color(0.82, 0.8, 0.72, a), size.x, a)


func _centred(view: CanvasItem, font: Font, text: String, y: float, font_size: int, c: Color, width: float, a: float) -> void:
	var w := font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size).x
	var at := Vector2((width - w) / 2.0, y)
	view.draw_string_outline(font, at, text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, 4, Color(0, 0, 0, 0.8 * a))
	view.draw_string(font, at, text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, c)
