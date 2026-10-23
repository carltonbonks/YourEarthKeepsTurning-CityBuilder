class_name Town
extends RefCounted
## The town's layout: rings of plots around the hearth, the obstacles already on
## some of them, thickets out past the town, gates, and paving.
##
## Plots touch each other along a ring, so a stretch of buildings is a wall and
## people walk round it along the lanes between rings. Buildings place themselves
## on the free plot that suits them (the "near" key in buildings.json), never where
## they would cut the hearth off from the wilds. A gate (a building with "gate") fills
## a plot beside a building (best a gap between two) that the busiest desire path runs through:
## townsfolk and heroes walk through it, raiders batter it down or go round. Desire paths wear in by
## themselves (Pathing.wear_trails); once a building with "paves" stands, stone-layers
## pave the busiest worn paths a stretch at a time for stone. See data/town.json.

## Score added for building on a lane plot: buildings leave the lanes free unless nothing else is left.
const LANE_PENALTY := 5000.0
## How much a gate likes a lane plot, in the same units as the feet passing through it.
const GATE_LANE_BONUS := 40.0

var w: World
var pathing: Pathing
## {ring, sector, a0, a1, r0, r1, pos, cells: PackedInt32Array, obstacle, building, lane}
## building = index into World.buildings, or -1. lane = left free between clusters (see _mark_lanes).
var plots: Array[Dictionary] = []
## Patches of scrub that slow walkers: {pos, radius}.
var thickets: Array[Dictionary] = []
## Squares of road already paid for, per road kind (each payment covers a stretch).
var _paid := {}
var _plot_of := PackedInt32Array()  ## Square -> plot index, or -1.
## Where the watch post being placed wants to stand (see _guard_point), worked out once per choose_plot.
var _guard_at := Vector2.ZERO


func _init(world: World) -> void:
	w = world
	pathing = w.pathing
	_plot_of.resize(pathing.cells * pathing.cells)
	_plot_of.fill(-1)
	_make_plots()
	_mark_lanes()
	_place_obstacles()
	_place_thickets()


# --- Layout ------------------------------------------------------------------

func _make_plots() -> void:
	var town := w.content.town
	var sectors := int(town["sectors"])
	var depth := float(town["ring_depth"])
	var start := -PI / sectors  # Sectors are centred on east, south-east, south, ...
	for ring in town["rings"].size():
		var def: Dictionary = town["rings"][ring]
		var radius := float(def["radius"])
		var per_sector := maxi(1, roundi(TAU * radius / float(town["plot_width"]) / sectors))
		var count := per_sector * sectors
		var width := TAU / count
		var first := plots.size()
		for i in count:
			var a0 := start + i * width
			plots.append({"ring": ring, "sector": i / per_sector, "ring_first": first, "ring_count": count, "a0": a0, "a1": a0 + width,
				"r0": radius - depth / 2.0, "r1": radius + depth / 2.0,
				"pos": Vector2.from_angle(a0 + width / 2.0) * radius, "cells": PackedInt32Array(),
				"obstacle": "", "building": -1, "lane": false})
		for i in pathing.cells_in_circle(Vector2.ZERO, radius + depth / 2.0):
			var p := pathing.center(i)
			if p.length() < radius - depth / 2.0:
				continue
			var k := int(floor(fposmod(p.angle() - start, TAU) / width)) % count
			plots[first + k]["cells"].append(i)
			_plot_of[i] = first + k


