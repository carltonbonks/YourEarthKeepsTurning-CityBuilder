class_name Town
extends RefCounted
## The town's layout: rings of plots around the hearth, the obstacles already on
## some of them, thickets out past the town, and the roads the player stakes out.
##
## Plots touch each other along a ring, so a stretch of buildings is a wall and
## people walk round it along the lanes between rings. Buildings place themselves
## on the free plot that suits them (the "near" key in buildings.json); they never
## land on a staked road and never where they would cut the hearth off from the
## wilds. Staking a road is free; stone-layers (craftspeople, once a building with
## "paves" stands) pave it a stretch at a time for stone. See data/town.json.

var w: World
var pathing: Pathing
## {ring, sector, a0, a1, r0, r1, pos, cells: PackedInt32Array, age, obstacle, building}
## building = index into World.buildings, or -1.
var plots: Array[Dictionary] = []
## Patches of scrub that slow walkers: {pos, radius}.
var thickets: Array[Dictionary] = []
## Staked roads in the order they were staked: {points: Array of Vector2, cells: PackedInt32Array}.
var roads: Array[Dictionary] = []
## How many staked roads cross each square.
var staked := PackedByteArray()
## Bumped whenever stakes change, so the road planner knows to look again.
var staked_version := 0
## Squares of road already paid for, per road kind (each payment covers a stretch).
var _paid := {}
var _plot_of := PackedInt32Array()  ## Square -> plot index, or -1.
var _planner := AStarGrid2D.new()
var _planner_seen := [-1, -1]  ## pathing.version and staked_version the planner was last set up for.


func _init(world: World) -> void:
	w = world
	pathing = w.pathing
	staked.resize(pathing.cells * pathing.cells)
	_plot_of.resize(pathing.cells * pathing.cells)
	_plot_of.fill(-1)
	_planner.region = pathing.astar.region
	_planner.cell_size = pathing.astar.cell_size
	_planner.offset = pathing.astar.offset
	_planner.diagonal_mode = AStarGrid2D.DIAGONAL_MODE_ONLY_IF_NO_OBSTACLES
	_planner.update()
	_make_plots()
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
			plots.append({"ring": ring, "sector": i / per_sector, "a0": a0, "a1": a0 + width,
				"r0": radius - depth / 2.0, "r1": radius + depth / 2.0,
				"pos": Vector2.from_angle(a0 + width / 2.0) * radius, "cells": PackedInt32Array(),
				"age": def.get("age", ""), "obstacle": "", "building": -1})
		for i in pathing.cells_in_circle(Vector2.ZERO, radius + depth / 2.0):
			var p := pathing.center(i)
			if p.length() < radius - depth / 2.0:
				continue
			var k := int(floor(fposmod(p.angle() - start, TAU) / width)) % count
			plots[first + k]["cells"].append(i)
			_plot_of[i] = first + k


## Boulders and old oaks already sit on a few plots of the opening rings.
func _place_obstacles() -> void:
	var rng := SeededRng.stream(w.run.run_seed, "obstacles")
	var ids: Array = w.content.town["obstacles"].keys()
	ids.sort()
	for id: String in ids:
		for n in int(w.content.town["obstacles"][id]["count"]):
			for attempt in 20:
				var k := rng.randi_range(0, plots.size() - 1)
				var plot := plots[k]
				if plot["obstacle"] != "" or plot["age"] != "" or not _keeps_town_open(k):
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


func ring_open(plot: Dictionary) -> bool:
	return w.content.age_reached(w.run.age, plot["age"])


## A plot nothing stands on, in an opened ring, with no staked road across it.
func plot_free(k: int) -> bool:
	var plot := plots[k]
	if plot["obstacle"] != "" or int(plot["building"]) >= 0 or not ring_open(plot):
		return false
	for i in plot["cells"]:
		if staked[i] > 0:
			return false
	return true


## The plot a new building of this type would go on, or -1 if there is none.
func choose_plot(type: String) -> int:
	var order: Array = []
	for k in plots.size():
		if plot_free(k):
			order.append([_plot_score(type, k), k])
	order.sort()
	for pair: Array in order:
		if _keeps_town_open(pair[1]):
			return pair[1]
	return -1


## Lower is better. Each building type says what it wants to be near in buildings.json:
## "hearth" (inner rings, the default), "outer" (outer rings), "warned_side" (outer rings
## facing this round's warned attack) or another building's id (beside one of those).
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
		"warned_side":
			score = (rings - 1 - ring) * 30.0
			var best := PI
			for side in w.wave_sides:
				best = minf(best, absf(angle_difference(side, (plot["pos"] as Vector2).angle())))
			score += best * 80.0
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


