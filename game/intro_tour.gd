class_name IntroTour
extends Control
## The camera tour that opens a player's first run (Yusuf, 2026-10-26), in place of the round screen: about 25
## seconds, letterboxed, no HUD, one caption a shot (data/tips.json "tour"). What it films is real: a throwaway
## prologue run from the same seed, founded at random and stepped live with the first newcomer taken each dawn,
## so the gatherers and the hero's fight are the sim's own. The player's run is never touched: it is a separate
## RunState and starts fresh once the tour ends. A click, Space or Esc skips it. View only, like the cameras.

signal finished

## Game speed the prologue plays at, and how far into the first day it starts (sim seconds), so people are out.
const SIM_SPEED := 2.0
const PRE_ROLL_SECONDS := 2.0
## How fast the camera settles on each shot (per second), and the letterbox bars' share of the height.
const EASE := 2.2
const BAR := 0.09
## How much ground each shot takes in (a radius round its focus), as fitted by ArenaView.zoom_to_fit.
const REACH := {"hearth": 70.0, "town": 260.0, "hero": 90.0, "den": 120.0}

var arena: ArenaView
var prologue: RunState
var shots: Array = []
var _shot := -1
var _shot_left := 0.0
var _acc := 0.0
var _hero: Unit
var _den := Vector2.ZERO
var _caption: Label
var _hint: Label


func _init() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	_caption = Label.new()
	_caption.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_caption.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_caption.add_theme_font_size_override("font_size", 24)
	_caption.add_theme_color_override("font_color", Color("#f2e8d6"))
	_caption.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.8))
	_caption.add_theme_constant_override("shadow_offset_y", 2)
	add_child(_caption)
	_hint = Label.new()
	_hint.text = "Click or Space to skip"
	_hint.add_theme_font_size_override("font_size", 13)
	_hint.add_theme_color_override("font_color", Color("#9a9080"))
	add_child(_hint)
	hide()


## A prologue run for the tour: the run's seed, founded at random, its first round begun and stepped
## PRE_ROLL_SECONDS into the first day.
static func make_prologue(content: Content, seed_value: int) -> RunState:
	var r := RunState.new(content, seed_value)
	r.choose_random_tradition()
	r.begin_round()
	advance(r, PRE_ROLL_SECONDS)
	return r


## Steps a prologue by `seconds` of sim time, taking the first newcomer it can at each dawn (or nobody).
static func advance(r: RunState, seconds: float) -> void:
	var steps := int(seconds / r.world.dt)
	for i in steps:
		while r.phase == RunState.Phase.PICK:
			r.choose_pick(0 if r.can_take_pick(0) else -1)
		if r.phase != RunState.Phase.SIM:
			return
		r.step()


## The hero the hero shot follows: one in a fight if any, else the one farthest out (null with no heroes).
static func pick_hero(r: RunState) -> Unit:
	var best: Unit = null
	var best_score := -1.0
	for h in r.living_heroes():
		var score := h.pos.length() + (10000.0 if h.target != null and h.target.alive else 0.0)
		if score > best_score:
			best_score = score
			best = h
	return best


## Where the den shot looks: the den nearest the way the round's attack comes (the hearth if there are none).
static func pick_den(r: RunState) -> Vector2:
	var w := r.world
	var way: float = w.wave_sides[0] if not w.wave_sides.is_empty() else 0.0
	var best := Vector2.ZERO
	var best_gap := INF
	for den: Dictionary in w.dens:
		var p: Vector2 = den["pos"]
		var gap := absf(angle_difference(p.angle(), way))
		if gap < best_gap:
			best_gap = gap
			best = p
	return best


func playing() -> bool:
	return prologue != null


## Starts the tour on `view`, filming a prologue of this seed.
func start(content: Content, seed_value: int, view: ArenaView) -> void:
	arena = view
	prologue = make_prologue(content, seed_value)
	shots = content.tips.get("tour", [])
	arena.run = prologue
	arena.reset_camera()
	arena.night_camera = false
	_hero = pick_hero(prologue)
	_den = pick_den(prologue)
	_acc = 0.0
	_shot = -1
	_next_shot(true)
	show()


## Ends the tour (a skip or the last shot) and lets the run begin.
func finish() -> void:
	if prologue == null:
		return
	prologue.dispose()
	prologue = null
	hide()
	finished.emit()


func _gui_input(event: InputEvent) -> void:
	var mb := event as InputEventMouseButton
	if mb != null and mb.pressed:
		accept_event()
		finish()


func _next_shot(snap := false) -> void:
	_shot += 1
	if _shot >= shots.size():
		finish()
		return
	var shot: Dictionary = shots[_shot]
	_shot_left = float(shot.get("seconds", 5))
	_caption.text = shot.get("text", "")
	if shot["shot"] == "hero":
		_hero = pick_hero(prologue)
	if snap:
		var view := _view(shot["shot"])
		arena.pan = view[0]
		arena.zoom = view[1]


## Where a shot looks and how close: [pan, zoom].
func _view(shot: String) -> Array:
	var focus := Vector2.ZERO
	match shot:
		"hero":
			if _hero != null:
				focus = _hero.pos
		"den":
			focus = _den
	var reach: float = REACH.get(shot, prologue.content.num("world_radius") * 0.98)
	return [focus, arena.zoom_to_fit(reach, 0.9) if shot != "map" else arena.zoom_to_fit(reach, 1.0)]


func _process(delta: float) -> void:
	if prologue == null:
		return
	_acc += delta * SIM_SPEED
	var dt := prologue.world.dt
	var ticks := int(_acc / dt)
	_acc -= ticks * dt
	advance(prologue, ticks * dt + dt * 0.5)
	_shot_left -= delta
	if _shot_left <= 0.0:
		_next_shot()
		if prologue == null:
			return
	var view := _view(shots[_shot]["shot"])
	var k := 1.0 - exp(-EASE * delta)
	arena.pan = arena.pan.lerp(view[0], k)
	arena.zoom = exp(lerpf(log(arena.zoom), log(view[1]), k))
	queue_redraw()


func _draw() -> void:
	var bar := size.y * BAR
	draw_rect(Rect2(0, 0, size.x, bar), Color.BLACK)
	draw_rect(Rect2(0, size.y - bar, size.x, bar), Color.BLACK)
	_caption.position = Vector2(0, size.y - bar * 2.2)
	_caption.size = Vector2(size.x, bar * 1.1)
	_hint.position = Vector2(size.x - _hint.get_combined_minimum_size().x - 16.0, (bar - _hint.get_combined_minimum_size().y) * 0.5)
