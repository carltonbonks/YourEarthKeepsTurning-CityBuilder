class_name Earth
extends RefCounted
## The shifting earth (`world.earth`), read as a dial (Yusuf, 2026-10-24). Past the still town the land is
## rings of earth plates, the cuts staggered ring to ring like bricks, and once between rounds the rings click
## round the hearth (`shift`, called by RunState as a new round begins): each ring turns a whole plate's width
## at its own pace and way, so the motion can be learned. The whole ring turns as one; plates keep their places.
## - The near ring's plates have kinds (Fen, Greenwood, Stonefield, Barrow): the ground the night's attack must
##   cross on its way in (`kind_at`, `crossing`). Each kind gives and takes: how fast people walk on it
##   (`walk_factor`), how far the hearth and towers see raiders on it (`sight_at`), plants regrowing (`dawn`),
##   raiders getting up again and heroes digging grave goods (World.damage).
## - The town can Feed the earth once a round (`feed`): the near ring turns one more plate now.
## - Each seam has a kind (subducting, colliding, a rift) and pressure marks. Each turn fills a few marks; a full
##   seam warns for a round (`doomed`, `full_seams`) and then wakes at the next turn: a trench swallows what sits
##   on its diving side, a colliding seam raises a ridge with a rich vein of rare stone, a rift grows a valley.
## Everything on a plate rides it: resource nodes, dens and the war camp, thickets, trails and roads, outposts
## and anyone standing out there. Numbers are in data/plates.json.

var w: World
var def: Dictionary
## Per ring: {name, r0, r1, step (radians a click turns it), click_every, seams: Array[float] (plate k runs from
## seams[k] to seams[k + 1]), kinds: per seam "subduct", "collide" or "rift" (rolled once per run), divers: per seam
## 0 when the plate behind dives, 1 the plate ahead, pressure: per seam its marks, ridges: per seam the turns its
## ridge still stands, upthrust: per seam the index of the node its ridge raised, or -1, plate_kinds: per plate its
## kind id from near_kinds (the near ring only; "" elsewhere)}.
var rings: Array[Dictionary] = []
## Shifts so far this run.
var shifts := 0
## Times the town fed the earth this run.
var fed := 0
## The round the town last fed the earth (once a round).
var fed_round := -1
## The geomancer's Hold: the near ring skips its next turn.
var hold_near := false
## What the last shift did (see RunRecord "shift"): {shift, swallowed, dens_swallowed, ridges, raised, grown,
## roads_refunded, woke (the kind of the first seam that woke, "" for none), woke_ring, wakes (how many woke),
## held (the near ring was held), finds (node type -> earth finds left)}. Empty before the first shift.
var last := {}
## Where the last shift did each thing, for the earth report and the map's pulses: {kind ("sank", "den_sank",
## "grew", "raised", "find"), type (node or den type), pos, worked (a node the town had gathered from), great (done by a
## seam that woke)}.
var events: Array[Dictionary] = []
## The first seam that woke in the last shift: {ring, seam, kind, angle}, or {} when none did; `woken` has them all.
var woke := {}
var woken: Array[Dictionary] = []
## Short ridges the geomancer raised in the near ring: {a (angle), r, length, lasts (turns of the earth left)}.
## They ride the near ring's plates and wear away.
var raised_ridges: Array[Dictionary] = []
## Goes up whenever the land changes outside a shift (a spell), so the map pulses the new events.
var changes := 0
## Goes up whenever the rings turn (a shift or a feeding), so the map slides the land into place.
var turned := 0
## What the last finished spell did: {grown, raised, dens_swallowed, finds} (see finish_spell).
var spell_done := {}
## The last turn's turn per ring and plate, in radians (for the map's slide).
var last_turns: Array = []
var _ridge_cells := PackedInt32Array()
## The full subducting seams (for doomed), and the [shifts, turned, changes] they were found for.
var _doomers: Array = []
var _doomers_for: Array = []
## The squares out on the plates (see _index_cells).
var _cells := PackedInt32Array()
var _cell_ring := PackedByteArray()
var _cell_r := PackedFloat32Array()
var _cell_a := PackedFloat32Array()
var _j_of := PackedInt32Array()  ## Square -> its place in _cells, or -1 on the still ground.
var _ring_angles: Array[PackedFloat32Array] = []  ## Per ring, its squares' angles in order (for arcs).
var _ring_js: Array[PackedInt32Array] = []  ## Per ring, the _cells places in that order.
## Each near kind's numbers with what relics, traditions and standing buildings add by its tags (plate_knobs),
## and what they were worked out from: [relic count, tradition count, World.building_plate_knobs].
var _kinds_now := {}
var _kinds_from := []