## Puts building index b on plot k: the plot turns solid.
func occupy(k: int, b: int) -> void:
	plots[k]["building"] = b
	_set_plot_solid(k, true)


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


# --- Staking roads ---------------------------------------------------------------

## The squares a road through these waypoints would cover: it bends round buildings and
## obstacles, prefers the lanes between rings and roads already staked, and cuts across
## free plots only where it has to. Empty if a waypoint can't be reached.
func route(points: Array) -> PackedInt32Array:
	var out := PackedInt32Array()
	if points.size() < 2:
		return out
	_refresh_planner()
	for n in points.size() - 1:
		var a := pathing.open_near(pathing.index_of(points[n]))
		var b := pathing.open_near(pathing.index_of(points[n + 1]))
		if pathing.is_solid(a) or pathing.is_solid(b):
			return PackedInt32Array()
		var ids := _planner.get_id_path(Vector2i(a % pathing.cells, a / pathing.cells), Vector2i(b % pathing.cells, b / pathing.cells))
		if ids.is_empty() and a != b:
			return PackedInt32Array()
		if ids.is_empty():
			ids = [Vector2i(a % pathing.cells, a / pathing.cells)]
		for c in ids:
			var i := c.y * pathing.cells + c.x
			if out.is_empty() or out[-1] != i:
				out.append(i)
	return out


func _refresh_planner() -> void:
	if _planner_seen == [pathing.version, staked_version]:
		return
	_planner_seen = [pathing.version, staked_version]
	_planner.fill_solid_region(_planner.region, false)
	_planner.fill_weight_scale_region(_planner.region, 1.0)
	for k in plots.size():
		var plot := plots[k]
		if not ring_open(plot):
			continue
		var solid: bool = plot["obstacle"] != "" or int(plot["building"]) >= 0
		for i in plot["cells"]:
			var c := Vector2i(i % pathing.cells, i / pathing.cells)
			if solid:
				_planner.set_point_solid(c, true)
			elif staked[i] == 0:
				_planner.set_point_weight_scale(c, 3.0)
	for road in roads:
		for i in road["cells"]:
			_planner.set_point_weight_scale(Vector2i(i % pathing.cells, i / pathing.cells), 0.6)


## Stakes out a road through the waypoints. Returns false if no road fits.
func stake(points: Array) -> bool:
	var cells := route(points)
	if cells.size() < 2:
		return false
	roads.append({"points": points.duplicate(), "cells": cells})
	for i in cells:
		staked[i] = mini(255, staked[i] + 1)
	staked_version += 1
	return true


## Pulls up the stakes of the last road. Stretches already paved stay paved.
func unstake_last() -> bool:
	if roads.is_empty():
		return false
	var road: Dictionary = roads.pop_back()
	for i in road["cells"]:
		staked[i] = maxi(0, staked[i] - 1)
	staked_version += 1
	return true


func staked_count() -> int:
	var n := 0
	for s in staked:
		if s > 0:
			n += 1
	return n


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


## The next staked square waiting to be paved (in the order roads were staked), skipping `taken`; -1 if none.
func next_to_pave(taken: Array) -> int:
	var best := best_road()
	if best < 0:
		return -1
	for road in roads:
		for i in road["cells"]:
			if pathing.ground[i] < best and not pathing.is_solid(i) and not taken.has(i):
				return i
	return -1


## True if the next stretch of the best road is already paid for or the town can pay for it
## and still keep "keep_in_stock" of each good for building.
func can_afford_paving() -> bool:
	var kind := best_road()
	return kind >= 0 and (int(_paid.get(kind, 0)) > 0 or _can_pay(road_def(kind)["cost"]))


func _can_pay(cost: Dictionary) -> bool:
	var keep := int(w.content.town["keep_in_stock"])
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
		w.run.note_paving(cost)
		_paid[kind] = int(w.content.town["stretch_cells"])
	_paid[kind] = int(_paid[kind]) - 1
	pathing.set_ground(i, kind)
	return true


## Squares of each road kind laid so far, by id.
func paved_counts() -> Dictionary:
	var out := {}
	for j in w.content.town["roads"].size():
		var n := pathing.count_ground(Pathing.FIRST_ROAD + j)
		if n > 0:
			out[pathing.kind_ids[Pathing.FIRST_ROAD + j]] = n
	return out
