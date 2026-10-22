class_name ArenaView
extends Control
## Draws the settlement map with placeholder shapes. Read-only: it only looks at
## the RunState / World and never changes them, so art can be swapped freely.
## By default the map is tilted (isometric): the ground is turned 45 degrees and squashed, buildings
## stand up as blocks, and everything standing is drawn back to front so nearer things cover farther
## ones. V switches to the flat top-down view. The sim never knows: only the view's projection changes.
## Mouse wheel zooms, dragging pans, hovering shows a tooltip (see Tooltips). As each night falls the
## camera closes in on the town and afterwards goes back (NightCamera), unless the player moves it.
## Light (Lighting) is drawn on a child layer that adds light, and the tooltip on a layer above that.

const HERO_RADIUS := 9.0
const FOLK_RADIUS := 5.5
const ENEMY_RADIUS := 7.0
const BOSS_RADIUS := 15.0
const MIN_ZOOM := 1.0
const MAX_ZOOM := 4.0
const PAVE_GLOW_SECONDS := 6.0
## How much the tilted ground is squashed top to bottom (0.5 is classic 2:1 isometric).
const ISO_SQUASH := 0.5
const HALF_ROOT2 := 0.70710678
## Placeholder heights of standing buildings, in world units. Buildings that shoot stand taller.
const BUILDING_HEIGHT := 14.0
const TOWER_HEIGHT := 32.0
## How long the land takes to slide into place after the earth turns, in milliseconds (view only).
const SLIDE_MS := 1800.0
## After a shift, the places the earth changed pulse this long (sank red, grew green, rich stone gold).
const PULSE_MS := 8000.0
const PULSE_COLORS := {"sank": Color("#e06048"), "den_sank": Color("#e06048"), "grew": Color("#8fd070"), "raised": Color("#ffd28a"), "find": Color("#c8c0f0")}
## The controls hint shows for this many rounds.
const HELP_ROUNDS := 2
## What each kind of standing thing is, for the back-to-front pass.
enum Kind { NODE, DEN, BUILDING, HEARTH, FOLK, ENEMY, HERO, PEDLAR }

var run: RunState
var iso := true  ## Tilted (isometric) view; false is the flat top-down view.
var zoom := 1.2
var pan := Vector2.ZERO  ## World point at the centre of the view.
var _dragging := false
var _mouse := Vector2(-1, -1)  ## Last mouse position over the map; negative when it is elsewhere.
var _press_at := Vector2.ZERO
var _moved := false
## Squares worth drawing (trails, paths, roads), rebuilt when the ground changes: [index, ground kind].
var _ground_cache: Array = []
var _ground_seen := [-1, null]
## Square index -> world time it was paved (or re-laid), for the glow.
var _paved_at := {}
## The earth's last shift as seen here ([shift count, world]) and when the slide that shows it began.
var _shift_seen := [-1, null, 0]
var _slide_from_ms := -1.0
var _pulse_from_ms := -1.0
var night := NightCamera.new()
var pickups := PickupPopups.new()
var celebrations := Celebrations.new()
var light := Lighting.new()
var _light_layer: Control
var _top_layer: Control
## The plot the hovered building card would go on, blinked on the map; -1 for none.
var preview_plot := -1


func reset_camera() -> void:
	zoom = 1.2
	pan = Vector2.ZERO
	night = NightCamera.new()


## Points the view at a ground point, zooming in a little if the view is wide.
func look_at_point(p: Vector2) -> void:
	night.release()
	pan = p
	zoom = maxf(zoom, 2.0)


## The zoom at which a circle of this radius round the hearth fills `fill` of the view.
func zoom_to_fit(radius: float, fill: float) -> float:
	var base := _scale() / zoom
	# Tilted, the circle is twice as wide as it is tall on screen.
	var fit := minf(fill * size.y / radius, fill * size.x / (2.0 * radius)) if iso else fill * minf(size.x, size.y) / (2.0 * radius)
	return clampf(fit / maxf(base, 0.0001), MIN_ZOOM, MAX_ZOOM)


func _ready() -> void:
	var add := CanvasItemMaterial.new()
	add.blend_mode = CanvasItemMaterial.BLEND_MODE_ADD
	_light_layer = _layer(_draw_lights)
	_light_layer.material = add
	_top_layer = _layer(_draw_top)


## A see-through child layer covering the map, drawn by `draw_with`.
func _layer(draw_with: Callable) -> Control:
	var layer := Control.new()
	layer.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	layer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	layer.draw.connect(draw_with)
	add_child(layer)
	return layer


func _process(delta: float) -> void:
	if run != null:
		night.update(self, delta)
		pickups.update(run.world, Time.get_ticks_msec())
		celebrations.update(run, Time.get_ticks_msec())
	queue_redraw()
	_light_layer.queue_redraw()
	_top_layer.queue_redraw()