## Buildings stand in clusters of about `cluster` plots (data/town.json) with a lane plot
## between clusters, left free for people to pass and for gates. Lanes line up from ring to
## ring: every lane carries on into the plot straight out from it, and the outer rings, which
## have more plots, get extra lanes so no cluster runs longer than cluster + 1.
func _mark_lanes() -> void:
	var size := int(w.content.town["cluster"])
	var inner: Array[int] = []
	for ring in w.content.town["rings"].size():
		var ring_plots: Array[int] = []
		for k in plots.size():
			if int(plots[k]["ring"]) == ring:
				ring_plots.append(k)
		var count := ring_plots.size()
		var width := TAU / count
		var start := float(plots[ring_plots[0]]["a0"])
		var forced := {}
		if inner.is_empty():
			forced[0] = true
		for k in inner:
			var mid := (float(plots[k]["a0"]) + float(plots[k]["a1"])) / 2.0
			forced[int(floor(fposmod(mid - start, TAU) / width)) % count] = true
		var lanes: Array = forced.keys()
		lanes.sort()
		# Split each run of plots between two lanes into clusters as even as possible.
		var extra: Array[int] = []
		for n in lanes.size():
			var from: int = lanes[n]
			var run := posmod(int(lanes[(n + 1) % lanes.size()]) - from - 1, count)
			if lanes.size() == 1:
				run = count - 1
			var cuts := ceili(maxf(0.0, run - size - 1) / float(size + 2))
			var left := run - cuts
			var at := from
			for c in cuts:
				at += int(floor(float(left) * (c + 1) / (cuts + 1))) - int(floor(float(left) * c / (cuts + 1))) + 1
				extra.append(posmod(at, count))
		inner.clear()
		for i in lanes + extra:
			plots[ring_plots[i]]["lane"] = true
			inner.append(ring_plots[i])


## Boulders and old oaks already sit on a few plots of the inner rings (obstacle_rings in data/town.json).
func _place_obstacles() -> void:
	var rng := SeededRng.stream(w.run.run_seed, "obstacles")
	var ids: Array = w.content.town["obstacles"].keys()
	var inner := int(w.content.town["obstacle_rings"])
	ids.sort()
	for id: String in ids:
		for n in int(w.content.town["obstacles"][id]["count"]):
			for attempt in 20:
				var k := rng.randi_range(0, plots.size() - 1)
				var plot := plots[k]
				if plot["obstacle"] != "" or int(plot["ring"]) >= inner or not _keeps_town_open(k):
					continue
				plot["obstacle"] = id
				_set_plot_solid(k, true)
				break


func _place_thickets() -> void:
	var def: Dictionary = w.content.town["thickets"]
	var rng := SeededRng.stream(w.run.run_seed, "thickets")
	var far := w.content.num("world_radius") * 0.95
	for n in int(def["count"]):
		var radius := rng.randf_range(float(def["radius_min"]), float(def["radius_max"]))
		var at := Vector2.from_angle(rng.randf() * TAU) * rng.randf_range(float(def["min_distance"]) + radius, far - radius)
		thickets.append({"pos": at, "radius": radius})
		for i in pathing.cells_in_circle(at, radius):
			pathing.set_ground(i, Pathing.THICKET)


func _set_plot_solid(k: int, solid: bool) -> void:
	for i in plots[k]["cells"]:
		pathing.set_solid(i, solid)


## The outermost ring's outer edge: past it is open ground.
func outer_edge() -> float:
	var last: Dictionary = w.content.town["rings"][-1]
	return float(last["radius"]) + float(w.content.town["ring_depth"])


## True if, with plot k filled, the hearth can still be reached from the wilds.
func _keeps_town_open(k: int) -> bool:
	_set_plot_solid(k, true)
	var open := pathing.connected(Vector2.ZERO, Vector2(outer_edge() + 30.0, 0.0))
	_set_plot_solid(k, false)
	return open


## True if the plot's ring is open: the first start_rings are, and each age-up or cleared ring opens the next.
func ring_open(plot: Dictionary) -> bool:
	return int(plot["ring"]) < w.run.rings_open


## How full the open rings are: the share of their building plots (not lanes or obstacles) with a building on.
func fullness() -> float:
	var usable := 0
	var taken := 0
	for plot in plots:
		if ring_open(plot) and not plot["lane"] and plot["obstacle"] == "":
			usable += 1
			if int(plot["building"]) >= 0:
				taken += 1
	return float(taken) / maxf(1.0, float(usable))


## A plot nothing stands on, in an opened ring.
func plot_free(k: int) -> bool:
	var plot := plots[k]
	if plot["obstacle"] != "" or int(plot["building"]) >= 0 or not ring_open(plot):
		return false
	return true


## The plot a new building of this type would go on, or -1 if there is none.
## A gate only goes beside a building (or obstacle) of its ring, best in a gap between two,
## where the busiest desire path runs; it never shuts anyone in, since your people walk through.
## Other buildings keep off lanes and paved road unless nothing else is left.
func choose_plot(type: String) -> int:
	var gate := is_gate_type(type)
	if w.content.buildings[type].get("near", "") == "gate_guard":
		_guard_at = _guard_point()
	var order: Array = []
	for k in plots.size():
		if plot_free(k) and (not gate or _sides_closed(k) > 0):
			var score := _gate_score(k) if gate else _plot_score(type, k) + (1000.0 if _paved_in(k) > 0 else 0.0)
			if not gate and plots[k]["lane"]:
				score += LANE_PENALTY
			order.append([score, k])
	order.sort()
	for pair: Array in order:
		if gate or _keeps_town_open(pair[1]):
			return pair[1]
	return -1


