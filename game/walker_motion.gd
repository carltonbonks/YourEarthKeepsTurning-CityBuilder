class_name WalkerMotion
extends RefCounted
## How a walker's sprite moves between the sim's steps (Yusuf, 2026-10-29, rendered art slice 2). The sim moves
## people ten times a second; this keeps a smoothed spot for each one so they glide, which way they face, whether
## they are walking (and how far, so the legs keep pace at any speed) or swinging a blow, and a short flash when
## they are hit. View only: it reads units and never changes them. ArenaView asks `look` once per drawn walker.

## How quickly the drawn spot catches up with the real one (ms to close most of the gap), and how far apart they
## may get before it jumps (a unit put somewhere new, not walking there).
const SMOOTH_MS := 60.0
const SNAP := 30.0
## World units walked per walk frame, so legs keep pace with the ground.
const STRIDE := 4.0
## A walker that stopped this long ago (ms) stands still.
const WALK_HOLD_MS := 220.0
## How long a blow's swing plays (ms of real time) and a hit's flash lasts.
const ATTACK_MS := 360.0
const HIT_MS := 140.0
## How far (world units) a walker goes before it turns to face its way.
const TURN_STEP := 0.8
## The flash: drawn this much brighter and redder, fading over HIT_MS.
const HIT_TINT := Color(2.2, 0.85, 0.8)

## Instance id -> what was seen of that walker last frame.
var _seen := {}


## Where to draw a walker whose real spot is `raw` and how: {"at": the smoothed spot, "facing": 0..facings-1,
## "walked": distance walked so far (for the walk frame), "walking", "attack": the swing's progress 0..1 or -1,
## "tint"}. At first it faces the hearth.
func look(u: Unit, raw: Vector2, facings: int, now: float) -> Dictionary:
	var key := u.get_instance_id()
	var v: Dictionary = _seen.get(key, {})
	if v.is_empty():
		v = {"at": raw, "raw": raw, "turn_from": raw, "facing": SpriteBook.facing_of(-raw, facings), "walked": 0.0,
			"moved": -INF, "cd": u.cooldown_left, "attack": -INF, "hp": u.hp, "hit": -INF, "t": now}
		if _seen.size() > 4000:
			_seen.clear()
		_seen[key] = v
	var dt := maxf(0.0, now - float(v["t"]))
	v["t"] = now
	var step := raw.distance_to(v["raw"])
	if step > 0.001:
		v["moved"] = now
		v["walked"] = float(v["walked"]) + minf(step, SNAP)
		v["raw"] = raw
	if raw.distance_to(v["turn_from"]) >= TURN_STEP:
		v["facing"] = SpriteBook.facing_of(raw - Vector2(v["turn_from"]), facings)
		v["turn_from"] = raw
	# A cooldown that went up means a blow was just struck; it faces whoever it hit.
	if u.cooldown_left > float(v["cd"]) + 0.001:
		v["attack"] = now
		if u.target != null and u.target.alive and u.target.pos != raw:
			v["facing"] = SpriteBook.facing_of(u.target.pos - raw, facings)
	v["cd"] = u.cooldown_left
	if u.hp < float(v["hp"]) - 0.001:
		v["hit"] = now
	v["hp"] = u.hp
	var at: Vector2 = v["at"]
	at = raw if at.distance_to(raw) > SNAP else at.lerp(raw, 1.0 - exp(-dt / SMOOTH_MS))
	v["at"] = at
	var swing := (now - float(v["attack"])) / ATTACK_MS
	var flash := clampf(1.0 - (now - float(v["hit"])) / HIT_MS, 0.0, 1.0)
	return {
		"at": at,
		"facing": v["facing"],
		"walked": v["walked"],
		"walking": now - float(v["moved"]) < WALK_HOLD_MS,
		"attack": swing if swing >= 0.0 and swing < 1.0 else -1.0,
		"tint": Color.WHITE.lerp(HIT_TINT, flash),
	}


## Where a walker was last drawn and which way it faced ({"at", "facing", ...}), or {} if it never was.
func last(u: Unit) -> Dictionary:
	return _seen.get(u.get_instance_id(), {})