func _init(world: World) -> void:
	w = world
	def = w.content.plates
	var rng := SeededRng.stream(w.run.run_seed, "earth")
	var start := rng.randf() * TAU
	var kinds: Array = def["near_kinds"].keys()
	kinds.sort()
	var dealt: Array = []
	while not kinds.is_empty():
		var k: String = rng.pick(kinds)
		kinds.erase(k)
		dealt.append(k)
	for ri in def["rings"].size():
		var rd: Dictionary = def["rings"][ri]
		var n := int(rd["plates"])
		var width: float = TAU / n
		# Each ring starts half a plate on from the one inside it, so the cuts never line up (like bricks).
		var first: float = start + ri * width * 0.5
		var ring := {"name": rd["name"], "r0": float(rd["r0"]), "r1": float(rd["r1"]),
			"step": width * float(rd.get("dir", 1)), "click_every": maxi(1, int(rd.get("click_every", 1))),
			"seams": [], "kinds": [], "divers": [], "pressure": [], "ridges": [], "upthrust": [], "plate_kinds": []}
		var shares: Dictionary = def["seam_shares"].duplicate()
		if not _grows_rifts(ri):
			shares.erase("rift")
		for k in n:
			ring["seams"].append(first + k * width + rng.randf_range(-0.15, 0.15) * width)
			ring["kinds"].append(rng.weighted(shares))
			ring["divers"].append(rng.randi_range(0, 1))
			ring["pressure"].append(0)
			ring["ridges"].append(0)
			ring["upthrust"].append(-1)
			ring["plate_kinds"].append(dealt[k % dealt.size()] if ri == 0 else "")
		rings.append(ring)


func enabled() -> bool:
	return bool(def.get("enabled", true))


## True if a rift in ring ri has something to grow (the near ring by its plates' kinds).
func _grows_rifts(ri: int) -> bool:
	return ri == 0 or not def["rings"][ri]["rift_nodes"].is_empty()


# --- Where things are ----------------------------------------------------------

## The ring a point lies in, or -1 on the still ground (the eye) or past the map.
func ring_at(p: Vector2) -> int:
	var r := p.length()
	for ri in rings.size():
		if r >= float(rings[ri]["r0"]) and (r < float(rings[ri]["r1"]) or ri == rings.size() - 1):
			return ri
	return -1


## The plate of ring ri that angle a lies on.
func plate_at(ri: int, a: float, seams: Array = []) -> int:
	if seams.is_empty():
		seams = rings[ri]["seams"]
	for k in seams.size():
		if _in_span(a, seams[k], seams[(k + 1) % seams.size()]):
			return k
	return 0


static func _in_span(a: float, s0: float, s1: float) -> bool:
	return fposmod(a - s0, TAU) < fposmod(s1 - s0, TAU)


## The near plate's kind (an id from near_kinds) at angle a, as the land lies now.
func kind_at_angle(a: float) -> String:
	if rings.is_empty():
		return ""
	return rings[0]["plate_kinds"][plate_at(0, a)]


## The near plate's kind under p, or "" off the near ring.
func kind_at(p: Vector2) -> String:
	if not enabled() or ring_at(p) != 0:
		return ""
	return kind_at_angle(p.angle())


## The kind of near ground an attack from angle a crosses on its way in: now, or after `extra` more clicks of the
## near ring (a Feed shows what one more would do).
func crossing(a: float, extra := 0) -> String:
	if not enabled():
		return ""
	return kind_at_angle(a - extra * float(rings[0]["step"]))


## What a near kind's numbers are before anything adds to them (a kind leaves out the ones it doesn't change).
const KNOB_BASE := {"walk": 1.0, "raider_walk": 1.0, "sight": 1.0, "regrow": 0.0, "rise_chance": 0.0, "grave_goods": 0.0}


## A near kind's data (data/plates.json near_kinds), with its numbers as they stand now: plate_knobs
## ({tag: {knob: add}}) from owned relics, traditions and standing buildings add to every kind with that tag.
func kind_def(kind: String) -> Dictionary:
	var base: Dictionary = def["near_kinds"].get(kind, {})
	if base.is_empty():
		return base
	var from := [w.run.relics.size(), w.run.traditions.size(), w.building_plate_knobs]
	if _kinds_from.size() != 3 or _kinds_from[0] != from[0] or _kinds_from[1] != from[1] or not is_same(_kinds_from[2], from[2]):
		_kinds_now = {}
		_kinds_from = from
	if not _kinds_now.has(kind):
		var tags: Array = base.get("tags", [])
		var adds := w.run.tag_sums("plate_knobs", tags)
		for tag: String in w.building_plate_knobs:
			if tag in tags:
				for knob: String in w.building_plate_knobs[tag]:
					adds[knob] = float(adds.get(knob, 0.0)) + float(w.building_plate_knobs[tag][knob])
		var out := base.duplicate()
		for knob: String in adds:
			out[knob] = maxf(0.0, float(base.get(knob, KNOB_BASE.get(knob, 0.0))) + float(adds[knob]))
		_kinds_now[kind] = out
	return _kinds_now[kind]


## How fast someone walks at p for its near plate's kind (1 elsewhere): a Fen slows everyone, a Stonefield
## speeds raiders.
func walk_factor(p: Vector2, enemy: bool) -> float:
	var kind := kind_at(p)
	if kind == "":
		return 1.0
	var kd := kind_def(kind)
	return float(kd.get("walk", 1.0)) * (float(kd.get("raider_walk", 1.0)) if enemy else 1.0)


## How far the hearth and towers see a raider standing at p, against their range (1 off the near ring).
func sight_at(p: Vector2) -> float:
	var kind := kind_at(p)
	return float(kind_def(kind).get("sight", 1.0)) if kind != "" else 1.0


