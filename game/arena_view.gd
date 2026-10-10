class_name ArenaView
extends Control
## Draws the settlement map with placeholder shapes. Read-only: it only looks at
## the RunState / World and never changes them, so art can be swapped freely.
## Mouse wheel zooms, dragging pans.

const HERO_RADIUS := 9.0
const FOLK_RADIUS := 5.5
const ENEMY_RADIUS := 7.0
const BOSS_RADIUS := 15.0
const MIN_ZOOM := 1.0
const MAX_ZOOM := 4.0

var run: RunState
var zoom := 1.2
var pan := Vector2.ZERO  ## World point at the centre of the view.
var _dragging := false


func reset_camera() -> void:
	zoom = 1.2
	pan = Vector2.ZERO


func _process(_delta: float) -> void:
	queue_redraw()


func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		if mb.pressed and (mb.button_index == MOUSE_BUTTON_WHEEL_UP or mb.button_index == MOUSE_BUTTON_WHEEL_DOWN):
			var before := _to_world(mb.position)
			zoom = clampf(zoom * (1.15 if mb.button_index == MOUSE_BUTTON_WHEEL_UP else 1.0 / 1.15), MIN_ZOOM, MAX_ZOOM)
			pan += before - _to_world(mb.position)
			accept_event()
		elif mb.button_index == MOUSE_BUTTON_LEFT or mb.button_index == MOUSE_BUTTON_RIGHT:
			_dragging = mb.pressed
	elif event is InputEventMouseMotion and _dragging:
		pan -= (event as InputEventMouseMotion).relative / _scale()


func _scale() -> float:
	if run == null:
		return 1.0
	return minf(size.x, size.y) / (run.content.num("world_radius") * 2.1) * zoom


func _to_screen(p: Vector2) -> Vector2:
	return size / 2.0 + (p - pan) * _scale()


func _to_world(s: Vector2) -> Vector2:
	return (s - size / 2.0) / _scale() + pan


