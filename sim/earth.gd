class_name Earth
extends RefCounted
## The shifting earth (`world.earth`). Past the still town the land is rings of earth plates, the cuts
## staggered ring to ring like bricks, and once between rounds every ring turns round the hearth
## (`shift`, called by RunState as a new round begins). Each plate also sways a little faster or slower
## than its ring, so the seams between plates close and open:
## - a closing seam that subducts swallows what sits on the diving plate's edge (nodes turn to embers,
##   dens go under with their monsters, paving is refunded);
## - a closing seam that collides pushes everything to the seam and raises a ridge (solid, with a pass)
##   that grows each colliding shift and in time raises an upthrust node;
## - an opening seam is a rift: raw, slow ground until the next shift, often with a fresh node.
## Everything on a plate rides it: resource nodes, dens and the war camp, thickets, trails and roads,
## and anyone standing out there. The next shift can be worked out in advance (`forecast`, `doomed`) for
## tests and for later buildings, relics and heroes that read the earth; the map doesn't show it. Numbers are in data/plates.json.

var w: World
var def: Dictionary
## Per ring: {name, r0, r1, turn, sway (radians), seams: Array[float] (plate k runs from seams[k] to
## seams[k + 1]; seam k sits between plate k - 1 behind it and plate k ahead), kinds: per seam "subduct"
## or "collide" (rolled once per run), divers: per seam 0 when the plate behind dives, 1 the plate ahead,
## periods / phases: each plate's sway wave, ridges: per seam the ridge's height, upthrust: per seam the
## index of the node its ridge raised, or -1}.
var rings: Array[Dictionary] = []
## Shifts so far this run.
var shifts := 0
## Rift strips that stay raw ground until the next shift: {ring, a0, a1} (radians, a0 to a1 clockwise).
var raw: Array[Dictionary] = []
## What the last shift did (see RunRecord "shift"): {shift, swallowed, dens_swallowed, ridges, raised,
## rifts, grown, roads_refunded, woke (the kind of seam that woke, "" for none), woke_ring}. Empty before the first shift.
var last := {}
## Where the last shift did each thing, for the earth report and the map's pulses: {kind ("sank", "den_sank",
## "grew", "raised"), type (node or den type), pos, worked (a node the town had gathered from), great (done by the
## seam that woke)}.
var events: Array[Dictionary] = []
## The seam that woke in the last shift: {ring, seam, kind, angle}, or {} when none did.
var woke := {}
## The last shift's turn per ring and plate, in radians (for the map's slide).
var last_turns: Array = []
var _ridge_cells := PackedInt32Array()
## The squares out on the plates (see _index_cells).
var _cells := PackedInt32Array()
var _cell_ring := PackedByteArray()
var _cell_r := PackedFloat32Array()
var _cell_a := PackedFloat32Array()
var _j_of := PackedInt32Array()  ## Square -> its place in _cells, or -1 on the still ground.
var _ring_angles: Array[PackedFloat32Array] = []  ## Per ring, its squares' angles in order (for arcs).
var _ring_js: Array[PackedInt32Array] = []  ## Per ring, the _cells places in that order.
var _plan_cache := {}
var _plan_for := -1


func _init(world: World) -> void:
	w = world
	def = w.content.plates
	var rng := SeededRng.stream(w.run.run_seed, "earth")
	var start := rng.randf() * TAU
	for ri in def["rings"].size():
		var rd: Dictionary = def["rings"][ri]
		var n := int(rd["plates"])
		var width: float = TAU / n
		# Each ring starts half a plate on from the one inside it, so the cuts never line up (like bricks).
		var first: float = start + ri * width * 0.5
		var ring := {"name": rd["name"], "r0": float(rd["r0"]), "r1": float(rd["r1"]),
			"turn": deg_to_rad(float(rd["turn"])), "sway": deg_to_rad(float(rd["sway"])),
			"seams": [], "kinds": [], "divers": [], "periods": [], "phases": [], "ridges": [], "upthrust": []}
		for k in n:
			ring["seams"].append(first + k * width + rng.randf_range(-0.2, 0.2) * width)
			ring["kinds"].append("subduct" if rng.randf() < float(def["subduct_share"]) else "collide")
			ring["divers"].append(rng.randi_range(0, 1))
			ring["periods"].append(rng.randi_range(int(def["sway_period_min"]), int(def["sway_period_max"])))
			ring["phases"].append(rng.randf() * TAU)
			ring["ridges"].append(0)
			ring["upthrust"].append(-1)
		rings.append(ring)


