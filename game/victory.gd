class_name Victory
extends RefCounted
## A won run's ending on the map (Yusuf, 2026-10-25: winning should land harder). The night lifts, the camera
## closes in on the hearth, every hero and townsperson comes home to stand round the fire and jumps for joy,
## and confetti falls. After SHOW_MS (or a click or Space) the end screen opens over it, and the party carries on
## behind. View only, like ArenaView: people are drawn at their places round the hearth, the sim never moves them.
## Timings are in real milliseconds.

## How long everyone takes to come home to the hearth.
const GATHER_MS := 1800.0
## How long the camera takes to close in on the hearth.
const CAMERA_MS := 2200.0
## How long the night takes to lift.
const DAWN_MS := 2500.0
## How long before the end screen opens by itself.
const SHOW_MS := 6500.0
## Rings of people round the hearth: the first ring's distance from its middle, then the gap between people
## (heroes stand wider, on the inner rings), in world units.
const FIRST_RING := 50.0
const HERO_SPACING := 24.0
const FOLK_SPACING := 14.0
## The circle round the hearth the camera frames, and how much of the view it fills.
const FRAME_RADIUS := 100.0
const FILL := 0.85
## How high a jump goes, in a person's own radii, and how fast they jump (per millisecond).
const HOP := 1.5
const HOP_SPEED := 0.0075
const CONFETTI := 160
const COLORS := ["#ffd870", "#e05a4f", "#5fb0ff", "#7fd06a", "#f5f0e6", "#e58ad0", "#ffa040"]
const GOLD := Color("#ffd870")

## When the ending began (ms), or -1 before a win.
var born := -1.0
## The end screen has been opened (by itself or by a click).
var finished := false
## Where each person stands round the hearth: unit instance id -> [spot, index].
var _spots := {}
var _from_zoom := 1.0
var _from_pan := Vector2.ZERO
var _released := false
## Each piece: [x share, start y share (above the top), fall px/s, sway px, sway phase, spin speed, colour, size].
var _confetti: Array = []
var _rounds := 0


func active() -> bool:
	return born >= 0.0


## True while the ending plays and the end screen has not opened yet.
func playing() -> bool:
	return active() and not finished


## Begins the ending: everyone alive gets a place round the hearth, heroes nearest the fire.
func start(run: RunState, view: ArenaView, now_ms: float) -> void:
	born = now_ms
	finished = false
	_released = false
	_from_zoom = view.zoom
	_from_pan = view.pan
	_rounds = run.round_number
	_spots.clear()
	var people: Array[Unit] = []
	people.append_array(run.living_heroes())
	var heroes := people.size()
	for u in run.world.folk:
		if u.alive:
			people.append(u)
	var places := layout(heroes, people.size() - heroes)
	for i in people.size():
		_spots[people[i].get_instance_id()] = [places[i], i]
	var rng := SeededRng.stream(run.run_seed, "confetti")
	_confetti.clear()
	for i in CONFETTI:
		_confetti.append([rng.randf(), rng.randf_range(0.05, 1.3), rng.randf_range(90.0, 180.0), rng.randf_range(8.0, 26.0),
			rng.randf() * TAU, rng.randf_range(2.0, 7.0), Color(COLORS[i % COLORS.size()]), rng.randf_range(4.0, 7.0)])


## Places round the hearth: `heroes` on the inner rings, then `folk`, each ring as full as its spacing allows.
static func layout(heroes: int, folk: int) -> Array[Vector2]:
	var out: Array[Vector2] = []
	var r := FIRST_RING
	for group: Array in [[heroes, HERO_SPACING], [folk, FOLK_SPACING]]:
		var left: int = group[0]
		var gap: float = group[1]
		while left > 0:
			var fits := maxi(1, int(TAU * r / gap))
			var here := mini(left, fits)
			# Each ring starts a little round from the last, so the rows don't line up in spokes.
			var turn := r * 0.37
			for k in here:
				out.append(Vector2.from_angle(turn + TAU * k / here) * r)
			left -= here
			r += gap
	return out


## The player moved the camera: leave it where they put it.
func release() -> void:
	_released = true


## Opens the end screen now.
func skip() -> void:
	finished = true


## Moves the camera for this frame; true on the frame the end screen should open by itself.
func update(view: ArenaView, now_ms: float) -> bool:
	if not active():
		return false
	var t := now_ms - born
	if not _released:
		var k := smoothstep(0.0, CAMERA_MS, t)
		view.zoom = lerpf(_from_zoom, maxf(_from_zoom, view.zoom_to_fit(FRAME_RADIUS, FILL)), k)
		view.pan = _from_pan.lerp(Vector2.ZERO, k)
	if not finished and t >= SHOW_MS:
		finished = true
		return true
	return false