## The plots on either side of plot k in its ring.
func ring_neighbours(k: int) -> Array[int]:
	var first := int(plots[k]["ring_first"])
	var count := int(plots[k]["ring_count"])
	return [first + posmod(k - first - 1, count), first + posmod(k - first + 1, count)]


## The plots in plot k's cluster: the run of plots between two lanes in its ring. A lane plot (a gate's, or
## a building that found nowhere else) counts the plots on either side of it instead.
func cluster_plots(k: int) -> Array[int]:
	var out: Array[int] = [k]
	if plots[k]["lane"]:
		out.append_array(ring_neighbours(k))
		return out
	var count := int(plots[k]["ring_count"])
	for side: int in [-1, 1]:
		var at := k
		for step in count - 1:
			var first := int(plots[at]["ring_first"])
			at = first + posmod(at - first + side, count)
			if at == k or plots[at]["lane"]:
				break
			if not out.has(at):
				out.append(at)
	return out


## The other finished buildings in building i's cluster (indices into World.buildings).
func cluster_mates(i: int) -> Array[int]:
	var out: Array[int] = []
	for k in cluster_plots(int(w.buildings[i]["plot"])):
		var b := int(plots[k]["building"])
		if b >= 0 and b != i and float(w.buildings[b]["work_left"]) <= 0.0:
			out.append(b)
	return out


## The row (data/combos.json) building i is part of now, as a one-item list: it was ordered on a row card as the
## row's main building, and it and its partner both stand finished.
func combos_of(i: int) -> Array[String]:
	var out: Array[String] = []
	var b := w.buildings[i]
	var id: String = b.get("row", "")
	if id == "" or w.content.combos[id]["building"] != b["type"] or float(b["work_left"]) > 0.0:
		return out
	var mate := int(b.get("row_mate", -1))
	if mate >= 0 and float(w.buildings[mate]["work_left"]) <= 0.0:
		out.append(id)
	return out


## The sum of one effect key over the rows building i is part of.
func combo_effect(i: int, key: String) -> float:
	var total := 0.0
	for id in combos_of(i):
		total += float(w.content.combos[id]["effect"].get(key, 0.0))
	return total


## Where a row card's two buildings go: [plot for a, plot for b] in one cluster, or [] if no cluster has room.
## Building a takes the best plot (by its own wants) whose cluster has another free plot, and b the free plot
## there that suits it best; neither may wall off the hearth.
func choose_row(a: String, b: String) -> Array[int]:
	var order: Array = []
	for k in plots.size():
		if plot_free(k) and not plots[k]["lane"]:
			order.append([_plot_score(a, k) + (1000.0 if _paved_in(k) > 0 else 0.0), k])
	order.sort()
	for pair: Array in order:
		var k: int = pair[1]
		var best := -1
		var best_score := INF
		for p in cluster_plots(k):
			if p == k or not plot_free(p) or plots[p]["lane"]:
				continue
			var score := _plot_score(b, p)
			if score < best_score:
				best_score = score
				best = p
		if best < 0 or not _keeps_town_open(k):
			continue
		_set_plot_solid(k, true)
		var open := _keeps_town_open(best)
		_set_plot_solid(k, false)
		if open:
			return [k, best]
	return []


## How many sides of plot k (0 to 2) have something standing on them.
func _sides_closed(k: int) -> int:
	var n := 0
	for side in ring_neighbours(k):
		if int(plots[side]["building"]) >= 0 or plots[side]["obstacle"] != "":
			n += 1
	return n


## Lower is better: a true gap first, then the plot the most feet pass through (a lane counts
## as a few more), outer rings first on a tie.
func _gate_score(k: int) -> float:
	var feet := GATE_LANE_BONUS if plots[k]["lane"] else 0.0
	for i in plots[k]["cells"]:
		feet += pathing.traffic[i] + (4.0 if pathing.ground[i] >= Pathing.TRAIL else 0.0)
	return (0.0 if _sides_closed(k) == 2 else 100000.0) - feet - int(plots[k]["ring"]) * 0.5


