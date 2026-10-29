class_name Earth
extends RefCounted
## The turning earth (`world.earth`), read as this round's weather (Yusuf, 2026-10-25). Just past the still
## town lies one ring of plates, each of a kind (Fen, Greenwood, Stonefield, Barrow), and once between rounds
## the ring clicks round the hearth by one whole plate (`shift`, called by RunState as a new round begins).
## The night's attack crosses one of these plates on its way in (`crossing`), and each kind gives and takes:
## how fast people walk on it (`walk_factor`), how far the hearth and towers see raiders on it (`sight_at`),
## plants regrowing (`dawn`), raiders getting up again and heroes digging grave goods (World.damage).
## Relics, traditions and buildings change a kind's numbers by its tags (`kind_def`, plate_knobs).
## Everything on the ring rides it: resource nodes, thickets, trails and roads, and anyone standing there.
## Numbers are in data/plates.json.

var w: World
var def: Dictionary
## Per ring: {name, r0, r1, step (radians a click turns it), click_every, seams: Array[float] (plate k runs from
## seams[k] to seams[k + 1]), plate_kinds: per plate its kind id from near_kinds}.
var rings: Array[Dictionary] = []
## Shifts so far this run.
var shifts := 0
## What the last shift did (see RunRecord "shift"): {shift, roads_refunded}. Empty before the first shift.
var last := {}
## Goes up whenever the ring turns, so the map slides the land into place.
var turned := 0
## The last turn's turn per ring, in radians (for the map's slide).
var last_turns: Array = []
## The squares out on the ring (see _index_cells).
var _cells := PackedInt32Array()
var _cell_ring := PackedByteArray()
var _cell_r := PackedFloat32Array()
var _cell_a := PackedFloat32Array()
var _j_of := PackedInt32Array()  ## Square -> its place in _cells, or -1 off the ring.
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
		var ring := {"name": rd["name"], "r0": float(rd["r0"]), "r1": float(rd["r1"]),
			"step": width * float(rd.get("dir", 1)), "click_every": maxi(1, int(rd.get("click_every", 1))),
			"seams": [], "plate_kinds": []}
		for k in n:
			ring["seams"].append(start + k * width + rng.randf_range(-0.15, 0.15) * width)
			ring["plate_kinds"].append(dealt[k % dealt.size()])
		rings.append(ring)


func enabled() -> bool:
	return bool(def.get("enabled", true)) and not rings.is_empty()


# --- Where things are ----------------------------------------------------------

## The ring a point lies in, or -1 off the plates.
func ring_at(p: Vector2) -> int:
	var r := p.length()
	for ri in rings.size():
		if r >= float(rings[ri]["r0"]) and r < float(rings[ri]["r1"]):
			return ri
	return -1


## The plate of ring ri that angle a lies on.
func plate_at(ri: int, a: float) -> int:
	var seams: Array = rings[ri]["seams"]
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


## The near plate's kind under p, or "" off the ring.
func kind_at(p: Vector2) -> String:
	if not enabled() or ring_at(p) != 0:
		return ""
	return kind_at_angle(p.angle())


## The kind of ground an attack from angle a crosses on its way in.
func crossing(a: float) -> String:
	if not enabled():
		return ""
	return kind_at_angle(a)


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


## How fast someone walks at p for its plate's kind (1 elsewhere): a Fen slows everyone, a Stonefield
## speeds raiders.
func walk_factor(p: Vector2, enemy: bool) -> float:
	var kind := kind_at(p)
	if kind == "":
		return 1.0
	var kd := kind_def(kind)
	return float(kd.get("walk", 1.0)) * (float(kd.get("raider_walk", 1.0)) if enemy else 1.0)


## How far the hearth and towers see a raider standing at p, against their range (1 off the ring).
func sight_at(p: Vector2) -> float:
	var kind := kind_at(p)
	return float(kind_def(kind).get("sight", 1.0)) if kind != "" else 1.0


## How far ring ri turns on shift n, in radians: a whole plate's width on its clicks, else none. Stillstone holds
## it still; the Lodestone wheel turns it further (earth_turns).
func turn_of(ri: int, n: int) -> float:
	if w.run.has_effect("still_ring"):
		return 0.0
	var ring := rings[ri]
	if n % int(ring["click_every"]) != 0:
		return 0.0
	return float(ring["step"]) * (1.0 + w.run.mod("earth_turns"))


## How far the land at p turned in the last turn (radians), for the map's slide.
func last_turn(p: Vector2) -> float:
	var ri := ring_at(p)
	if ri < 0 or last_turns.is_empty():
		return 0.0
	return float(last_turns[ri])


# --- The shift ---------------------------------------------------------------