func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		if mb.pressed and (mb.button_index == MOUSE_BUTTON_WHEEL_UP or mb.button_index == MOUSE_BUTTON_WHEEL_DOWN):
			var before := _to_world(mb.position)
			night.release()
			zoom = clampf(zoom * (1.15 if mb.button_index == MOUSE_BUTTON_WHEEL_UP else 1.0 / 1.15), MIN_ZOOM, MAX_ZOOM)
			pan += before - _to_world(mb.position)
			accept_event()
		elif mb.button_index == MOUSE_BUTTON_LEFT or mb.button_index == MOUSE_BUTTON_RIGHT:
			_dragging = mb.pressed
			if mb.pressed:
				_press_at = mb.position
				_moved = false
	elif event is InputEventMouseMotion:
		_mouse = (event as InputEventMouseMotion).position
		if _dragging and _mouse.distance_to(_press_at) > 5.0:
			_moved = true
		if _dragging and _moved:
			night.release()
			pan -= _unproject((event as InputEventMouseMotion).relative / _scale())


func _unhandled_key_input(event: InputEvent) -> void:
	var key := event as InputEventKey
	if key != null and key.pressed and not key.echo and key.keycode == KEY_V:
		iso = not iso
		get_viewport().set_input_as_handled()


func _notification(what: int) -> void:
	if what == NOTIFICATION_MOUSE_EXIT:
		_mouse = Vector2(-1, -1)


func _scale() -> float:
	if run == null:
		return 1.0
	# Tilted, the map is half as tall as it is wide, so it can fill more of a wide screen.
	var fit := minf(size.x, size.y / ISO_SQUASH) * 0.8 if iso else minf(size.x, size.y)
	return fit / (run.content.num("world_radius") * 2.1) * zoom


## A world offset as a screen offset before zooming: turned 45 degrees and squashed when tilted.
func _project(d: Vector2) -> Vector2:
	if not iso:
		return d
	return Vector2(d.x - d.y, (d.x + d.y) * ISO_SQUASH) * HALF_ROOT2


func _unproject(v: Vector2) -> Vector2:
	if not iso:
		return v
	var across := v.x / HALF_ROOT2  # x - y
	var down := v.y / (HALF_ROOT2 * ISO_SQUASH)  # x + y
	return Vector2((across + down) / 2.0, (down - across) / 2.0)


## Where a ground point is on screen.
func _to_screen(p: Vector2) -> Vector2:
	return size / 2.0 + _project(p - pan) * _scale()


## The ground point under a screen point.
func _to_world(s: Vector2) -> Vector2:
	return _unproject((s - size / 2.0) / _scale()) + pan


## The middle of a round marker of screen radius r standing on a ground point (it sits on the ground when tilted).
func _stand(p: Vector2, r: float) -> Vector2:
	return _to_screen(p) - Vector2(0.0, r if iso else 0.0)


## How many pixels a height in world units rises on screen (none in the flat view).
func _lift(height: float) -> float:
	return height * _scale() if iso else 0.0


func _draw() -> void:
	if run == null:
		return
	var content := run.content
	var w := run.world
	var s := _scale()
	var font := get_theme_default_font()
	var radius := content.num("world_radius")

	# Ground: the wilds, then the settlement clearing. Flat circles become ellipses when tilted.
	draw_rect(Rect2(Vector2.ZERO, size), Color("#161a17"))
	_ground_circle(Vector2.ZERO, radius, Color("#25301f"), 96)
	_watch_shift()
	for thicket in w.town.thickets:
		_ground_circle(_slid(thicket["pos"]), float(thicket["radius"]), Color(content.town["thickets"]["color"]), 24)
	_draw_earth()
	_ground_circle(Vector2.ZERO, content.num("settlement_radius"), Color("#33402a"), 64)
	draw_polyline(_closed(_ground_ring(Vector2.ZERO, content.num("settlement_radius"), 64)), Color("#4d5c3a"), 1.0)
	_draw_plots()
	_draw_ground()
	_draw_preview()
	_ground_circle(Vector2.ZERO, World.HEARTH_RADIUS, Color("#5a4030"), 32)

	# Warned attack sides: red wedges at the map edge until the wave arrives.
	if not w.wave_spawned:
		for angle in w.wave_sides:
			var dir := Vector2.from_angle(angle)
			var side := dir.orthogonal() * 22.0 / s
			draw_colored_polygon(_screen_poly(PackedVector2Array([dir * radius * 0.86, dir * radius + side, dir * radius - side])),
				Color("#c0403a"))

	# Everything standing, back to front: nearer things (lower on screen) cover farther ones.
	# The flat view keeps the old layers (resources, dens, buildings, hearth, townsfolk, enemies, heroes).
	var things: Array = []
	var keys := PackedInt64Array()
	for node in w.nodes:
		if w.node_active(node):
			_queue(things, keys, Kind.NODE, node, node["pos"])
	for den in w.dens:
		_queue(things, keys, Kind.DEN, den, den["pos"])
	for bi in w.buildings.size():
		_queue(things, keys, Kind.BUILDING, bi, w.buildings[bi]["pos"])
	if w.pedlar.is_open():
		_queue(things, keys, Kind.PEDLAR, null, w.pedlar.camp["pos"])
	_queue(things, keys, Kind.HEARTH, null, Vector2.ZERO)
	for u in w.folk:
		if u.alive:
			_queue(things, keys, Kind.FOLK, u, u.pos)
	for e in w.enemies:
		if e.alive and e.spawned:
			_queue(things, keys, Kind.ENEMY, e, e.pos)
	for hero in run.heroes:
		if hero.alive:
			_queue(things, keys, Kind.HERO, hero, hero.pos)
	keys.sort()
	for key in keys:
		var thing: Array = things[key & 0xFFFF]
		match thing[0]:
			Kind.NODE:
				_draw_node(thing[1], font)
			Kind.DEN:
				_draw_den(thing[1], font)
			Kind.BUILDING:
				_draw_building(thing[1], font)
			Kind.HEARTH:
				_draw_hearth()
			Kind.FOLK:
				_draw_folk(thing[1])
			Kind.ENEMY:
				_draw_enemy(thing[1])
			Kind.HERO:
				_draw_hero(thing[1], font)
			Kind.PEDLAR:
				_draw_pedlar(font)

	# Shots fly at chest height.
	var chest := _chest()
	var fire_shots := Lighting.fire_shots(run)
	for shot in w.shots:
		var c := Color("#fff3b0") if shot["ranged"] else Color("#ffffff")
		if fire_shots and shot.get("tower", false):
			c = Color("#ffa040")
		draw_line(_to_screen(shot["from"]) + chest, _to_screen(shot["to"]) + chest, Color(c, 0.6), 1.5 if shot["ranged"] else 2.5)

	# Night falls over everything.
	var dark := Lighting.darkness(run)
	if dark > 0.0:
		draw_rect(Rect2(Vector2.ZERO, size), Color(0.02, 0.03, 0.12, dark))
	_draw_earth_pulses()
	celebrations.draw_highlights(self, size, Time.get_ticks_msec(), _to_screen, main_color)