## Lower is better. Each building type says what it wants to be near in buildings.json:
## "hearth" (inner rings, the default), "outer" (outer rings), "tended" (outer rings, by the most
## untended nodes it would tend), "warned_side" (outer rings facing this round's warned attack), "gate_guard" (just outside a gate, see _guard_point)
## or another building's id (beside one of those).
func _plot_score(type: String, k: int) -> float:
	var plot := plots[k]
	var ring := int(plot["ring"])
	var rings := 0
	for p in plots:
		if ring_open(p):
			rings = maxi(rings, int(p["ring"]) + 1)
	var near: String = w.content.buildings[type].get("near", "hearth")
	var score := 0.0
	match near:
		"hearth":
			score = ring * 60.0
		"outer":
			score = (rings - 1 - ring) * 60.0
		"tended":
			score = (rings - 1 - ring) * 60.0 - _untended_reach(type, plot["pos"]) * 2.0
		"warned_side":
			score = (rings - 1 - ring) * 30.0
			var best := PI
			for side in w.wave_sides:
				best = minf(best, absf(angle_difference(side, (plot["pos"] as Vector2).angle())))
			score += best * 80.0
		"gate_guard":
			score = (plot["pos"] as Vector2).distance_to(_guard_at)
		_:
			var best := ring * 60.0 + 200.0
			for b in w.buildings:
				if b["type"] == near:
					best = minf(best, (plot["pos"] as Vector2).distance_to(b["pos"]))
			score = best
	# Buildings like company: a plot beside another building is a little more likely.
	for other in [k - 1, k + 1]:
		if other >= 0 and other < plots.size() and plots[other]["ring"] == ring and int(plots[other]["building"]) >= 0:
			score -= 12.0
	# A little seeded jitter so towns grow a bit differently each run.
	score += float(hash([w.run.run_seed, k, w.buildings.size()]) % 1000) / 1000.0 * 20.0
	return score


## Where the next watch post should stand: just outside the gate with the fewest posts guarding
## it (the oldest on a tie). Once every gate has one, or there is no gate, it guards the next
## likely gate spot instead: an unguarded lane beside buildings that the most feet pass through,
## facing the warned attack on a tie. A post guards the gate or lane nearest it within guard_within.
func _guard_point() -> Vector2:
	var within := float(w.content.town["gate"]["guard_within"])
	var posts: Array[Vector2] = []
	for b in w.buildings:
		if w.content.buildings[b["type"]].get("near", "") == "gate_guard":
			posts.append(b["pos"])
	var target := Vector2.INF
	var fewest := 1
	for b in w.buildings:
		if is_gate_type(b["type"]):
			var guards := posts.filter(func(p: Vector2) -> bool: return p.distance_to(b["pos"]) < within).size()
			if guards < fewest:
				fewest = guards
				target = b["pos"]
	if target == Vector2.INF:
		var best := INF
		for k in plots.size():
			if not plot_free(k) or not plots[k]["lane"]:
				continue
			var at: Vector2 = plots[k]["pos"]
			if posts.any(func(p: Vector2) -> bool: return p.distance_to(at) < within):
				continue
			var facing := PI
			for side in w.wave_sides:
				facing = minf(facing, absf(angle_difference(side, at.angle())))
			var closed := _sides_closed(k)
			var score := _gate_score(k) + (200000.0 if closed == 0 else 0.0) + facing * 10.0
			if score < best:
				best = score
				target = at
	if target == Vector2.INF:
		# Every gate and lane is guarded: stack on the least-guarded gate.
		fewest = posts.size() + 1
		for b in w.buildings:
			if is_gate_type(b["type"]):
				var guards := posts.filter(func(p: Vector2) -> bool: return p.distance_to(b["pos"]) < within).size()
				if guards < fewest:
					fewest = guards
					target = b["pos"]
	if target == Vector2.INF:
		return Vector2.ZERO
	# Straight out from the gate, one ring further; the lane there stays free, so the post stands beside the path.
	var step := float(w.content.town["rings"][1]["radius"]) - float(w.content.town["rings"][0]["radius"])
	return target + target.normalized() * step