## How far plate k of ring ri turns on shift n, in radians: a whole plate's width on its ring's clicks, else none.
func turn_of(ri: int, _k: int, n: int) -> float:
	# Stillstone holds the near ring still, and so does the geomancer's Hold for a turn.
	if ri == 0 and (w.run.has_effect("still_ring") or hold_near):
		return 0.0
	var ring := rings[ri]
	return float(ring["step"]) if n % int(ring["click_every"]) == 0 else 0.0


# --- Seams and their pressure -------------------------------------------------------

## Every seam as it is now, for the map and hover: [{ring, seam, angle, kind, pressure, full}].
func seams() -> Array:
	var out: Array = []
	if not enabled():
		return out
	var full := int(def["pressure"]["full"])
	for ri in rings.size():
		for k in rings[ri]["seams"].size():
			var marks := int(rings[ri]["pressure"][k])
			out.append({"ring": ri, "seam": k, "angle": float(rings[ri]["seams"][k]), "kind": rings[ri]["kinds"][k],
				"pressure": marks, "full": marks >= full})
	return out


## The seams that wake at the next turn (full of pressure).
func full_seams() -> Array:
	return seams().filter(func(s: Dictionary) -> bool: return s["full"])


## The seam within reach world units of p, as a seams() entry, or {}.
func seam_near(p: Vector2, reach: float) -> Dictionary:
	var ri := ring_at(p)
	if ri < 0 or not enabled():
		return {}
	for entry: Dictionary in seams():
		if int(entry["ring"]) == ri and absf(angle_difference(float(entry["angle"]), p.angle())) * p.length() <= reach:
			return entry
	return {}


## True if a full seam's wake will swallow whatever stands at p at the next turn (it shows cracks). The rings
## turn as one, so where p sits against the seam now is where it will sit then.
func doomed(p: Vector2) -> bool:
	if not enabled():
		return false
	if _doomers_for != [shifts, turned, changes]:
		_doomers = full_seams().filter(func(s: Dictionary) -> bool: return s["kind"] == "subduct")
		_doomers_for = [shifts, turned, changes]
	for entry: Dictionary in _doomers:
		if _under_wake(p, entry):
			return true
	return false


## The seam with the most pressure (nearest ring first on a tie), as a seams() entry, or {} when none has any.
func fullest_seam() -> Dictionary:
	var best := {}
	for entry: Dictionary in seams():
		if int(entry["pressure"]) > int(best.get("pressure", 0)):
			best = entry
	return best


## How far plate land at p turns in the next shift (radians; 0 on the still ground).
func next_turn(p: Vector2) -> float:
	var ri := ring_at(p)
	if not enabled() or ri < 0:
		return 0.0
	return turn_of(ri, plate_at(ri, p.angle()), shifts + 1)


## How far the land at p turned in the last turn (radians), for the map's slide.
func last_turn(p: Vector2) -> float:
	var ri := ring_at(p)
	if ri < 0 or last_turns.is_empty():
		return 0.0
	return float(last_turns[ri])


## The squares the ridges hold right now (for drawing).
func ridge_cells() -> PackedInt32Array:
	return _ridge_cells


## True if square i is a ridge right now.
func is_ridge(i: int) -> bool:
	return _ridge_cells.has(i)


# --- The shift ---------------------------------------------------------------

## Turns the earth once. Called as a new round begins (never in the first round): the rings click, full seams
## wake, and fresh pressure fills a few seams.
func shift() -> void:
	if not enabled():
		return
	var n := shifts + 1
	var rng := SeededRng.stream(w.run.run_seed, "earth_shift", n)
	last = {"shift": n, "swallowed": {}, "dens_swallowed": 0, "ridges": 0, "raised": {}, "grown": {},
		"roads_refunded": 0, "woke": "", "woke_ring": -1, "wakes": 0, "held": hold_near, "finds": {}}
	events = []
	var turns: Array = []
	for ri in rings.size():
		turns.append(turn_of(ri, 0, n))
	hold_near = false
	var roads_before := _count_roads()
	_turn_rings(turns)
	for ridge in raised_ridges:
		ridge["lasts"] = int(ridge["lasts"]) - 1
	raised_ridges = raised_ridges.filter(func(r: Dictionary) -> bool: return int(r["lasts"]) > 0)
	_wear_ridges()
	_wake_full(rng)
	_add_pressure(rng)
	_settle(roads_before)
	shifts = n
	w.market.outposts_ridden()
	_tell()


## The town feeds the earth: pays the stone (RunState.feed_earth) and the near ring turns one more plate now.
func feed() -> void:
	if not enabled():
		return
	var turns: Array = []
	for ri in rings.size():
		turns.append(float(rings[0]["step"]) if ri == 0 else 0.0)
	var roads_before := _count_roads()
	events = []
	_turn_rings(turns)
	_settle(roads_before)
	fed += 1
	fed_round = w.run.round_number
	changes += 1


## What a feeding costs now: more each time.
func feed_cost() -> Dictionary:
	var fd: Dictionary = def["feed"]
	var stone := float(int(fd["cost"]) + int(fd["step"]) * fed)
	# A geomancer knows where the earth is hungriest.
	for type: String in w.content.buildings:
		if w.content.buildings[type].get("spells", false) and w.count_buildings(type) > 0:
			stone *= float(fd["geomancer_share"])
			break
	return {"stone": maxi(1, roundi(stone))}


