class_name ArenaView
extends Control
## Draws the settlement map with placeholder shapes. Read-only: it only looks at
## the RunState / World and never changes them, so art can be swapped freely.
## Mouse wheel zooms, dragging pans, hovering shows a tooltip (see Tooltips).
## While staking a road (BuildPanel), clicks add waypoints and right-click removes the last;
## the planned road is previewed, and BuildPanel hands the waypoints to RunState.stake_road.

signal stake_points_changed

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
var _mouse := Vector2(-1, -1)  ## Last mouse position over the map; negative when it is elsewhere.
var _press_at := Vector2.ZERO
var _moved := false
## Road staking: on while the player is placing waypoints.
var staking := false
var stake_points: Array = []
var _preview := PackedInt32Array()
## Squares worth drawing (trails, roads, stakes), rebuilt when the ground or the stakes change:
## [index, ground kind, staked] per square.
var _ground_cache: Array = []
var _ground_seen := [-1, -1, null]


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
			if mb.pressed:
				_press_at = mb.position
				_moved = false
			elif staking and not _moved:
				# A click (not a drag) while staking: add a waypoint, or drop the last one.
				if mb.button_index == MOUSE_BUTTON_LEFT:
					stake_points.append(_to_world(mb.position))
				elif not stake_points.is_empty():
					stake_points.pop_back()
				_update_preview()
				accept_event()
	elif event is InputEventMouseMotion:
		_mouse = (event as InputEventMouseMotion).position
		if _dragging and _mouse.distance_to(_press_at) > 5.0:
			_moved = true
		if _dragging and _moved:
			pan -= (event as InputEventMouseMotion).relative / _scale()


func start_staking() -> void:
	staking = true
	stake_points = []
	_update_preview()


func stop_staking() -> void:
	staking = false
	stake_points = []
	_update_preview()


func _update_preview() -> void:
	_preview = run.world.town.route(stake_points) if run != null and stake_points.size() >= 2 else PackedInt32Array()
	stake_points_changed.emit()


## True if the waypoints so far make a road that fits.
func preview_ok() -> bool:
	return _preview.size() >= 2


func _notification(what: int) -> void:
	if what == NOTIFICATION_MOUSE_EXIT:
		_mouse = Vector2(-1, -1)


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
	for thicket in w.town.thickets:
		draw_circle(_to_screen(thicket["pos"]), float(thicket["radius"]) * s, Color(content.town["thickets"]["color"]))
	draw_circle(center, content.num("settlement_radius") * s, Color("#33402a"))
	draw_arc(center, content.num("settlement_radius") * s, 0, TAU, 64, Color("#4d5c3a"), 1.0)
	_draw_plots()
	_draw_ground()

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
		if not w.node_active(node):
			continue
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

	# Buildings fill their plot: solid when raised, outline plus progress while being built.
	for b in w.buildings:
		var def: Dictionary = content.buildings[b["type"]]
		var p := _to_screen(b["pos"])
		var half := maxf(4.0, 11.0 * s)
		var shape := _screen_poly(w.town.plot_outline(b["plot"]))
		var col := Color(def["color"])
		var work_left := float(b["work_left"])
		if work_left <= 0.0:
			draw_colored_polygon(shape, col)
			draw_polyline(_closed(shape), Color("#e8d9a8"), 1.0)
		else:
			var done := 1.0 - work_left / float(def["work"])
			draw_colored_polygon(shape, Color(col, 0.25))
			draw_polyline(_closed(shape), col, 1.5)
			_bar(p + Vector2(-half, half + 3), half * 2.0, done, Color("#e8d9a8"))
		# Stalls show a dot per good on sale; workshops show how far the current good is.
		if work_left <= 0.0 and def.has("stall"):
			for k in b["goods"].size():
				draw_circle(p + Vector2(-half + 3.0 + k * 5.0, half + 4.0), 2.0, Color("#ffd24a"))
		elif work_left <= 0.0 and def.has("workshop") and b["craft"] != "":
			var recipe: Dictionary = content.market["recipes"][b["craft"]]
			_bar(p + Vector2(-half, half + 3), half * 2.0, 1.0 - float(b["craft_left"]) / float(recipe["work"]), Color("#ffd24a"))
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
	if staking:
		_draw_staking(font)
	var help := "Click to add road waypoints, right-click to undo one, drag to look around" if staking \
		else "Mouse wheel to zoom, drag to look around, point at anything for details"
	draw_string(font, Vector2(8, size.y - 8), help, HORIZONTAL_ALIGNMENT_LEFT, -1, 11, Color("#ffd27a") if staking else Color("#8a9088"))
	if _mouse.x >= 0.0 and not _dragging:
		var tip := hovered(_mouse)
		if not tip.is_empty():
			_draw_tip(tip, _mouse, font)