## Shots fly at chest height.
func _chest() -> Vector2:
	return Vector2(0.0, -FOLK_RADIUS * maxf(1.0, zoom * 0.7) if iso else 0.0)


## The light layer (blended by adding): sunlight over the map, the hearth's glow, and burning shots.
func _draw_lights() -> void:
	if run == null:
		return
	var w := run.world
	var s := _scale()
	var now := float(Time.get_ticks_msec())
	_light_layer.draw_rect(Rect2(Vector2.ZERO, size), Lighting.sun(run))
	var night_share := Lighting.darkness(run) / Lighting.NIGHT
	if not w.cold_tonight:
		var reach := World.HEARTH_RADIUS * s * lerpf(Lighting.HEARTH_REACH_DAY, Lighting.HEARTH_REACH_NIGHT, night_share)
		var squash := ISO_SQUASH if iso else 1.0
		var flick := Lighting.flicker(now)
		var c := Lighting.dim(Lighting.FIRE, (0.1 + 0.26 * night_share) * flick)
		light.draw_glow(_light_layer, _to_screen(Vector2.ZERO), reach * flick, reach * squash * flick, c)
		# A brighter heart round the flames themselves.
		var core := World.HEARTH_RADIUS * s * 1.2
		var flame := Vector2(0.0, World.HEARTH_RADIUS * s * 0.3 if iso else 0.0)
		light.draw_glow(_light_layer, _to_screen(Vector2.ZERO) - flame, core, core, Lighting.dim(Lighting.FIRE, (0.13 + 0.3 * night_share) * flick))
	if Lighting.fire_shots(run):
		var chest := _chest()
		var r := maxf(10.0, Lighting.SHOT_GLOW * s)
		for shot in w.shots:
			if not shot.get("tower", false):
				continue
			var fade := 1.0 - clampf((w.time - float(shot["time"])) / Lighting.SHOT_SECONDS, 0.0, 1.0)
			var c := Lighting.dim(Lighting.FIRE, (0.25 + 0.5 * night_share) * fade)
			var from := _to_screen(shot["from"]) + chest
			var to := _to_screen(shot["to"]) + chest
			light.draw_glow(_light_layer, (from + to) / 2.0, r * 0.6, r * 0.6, Lighting.dim(c, 0.6))
			light.draw_glow(_light_layer, to, r, r, c)
	celebrations.draw_lights(_light_layer, light, now, _to_screen, run.heroes, HERO_RADIUS * maxf(1.0, zoom * 0.7))