## Turns each ring by its turn (radians): the ground, everything on it, its seams and the raised ridges ride.
func _turn_rings(turns: Array) -> void:
	var plans: Array = []
	for ri in rings.size():
		var t := float(turns[ri])
		plans.append({"turns": rings[ri]["seams"].map(func(_s: float) -> float: return t),
			"seams": rings[ri]["seams"].map(func(s: float) -> float: return s + t)})
	_clear_slow_ground()
	_move_ground(plans)
	_move_things(turns)
	for ri in rings.size():
		rings[ri]["seams"] = plans[ri]["seams"]
	for ridge in raised_ridges:
		ridge["a"] = float(ridge["a"]) + float(turns[0])
	last_turns = turns.duplicate()
	turned += 1


## After the land has moved: ground laid again, nothing left on a ridge, lost paving paid back.
func _settle(roads_before: Dictionary) -> void:
	_stamp_ground()
	_off_ridges()
	_refund_roads(roads_before)


## Trails, worn paths and roads out on the plates ride them square by square (each square looks back to
## where its ground came from); thickets are stamped again afterwards.
func _move_ground(plans: Array) -> void:
	var p := w.pathing
	_index_cells()
	var old := p.ground.duplicate()
	var old_traffic := p.traffic.duplicate()
	var dest := {}
	for j in _cells.size():
		var i := _cells[j]
		if old[i] < Pathing.TRAIL:
			continue
		var ri := _cell_ring[j]
		var t := float(plans[ri]["turns"][0])
		if t == 0.0:
			continue
		var c := p.cell_of(Vector2.from_angle(_cell_a[j] + t) * _cell_r[j])
		for dy in range(-1, 2):
			for dx in range(-1, 2):
				var cc := c + Vector2i(dx, dy)
				if cc.x >= 0 and cc.y >= 0 and cc.x < p.cells and cc.y < p.cells:
					dest[cc.y * p.cells + cc.x] = true
		p.set_ground(i, Pathing.PLAIN)
		p.traffic[i] = 0.0
	for i: int in dest:
		var j := _j_of[i]
		if j < 0:
			continue
		var ri := _cell_ring[j]
		var t := float(plans[ri]["turns"][0])
		if t == 0.0:
			continue
		var src := p.index_of(Vector2.from_angle(_cell_a[j] - t) * _cell_r[j])
		if old[src] >= Pathing.TRAIL and _j_of[src] >= 0 and _cell_ring[_j_of[src]] == ri:
			p.set_ground(i, old[src])
			p.traffic[i] = old_traffic[src]


## Every square out on the plates, once: its index, ring, distance from the hearth and angle, and per
## ring the squares in order of angle (so an arc's squares can be found quickly, see _arc).
func _index_cells() -> void:
	if not _cells.is_empty():
		return
	var p := w.pathing
	_j_of.resize(p.ground.size())
	_j_of.fill(-1)
	var per_ring: Array = []
	for ri in rings.size():
		per_ring.append([])
	for i in p.ground.size():
		var at := p.center(i)
		var ri := ring_at(at)
		if ri < 0 or at.length() > w.content.num("world_radius"):
			continue
		_j_of[i] = _cells.size()
		per_ring[ri].append([at.angle(), _cells.size()])
		_cells.append(i)
		_cell_ring.append(ri)
		_cell_r.append(at.length())
		_cell_a.append(at.angle())
	for ri in rings.size():
		var pairs: Array = per_ring[ri]
		pairs.sort_custom(func(x: Array, y: Array) -> bool: return x[0] < y[0])
		var angles := PackedFloat32Array()
		var js := PackedInt32Array()
		for pair: Array in pairs:
			angles.append(pair[0])
			js.append(pair[1])
		_ring_angles.append(angles)
		_ring_js.append(js)


## The _cells places of ring ri's squares from angle a0 clockwise to a1.
func _arc(ri: int, a0: float, a1: float) -> PackedInt32Array:
	var out := PackedInt32Array()
	var angles := _ring_angles[ri]
	var js := _ring_js[ri]
	var from := wrapf(a0, -PI, PI)
	var to := from + fposmod(a1 - a0, TAU)
	var spans := [[from, minf(to, PI)]]
	if to > PI:
		spans.append([-PI, to - TAU])
	for span: Array in spans:
		var lo := angles.bsearch(span[0])
		var hi := angles.bsearch(span[1], false)
		for n in range(lo, hi):
			out.append(js[n])
	return out


## The squares near a seam at angle a in ring ri, within half world units of it at their distance.
func _near_seam(ri: int, a: float, half: float) -> PackedInt32Array:
	var spread := half / float(rings[ri]["r0"]) + 0.02
	return _arc(ri, a - spread, a + spread)


## Before a turn: thickets and ridges come up (they are laid again where they end up).
func _clear_slow_ground() -> void:
	var p := w.pathing
	_index_cells()
	for i in _ridge_cells:
		p.set_solid(i, false)
	_ridge_cells = PackedInt32Array()
	for thicket in w.town.thickets:
		for i in p.cells_in_circle(thicket["pos"], float(thicket["radius"])):
			if p.ground[i] == Pathing.THICKET:
				p.set_ground(i, Pathing.PLAIN)