func enabled() -> bool:
	return bool(def.get("enabled", true))


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


## How fast plate k of ring ri turns on shift n, in radians: its ring's turn plus its own slow sway.
func turn_of(ri: int, k: int, n: int) -> float:
	# Stillstone holds the near ring still.
	if ri == 0 and w.run.has_effect("still_ring"):
		return 0.0
	var ring := rings[ri]
	return float(ring["turn"]) + float(ring["sway"]) * sin(TAU * n / float(ring["periods"][k]) + float(ring["phases"][k]))


# --- Planning a shift ------------------------------------------------------------

## What shift n will do, worked out from the seams as they are (nothing changes). Per ring:
## {turns: per plate, seams: the new seams, results: per seam {kind ("subduct", "collide", "rift",
## "quiet" or "held"), degrees (how far it closes or opens), lead, trail (the edges of the plates either
## side after turning: the plate behind's leading edge and the plate ahead's trailing edge)}}.
func plan(n: int) -> Array:
	var out: Array = []
	var quiet := deg_to_rad(float(def["quiet_degrees"]))
	var min_width := deg_to_rad(float(def["min_plate_degrees"]))
	for ri in rings.size():
		var ring := rings[ri]
		var seams: Array = ring["seams"]
		var count := seams.size()
		var turns: Array = []
		for k in count:
			turns.append(turn_of(ri, k, n))
		var new_seams: Array = []
		var results: Array = []
		for k in count:
			var behind := posmod(k - 1, count)
			var lead := float(seams[k]) + float(turns[behind])
			var trail := float(seams[k]) + float(turns[k])
			var close := float(turns[behind]) - float(turns[k])
			var kind := "quiet"
			var at := (lead + trail) / 2.0
			if close >= quiet:
				kind = ring["kinds"][k]
				if kind == "subduct":
					at = trail if int(ring["divers"][k]) == 0 else lead
			elif close <= -quiet:
				kind = "rift"
			new_seams.append(at)
			results.append({"kind": kind, "degrees": rad_to_deg(absf(close)), "lead": lead, "trail": trail})
		# A plate squeezed too thin stops shrinking: the closing seams either side wait at its own edges.
		for k in count:
			var ahead := (k + 1) % count
			if fposmod(float(new_seams[ahead]) - float(new_seams[k]), TAU) >= min_width:
				continue
			for s in [k, ahead]:
				var res: Dictionary = results[s]
				if res["kind"] in ["subduct", "collide", "quiet"]:
					res["kind"] = "held"
					new_seams[s] = float(seams[s]) + float(turns[k])
		out.append({"turns": turns, "seams": new_seams, "results": results})
	return out


func _next_plan() -> Array:
	if _plan_for != shifts:
		_plan_cache = {"plan": plan(shifts + 1)}
		_plan_for = shifts
	return _plan_cache["plan"]