## The top layer, over the light: goods carried in, the controls hint and the hover tooltip.
func _draw_top() -> void:
	if run == null:
		return
	var s := _scale()
	var font := get_theme_default_font()
	# Goods carried in rise over the hearth as "+2 stone", above the fire and its health bar.
	var hearth_top := World.HEARTH_RADIUS * s * (ISO_SQUASH + 0.3 if iso else 1.0) + 16.0
	pickups.draw(_top_layer, _to_screen(Vector2.ZERO) - Vector2(0.0, hearth_top), font, Time.get_ticks_msec(), main_color)
	# The controls hint is for a first run's opening rounds, and never under the building cards.
	if run.round_number <= HELP_ROUNDS and run.phase != RunState.Phase.BUILD:
		var help := "Mouse wheel to zoom, drag to look around, V for %s view, point at anything for details" % ("flat" if iso else "tilted")
		_top_layer.draw_string(font, Vector2(8, size.y - 8), help, HORIZONTAL_ALIGNMENT_LEFT, -1, 11, Color("#8a9088"))
	celebrations.draw_top(_top_layer, size, font, Time.get_ticks_msec(), _to_screen, run.heroes, HERO_RADIUS * maxf(1.0, zoom * 0.7))
	if _mouse.x >= 0.0 and not _dragging:
		var tip := hovered(_mouse)
		if not tip.is_empty():
			_draw_tip(tip, _mouse, font)


## Adds a standing thing to this frame's back-to-front pass. The sort key packs depth above the thing's index.
func _queue(things: Array, keys: PackedInt64Array, kind: Kind, ref: Variant, pos: Vector2) -> void:
	var depth := (_to_screen(pos).y + 50000.0) * 4.0 if iso else float(kind)
	keys.append((int(depth) << 16) | things.size())
	things.append([kind, ref])


func _draw_node(node: Dictionary, font: Font) -> void:
	var def: Dictionary = run.content.world["nodes"][node["type"]]
	var left := float(node["amount"]) / float(node["max"])
	var r := _node_radius(node)
	var at := _slid(node["pos"])
	var p := _stand(at, r)
	_shadow(at, r)
	var col := Color(def["color"])
	draw_circle(p, r, col if left > 0.0 else Color(col, 0.25))
	if zoom > 1.6:
		draw_string(font, p + Vector2(r + 2, 4), "%s %d" % [def["name"], node["amount"]], HORIZONTAL_ALIGNMENT_LEFT, -1, 10, Color("#c8c8b0"))


## Resource nodes: size shows how much is left.
func _node_radius(node: Dictionary) -> float:
	return maxf(3.0, (6.0 + 8.0 * float(node["amount"]) / float(node["max"])) * _scale() * 1.6)


func _draw_den(den: Dictionary, font: Font) -> void:
	var def: Dictionary = run.content.world["dens"][den["type"]]
	var r := _den_radius()
	if den.get("camp", false):
		# The land the war camp holds: townsfolk won't gather inside this ring.
		draw_polyline(_closed(_ground_ring(den["pos"], run.content.num("camp_hold_radius"), 40)), Color(0.8, 0.3, 0.2, 0.45), 1.5)
	var at := _slid(den["pos"])
	var p := _stand(at, r)
	_shadow(at, r)
	draw_circle(p, r, Color(def["color"]))
	draw_arc(p, r, 0, TAU, 24, Color("#a05050"), 2.0)
	draw_string(font, p + Vector2(-r, r + 12), def["name"], HORIZONTAL_ALIGNMENT_LEFT, -1, 11, Color("#d0a0a0"))


## The pedlar's camp: a striped tent with its health under it, and a slow gold beacon ring so it is
## found out past the town (Yusuf never noticed one).
func _draw_pedlar(font: Font) -> void:
	var camp: Dictionary = run.world.pedlar.camp
	var at := Vector2(camp["pos"])
	var r := _den_radius() * 1.25
	var base := _to_screen(at)
	var beat := 0.5 + 0.5 * sin(Time.get_ticks_msec() * 0.004)
	var ring := _ground_ring(at, r * (1.6 + 0.5 * beat) / _scale(), 40)
	draw_polyline(_closed(ring), Color(1.0, 0.85, 0.35, 0.75 - 0.5 * beat), 3.0)
	_shadow(at, r)
	var top := base + Vector2(0, -r * 1.8)
	draw_colored_polygon(PackedVector2Array([base + Vector2(-r, 0), top, base + Vector2(r, 0)]), Color("#c89a4a"))
	draw_colored_polygon(PackedVector2Array([base + Vector2(-r * 0.35, 0), top, base + Vector2(r * 0.35, 0)]), Color("#8a3a2a"))
	_bar(base + Vector2(-r, 4), r * 2.0, float(camp["hp"]) / float(run.content.pedlars["hp"]), Color("#d8b860"))
	var name: String = run.content.pedlars["pedlars"][camp["id"]]["name"]
	draw_string(font, base + Vector2(-r, 21), "Pedlar: %s (%d wares)" % [name, camp["wares"].size()], HORIZONTAL_ALIGNMENT_LEFT, -1, 12, Color("#ffe0a0"))


func _den_radius() -> float:
	return maxf(8.0, 18.0 * _scale() * 1.6)


