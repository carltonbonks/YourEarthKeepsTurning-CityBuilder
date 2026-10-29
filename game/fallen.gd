class_name Fallen
extends RefCounted
## Where walkers fell (Yusuf, 2026-10-29, rendered art slice 5): a townsperson, hero or raider killed in a fight
## plays its fall frames where it last stood, lies there a while and fades. A fallen hero lies longer, and a ring in
## the class's colour spreads round them as they fall, so the loss gets a beat of its own. Raiders who slip away
## at the night's end and people who leave town don't fall. View only: it watches units and never changes them.
## Timings are in real milliseconds, so a fall reads the same at 8x speed.

const FALL_MS := 420.0
## How long a body lies before it starts to fade, and how long the fade takes.
const LIE_MS := 7000.0
const HERO_LIE_MS := 16000.0
const FADE_MS := 1500.0
## A hero's ring: how long it spreads and how far, in the hero's own radii.
const RING_MS := 1100.0
const RING_GROW := 4.0
## Old bodies go first past this many.
const MAX_BODIES := 150

## Each body: {"id": sprite id, "at": world spot, "facing", "born": ms, "hero", "enemy", "boss": bools}.
var bodies: Array = []
## Walkers with art alive last frame, by instance id, to notice who fell.
var _live := {}
var _world: World = null


## Call once a frame, before drawing: notices who fell since last frame and drops bodies that have faded.
## `has_art(id)` says whether an id is drawn as a sprite; `motion` gives the spot and facing it was last drawn at.
func update(w: World, heroes: Array, motion: WalkerMotion, has_art: Callable, now: float) -> void:
	if w != _world:
		_world = w
		_live.clear()
		bodies.clear()
	for u: Unit in _live.values():
		if u.alive:
			continue
		# Only a death in a fight leaves a body (hp at 0); raiders who slip away keep theirs.
		if u.hp > 0.0:
			continue
		var seen := motion.last(u)
		bodies.append({"id": u.type_id, "at": seen.get("at", u.pos), "facing": int(seen.get("facing", 0)), "born": now,
			"hero": u.is_hero(), "enemy": u.is_enemy(), "boss": u.is_boss})
	# Seen afresh each frame, so people who left town are forgotten.
	_live = {}
	for u in w.folk:
		_watch(u, has_art)
	for e in w.enemies:
		if e.spawned:
			_watch(e, has_art)
	for h: Unit in heroes:
		_watch(h, has_art)
	bodies = bodies.filter(func(b: Dictionary) -> bool: return now - float(b["born"]) < _life(b))
	if bodies.size() > MAX_BODIES:
		bodies = bodies.slice(bodies.size() - MAX_BODIES)


func _watch(u: Unit, has_art: Callable) -> void:
	if u.alive and has_art.call(u.type_id):
		_live[u.get_instance_id()] = u


func _life(b: Dictionary) -> float:
	return (HERO_LIE_MS if b["hero"] else LIE_MS) + FADE_MS


## Which fall frame a body shows (0 .. frames-1): it plays through once, then lies on the last.
func frame(b: Dictionary, frames: int, now: float) -> int:
	return mini(frames - 1, int((now - float(b["born"])) / FALL_MS * frames))


## How much of a body is left to see: 1 while it lies, down to 0 as it fades.
func opacity(b: Dictionary, now: float) -> float:
	var lie := HERO_LIE_MS if b["hero"] else LIE_MS
	return clampf(1.0 - (now - float(b["born"]) - lie) / FADE_MS, 0.0, 1.0)


## A fallen hero's ring: how far it has spread (in the hero's radii) and how strong it still is, or [] once gone.
func ring(b: Dictionary, now: float) -> Array:
	var t := (now - float(b["born"])) / RING_MS
	if not b["hero"] or t < 0.0 or t >= 1.0:
		return []
	return [1.0 + RING_GROW * t, 1.0 - t]