## Where a point goes when the rings turn by `turns` (radians per ring). Points on the still ground stay.
func _carried(p: Vector2, turns: Array) -> Vector2:
	var ri := ring_at(p)
	return p if ri < 0 else p.rotated(float(turns[ri]))


func _move_things(turns: Array) -> void:
	for node in w.nodes:
		if not node.get("gone", false):
			node["pos"] = _carried(node["pos"], turns)
	for den in w.dens:
		var to := _carried(den["pos"], turns)
		den["turned"] = rad_to_deg(angle_difference(Vector2(den["pos"]).angle(), to.angle()))
		den["pos"] = to
	for thicket in w.town.thickets:
		thicket["pos"] = _carried(thicket["pos"], turns)
	for u: Unit in w.folk + w.run.heroes + w.enemies:
		if not u.alive:
			continue
		u.pos = _carried(u.pos, turns)
		u.wander_goal = _carried(u.wander_goal, turns)
		u.path_version = -1
		u.path = PackedVector2Array()


## Each turn a ridge wears one turn closer to gone.
func _wear_ridges() -> void:
	for ring in rings:
		for k in ring["ridges"].size():
			ring["ridges"][k] = maxi(0, int(ring["ridges"][k]) - 1)


## Every full seam wakes and empties.
func _wake_full(rng: SeededRng) -> void:
	woke = {}
	woken = []
	var full := int(def["pressure"]["full"])
	for ri in rings.size():
		for k in rings[ri]["seams"].size():
			if int(rings[ri]["pressure"][k]) < full:
				continue
			_wake(ri, k, rng)
			rings[ri]["pressure"][k] = 0


## Fresh pressure: per_turn marks, each on a seam picked by weight (its ring's wake_weight and its kind's weight),
## never one already full or one that has just woken. Ridgeheart fills colliding seams twice as fast, Rift Seed rifts,
## and a Wellspring (data/card_mods.json) draws the waking to the ring nearest the town.
func _add_pressure(rng: SeededRng) -> void:
	var pd: Dictionary = def["pressure"]
	var full := int(pd["full"])
	var just_woke := {}
	for entry in woken:
		just_woke["%d:%d" % [entry["ring"], entry["seam"]]] = true
	for mark in int(pd["per_turn"]):
		var weights := {}
		for ri in rings.size():
			var rd: Dictionary = def["rings"][ri]
			for k in rings[ri]["seams"].size():
				var key := "%d:%d" % [ri, k]
				if int(rings[ri]["pressure"][k]) >= full or just_woke.has(key):
					continue
				var kind: String = rings[ri]["kinds"][k]
				var weight := float(rd.get("wake_weight", 1.0)) * float(pd["weights"][kind])
				if kind == "collide" and w.run.has_effect("collide_pressure"):
					weight *= 2.0
				if kind == "rift" and w.run.has_effect("rift_pressure"):
					weight *= 2.0
				if ri == 0:
					weight *= 1.0 + w.run.mod("near_wake")
				# Keys sort as text, so pad them for a stable order past ten seams.
				weights["%02d:%02d" % [ri, k]] = weight
		var pick := rng.weighted(weights)
		if pick == "":
			return
		var ri := int(pick.get_slice(":", 0))
		var k := int(pick.get_slice(":", 1))
		rings[ri]["pressure"][k] = int(rings[ri]["pressure"][k]) + 1


## Seam k of ring ri wakes and does something big: a subducting seam swallows everything on its diving side within
## swallow_band of it, a colliding one raises a ridge and breaks open a rich upthrust node, a rift opens a valley of
## fresh nodes. Returns a line for the story.
func _wake(ri: int, k: int, rng: SeededRng) -> String:
	var wd: Dictionary = def["wake"]
	var ring := rings[ri]
	var a := float(ring["seams"][k])
	var kind: String = ring["kinds"][k]
	var entry := {"ring": ri, "seam": k, "kind": kind, "angle": a}
	woken.append(entry)
	if woke.is_empty():
		woke = entry
		last["woke"] = kind
		last["woke_ring"] = ri
	last["wakes"] = int(last.get("wakes", 0)) + 1
	var where := World.compass(a)
	match kind:
		"subduct":
			for node in w.nodes:
				if not node.get("gone", false) and _under_wake(node["pos"], entry):
					_swallow_node(node, true)
			# The ground on the lip goes under too: trails, worn paths and paving (paid back by _settle).
			_index_cells()
			var band := float(def["wake"]["swallow_band"])
			for j in _near_seam(ri, a, band):
				var i := _cells[j]
				if w.pathing.ground[i] >= Pathing.TRAIL and _under_wake(w.pathing.center(i), entry):
					w.pathing.set_ground(i, Pathing.PLAIN)
					w.pathing.traffic[i] = 0.0
			for di in range(w.dens.size() - 1, -1, -1):
				if _under_wake(w.dens[di]["pos"], entry):
					_swallow_den(di, true)
			return "a seam to the %s swallows its lip" % where
		"collide":
			ring["ridges"][k] = int(def["ridge_turns"]) + int(w.run.mod("ridge_longer"))
			last["ridges"] = int(last.get("ridges", 0)) + 1
			var type: String = def["upthrust"].get(w.run.age, "")
			var r := (float(ring["r0"]) + float(ring["r1"])) / 2.0
			var side := 1.0 if rng.randf() < 0.5 else -1.0
			if type != "":
				ring["upthrust"][k] = _raise(type, Vector2.from_angle(a + side * _margin(r)) * r, float(wd["rich"]), true)
			# Starstone comes up with it, on the other side of the seam.
			_leave_find("starstone", Vector2.from_angle(a - side * _margin(r)) * r, true)
			return "a ridge heaves up to the %s and breaks open rare stone" % where
		_:
			var count := int(wd["rift_nodes"]) + int(w.run.mod("rift_more"))
			var spread := 90.0 / maxf(float(ring["r0"]), 1.0)
			for i in count:
				var at := a + (i - (count - 1) / 2.0) * spread
				var types := _grows_at(ri, at)
				if types.is_empty():
					continue
				var r := rng.randf_range(float(ring["r0"]) + 20.0, float(ring["r1"]) - 20.0)
				_grow(rng.pick(types), Vector2.from_angle(at) * r, float(wd["rift_share"]), true)
			return "the ground splits open to the %s into a green valley" % where