## Where a point on a plate goes in a shift: {to: new position, fate: "ride", "swallowed" or "pushed",
## seam: the seam it was stopped at (-1 when it rides freely)}. Points on the still ground stay.
func _carry(p: Vector2, plans: Array) -> Dictionary:
	var ri := ring_at(p)
	if ri < 0:
		return {"to": p, "fate": "ride", "seam": -1, "ring": -1}
	var ring := rings[ri]
	var pl: Dictionary = plans[ri]
	var k := plate_at(ri, p.angle())
	var count: int = ring["seams"].size()
	var a := p.angle() + float(pl["turns"][k])
	var s0 := float(pl["seams"][k])
	var s1 := float(pl["seams"][(k + 1) % count])
	if _in_span(a, s0, s1):
		return {"to": Vector2.from_angle(a) * p.length(), "fate": "ride", "seam": -1, "ring": ri}
	# Past one of its plate's new edges: it ran into a closing seam.
	var past_lead := fposmod(a - s1, TAU)
	var before_trail := fposmod(s0 - a, TAU)
	var seam := (k + 1) % count if past_lead < before_trail else k
	var res: Dictionary = pl["results"][seam]
	# At the seam ahead this plate is the one behind it (diver 0); at the seam behind, the one ahead (diver 1).
	var mine := 0 if seam == (k + 1) % count else 1
	var edge := s1 if seam == (k + 1) % count else s0
	var inward := -1.0 if mine == 0 else 1.0
	var margin := _margin(p.length())
	if res["kind"] == "subduct" and int(ring["divers"][seam]) == mine:
		# Swallowed: what is left of it comes up on the far side of the seam.
		return {"to": Vector2.from_angle(edge - inward * margin) * p.length(), "fate": "swallowed", "seam": seam, "ring": ri}
	return {"to": Vector2.from_angle(edge + inward * margin) * p.length(), "fate": "pushed", "seam": seam, "ring": ri}


## How far (radians) things are kept off a seam at radius r, clear of any ridge on it.
func _margin(r: float) -> float:
	return (float(def["ridge_half_width"]) + 8.0) / maxf(r, 1.0)


## The next shift, seam by seam, for the map: [{ring, seam, angle (where it is now), kind, degrees}].
func forecast() -> Array:
	var out: Array = []
	if not enabled():
		return out
	var plans := _next_plan()
	for ri in rings.size():
		for k in rings[ri]["seams"].size():
			var res: Dictionary = plans[ri]["results"][k]
			out.append({"ring": ri, "seam": k, "angle": float(rings[ri]["seams"][k]), "kind": res["kind"],
				"degrees": float(res["degrees"])})
	return out


## The seam within reach world units of p, as a forecast entry, or {}.
func seam_near(p: Vector2, reach: float) -> Dictionary:
	var ri := ring_at(p)
	if ri < 0 or not enabled():
		return {}
	for entry: Dictionary in forecast():
		if int(entry["ring"]) == ri and absf(angle_difference(float(entry["angle"]), p.angle())) * p.length() <= reach:
			return entry
	return {}


## True if the next shift will swallow whatever stands at p (at a closing seam, or by the seam that wakes).
func doomed(p: Vector2) -> bool:
	if not enabled():
		return false
	var plans := _next_plan()
	var c := _carry(p, plans)
	return c["fate"] == "swallowed" or _under_wake(c["to"], _woken(plans))


## How far plate land at p turns in the next shift (radians; 0 on the still ground).
func next_turn(p: Vector2) -> float:
	var ri := ring_at(p)
	if not enabled() or ri < 0:
		return 0.0
	return float(_next_plan()[ri]["turns"][plate_at(ri, p.angle())])


## How far the land at p turned in the last shift (radians), for the map's slide.
func last_turn(p: Vector2) -> float:
	var ri := ring_at(p)
	if ri < 0 or last_turns.is_empty():
		return 0.0
	var turns: Array = last_turns[ri]
	return float(turns[plate_at(ri, p.angle())])


## The squares the ridges hold right now (for drawing).
func ridge_cells() -> PackedInt32Array:
	return _ridge_cells


## True if square i is a ridge right now.
func is_ridge(i: int) -> bool:
	return _ridge_cells.has(i)


## True if p is on a rift's raw ground.
func raw_at(p: Vector2) -> bool:
	var ri := ring_at(p)
	return ri >= 0 and _in_raw(ri, p.angle())


# --- The shift ---------------------------------------------------------------

## Turns the earth once. Called as a new round begins (never in the first round).
func shift() -> void:
	if not enabled():
		return
	var n := shifts + 1
	var plans := plan(n)
	var rng := SeededRng.stream(w.run.run_seed, "earth_shift", n)
	last = {"shift": n, "swallowed": {}, "dens_swallowed": 0, "ridges": 0, "raised": {}, "rifts": 0, "grown": {},
		"roads_refunded": 0, "woke": "", "woke_ring": -1}
	events = []
	woke = _woken(plans)
	var roads_before := _count_roads()
	_clear_slow_ground()
	_move_ground(plans)
	_move_things(plans)
	for ri in rings.size():
		rings[ri]["seams"] = plans[ri]["seams"]
	_grow_ridges(plans)
	_open_rifts(plans, rng)
	_wake(rng)
	_raise_upthrust(rng)
	_stamp_ground()
	_off_ridges()
	_refund_roads(roads_before)
	last_turns = plans.map(func(pl: Dictionary) -> Array: return pl["turns"])
	shifts = n
	_tell()