## How tall a building stands on screen: towers taller, gates flat, half-built ones part way up.
func _building_lift(bi: int) -> float:
	var b: Dictionary = run.world.buildings[bi]
	var def: Dictionary = run.content.buildings[b["type"]]
	if run.world.town.is_gate_type(b["type"]):
		return 0.0
	var done := clampf(1.0 - float(b["work_left"]) / float(def["work"]), 0.0, 1.0)
	return _lift(TOWER_HEIGHT if def.has("attack") else BUILDING_HEIGHT) * done


## Buildings fill their plot: solid when raised, outline plus progress while being built.
func _draw_building(bi: int, font: Font) -> void:
	var w := run.world
	var s := _scale()
	var b: Dictionary = w.buildings[bi]
	var def: Dictionary = run.content.buildings[b["type"]]
	var lift := _building_lift(bi)
	var p := _to_screen(b["pos"]) - Vector2(0.0, lift)  # The middle of the roof.
	var half := maxf(4.0, 11.0 * s)
	var shape := _screen_poly(w.town.plot_outline(b["plot"]))
	var col := Color(def["color"])
	var work_left := float(b["work_left"])
	if work_left <= 0.0 and w.town.is_gate_type(b["type"]):
		# A gate fades as raiders batter it, and shows its health.
		# Drawn open, so it reads as a way through: a faint floor, a dashed edge and two posts either
		# side of the opening (across the ring, the way people walk through).
		var whole := w.town.gate_health(bi)
		draw_colored_polygon(shape, Color(col, 0.12 + 0.18 * whole))
		var edge := _closed(shape)
		for k in edge.size() - 1:
			draw_dashed_line(edge[k], edge[k + 1], Color("#e8d9a8", 0.5 + 0.5 * whole), 1.5, 4.0)
		var pos := Vector2(b["pos"])
		var across: Vector2 = pos.normalized().orthogonal() if pos.length() > 0.0 else Vector2.RIGHT
		var post := maxf(2.5, 3.5 * s)
		var post_up := _lift(BUILDING_HEIGHT)
		for side: float in [-1.0, 1.0]:
			var at := _to_screen(pos + across * side * half / s * 0.75)
			draw_rect(Rect2(at - Vector2(post, post + post_up), Vector2(post * 2.0, post * 2.0 + post_up)),
				Color(col.lightened(0.2), 0.4 + 0.6 * whole))
		draw_line(_to_screen(pos - across * half / s * 0.35), _to_screen(pos + across * half / s * 0.35), Color("#e8d9a8", 0.35), 1.0)
		if whole < 1.0:
			_bar(p + Vector2(-half, half + 3), half * 2.0, whole, Color("#e0a050"))
	elif work_left <= 0.0:
		# A broken tower is drawn dark until it is mended at dawn; a hurt one shows its health.
		var tower_hp := float(def.get("tower_hp", 0.0))
		var broken := tower_hp > 0.0 and float(b["hp"]) <= 0.0
		_draw_block(shape, lift, col.darkened(0.6) if broken else col, Color("#e05050") if broken else Color("#e8d9a8"))
		if tower_hp > 0.0 and float(b["hp"]) < tower_hp:
			_bar(p + Vector2(-half, half + 3), half * 2.0, float(b["hp"]) / tower_hp, Color("#e05050"))
	else:
		var done := 1.0 - work_left / float(def["work"])
		draw_colored_polygon(shape, Color(col, 0.25))
		draw_polyline(_closed(shape), col, 1.5)
		if lift >= 1.0:
			_draw_block(shape, lift, Color(col, 0.55), col)
		_bar(p + Vector2(-half, half + 3), half * 2.0, done, Color("#e8d9a8"))
	# Stalls show a dot per good on sale; workshops show how far the current good is.
	if work_left <= 0.0 and def.has("stall"):
		for k in b["goods"].size():
			draw_circle(p + Vector2(-half + 3.0 + k * 5.0, half + 4.0), 2.0, Color("#ffd24a"))
	elif work_left <= 0.0 and def.has("workshop") and b["craft"] != "":
		var recipe: Dictionary = run.content.market["recipes"][b["craft"]]
		_bar(p + Vector2(-half, half + 3), half * 2.0, 1.0 - float(b["craft_left"]) / float(recipe["work"]), Color("#ffd24a"))
	if zoom > 1.4:
		draw_string(font, p + Vector2(-half, -half - 3), def["name"], HORIZONTAL_ALIGNMENT_LEFT, -1, 10, Color("#d8d0b8"))