## What fresh ground grows at angle a in ring ri: the near plate's kind's, else the ring's rift_nodes.
func _grows_at(ri: int, a: float) -> Array:
	if ri == 0:
		return kind_def(kind_at_angle(a)).get("grows", [])
	return def["rings"][ri]["rift_nodes"]


## True if p goes under a waking subducting seam (a seams() entry): on its diving side, within swallow_band
## of it. The plate behind a seam lies at smaller angles; diver 0 is that one.
func _under_wake(p: Vector2, entry: Dictionary) -> bool:
	if entry.is_empty() or entry["kind"] != "subduct" or ring_at(p) != int(entry["ring"]):
		return false
	var side := -1.0 if int(rings[int(entry["ring"])]["divers"][int(entry["seam"])]) == 0 else 1.0
	var off := angle_difference(float(entry["angle"]), p.angle())
	return signf(off) == side and absf(off) * p.length() <= float(def["wake"]["swallow_band"])


## How far (radians) things are kept off a seam at radius r, clear of any ridge on it.
func _margin(r: float) -> float:
	return (float(def["ridge_half_width"]) + 8.0) / maxf(r, 1.0)


# --- Each dawn ----------------------------------------------------------------------

## Plants on a near plate whose kind regrows them (the Greenwood) regrow a share of their full size.
func dawn() -> void:
	if not enabled():
		return
	for node in w.nodes:
		if node.get("gone", false) or not w.regrows(node) or not w.content.has_tag("node", node["type"], "plant"):
			continue
		var share := float(kind_def(kind_at(node["pos"])).get("regrow", 0.0))
		if share > 0.0:
			node["amount"] = mini(int(node["max"]), int(node["amount"]) + maxi(1, roundi(int(node["max"]) * share)))


func _swallow_node(node: Dictionary, great := false) -> void:
	# An earth find nobody dug out goes back under.
	if w.content.world["nodes"][node["type"]].get("find", false):
		_remove_node(node)
		return
	var embers: String = def["embers"]
	last["swallowed"][node["type"]] = int(last["swallowed"].get(node["type"], 0)) + 1
	events.append({"kind": "sank", "type": node["type"], "pos": node["pos"],
		"worked": int(node["amount"]) < int(node["max"]), "great": great})
	_feed_the_deep(int(w.run.mod("swallow_node_shells")), false)
	if node["type"] == embers:
		_remove_node(node)
		return
	var e: Dictionary = w.content.world["nodes"][embers]
	node["type"] = embers
	node["gives"] = e["gives"]
	node["amount"] = int(e["amount"])
	node["max"] = int(e["amount"])
	node["heroes_only"] = false
	node["wild"] = false
	node["age"] = ""


## Takes a node off the map. It keeps its place in World.nodes (townsfolk and heroes hold node indices).
func _remove_node(node: Dictionary) -> void:
	node["gone"] = true
	node["amount"] = 0
	node["max"] = 0


## A den goes under: its wanderers with it, and the dens after it move up one place.
func _swallow_den(di: int, great := false) -> void:
	last["dens_swallowed"] = int(last["dens_swallowed"]) + 1
	events.append({"kind": "den_sank", "type": w.dens[di]["type"], "pos": w.dens[di]["pos"], "worked": false, "great": great})
	# What the den held stays where it went under, for a hero to dig out.
	_leave_find("hoard", w.dens[di]["pos"], great)
	_feed_the_deep(int(w.run.mod("swallow_den_shells")), w.run.has_effect("swallow_item"))
	if w.dens[di].get("camp", false):
		# The war camp's raiders go down with it, and so do the spoils heroes would have won clearing it.
		last["camp_swallowed"] = true
		w.run.tell("The earth swallows the war camp, raiders, spoils and all.")
	else:
		w.run.tell("The earth swallows the %s, and everything in it." % w.content.world["dens"][w.dens[di]["type"]]["name"].to_lower())
	for e in w.enemies:
		if e.den_index == di:
			e.alive = false
		elif e.den_index > di:
			e.den_index -= 1
	w.dens.remove_at(di)