## The tooltip for whatever is under a screen point ({} if nothing). Small, moving things win over big, still ones.
func hovered(at: Vector2) -> Dictionary:
	var w := run.world
	var grow := maxf(1.0, zoom * 0.7)
	for hero in run.heroes:
		if hero.alive and _near(hero.pos, at, HERO_RADIUS * grow):
			return Tooltips.hero(run, hero)
	for e in w.enemies:
		if e.alive and e.spawned and _near(e.pos, at, (BOSS_RADIUS if e.is_boss else ENEMY_RADIUS) * grow):
			return Tooltips.enemy(run, e.type_id, e)
	for u in w.folk:
		if u.alive and _near(u.pos, at, FOLK_RADIUS * grow):
			return Tooltips.folk(run, u)
	var plot := w.town.plot_at(_to_world(at))
	if plot >= 0 and int(w.town.plots[plot]["building"]) >= 0:
		return Tooltips.building(run, w.town.plots[plot]["building"])
	if plot >= 0 and w.town.plots[plot]["obstacle"] != "":
		return Tooltips.obstacle(run, w.town.plots[plot]["obstacle"])
	if _near(Vector2.ZERO, at, World.HEARTH_RADIUS * _scale()):
		return Tooltips.hearth(run)
	for den in w.dens:
		if _near(den["pos"], at, maxf(8.0, 18.0 * _scale() * 1.6)):
			return Tooltips.den(run, den)
	for node in w.nodes:
		if w.node_active(node) and _near(node["pos"], at, maxf(3.0, 14.0 * _scale() * 1.6)):
			return Tooltips.node(run, node)
	var square := w.pathing.index_of(_to_world(at))
	if w.pathing.ground[square] != Pathing.PLAIN or w.town.staked[square] > 0:
		return Tooltips.ground(run, square)
	return {}


func _near(world_pos: Vector2, at: Vector2, radius: float) -> bool:
	return _to_screen(world_pos).distance_to(at) <= radius + 3.0


## A dark box beside the mouse: title, lines, tags, then warnings in orange. Kept inside the map.
func _draw_tip(tip: Dictionary, at: Vector2, font: Font) -> void:
	var rows: Array = [[tip["title"], 13, Color("#f0e6c8")]]
	for line: String in tip["lines"]:
		for part in _wrap(line):
			rows.append([part, 11, Color("#c8ccc0")])
	if not tip["tags"].is_empty():
		rows.append(["Tags", 11, Color("#9fc4e0")])
		for tag: String in tip["tags"]:
			for part in _wrap("- " + tag):
				rows.append([part, 11, Color("#9fc4e0")])
	for warning: String in tip["warnings"]:
		for part in _wrap(warning):
			rows.append([part, 11, Color("#ffb060")])
	var width := 0.0
	for row: Array in rows:
		width = maxf(width, font.get_string_size(row[0], HORIZONTAL_ALIGNMENT_LEFT, -1, row[1]).x)
	var line_h := 15.0
	var box := Vector2(width + 16.0, rows.size() * line_h + 10.0)
	var pos := at + Vector2(16, 16)
	pos.x = clampf(pos.x, 0.0, maxf(0.0, size.x - box.x))
	if pos.y + box.y > size.y:
		pos.y = maxf(0.0, at.y - box.y - 8.0)
	draw_rect(Rect2(pos, box), Color(0.05, 0.06, 0.05, 0.92))
	draw_rect(Rect2(pos, box), Color("#6a7458"), false, 1.0)
	for i in rows.size():
		var row: Array = rows[i]
		draw_string(font, pos + Vector2(8, 18 + i * line_h), row[0], HORIZONTAL_ALIGNMENT_LEFT, width, row[1], row[2])


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
	if hero.resting:
		# Sleepers are drawn dimmer, with a "z".
		draw_circle(p, r * 0.8, Color(color, 0.55))
		draw_string(font, p + Vector2(r * 0.6, -r * 0.6), "z", HORIZONTAL_ALIGNMENT_LEFT, -1, 12, Color("#cfe0ff"))
	else:
		draw_circle(p, r, color)
		draw_arc(p, r, 0, TAU, 24, Color.WHITE if hero.energy > 0.0 else Color("#e05050"), 1.5)
	draw_string(font, p + Vector2(-4, 4), hero.display_name.left(1), HORIZONTAL_ALIGNMENT_LEFT, -1, 11, Color.BLACK)
	_bar(p + Vector2(-r, -r - 9), r * 2.0, hero.hp_fraction(), Color("#5ee07a"))
	_bar(p + Vector2(-r, -r - 5), r * 2.0, hero.energy / run.content.num("hero_energy_max"), Color("#7fd0ff"))
	draw_string(font, p + Vector2(r + 3, 4), hero.display_name, HORIZONTAL_ALIGNMENT_LEFT, -1, 11, Color.WHITE)