## A flat shape stood up as a block `lift` pixels tall: the walls facing the viewer, shaded as if lit
## from the left, then the roof. With no lift it is the flat shape.
func _draw_block(base: PackedVector2Array, lift: float, color: Color, edge: Color) -> void:
	if lift < 1.0:
		draw_colored_polygon(base, color)
		draw_polyline(_closed(base), edge, 1.0)
		return
	var up := Vector2(0.0, -lift)
	var middle := Vector2.ZERO
	for q in base:
		middle += q
	middle /= base.size()
	var walls: Array = []
	for k in base.size():
		var a := base[k]
		var b := base[(k + 1) % base.size()]
		var out := (b - a).orthogonal().normalized()
		if out.dot((a + b) / 2.0 - middle) < 0.0:
			out = -out
		if out.y > 0.05:  # Faces the viewer.
			walls.append([(a.y + b.y) / 2.0, a, b, out.x])
	walls.sort_custom(func(x: Array, y: Array) -> bool: return x[0] < y[0])
	for wall: Array in walls:
		var a: Vector2 = wall[1]
		var b: Vector2 = wall[2]
		draw_colored_polygon(PackedVector2Array([a, b, b + up, a + up]), color.darkened(0.3 + 0.2 * float(wall[3])))
	var roof := PackedVector2Array()
	for q in base:
		roof.append(q + up)
	draw_colored_polygon(roof, color)
	draw_polyline(_closed(roof), edge, 1.0)


func _draw_hearth() -> void:
	var s := _scale()
	var hearth_r := World.HEARTH_RADIUS * s
	var center := _to_screen(Vector2.ZERO)
	if not iso:
		draw_circle(center, hearth_r, Color("#5a4030"))
	var fire := hearth_r * (0.3 if iso else 0.55)
	draw_circle(center - Vector2(0.0, fire if iso else 0.0), fire, Color("#ff9a3a") if not run.world.cold_tonight else Color("#6a6a7a"))
	var top := hearth_r * ISO_SQUASH + fire if iso else hearth_r
	_bar(center + Vector2(-hearth_r, -top - 8), hearth_r * 2.0, run.world.hearth_hp / run.hearth_max_hp(), Color("#7fd0ff"))


func _draw_folk(u: Unit) -> void:
	var r := FOLK_RADIUS * maxf(1.0, zoom * 0.7)
	var p := _stand(u.pos, r)
	_shadow(u.pos, r)
	draw_circle(p, r, Color(run.content.townsfolk[u.type_id]["color"]))
	if u.carry_amount > 0:
		draw_circle(p + Vector2(r, -r), r * 0.5, Color(main_color(u.carrying)))
	if u.hp < u.max_hp:
		_bar(p + Vector2(-r, -r - 4), r * 2.0, u.hp_fraction(), Color("#5ee07a"))


func _draw_enemy(e: Unit) -> void:
	var r := (BOSS_RADIUS if e.is_boss else ENEMY_RADIUS) * maxf(1.0, zoom * 0.7)
	var p := _stand(e.pos, r)
	_shadow(e.pos, r)
	draw_circle(p, r, Color(run.content.enemies[e.type_id]["color"]))
	if e.den_index >= 0:
		draw_arc(p, r, 0, TAU, 16, Color("#301818"), 1.5)
	_bar(p + Vector2(-r, -r - 5), r * 2.0, e.hp_fraction(), Color("#e05050"))


## A soft dark ellipse on the ground under something standing (tilted view only).
func _shadow(p: Vector2, r: float) -> void:
	if iso:
		draw_colored_polygon(_ground_ring(p, r * 0.9 / _scale(), 12), Color(0, 0, 0, 0.3))


## A flat circle on the ground (an ellipse when tilted).
func _ground_circle(p: Vector2, radius: float, color: Color, points: int) -> void:
	if iso:
		draw_colored_polygon(_ground_ring(p, radius, points), color)
	else:
		draw_circle(_to_screen(p), radius * _scale(), color)


func _ground_ring(p: Vector2, radius: float, points: int) -> PackedVector2Array:
	var out := PackedVector2Array()
	for k in points:
		out.append(_to_screen(p + Vector2.from_angle(TAU * k / points) * radius))
	return out


## A ground square around a world point (a diamond when tilted).
func _ground_square(p: Vector2, half: float, color: Color, filled := true) -> void:
	var corners := _screen_poly(PackedVector2Array([p + Vector2(-half, -half), p + Vector2(half, -half),
		p + Vector2(half, half), p + Vector2(-half, half)]))
	if filled:
		draw_colored_polygon(corners, color)
	else:
		draw_polyline(_closed(corners), color, 1.5)


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
	var building := _building_at(at)
	if building >= 0:
		return Tooltips.building(run, building)
	var plot := w.town.plot_at(_to_world(at))
	if plot >= 0 and w.town.plots[plot]["obstacle"] != "":
		return Tooltips.obstacle(run, w.town.plots[plot]["obstacle"])
	if _to_world(at).length() <= World.HEARTH_RADIUS + 3.0 / _scale():
		return Tooltips.hearth(run)
	if w.pedlar.is_open() and _near(w.pedlar.camp["pos"], at, _den_radius()):
		return Tooltips.pedlar_camp(run)
	for den in w.dens:
		if _near(den["pos"], at, _den_radius()):
			return Tooltips.den(run, den)
	for node in w.nodes:
		if w.node_active(node) and _near(node["pos"], at, maxf(3.0, 14.0 * _scale() * 1.6)):
			return Tooltips.node(run, node)
	var square := w.pathing.index_of(_to_world(at))
	if w.earth.is_ridge(square):
		return Tooltips.earth(run, "ridge")
	var seam: Dictionary = w.earth.seam_near(_to_world(at), 6.0 / _scale())
	if not seam.is_empty():
		return Tooltips.seam(run, seam)
	if w.earth.raw_at(_to_world(at)) and w.pathing.ground[square] == Pathing.THICKET:
		return Tooltips.earth(run, "raw")
	if w.pathing.ground[square] != Pathing.PLAIN :
		return Tooltips.ground(run, square)
	return {}