## Hungry Deep Idol: the town is paid for what the earth takes, and a den gives up an item to a hero.
func _feed_the_deep(shells: int, item: bool) -> void:
	if shells <= 0:
		return
	w.run.stock["shells"] = int(w.run.stock["shells"]) + shells
	w.run.relic_fired("swallow_shells", shells)
	var heroes := w.run.living_heroes()
	if item and not heroes.is_empty():
		var rng := SeededRng.stream(w.run.run_seed, "deep_gift", shifts)
		w.hero_ai.give_item(rng.pick(heroes), Loot.roll(w.content, rng, w.run.round_number, w.run.age))


# --- The geomancer's spells (data/plates.json spells; cast through RunState.cast_spell) ----------

## A spell finishes: does what it does to the land now. Returns a line for the story. What it did is in
## spell_done ({grown, raised, dens_swallowed, finds}) and events; the last shift's report is left as it was.
func finish_spell(id: String, rng: SeededRng, extra_lasts := 0) -> String:
	var shift_report := last
	var shift_woke := woke
	var shift_woken := woken
	last = {"swallowed": {}, "dens_swallowed": 0, "raised": {}, "grown": {}, "finds": {}, "ridges": 0, "wakes": 0}
	woke = {}
	woken = []
	events = []
	var line := ""
	match id:
		"hold":
			hold_near = true
			line = "the near ring will hold still at the next turn of the earth"
		"wake":
			line = _wake_fullest(rng)
		"ridge":
			line = _raise_near_ridge(rng, extra_lasts)
		"sink_den":
			line = _sink_a_den()
	spell_done = last
	last = shift_report
	woke = shift_woke
	woken = shift_woken
	changes += 1
	return line


## The seam with the most pressure wakes now and empties.
func _wake_fullest(rng: SeededRng) -> String:
	var entry := fullest_seam()
	if entry.is_empty():
		return "the earth stirs, but no seam has any pressure to give"
	var ri := int(entry["ring"])
	var k := int(entry["seam"])
	var roads_before := _count_roads()
	_clear_slow_ground()
	var line := _wake(ri, k, rng)
	rings[ri]["pressure"][k] = 0
	_settle(roads_before)
	return line


## A short ridge just past the town, facing this round's first warned side, with stone and plants sprouting
## on the town's side of it.
func _raise_near_ridge(rng: SeededRng, extra_lasts := 0) -> String:
	var sd: Dictionary = def["spells"]["ridge"]
	var a: float = w.wave_sides[0] if not w.wave_sides.is_empty() else rng.randf() * TAU
	var r := float(sd["r"])
	raised_ridges.append({"a": a, "r": r, "length": float(sd["length"]), "lasts": int(sd["lasts"]) + extra_lasts})
	_index_cells()
	_stamp_raised_ridges()
	_off_ridges()
	var sprouts: Array = sd["sprouts"]
	for i in sprouts.size():
		var at := a + (i - (sprouts.size() - 1) / 2.0) * float(sd["length"]) / 2.0 / r
		_grow(sprouts[i], Vector2.from_angle(at) * (r - float(sd["half_width"]) - 22.0), 1.0, true)
	return "a ridge rises to the %s, across the raiders' way" % World.compass(a)


## The earth swallows a den: the one the warned attack comes by, else the nearest. Its hoard stays for heroes.
func _sink_a_den() -> String:
	var target := -1
	for di in w.dens.size():
		if w.dens[di].get("camp", false):
			continue
		if not w.wave_side_dens.is_empty() and w.dens[di]["type"] == w.wave_side_dens[0]:
			target = di
			break
		if target < 0 or Vector2(w.dens[di]["pos"]).length() < Vector2(w.dens[target]["pos"]).length():
			target = di
	if target < 0:
		return "the earth trembles, but no den is left to swallow"
	var name: String = w.content.world["dens"][w.dens[target]["type"]]["name"].to_lower()
	_swallow_den(target, true)
	return "the earth opens under the %s" % name


## An earth find (data/plates.json finds) that heroes dig out for an item.
func _leave_find(kind: String, at: Vector2, great: bool) -> void:
	var type: String = def["finds"][kind]
	events.append({"kind": "find", "type": type, "pos": at, "worked": false, "great": great})
	var finds: Dictionary = last.get_or_add("finds", {})
	finds[type] = int(finds.get(type, 0)) + 1
	_add(type, at, 1.0)


## A fresh node in a valley.
func _grow(type: String, at: Vector2, share: float, great: bool) -> int:
	last["grown"][type] = int(last["grown"].get(type, 0)) + 1
	events.append({"kind": "grew", "type": type, "pos": at, "worked": false, "great": great})
	return _add(type, at, share)


## An upthrust node beside a ridge.
func _raise(type: String, at: Vector2, share: float, great: bool) -> int:
	last["raised"][type] = int(last["raised"].get(type, 0)) + 1
	events.append({"kind": "raised", "type": type, "pos": at, "worked": false, "great": great})
	return _add(type, at, share)


## share = how full it starts against the type's usual amount; above 1 it is a rich node that holds more.
func _add(type: String, at: Vector2, share: float) -> int:
	var ndef: Dictionary = w.content.world["nodes"][type]
	var amount := maxi(1, roundi(int(ndef["amount"]) * share))
	w.nodes.append({"type": type, "gives": ndef["gives"], "pos": at,
		"amount": amount, "max": maxi(amount, int(ndef["amount"])),
		"heroes_only": ndef.get("heroes_only", false), "wild": ndef.get("wild", false), "age": ndef.get("age", "")})
	return w.nodes.size() - 1