## The full size of the nodes a building that tends ("tends" in buildings.json) would reach from pos,
## leaving out nodes another building of its kind already tends.
func _untended_reach(type: String, pos: Vector2) -> float:
	var tends: Dictionary = w.content.buildings[type].get("tends", {})
	var total := 0.0
	for node in w.nodes:
		if not w.tends_node(tends, pos, node):
			continue
		if w.buildings.any(func(b: Dictionary) -> bool: return b["type"] == type and w.tends_node(tends, b["pos"], node)):
			continue
		total += float(node["max"])
	return total


## Puts building index b on plot k: the plot turns solid (a gate stays open until it is built, see on_built).
## Paving under a new building is lifted and its goods go back into stock; a gate keeps the road through it.
func occupy(k: int, b: int) -> void:
	plots[k]["building"] = b
	if is_gate_type(w.buildings[b]["type"]):
		return
	var lifted := {}
	for i in plots[k]["cells"]:
		if pathing.ground[i] >= Pathing.FIRST_ROAD:
			lifted[pathing.ground[i]] = int(lifted.get(pathing.ground[i], 0)) + 1
	refund_roads(lifted)
	if not lifted.is_empty():
		w.run.tell("The stones under the new %s are lifted and stacked." % w.content.buildings[w.buildings[b]["type"]]["name"].to_lower())
	# Trails and paths are simply built over.
	for i in plots[k]["cells"]:
		pathing.set_ground(i, Pathing.PLAIN)
		pathing.traffic[i] = 0.0
	_set_plot_solid(k, true)


## Pays back lifted paving: lifted = road kind -> squares.
func refund_roads(lifted: Dictionary) -> void:
	for kind: int in lifted:
		var cost: Dictionary = road_def(kind)["cost"]
		for r: String in cost:
			var back := int(cost[r]) * int(lifted[kind]) / int(w.content.town["stretch_cells"])
			w.run.stock[r] = int(w.run.stock.get(r, 0)) + back


## Squares of paved road on plot k.
func _paved_in(k: int) -> int:
	var n := 0
	for i in plots[k]["cells"]:
		if pathing.ground[i] >= Pathing.FIRST_ROAD:
			n += 1
	return n


## The plot under a world point, or -1.
func plot_at(p: Vector2) -> int:
	var i := pathing.index_of(p)
	if i < 0 or i >= _plot_of.size():
		return -1
	var k := _plot_of[i]
	if k >= 0 and not ring_open(plots[k]):
		return -1
	return k


## Outline of a plot (a slice of ring) as world points, for drawing.
func plot_outline(k: int, steps := 4) -> PackedVector2Array:
	var plot := plots[k]
	var out := PackedVector2Array()
	for s in steps + 1:
		out.append(Vector2.from_angle(lerpf(plot["a0"], plot["a1"], float(s) / steps)) * float(plot["r1"]))
	for s in range(steps, -1, -1):
		out.append(Vector2.from_angle(lerpf(plot["a0"], plot["a1"], float(s) / steps)) * float(plot["r0"]))
	return out


# --- Paving --------------------------------------------------------------------

## True once a building that lets craftspeople pave (a stone-layers' yard) stands.
func can_pave() -> bool:
	for b in w.buildings:
		if w.content.buildings[b["type"]].get("paves", false) and float(b["work_left"]) <= 0.0:
			return true
	return false


## The name of the building that lets craftspeople pave (for hints), e.g. "stone-layers' yard".
func paver_name() -> String:
	for id: String in w.content.buildings:
		if w.content.buildings[id].get("paves", false):
			return w.content.buildings[id]["name"].to_lower()
	return ""


## The best road kind (ground kind index) the town's age allows.
func best_road() -> int:
	var best := -1
	var ids: Array = w.content.town["roads"].keys()
	for j in ids.size():
		if w.content.age_reached(w.run.age, w.content.town["roads"][ids[j]].get("age", "")):
			best = Pathing.FIRST_ROAD + j
	return best


func road_def(kind: int) -> Dictionary:
	return w.content.town["roads"][pathing.kind_ids[kind]]


## The busiest worn path (or older road) square waiting to be paved, skipping `taken`; -1 if none.
func next_to_pave(taken: Array) -> int:
	var best := best_road()
	if best < 0:
		return -1
	for i in pathing.busy_paths:
		if pathing.ground[i] >= Pathing.PATH and pathing.ground[i] < best and not pathing.is_solid(i) and not taken.has(i):
			return i
	return -1