## True when a screen point is on a round marker of screen radius `radius` standing at a world point.
func _near(world_pos: Vector2, at: Vector2, radius: float) -> bool:
	return _stand(world_pos, radius).distance_to(at) <= radius + 3.0


## The building under a screen point (-1 if none): its floor, walls or roof. The nearest one wins.
func _building_at(at: Vector2) -> int:
	var w := run.world
	var best := -1
	var best_y := -INF
	for bi in w.buildings.size():
		var base := _screen_poly(w.town.plot_outline(w.buildings[bi]["plot"]))
		var lift := _building_lift(bi)
		for rise: float in ([0.0, 0.5, 1.0] if lift >= 1.0 else [0.0]):
			if Geometry2D.is_point_in_polygon(at + Vector2(0.0, lift * rise), base):
				var y := _to_screen(w.buildings[bi]["pos"]).y
				if y > best_y:
					best = bi
					best_y = y
				break
	return best


## A dark box beside the mouse: title, lines, tags, then warnings in orange. Kept inside the map.
func _draw_tip(tip: Dictionary, at: Vector2, font: Font) -> void:
	var rows: Array = [[tip["title"], 13, Color("#f0e6c8")]]
	var colors: Dictionary = tip.get("line_colors", {})
	for i in tip["lines"].size():
		for part in _wrap(tip["lines"][i]):
			rows.append([part, 11, colors.get(i, Color("#c8ccc0"))])
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
	_top_layer.draw_rect(Rect2(pos, box), Color(0.05, 0.06, 0.05, 0.92))
	_top_layer.draw_rect(Rect2(pos, box), Color("#6a7458"), false, 1.0)
	for i in rows.size():
		var row: Array = rows[i]
		_top_layer.draw_string(font, pos + Vector2(8, 18 + i * line_h), row[0], HORIZONTAL_ALIGNMENT_LEFT, width, row[1], row[2])


## A good's colour: the main four have their own; anything else takes the colour of the node it comes from, lightened.
func main_color(resource: String) -> String:
	var main: Dictionary = {"food": "#d98aa8", "fuel": "#e0b050", "wood": "#7fbf6a", "stone": "#b0b4bc"}
	if main.has(resource):
		return main[resource]
	for id: String in run.content.world["nodes"]:
		var def: Dictionary = run.content.world["nodes"][id]
		if def["gives"] == resource and def.has("color"):
			return Color(def["color"]).lightened(0.45).to_html(false)
	return "#ffffff"


func _draw_hero(hero: Unit, font: Font) -> void:
	var r := HERO_RADIUS * maxf(1.0, zoom * 0.7)
	var p := _stand(hero.pos, r)
	_shadow(hero.pos, r)
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


## Ring plots: free ones in opened rings as nearly invisible outlines (Yusuf, 2026-10-21), obstacles filled in.
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
			draw_polyline(_closed(shape), Color(0.6, 0.65, 0.45, 0.05), 1.0)


## The plot a hovered building card would take, blinking about twice a second.
func _draw_preview() -> void:
	if preview_plot < 0 or preview_plot >= run.world.town.plots.size():
		return
	var pulse := 0.5 + 0.5 * sin(Time.get_ticks_msec() * 0.012)
	var shape := _screen_poly(run.world.town.plot_outline(preview_plot))
	draw_colored_polygon(shape, Color(1.0, 0.85, 0.35, 0.2 + 0.35 * pulse))
	draw_polyline(_closed(shape), Color(1.0, 0.9, 0.5, 0.55 + 0.45 * pulse), 2.5)


## The earth plates: raw rifts, ridges, and faint lines for the ring edges and seams. The earth just shifts:
## the map shows the land as it is, not what the next shift will do (Yusuf, 2026-10-20).
func _draw_earth() -> void:
	var earth := run.world.earth
	if not earth.enabled():
		return
	var colors: Dictionary = run.content.plates["colors"]
	for strip in earth.raw:
		var ring: Dictionary = earth.rings[int(strip["ring"])]
		draw_colored_polygon(_screen_poly(_sector(float(ring["r0"]), float(ring["r1"]), strip["a0"], strip["a1"])),
			Color(colors["raw"], 0.85))
	var cell := run.world.pathing.cell
	for i in earth.ridge_cells():
		_ground_square(run.world.pathing.center(i), cell * 0.55, Color(colors["ridge"]))
	var faint := Color(colors["seam"], 0.3)
	for ring in earth.rings:
		draw_polyline(_closed(_ground_ring(Vector2.ZERO, float(ring["r0"]), 96)), faint, 1.0)
		for a: float in ring["seams"]:
			var dir := Vector2.from_angle(a)
			draw_line(_to_screen(dir * float(ring["r0"])), _to_screen(dir * float(ring["r1"])), faint, 1.0)