## Turns the earth once. Called as a new round begins (never in the first round).
func shift() -> void:
	if not enabled():
		return
	var n := shifts + 1
	last = {"shift": n, "roads_refunded": 0}
	var turns: Array = []
	for ri in rings.size():
		turns.append(turn_of(ri, n))
	var roads_before := _count_roads()
	_clear_thickets()
	_move_ground(turns)
	_move_things(turns)
	for ri in rings.size():
		rings[ri]["seams"] = rings[ri]["seams"].map(func(s: float) -> float: return s + float(turns[ri]))
	last_turns = turns.duplicate()
	turned += 1
	_stamp_thickets()
	_refund_roads(roads_before)
	shifts = n


## Trails, worn paths and roads out on the ring ride it square by square (each square looks back to where its
## ground came from); thickets are stamped again afterwards.
func _move_ground(turns: Array) -> void:
	var p := w.pathing
	_index_cells()
	var old := p.ground.duplicate()
	var old_traffic := p.traffic.duplicate()
	var dest := {}
	for j in _cells.size():
		var i := _cells[j]
		var t := float(turns[_cell_ring[j]])
		if old[i] < Pathing.TRAIL or t == 0.0:
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
		var t := float(turns[ri])
		if t == 0.0:
			continue
		var src := p.index_of(Vector2.from_angle(_cell_a[j] - t) * _cell_r[j])
		if old[src] >= Pathing.TRAIL and _j_of[src] >= 0 and _cell_ring[_j_of[src]] == ri:
			p.set_ground(i, old[src])
			p.traffic[i] = old_traffic[src]


## Every square out on the ring, once: its index, ring, distance from the hearth and angle.
func _index_cells() -> void:
	if not _cells.is_empty():
		return
	var p := w.pathing
	_j_of.resize(p.ground.size())
	_j_of.fill(-1)
	for i in p.ground.size():
		var at := p.center(i)
		var ri := ring_at(at)
		if ri < 0 or at.length() > w.content.num("world_radius"):
			continue
		_j_of[i] = _cells.size()
		_cells.append(i)
		_cell_ring.append(ri)
		_cell_r.append(at.length())
		_cell_a.append(at.angle())


## Before a turn: thickets come up (they are laid again where they end up).
func _clear_thickets() -> void:
	var p := w.pathing
	for thicket in w.town.thickets:
		for i in p.cells_in_circle(thicket["pos"], float(thicket["radius"])):
			if p.ground[i] == Pathing.THICKET:
				p.set_ground(i, Pathing.PLAIN)


## After a turn: thickets slow walkers again where they now stand.
func _stamp_thickets() -> void:
	var p := w.pathing
	for thicket in w.town.thickets:
		for i in p.cells_in_circle(thicket["pos"], float(thicket["radius"])):
			if p.ground[i] < Pathing.TRAIL:
				p.set_ground(i, Pathing.THICKET)


## Where a point goes when the rings turn by `turns` (radians per ring). Points off the ring stay.
func _carried(p: Vector2, turns: Array) -> Vector2:
	var ri := ring_at(p)
	return p if ri < 0 else p.rotated(float(turns[ri]))


func _move_things(turns: Array) -> void:
	for node in w.nodes:
		if not node.get("gone", false):
			node["pos"] = _carried(node["pos"], turns)
	for den in w.dens:
		den["pos"] = _carried(den["pos"], turns)
	for thicket in w.town.thickets:
		thicket["pos"] = _carried(thicket["pos"], turns)
	for u: Unit in w.folk + w.run.heroes + w.enemies:
		if not u.alive:
			continue
		u.pos = _carried(u.pos, turns)
		u.wander_goal = _carried(u.wander_goal, turns)
		u.path_version = -1
		u.path = PackedVector2Array()


# --- Each dawn ----------------------------------------------------------------------

## Plants on a plate whose kind regrows them (the Greenwood) regrow a share of their full size.
func dawn() -> void:
	if not enabled():
		return
	for node in w.nodes:
		if node.get("gone", false) or not w.regrows(node) or not w.content.has_tag("node", node["type"], "plant"):
			continue
		var share := float(kind_def(kind_at(node["pos"])).get("regrow", 0.0))
		if share > 0.0:
			node["amount"] = mini(int(node["max"]), int(node["amount"]) + maxi(1, roundi(int(node["max"]) * share)))


func _count_roads() -> Dictionary:
	_index_cells()
	var out := {}
	var ground := w.pathing.ground
	for i in _cells:
		if ground[i] >= Pathing.FIRST_ROAD:
			out[ground[i]] = int(out.get(ground[i], 0)) + 1
	return out


## Paving the turn carried off the map's squares is paid back, as when a building is put up over a road.
func _refund_roads(before: Dictionary) -> void:
	var after := _count_roads()
	var lost := {}
	for kind: int in before:
		var gone := int(before[kind]) - int(after.get(kind, 0))
		if gone > 0:
			lost[kind] = gone
			last["roads_refunded"] = int(last.get("roads_refunded", 0)) + gone
	w.town.refund_roads(lost)
