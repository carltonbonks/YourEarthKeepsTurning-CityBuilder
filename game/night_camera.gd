class_name NightCamera
extends RefCounted
## Brings each night's fighting close. Over the last seconds of the day the map eases in on the town
## until it fills most of the view, and once the night is over it eases back to wherever the player
## had it. On the attack's night the view also takes in the way the attack comes, out to where bold
## heroes meet it in pitched battle (Yusuf, 2026-10-25: the old close-up missed that fight). View only, like ArenaView: it reads the clock and the town, never the rules.
## The player can take the camera back at any time (wheel, drag, or clicking a hero); it then stays
## where they put it until the next night. It never changes the game's speed (Yusuf, 2026-10-21).

## How long before nightfall the zoom starts, in game seconds (it follows game time, so a pause pauses it).
const LEAD_SECONDS := 8.0
## How long the way back takes once the night is over, in real seconds.
const RETURN_SECONDS := 1.4
## How much of the view the town fills at the closest point.
const FILL := 0.9
## Room left round the outermost building, so raiders at the walls are in view, in world units.
const MARGIN := 70.0
## How much wider than the town's reach the view stays, so fights just outside the walls are in it.
const LOOSE := 1.2
## Room round the spot where heroes meet the attack (meet_attack_at), in world units.
const FIGHT_MARGIN := 60.0

## 0 is the player's camera, 1 is closed in on the town.
var weight := 0.0
var _active := false
var _released := false
var _from_zoom := 1.0
var _from_pan := Vector2.ZERO


## How close the night is: 0 by day, rising over the day's last LEAD_SECONDS, 1 from nightfall until
## the round's next decision (a wave night runs on until the last raider is gone).
static func approach(run: RunState) -> float:
	if run == null or run.phase != RunState.Phase.SIM:
		return 0.0
	var day := run.content.num("day_seconds")
	return clampf((run.world.time_of_day() - (day - LEAD_SECONDS)) / LEAD_SECONDS, 0.0, 1.0)


## How far from the hearth the town reaches: its outermost building, plus room for the fight at its walls.
static func town_radius(run: RunState) -> float:
	var far := float(run.content.town["rings"][0]["radius"])
	for b: Dictionary in run.world.buildings:
		far = maxf(far, Vector2(b["pos"]).length())
	return far + float(run.content.town["ring_depth"]) / 2.0 + MARGIN


## What the camera frames at night: [centre, radius] of a circle on the ground. Usually the town with a
## little room; on the attack's day the circle stretches out the way it comes in (one way: the view slides
## toward it; several: it widens round the hearth).
static func frame(run: RunState) -> Array:
	var town := town_radius(run) * LOOSE
	var w := run.world
	if w.wave_sides.is_empty() or w.day_index() != run.content.int_num("days_per_round") - 1:
		return [Vector2.ZERO, town]
	var far := run.content.num("meet_attack_at") + FIGHT_MARGIN
	if far <= town:
		return [Vector2.ZERO, town]
	if w.wave_sides.size() > 1:
		return [Vector2.ZERO, far]
	# The smallest circle holding both the town and the fight on its one way in.
	return [Vector2.from_angle(w.wave_sides[0]) * (far - town) / 2.0, (far + town) / 2.0]


## The player moved the camera: leave it where they put it until the next night.
func release() -> void:
	_released = true


## Moves the view's camera for this frame; ArenaView calls it every frame.
func update(view: ArenaView, delta: float) -> void:
	var target := approach(view.run)
	if target > 0.0 and not _active:
		_active = true
		_released = false
		_from_zoom = view.zoom
		_from_pan = view.pan
	if not _active:
		return
	# In with the game clock, back out in real time (the sim is stopped on the dawn pick by then).
	weight = target if target >= weight else move_toward(weight, target, delta / RETURN_SECONDS)
	if not _released:
		var t := smoothstep(0.0, 1.0, weight)
		var aim := frame(view.run)
		var close := maxf(_from_zoom, view.zoom_to_fit(aim[1], FILL))
		view.zoom = lerpf(_from_zoom, close, t)
		view.pan = _from_pan.lerp(aim[0], t)
	if weight <= 0.0:
		_active = false