## Ground points outlining the strip of rings between radii r0 and r1, from angle a0 clockwise to a1.
func _sector(r0: float, r1: float, a0: float, a1: float) -> PackedVector2Array:
	var width := fposmod(a1 - a0, TAU)
	var steps := maxi(2, ceili(width / 0.04))
	var points := PackedVector2Array()
	for n in steps + 1:
		points.append(Vector2.from_angle(a0 + width * n / steps) * r1)
	for n in range(steps, -1, -1):
		points.append(Vector2.from_angle(a0 + width * n / steps) * r0)
	return points


## Starts the slide when the earth has just turned (not when a run is first shown), and the pulses when a
## geomancer's spell has just changed the land.
func _watch_shift() -> void:
	var w := run.world
	var seen := [w.earth.shifts, w, w.earth.changes]
	if seen == _shift_seen:
		return
	if _shift_seen[1] == w and w.earth.shifts > int(_shift_seen[0]):
		_slide_from_ms = Time.get_ticks_msec()
		_pulse_from_ms = _slide_from_ms
	elif _shift_seen[1] == w and w.earth.changes > int(_shift_seen[2]):
		_pulse_from_ms = Time.get_ticks_msec()
	_shift_seen = seen


## Rings that swell out from each place the last shift changed, for a few seconds after it.
func _draw_earth_pulses() -> void:
	if _pulse_from_ms < 0.0:
		return
	var t := Time.get_ticks_msec() - _pulse_from_ms
	if t >= PULSE_MS:
		_pulse_from_ms = -1.0
		return
	var fade := 1.0 - t / PULSE_MS
	var phase := fmod(t, 1200.0) / 1200.0
	for ev: Dictionary in run.world.earth.events:
		var col: Color = PULSE_COLORS.get(ev["kind"], Color.WHITE)
		col.a = fade * (1.0 - phase)
		var p := _to_screen(_slid(ev["pos"]))
		draw_arc(p, 8.0 + phase * (40.0 if ev["great"] else 24.0), 0, TAU, 32, col, 3.0 if ev["great"] else 2.0)


## Where a thing on the plates is drawn while the land slides into place after a shift.
func _slid(p: Vector2) -> Vector2:
	if _slide_from_ms < 0.0:
		return p
	var t := (Time.get_ticks_msec() - _slide_from_ms) / SLIDE_MS
	if t >= 1.0:
		_slide_from_ms = -1.0
		return p
	var ease_t := 1.0 - pow(1.0 - t, 3.0)
	return p.rotated(-(1.0 - ease_t) * run.world.earth.last_turn(p))


## Trails, worn paths and roads.
func _draw_ground() -> void:
	var w := run.world
	var seen := [w.pathing.ground_version, w]
	if seen != _ground_seen:
		var same_world: bool = _ground_seen[1] == w
		_ground_seen = seen
		var was := {}
		for entry: Array in _ground_cache:
			was[entry[0]] = entry[1]
		if not same_world:
			_paved_at.clear()
		_ground_cache = []
		for i in w.pathing.ground.size():
			var g: int = w.pathing.ground[i]
			if g >= Pathing.TRAIL:
				_ground_cache.append([i, g])
				# New roads glow, and so does the ground a new age lays round the hearth.
				var laid: bool = g >= Pathing.FIRST_ROAD or w.pathing.floor_kind[i] >= g
				if same_world and laid and int(was.get(i, 0)) != g:
					_paved_at[i] = w.time
	var cell := w.pathing.cell
	var trail := Color(run.content.town["trail"]["color"])
	var path := Color(run.content.town["path"]["color"])
	for entry: Array in _ground_cache:
		var p := w.pathing.center(entry[0])
		var g: int = entry[1]
		if g >= Pathing.FIRST_ROAD:
			_ground_square(p, cell * 0.5, Color(w.town.road_def(g)["color"]))
		elif g == Pathing.PATH:
			_ground_square(p, cell * 0.48, Color(path, 1.0))
		else:
			_ground_square(p, cell * 0.385, Color(trail.lightened(0.1), 0.88))
	# Squares paved in the last few seconds glow, so you can see the stone-layers at work.
	for i: int in _paved_at.keys():
		var age := w.time - float(_paved_at[i])
		if age > PAVE_GLOW_SECONDS or age < 0.0:
			_paved_at.erase(i)
			continue
		_ground_square(w.pathing.center(i), cell * 0.5, Color("#ffe08a", 0.9 * (1.0 - age / PAVE_GLOW_SECONDS)), false)


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