## Trails, worn paths and roads out on the plates ride them square by square (each square looks back to
## where its ground came from); thickets and raw rifts are stamped again afterwards. Ground in a rift's
## new strip starts plain.
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
		var k := plate_at(ri, _cell_a[j])
		var c := p.cell_of(Vector2.from_angle(_cell_a[j] + float(plans[ri]["turns"][k])) * _cell_r[j])
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
		var a := _cell_a[j]
		var pl: Dictionary = plans[ri]
		var k := plate_at(ri, a, pl["seams"])
		var from_angle := a - float(pl["turns"][k])
		var seams: Array = rings[ri]["seams"]
		if not _in_span(from_angle, seams[k], seams[(k + 1) % seams.size()]):
			continue
		var src := p.index_of(Vector2.from_angle(from_angle) * _cell_r[j])
		if old[src] >= Pathing.TRAIL and _j_of[src] >= 0:
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


## Before a shift: thickets, raw rifts and ridges come up (they are laid again where they end up).
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
	for strip in raw:
		for j in _arc(int(strip["ring"]), strip["a0"], strip["a1"]):
			if p.ground[_cells[j]] == Pathing.THICKET:
				p.set_ground(_cells[j], Pathing.PLAIN)


func _move_things(plans: Array) -> void:
	for node in w.nodes:
		if node.get("gone", false):
			continue
		var c := _carry(node["pos"], plans)
		node["pos"] = c["to"]
		if c["fate"] == "swallowed":
			_swallow_node(node)
	var drowned: Array[int] = []
	for di in w.dens.size():
		var den := w.dens[di]
		var c := _carry(den["pos"], plans)
		den["turned"] = rad_to_deg(angle_difference(Vector2(den["pos"]).angle(), Vector2(c["to"]).angle()))
		den["pos"] = c["to"]
		# The war camp is men in tents: they move off the seam, they don't go under.
		if c["fate"] == "swallowed" and not den.get("camp", false):
			drowned.append(di)
	drowned.reverse()
	for di in drowned:
		_swallow_den(di)
	var kept: Array[Dictionary] = []
	for thicket in w.town.thickets:
		var c := _carry(thicket["pos"], plans)
		thicket["pos"] = c["to"]
		if c["fate"] != "swallowed":
			kept.append(thicket)
	w.town.thickets = kept
	for u: Unit in w.folk + w.run.heroes + w.enemies:
		if not u.alive:
			continue
		u.pos = _carry(u.pos, plans)["to"]
		u.wander_goal = _carry(u.wander_goal, plans)["to"]
		u.path_version = -1
		u.path = PackedVector2Array()


func _swallow_node(node: Dictionary, great := false) -> void:
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
	_feed_the_deep(int(w.run.mod("swallow_den_shells")), w.run.has_effect("swallow_item"))
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


## Closing colliding seams push their ridge up a step; every other seam's ridge wears down a step.
func _grow_ridges(plans: Array) -> void:
	for ri in rings.size():
		var ring := rings[ri]
		for k in ring["seams"].size():
			if plans[ri]["results"][k]["kind"] == "collide":
				ring["ridges"][k] = int(ring["ridges"][k]) + 1
				last["ridges"] = int(last["ridges"]) + 1
			else:
				ring["ridges"][k] = maxi(0, int(ring["ridges"][k]) - 1)