## Where a person is drawn: walking home to their place round the hearth, then standing there.
func place(u: Unit, now_ms: float) -> Vector2:
	if not active() or not _spots.has(u.get_instance_id()):
		return u.pos
	var k := smoothstep(0.0, GATHER_MS, now_ms - born)
	return u.pos.lerp(_spots[u.get_instance_id()][0], k)


## How high a person is off the ground this frame, in their own radii: nothing until they are home.
func hop(u: Unit, now_ms: float) -> float:
	if not active() or not _spots.has(u.get_instance_id()):
		return 0.0
	var t := now_ms - born - GATHER_MS * 0.8
	if t <= 0.0:
		return 0.0
	var i: int = _spots[u.get_instance_id()][1]
	return HOP * clampf(t / 400.0, 0.0, 1.0) * absf(sin(t * HOP_SPEED + i * 1.7))


## Share of the night's darkness still over the map: 1 before a win, lifting to 0 as the ending begins.
func night_left(now_ms: float) -> float:
	if not active():
		return 1.0
	return 1.0 - smoothstep(0.0, DAWN_MS, now_ms - born)


## Over the light: the hearth's victory glow.
func draw_lights(view: CanvasItem, light: Lighting, hearth: Vector2, scale: float, now_ms: float) -> void:
	if not active():
		return
	var k := smoothstep(0.0, 900.0, now_ms - born) * (0.85 + 0.15 * sin(now_ms * 0.004))
	var r := FRAME_RADIUS * scale * 1.3
	light.draw_glow(view, hearth, r, r * 0.6, Lighting.dim(GOLD, 0.35 * k))


## On the top layer: confetti falling over the whole map, and the victory title until the end screen opens.
func draw_top(view: CanvasItem, size: Vector2, font: Font, now_ms: float) -> void:
	if not active():
		return
	var t := (now_ms - born) / 1000.0
	for piece: Array in _confetti:
		var y := -float(piece[1]) * size.y + float(piece[2]) * t
		if y < -20.0:
			continue
		y = fposmod(y + 20.0, size.y + 40.0) - 20.0
		var x := float(piece[0]) * size.x + float(piece[3]) * sin(t * 2.0 + float(piece[4]))
		var spin := t * float(piece[5]) + float(piece[4])
		# A small paper square tumbling: its width shrinks and grows as it turns.
		var half := Vector2(float(piece[7]) * absf(cos(spin)) + 1.0, float(piece[7]) * 0.6)
		var corners := PackedVector2Array()
		for c: Vector2 in [Vector2(-1, -1), Vector2(1, -1), Vector2(1, 1), Vector2(-1, 1)]:
			corners.append(Vector2(x, y) + (c * half).rotated(spin * 0.4))
		view.draw_colored_polygon(corners, piece[6])
	if finished:
		return
	var a := clampf((now_ms - born - 300.0) / 500.0, 0.0, 1.0)
	if a <= 0.0:
		return
	# Low on the map, so the people round the hearth stay in view above it.
	var band := Rect2(0.0, size.y - 150.0, size.x, 116.0)
	view.draw_rect(band, Color(0.05, 0.04, 0.02, 0.65 * a))
	view.draw_line(band.position, band.position + Vector2(size.x, 0), Color(GOLD, 0.8 * a), 2.0)
	view.draw_line(band.end - Vector2(size.x, 0), band.end, Color(GOLD, 0.8 * a), 2.0)
	_centred(view, font, "Victory!", band.position.y + 54.0, 44, Color(GOLD, a), size.x, a)
	_centred(view, font, "The people endured all %d rounds." % _rounds, band.position.y + 84.0, 18, Color(0.95, 0.92, 0.84, a), size.x, a)
	_centred(view, font, "Click to carry on", band.position.y + 106.0, 12, Color(0.75, 0.73, 0.66, a), size.x, a)


func _centred(view: CanvasItem, font: Font, text: String, y: float, font_size: int, c: Color, width: float, a: float) -> void:
	var w := font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size).x
	var at := Vector2((width - w) / 2.0, y)
	view.draw_string_outline(font, at, text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, 4, Color(0, 0, 0, 0.8 * a))
	view.draw_string(font, at, text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, c)