## Ring plots: free ones in opened rings as faint outlines, obstacles filled in.
func _draw_plots() -> void:
	var town := run.world.town
	for k in town.plots.size():
		var plot: Dictionary = town.plots[k]
		if not town.ring_open(plot) or int(plot["building"]) >= 0:
			continue
		var shape := _screen_poly(town.plot_outline(k))
		if plot["obstacle"] != "":
			draw_colored_polygon(shape, Color(run.content.town["obstacles"][plot["obstacle"]]["color"]))
		else:
			draw_polyline(_closed(shape), Color(0.6, 0.65, 0.45, 0.18), 1.0)


## Trails, roads and staked squares.
func _draw_ground() -> void:
	var w := run.world
	var seen := [w.pathing.ground_version, w.town.staked_version, w]
	if seen != _ground_seen:
		_ground_seen = seen
		_ground_cache = []
		for i in w.pathing.ground.size():
			var g := w.pathing.ground[i]
			if g >= Pathing.TRAIL or w.town.staked[i] > 0:
				_ground_cache.append([i, g, w.town.staked[i] > 0])
	var s := _scale()
	var cell := w.pathing.cell * s
	var trail := Color(run.content.town["trail"]["color"])
	for entry: Array in _ground_cache:
		var p := _to_screen(w.pathing.center(entry[0]))
		var g: int = entry[1]
		if g >= Pathing.FIRST_ROAD:
			draw_rect(Rect2(p - Vector2(cell, cell) / 2.0, Vector2(cell, cell)), Color(w.town.road_def(g)["color"]))
		elif g == Pathing.TRAIL:
			draw_rect(Rect2(p - Vector2(cell, cell) * 0.35, Vector2(cell, cell) * 0.7), Color(trail, 0.8))
		if entry[2] and g < Pathing.FIRST_ROAD:
			draw_circle(p, maxf(1.0, cell * 0.18), Color("#e8c070"))


## The road being staked: waypoints and the planned squares.
func _draw_staking(font: Font) -> void:
	var w := run.world
	var cell := w.pathing.cell * _scale()
	for i in _preview:
		var p := _to_screen(w.pathing.center(i))
		draw_rect(Rect2(p - Vector2(cell, cell) * 0.3, Vector2(cell, cell) * 0.6), Color("#ffd27a"))
	for n in stake_points.size():
		var p := _to_screen(stake_points[n])
		draw_circle(p, 5.0, Color("#ffd27a"))
		draw_string(font, p + Vector2(6, -6), str(n + 1), HORIZONTAL_ALIGNMENT_LEFT, -1, 11, Color("#ffd27a"))
	if stake_points.size() >= 2 and _preview.is_empty():
		draw_string(font, _to_screen(stake_points[-1]) + Vector2(8, 14), "no road fits here", HORIZONTAL_ALIGNMENT_LEFT, -1, 11, Color("#ff8060"))


func _screen_poly(points: PackedVector2Array) -> PackedVector2Array:
	var out := PackedVector2Array()
	for p in points:
		out.append(_to_screen(p))
	return out


func _closed(points: PackedVector2Array) -> PackedVector2Array:
	var out := points.duplicate()
	out.append(points[0])
	return out


func _bar(at: Vector2, width: float, fraction: float, color: Color) -> void:
	draw_rect(Rect2(at, Vector2(width, 3)), Color(0, 0, 0, 0.6))
	draw_rect(Rect2(at, Vector2(width * clampf(fraction, 0.0, 1.0), 3)), color)


## Splits a line into pieces of about `limit` characters at spaces.
func _wrap(text: String, limit := 56) -> Array[String]:
	var out: Array[String] = []
	var line := ""
	for word in text.split(" "):
		if line != "" and line.length() + 1 + word.length() > limit:
			out.append(line)
			line = word
		else:
			line = word if line == "" else line + " " + word
	out.append(line)
	return out