func _open_rifts(plans: Array, rng: SeededRng) -> void:
	raw = []
	for ri in rings.size():
		var ring := rings[ri]
		var rd: Dictionary = def["rings"][ri]
		for k in ring["seams"].size():
			var res: Dictionary = plans[ri]["results"][k]
			if res["kind"] != "rift":
				continue
			raw.append({"ring": ri, "a0": float(res["lead"]), "a1": float(res["trail"])})
			last["rifts"] = int(last["rifts"]) + 1
			# Rift Seed: every wide rift grows something.
			var chance := 1.0 if w.run.has_effect("rift_growth") else float(def["rift_node_chance"])
			if rd["rift_nodes"].is_empty() or float(res["degrees"]) < float(def["rift_min_degrees"]) \
					or rng.randf() >= chance:
				continue
			var type: String = rng.pick(rd["rift_nodes"])
			var ndef: Dictionary = w.content.world["nodes"][type]
			var living := w.nodes.filter(func(n: Dictionary) -> bool: return n["type"] == type and not n.get("gone", false)).size()
			if living >= int(ndef["count"]) * float(def["rift_node_cap"]):
				continue
			var r := rng.randf_range(float(ring["r0"]) + 20.0, float(ring["r1"]) - 20.0)
			var at := Vector2.from_angle((float(res["lead"]) + float(res["trail"])) / 2.0) * r
			_grow(type, at, float(def["rift_node_share"]), false)
			if w.run.has_effect("rift_growth"):
				w.run.relic_fired("rift_growth")


## The seam that wakes this shift (see "wake" in data/plates.json): the one that closes or opens furthest,
## weighted by its ring's wake_weight and its kind's weight; a rift only where its ring grows something. {} when none moves.
func _woken(plans: Array) -> Dictionary:
	var best := {}
	var best_score := 0.0
	for ri in rings.size():
		var rd: Dictionary = def["rings"][ri]
		for k in rings[ri]["seams"].size():
			var res: Dictionary = plans[ri]["results"][k]
			if not res["kind"] in ["subduct", "collide", "rift"] or (res["kind"] == "rift" and rd["rift_nodes"].is_empty()):
				continue
			var score := float(res["degrees"]) * float(rd.get("wake_weight", 1.0)) * float(def["wake"]["weights"][res["kind"]])
			if score > best_score:
				best_score = score
				best = {"ring": ri, "seam": k, "kind": res["kind"], "angle": float(plans[ri]["seams"][k])}
	return best


## The seam that woke does something big: a subducting seam swallows everything on its diving side within
## swallow_band of it, a colliding one breaks open a rich upthrust node at once, a rift opens a valley of fresh nodes.
func _wake(rng: SeededRng) -> void:
	if woke.is_empty():
		return
	var wd: Dictionary = def["wake"]
	var ri := int(woke["ring"])
	var k := int(woke["seam"])
	var ring := rings[ri]
	var a := float(woke["angle"])
	last["woke"] = woke["kind"]
	last["woke_ring"] = ri
	match woke["kind"]:
		"subduct":
			for node in w.nodes:
				if not node.get("gone", false) and _under_wake(node["pos"], woke):
					_swallow_node(node, true)
			for di in range(w.dens.size() - 1, -1, -1):
				if not w.dens[di].get("camp", false) and _under_wake(w.dens[di]["pos"], woke):
					_swallow_den(di, true)
		"collide":
			ring["ridges"][k] = maxi(int(ring["ridges"][k]), int(def["upthrust_height"]))
			var type: String = def["upthrust"].get(w.run.age, "")
			var held := int(ring["upthrust"][k])
			if type != "" and (held < 0 or w.nodes[held].get("gone", false)):
				var r := (float(ring["r0"]) + float(ring["r1"])) / 2.0
				var side := 1.0 if rng.randf() < 0.5 else -1.0
				ring["upthrust"][k] = _raise(type, Vector2.from_angle(a + side * _margin(r)) * r, float(wd["rich"]), true)
		"rift":
			var types: Array = def["rings"][ri]["rift_nodes"]
			var strip := {"a0": a, "a1": a}
			for each in raw:
				if int(each["ring"]) == ri and _in_span(a, each["a0"], each["a1"]):
					strip = each
			var width := fposmod(float(strip["a1"]) - float(strip["a0"]), TAU)
			for i in int(wd["rift_nodes"]):
				var at := float(strip["a0"]) + width * (i + 0.5) / float(wd["rift_nodes"])
				var r := rng.randf_range(float(ring["r0"]) + 20.0, float(ring["r1"]) - 20.0)
				_grow(rng.pick(types), Vector2.from_angle(at) * r, float(wd["rift_share"]), true)