## Thickets slow walkers; ridges are solid. Laid fresh after every turn.
func _stamp_ground() -> void:
	var p := w.pathing
	_index_cells()
	for thicket in w.town.thickets:
		for i in p.cells_in_circle(thicket["pos"], float(thicket["radius"])):
			if p.ground[i] < Pathing.TRAIL:
				p.set_ground(i, Pathing.THICKET)
	var half := float(def["ridge_half_width"])
	var pass_half := float(def["pass_width"]) / 2.0
	for ri in rings.size():
		var ring := rings[ri]
		var mid := (float(ring["r0"]) + float(ring["r1"])) / 2.0
		for k in ring["seams"].size():
			if int(ring["ridges"][k]) <= 0:
				continue
			var a := float(ring["seams"][k])
			for j in _near_seam(ri, a, half):
				var r := _cell_r[j]
				if r < float(ring["r0"]) + 10.0 or r > float(ring["r1"]) - 10.0 or absf(r - mid) < pass_half:
					continue
				if absf(angle_difference(a, _cell_a[j])) * r <= half:
					_ridge_cells.append(_cells[j])
					p.set_solid(_cells[j], true)
	_stamp_raised_ridges()


## The geomancer's ridges are stamped too: solid squares along an arc of the near ring.
func _stamp_raised_ridges() -> void:
	var half := float(def["spells"]["ridge"]["half_width"])
	for ridge in raised_ridges:
		var r := float(ridge["r"])
		var spread := float(ridge["length"]) / 2.0 / r
		for j in _arc(0, float(ridge["a"]) - spread, float(ridge["a"]) + spread):
			if absf(_cell_r[j] - r) <= half:
				_ridge_cells.append(_cells[j])
				w.pathing.set_solid(_cells[j], true)


## Nothing is left standing on a ridge: it steps off to the side of the seam it was on.
func _off_ridges() -> void:
	var things: Array = []
	for node in w.nodes:
		things.append(node)
	for den in w.dens:
		things.append(den)
	for thing: Dictionary in things:
		thing["pos"] = _off_ridge(thing["pos"])
	for u: Unit in w.folk + w.run.heroes + w.enemies:
		if u.alive:
			u.pos = _off_ridge(u.pos)


func _off_ridge(p: Vector2) -> Vector2:
	var ri := ring_at(p)
	if ri < 0:
		return p
	var ring := rings[ri]
	var r := p.length()
	for k in ring["seams"].size():
		if int(ring["ridges"][k]) <= 0:
			continue
		var off := angle_difference(float(ring["seams"][k]), p.angle())
		if absf(off) * r <= float(def["ridge_half_width"]) + 6.0:
			return Vector2.from_angle(float(ring["seams"][k]) + signf(off if off != 0.0 else 1.0) * _margin(r)) * r
	# Off a geomancer's ridge: step to whichever face is nearer.
	var half := float(def["spells"]["ridge"]["half_width"]) + 6.0
	for ridge in raised_ridges:
		var rr := float(ridge["r"])
		if absf(r - rr) <= half and absf(angle_difference(float(ridge["a"]), p.angle())) * rr <= float(ridge["length"]) / 2.0 + 6.0:
			return p.normalized() * (rr - half if r < rr else rr + half)
	return p


func _count_roads() -> Dictionary:
	_index_cells()
	var out := {}
	var ground := w.pathing.ground
	for i in _cells:
		if ground[i] >= Pathing.FIRST_ROAD:
			out[ground[i]] = int(out.get(ground[i], 0)) + 1
	return out


## Paving the earth swallowed is paid back, as when a building is put up over a road.
func _refund_roads(before: Dictionary) -> void:
	var after := _count_roads()
	var lost := {}
	for kind: int in before:
		var gone := int(before[kind]) - int(after.get(kind, 0))
		if gone > 0:
			lost[kind] = gone
			last["roads_refunded"] = int(last.get("roads_refunded", 0)) + gone
	w.town.refund_roads(lost)


func _tell() -> void:
	var parts: Array[String] = []
	var swallowed := 0
	for t: String in last["swallowed"]:
		swallowed += int(last["swallowed"][t])
	if swallowed > 0:
		parts.append("%d resource%s sink%s at a waking seam" % [swallowed, "" if swallowed == 1 else "s", "s" if swallowed == 1 else ""])
	if int(last["ridges"]) > 0:
		parts.append("a ridge heaves up where plates collide")
	var grown := 0
	for t: String in last["grown"]:
		grown += int(last["grown"][t])
	if grown > 0:
		parts.append("%d fresh patch%s grow%s in a valley" % [grown, "" if grown == 1 else "es", "s" if grown == 1 else ""])
	for t: String in last["raised"]:
		parts.append("a ridge breaks open: %s" % w.content.world["nodes"][t]["name"].to_lower())
	if bool(last.get("held", false)):
		parts.append("the near ring holds still")
	var line := "The earth turns."
	if not parts.is_empty():
		line = "The earth turns: %s." % "; ".join(parts)
	w.run.tell(line)