## True if the next stretch of the best road is already paid for or the town can pay for it
## and still keep "keep_in_stock" of each good for building.
func can_afford_paving() -> bool:
	var kind := best_road()
	return kind >= 0 and (int(_paid.get(kind, 0)) > 0 or _can_pay(road_def(kind)["cost"]))


func _can_pay(cost: Dictionary, keep := int(w.content.town["keep_in_stock"])) -> bool:
	for r: String in cost:
		if int(w.run.stock.get(r, 0)) < int(cost[r]) + keep:
			return false
	return true


## Seconds of work one square of the best road takes.
func pave_work() -> float:
	var kind := best_road()
	return float(road_def(kind)["work"]) / float(w.content.town["stretch_cells"])


## Lays the best road on square i, paying for a new stretch when needed. False if the town can't pay.
func pave(i: int) -> bool:
	var kind := best_road()
	if kind < 0 or pathing.ground[i] >= kind:
		return kind >= 0
	if int(_paid.get(kind, 0)) <= 0:
		var cost: Dictionary = road_def(kind)["cost"]
		if not _can_pay(cost):
			return false
		for r: String in cost:
			w.run.stock[r] = int(w.run.stock[r]) - int(cost[r])
		w.run.record.note_spend("paving", cost)
		_paid[kind] = int(w.content.town["stretch_cells"])
	_paid[kind] = int(_paid[kind]) - 1
	pathing.set_ground(i, kind)
	return true


## A new age lays its ground (data/ages.json "hearth_ground": "path" or a road id) on every open
## square round the hearth out to "hearth_ground_radius", keeping better ground where it is already
## laid. Returns how many squares changed.
func lay_hearth_ground(age_id: String) -> int:
	var ages := w.content.ages
	var id: String = ages["ages"][age_id].get("hearth_ground", "")
	var kind := pathing.kind_ids.find(id)
	if kind < 0:
		return 0
	var n := 0
	for i in pathing.cells_in_circle(Vector2.ZERO, float(ages["hearth_ground_radius"])):
		if pathing.is_solid(i):
			continue
		if pathing.ground[i] < kind:
			n += 1
		pathing.lay(i, kind)
	return n


## Squares of each road kind laid so far, by id.
func paved_counts() -> Dictionary:
	var out := {}
	for j in w.content.town["roads"].size():
		var n := pathing.count_ground(Pathing.FIRST_ROAD + j)
		if n > 0:
			out[pathing.kind_ids[Pathing.FIRST_ROAD + j]] = n
	return out


# --- Gates ---------------------------------------------------------------------

func is_gate_type(type: String) -> bool:
	return w.content.buildings[type].has("gate_hp")


## Health of each square of a gate building.
func gate_hp(b: int) -> float:
	return float(w.content.buildings[w.buildings[b]["type"]]["gate_hp"])


## A building is finished: a gate goes up across its plot.
func on_built(b: int) -> void:
	if b < 0 or b >= w.buildings.size() or not is_gate_type(w.buildings[b]["type"]):
		return
	for i in plots[w.buildings[b]["plot"]]["cells"]:
		pathing.set_wall(i, gate_hp(b))


## At dawn every finished gate is mended to full health, broken squares too.
func patch_walls() -> void:
	for b in w.buildings.size():
		if is_gate_type(w.buildings[b]["type"]) and float(w.buildings[b]["work_left"]) <= 0.0:
			on_built(b)


## {built, broken} gate counts (a gate is broken when raiders have opened any square of it).
func gate_counts() -> Dictionary:
	var out := {"built": 0, "broken": 0}
	for b in w.buildings.size():
		if is_gate_type(w.buildings[b]["type"]) and float(w.buildings[b]["work_left"]) <= 0.0:
			out["built"] += 1
			for i in plots[w.buildings[b]["plot"]]["cells"]:
				if pathing.wall_hp[i] <= 0.0:
					out["broken"] += 1
					break
	return out


## How whole gate building b is, 0..1 (its weakest square).
func gate_health(b: int) -> float:
	var worst := 1.0
	for i in plots[w.buildings[b]["plot"]]["cells"]:
		worst = minf(worst, pathing.wall_hp[i] / gate_hp(b))
	return worst