## True if p (where the shift carried it) goes under a waking subducting seam: on its diving side, within
## swallow_band of it. The plate behind a seam lies at smaller angles; diver 0 is that one.
func _under_wake(p: Vector2, wake: Dictionary) -> bool:
	if wake.is_empty() or wake["kind"] != "subduct" or ring_at(p) != int(wake["ring"]):
		return false
	var side := -1.0 if int(rings[int(wake["ring"])]["divers"][int(wake["seam"])]) == 0 else 1.0
	var off := angle_difference(float(wake["angle"]), p.angle())
	return signf(off) == side and absf(off) * p.length() <= float(def["wake"]["swallow_band"])


## A ridge tall enough raises one upthrust node of the town's age beside its pass.
func _raise_upthrust(rng: SeededRng) -> void:
	var type: String = def["upthrust"].get(w.run.age, "")
	if type == "":
		return
	var standing := 0
	for ring in rings:
		for held: int in ring["upthrust"]:
			if held >= 0 and not w.nodes[held].get("gone", false):
				standing += 1
	# Ridgeheart: a step lower, and more of them.
	var height := maxi(1, int(def["upthrust_height"]) - int(w.run.mod("upthrust_ease")))
	var cap := int(def["upthrust_cap"]) + int(w.run.mod("upthrust_more"))
	for ri in rings.size():
		var ring := rings[ri]
		for k in ring["seams"].size():
			if int(ring["ridges"][k]) < height or standing >= cap:
				continue
			var held := int(ring["upthrust"][k])
			if held >= 0 and not w.nodes[held].get("gone", false) and w.nodes[held]["type"] == type:
				continue
			standing += 1
			var r := (float(ring["r0"]) + float(ring["r1"])) / 2.0
			var side := 1.0 if rng.randf() < 0.5 else -1.0
			ring["upthrust"][k] = _raise(type, Vector2.from_angle(float(ring["seams"][k]) + side * _margin(r)) * r, 1.0, false)


## A fresh node in a rift.
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


## Thickets and raw rifts slow walkers; ridges are solid. Laid fresh after every shift.
func _stamp_ground() -> void:
	var p := w.pathing
	_index_cells()
	for thicket in w.town.thickets:
		for i in p.cells_in_circle(thicket["pos"], float(thicket["radius"])):
			if p.ground[i] < Pathing.TRAIL:
				p.set_ground(i, Pathing.THICKET)
	for strip in raw:
		for j in _arc(int(strip["ring"]), strip["a0"], strip["a1"]):
			if p.ground[_cells[j]] < Pathing.TRAIL:
				p.set_ground(_cells[j], Pathing.THICKET)
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


func _in_raw(ri: int, a: float) -> bool:
	for strip in raw:
		if int(strip["ring"]) == ri and _in_span(a, strip["a0"], strip["a1"]):
			return true
	return false


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
			last["roads_refunded"] = int(last["roads_refunded"]) + gone
	w.town.refund_roads(lost)


func _tell() -> void:
	var parts: Array[String] = []
	var swallowed := 0
	for t: String in last["swallowed"]:
		swallowed += int(last["swallowed"][t])
	if swallowed > 0:
		parts.append("%d resource%s sink%s at the seams" % [swallowed, "" if swallowed == 1 else "s", "s" if swallowed == 1 else ""])
	if int(last["ridges"]) > 0:
		parts.append("ridges push up where plates collide")
	var grown := 0
	for t: String in last["grown"]:
		grown += int(last["grown"][t])
	if grown > 0:
		parts.append("%d fresh patch%s grow%s in the rifts" % [grown, "" if grown == 1 else "es", "s" if grown == 1 else ""])
	for t: String in last["raised"]:
		parts.append("a ridge breaks open: %s" % w.content.world["nodes"][t]["name"].to_lower())
	var line := "The earth turns."
	if not parts.is_empty():
		line = "The earth turns: %s." % "; ".join(parts)
	w.run.tell(line)