func _draw() -> void:
	if run == null:
		return
	var content := run.content
	var w := run.world
	var s := _scale()
	var font := get_theme_default_font()
	var center := _to_screen(Vector2.ZERO)
	var radius := content.num("world_radius")

	# Ground: the wilds, then the settlement clearing.
	draw_rect(Rect2(Vector2.ZERO, size), Color("#161a17"))
	draw_circle(center, radius * s, Color("#25301f"))
	draw_circle(center, content.num("settlement_radius") * s, Color("#33402a"))
	draw_arc(center, content.num("settlement_radius") * s, 0, TAU, 64, Color("#4d5c3a"), 1.0)

	# Warned attack sides: red wedges at the map edge until the wave arrives.
	if not w.wave_spawned:
		for angle in w.wave_sides:
			var dir := Vector2.from_angle(angle)
			var tip := _to_screen(dir * radius * 0.86)
			var base := _to_screen(dir * radius * 1.0)
			var side := dir.orthogonal() * 22.0
			draw_colored_polygon(PackedVector2Array([tip, base + side, base - side]), Color("#c0403a"))

	# Resource nodes: size shows how much is left.
	for node in w.nodes:
		var def: Dictionary = content.world["nodes"][node["type"]]
		var p := _to_screen(node["pos"])
		var left := float(node["amount"]) / float(node["max"])
		var r := maxf(3.0, (6.0 + 8.0 * left) * s * 1.6)
		var col := Color(def["color"])
		draw_circle(p, r, col if left > 0.0 else Color(col, 0.25))
		if zoom > 1.6:
			draw_string(font, p + Vector2(r + 2, 4), "%s %d" % [def["name"], node["amount"]], HORIZONTAL_ALIGNMENT_LEFT, -1, 10, Color("#c8c8b0"))

	# Dens.
	for den in w.dens:
		var def: Dictionary = content.world["dens"][den["type"]]
		var p := _to_screen(den["pos"])
		var r := maxf(8.0, 18.0 * s * 1.6)
		draw_circle(p, r, Color(def["color"]))
		draw_arc(p, r, 0, TAU, 24, Color("#a05050"), 2.0)
		draw_string(font, p + Vector2(-r, r + 12), def["name"], HORIZONTAL_ALIGNMENT_LEFT, -1, 11, Color("#d0a0a0"))

	# Buildings: solid when raised, outline plus progress while being built.
	for b in w.buildings:
		var def: Dictionary = content.buildings[b["type"]]
		var p := _to_screen(b["pos"])
		var half := maxf(4.0, World.BUILDING_SIZE * 0.5 * s)
		var rect := Rect2(p - Vector2(half, half), Vector2(half, half) * 2.0)
		var col := Color(def["color"])
		var work_left := float(b["work_left"])
		if work_left <= 0.0:
			draw_rect(rect, col)
			draw_rect(rect, Color("#e8d9a8"), false, 1.0)
		else:
			var done := 1.0 - work_left / float(def["work"])
			draw_rect(rect, Color(col, 0.25))
			draw_rect(rect, col, false, 1.5)
			_bar(p + Vector2(-half, half + 3), half * 2.0, done, Color("#e8d9a8"))
		if zoom > 1.4:
			draw_string(font, p + Vector2(-half, -half - 3), def["name"], HORIZONTAL_ALIGNMENT_LEFT, -1, 10, Color("#d8d0b8"))

	# Hearth.
	var hearth_r := World.HEARTH_RADIUS * s
	draw_circle(center, hearth_r, Color("#5a4030"))
	draw_circle(center, hearth_r * 0.55, Color("#ff9a3a") if not w.cold_tonight else Color("#6a6a7a"))
	_bar(center + Vector2(-hearth_r, -hearth_r - 8), hearth_r * 2.0, w.hearth_hp / run.hearth_max_hp(), Color("#7fd0ff"))

	# Shots.
	for shot in w.shots:
		var c := Color("#fff3b0") if shot["ranged"] else Color("#ffffff")
		draw_line(_to_screen(shot["from"]), _to_screen(shot["to"]), Color(c, 0.6), 1.5 if shot["ranged"] else 2.5)

	# Townsfolk.
	for u in w.folk:
		if not u.alive:
			continue
		var p := _to_screen(u.pos)
		var r := FOLK_RADIUS * maxf(1.0, zoom * 0.7)
		draw_circle(p, r, Color(content.townsfolk[u.type_id]["color"]))
		if u.carry_amount > 0:
			draw_circle(p + Vector2(r, -r), r * 0.5, Color(main_color(u.carrying)))
		if u.hp < u.max_hp:
			_bar(p + Vector2(-r, -r - 4), r * 2.0, u.hp_fraction(), Color("#5ee07a"))

	# Enemies.
	for e in w.enemies:
		if not e.alive or not e.spawned:
			continue
		var p := _to_screen(e.pos)
		var r := (BOSS_RADIUS if e.is_boss else ENEMY_RADIUS) * maxf(1.0, zoom * 0.7)
		draw_circle(p, r, Color(content.enemies[e.type_id]["color"]))
		if e.den_index >= 0:
			draw_arc(p, r, 0, TAU, 16, Color("#301818"), 1.5)
		_bar(p + Vector2(-r, -r - 5), r * 2.0, e.hp_fraction(), Color("#e05050"))

	# Heroes.
	for hero in run.heroes:
		if hero.alive:
			_draw_hero(hero, _to_screen(hero.pos), font)

	# Night falls over everything.
	var dark := _darkness()
	if dark > 0.0:
		draw_rect(Rect2(Vector2.ZERO, size), Color(0.02, 0.03, 0.12, dark))
	draw_string(font, Vector2(8, size.y - 8), "Mouse wheel to zoom, drag to look around", HORIZONTAL_ALIGNMENT_LEFT, -1, 11, Color("#8a9088"))


## How dark it is: 0 by day, rising through dusk, 0.45 at night.
func _darkness() -> float:
	var w := run.world
	if run.phase == RunState.Phase.BUILD:
		return 0.0
	var day := run.content.num("day_seconds")
	var dusk := run.content.num("dusk_seconds")
	var t := w.time_of_day()
	if t >= day:
		return 0.45
	if t >= day - dusk:
		return 0.45 * (t - (day - dusk)) / dusk
	return 0.0


func main_color(resource: String) -> String:
	return {"food": "#d98aa8", "fuel": "#e0b050", "wood": "#7fbf6a", "stone": "#b0b4bc"}.get(resource, "#ffffff")


func _draw_hero(hero: Unit, p: Vector2, font: Font) -> void:
	var r := HERO_RADIUS * maxf(1.0, zoom * 0.7)
	var color := Color(run.content.hero_classes[hero.type_id]["color"])
	draw_circle(p, r, color)
	draw_arc(p, r, 0, TAU, 24, Color.WHITE, 1.5)
	draw_string(font, p + Vector2(-4, 4), hero.display_name.left(1), HORIZONTAL_ALIGNMENT_LEFT, -1, 11, Color.BLACK)
	_bar(p + Vector2(-r, -r - 6), r * 2.0, hero.hp_fraction(), Color("#5ee07a"))
	draw_string(font, p + Vector2(r + 3, 4), hero.display_name, HORIZONTAL_ALIGNMENT_LEFT, -1, 11, Color.WHITE)


func _bar(at: Vector2, width: float, fraction: float, color: Color) -> void:
	draw_rect(Rect2(at, Vector2(width, 3)), Color(0, 0, 0, 0.6))
	draw_rect(Rect2(at, Vector2(width * clampf(fraction, 0.0, 1.0), 3)), color)
