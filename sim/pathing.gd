class_name Pathing
extends RefCounted
## The ground of the map as a grid of squares, and how units find their way across it.
##
## Each square is open or solid (a building, an obstacle) and has a kind of ground
## that sets how fast anyone walks over it: plain, thicket, a trail worn by feet, or
## a road the stone-layers paved. Units ask for the next point to head for and
## follow a cached route; routes are found with Godot's AStarGrid2D (headless and
## deterministic) and redone when the ground changes or the goal moves.
## Feet wear trails: walking adds to a square's traffic, and each dawn the busiest
## squares turn into trails while unused trails fade.
## Palisades: a square can hold a stretch of wall (or a gate where a road crosses one).
## Townsfolk and heroes climb over wall slowly and walk through gates; raiders get their own
## grid where wall and gates are costly, and batter them down when they walk into one
## (World.walk_toward).

## Ground kinds. Roads follow, one kind per entry in data/town.json "roads", in order.
const PLAIN := 0
const THICKET := 1
const TRAIL := 2
const FIRST_ROAD := 3
## Goals closer than this are walked to in a straight line.
const STRAIGHT_RANGE := 20.0

var cell: float
var cells: int  ## Squares per side.
var origin: Vector2  ## World position of the corner of square (0, 0).
var astar := AStarGrid2D.new()  ## Townsfolk and heroes: walls are slow to climb, gates open.
var enemy_astar := AStarGrid2D.new()  ## Raiders: walls and gates cost extra (time to batter through).
var solid := PackedByteArray()  ## 1 where a building or obstacle stands.
var wall_hp := PackedFloat32Array()  ## Health of the wall or gate on each square; 0 = none (or broken).
var gate := PackedByteArray()  ## 1 where a staked road crosses a staked wall.
var wall_detour := 0.0  ## Extra squares a raider walks to avoid one point of wall health.
var climb_speed := 1.0  ## Walking speed multiplier for townsfolk and heroes climbing over a palisade.
var ground := PackedByteArray()
var traffic := PackedFloat32Array()
var speeds := PackedFloat32Array()  ## Walking speed multiplier per ground kind.
var kind_ids: Array[String] = ["plain", "thicket", "trail"]  ## Ground kind index -> id (road ids after trail).
## Bumped whenever a square turns solid or open; cached routes older than this are redone.
var version := 0
## Bumped whenever a square's ground changes (routes still work, just not the fastest; drawing redraws).
var ground_version := 0
var _max_speed := 1.0
var _trail: Dictionary


func _init(content: Content) -> void:
	var town := content.town
	cell = float(town["cell"])
	var radius := content.num("world_radius")
	cells = int(ceil(radius * 2.0 / cell))
	origin = Vector2(-cells * cell / 2.0, -cells * cell / 2.0)
	for grid: AStarGrid2D in [astar, enemy_astar]:
		grid.region = Rect2i(0, 0, cells, cells)
		grid.cell_size = Vector2(cell, cell)
		grid.offset = origin + Vector2(cell, cell) / 2.0
		grid.diagonal_mode = AStarGrid2D.DIAGONAL_MODE_ONLY_IF_NO_OBSTACLES
		grid.default_compute_heuristic = AStarGrid2D.HEURISTIC_EUCLIDEAN
		grid.default_estimate_heuristic = AStarGrid2D.HEURISTIC_EUCLIDEAN
		grid.update()
	ground.resize(cells * cells)
	traffic.resize(cells * cells)
	solid.resize(cells * cells)
	wall_hp.resize(cells * cells)
	gate.resize(cells * cells)
	wall_detour = float(town["palisade"]["raider_detour"])
	climb_speed = float(town["palisade"]["climb_speed"])
	_trail = town["trail"]
	speeds = PackedFloat32Array([1.0, float(town["thickets"]["speed"]), float(_trail["speed"])])
	for id: String in town["roads"]:
		kind_ids.append(id)
		speeds.append(float(town["roads"][id]["speed"]))
	for s in speeds:
		_max_speed = maxf(_max_speed, s)
	# Weights are relative to the fastest ground so the distance estimate never overshoots.
	astar.fill_weight_scale_region(astar.region, _max_speed)
	enemy_astar.fill_weight_scale_region(enemy_astar.region, _max_speed)


# --- Squares -----------------------------------------------------------------

func cell_of(p: Vector2) -> Vector2i:
	var c := Vector2i(floori((p.x - origin.x) / cell), floori((p.y - origin.y) / cell))
	return c.clamp(Vector2i.ZERO, Vector2i(cells - 1, cells - 1))


func index_of(p: Vector2) -> int:
	var c := cell_of(p)
	return c.y * cells + c.x


func center(i: int) -> Vector2:
	return origin + (Vector2(_cell_at(i)) + Vector2(0.5, 0.5)) * cell


func _cell_at(i: int) -> Vector2i:
	return Vector2i(i % cells, i / cells)


## True where a building or obstacle stands (walls don't count).
func is_solid(i: int) -> bool:
	return solid[i] == 1


## True if this square stops a walker: anything solid, and for raiders any standing wall or
## gate (they batter it). Townsfolk and heroes climb over walls instead (see walk_speed).
func blocks(i: int, enemy: bool) -> bool:
	return solid[i] == 1 or (enemy and wall_hp[i] > 0.0)


## True if a townsperson or hero has to climb to cross this square (standing wall, not a gate).
func climb(i: int) -> bool:
	return wall_hp[i] > 0.0 and gate[i] == 0


func set_solid(i: int, value: bool) -> void:
	if is_solid(i) == value:
		return
	solid[i] = 1 if value else 0
	if value:
		set_ground(i, PLAIN)
		traffic[i] = 0.0
	_sync(i)


func set_ground(i: int, kind: int) -> void:
	if ground[i] == kind:
		return
	ground[i] = kind
	_sync_weights(i)
	ground_version += 1


## Puts up (hp > 0) or takes down (hp 0) a stretch of wall on square i; is_gate opens it to townsfolk and heroes.
func set_wall(i: int, hp: float, is_gate: bool) -> void:
	var was := [wall_hp[i] > 0.0, gate[i]]
	wall_hp[i] = maxf(0.0, hp)
	gate[i] = 1 if is_gate else 0
	if hp > 0.0:
		traffic[i] = 0.0
	if was != [wall_hp[i] > 0.0, gate[i]]:
		_sync(i)
		ground_version += 1


## A raider's blow on the wall at square i. Returns true if it broke.
func hit_wall(i: int, amount: float) -> bool:
	if wall_hp[i] <= 0.0:
		return false
	wall_hp[i] -= amount
	if wall_hp[i] > 0.0:
		return false
	set_wall(i, 0.0, gate[i] == 1)
	return true


func _sync(i: int) -> void:
	var c := _cell_at(i)
	astar.set_point_solid(c, solid[i] == 1)
	enemy_astar.set_point_solid(c, solid[i] == 1)
	_sync_weights(i)
	version += 1


func _sync_weights(i: int) -> void:
	var c := _cell_at(i)
	var base := _max_speed / speeds[ground[i]]
	astar.set_point_weight_scale(c, _max_speed / climb_speed if climb(i) else base)
	enemy_astar.set_point_weight_scale(c, base + (wall_hp[i] * wall_detour * _max_speed if wall_hp[i] > 0.0 else 0.0))


## Walking speed multiplier at a point.
func speed_at(p: Vector2, enemy := false) -> float:
	return walk_speed(index_of(p), enemy)


## Walking speed multiplier on square i: the ground's, or climbing speed over a palisade for townsfolk and heroes.
func walk_speed(i: int, enemy: bool) -> float:
	return climb_speed if not enemy and climb(i) else speeds[ground[i]]


func is_road(i: int) -> bool:
	return ground[i] >= FIRST_ROAD


## Square indices whose centres lie inside a circle.
func cells_in_circle(at: Vector2, radius: float) -> PackedInt32Array:
	var out := PackedInt32Array()
	var lo := cell_of(at - Vector2(radius, radius))
	var hi := cell_of(at + Vector2(radius, radius))
	for y in range(lo.y, hi.y + 1):
		for x in range(lo.x, hi.x + 1):
			var i := y * cells + x
			if center(i).distance_to(at) <= radius:
				out.append(i)
	return out


## The nearest open square to square i (i itself if open), searching outward a few squares.
func open_near(i: int, enemy := false) -> int:
	if not _closed(i, enemy):
		return i
	var c := _cell_at(i)
	for r in range(1, 8):
		var best := -1
		var best_d := INF
		for y in range(c.y - r, c.y + r + 1):
			for x in range(c.x - r, c.x + r + 1):
				if x < 0 or y < 0 or x >= cells or y >= cells or maxi(absi(x - c.x), absi(y - c.y)) != r:
					continue
				var j := y * cells + x
				var d := Vector2(x - c.x, y - c.y).length_squared()
				if not _closed(j, enemy) and d < best_d:
					best_d = d
					best = j
		if best >= 0:
			return best
	return i


## Squares a route can't end on: solid for raiders (they route through walls), blocked for the rest.
func _closed(i: int, enemy: bool) -> bool:
	return solid[i] == 1 if enemy else blocks(i, false)


# --- Routes ------------------------------------------------------------------

## A route of square centres from one point to another, going round solid squares
## and preferring fast ground. A goal inside something solid (a building) gets a route
## to the nearest open square; the unit walks the last bit straight in.
func find_path(from: Vector2, to: Vector2, enemy := false) -> PackedVector2Array:
	var a := open_near(index_of(from), enemy)
	var b := open_near(index_of(to), enemy)
	if a == b or _closed(a, enemy) or _closed(b, enemy):
		return PackedVector2Array()
	return (enemy_astar if enemy else astar).get_point_path(_cell_at(a), _cell_at(b))


## True if a route joins the two points without going through anything solid.
func connected(from: Vector2, to: Vector2) -> bool:
	var a := open_near(index_of(from))
	var b := open_near(index_of(to))
	if a == b:
		return true
	return not astar.get_id_path(_cell_at(a), _cell_at(b), false).is_empty()


## The point a unit should head for next on its way to `goal`. In plain sight on even
## ground it is the goal itself; otherwise the next point of a cached route, redone when
## the town changes or the goal has moved a fair way. An empty cached route means "straight".
func next_point(unit: Unit, goal: Vector2) -> Vector2:
	var dist := unit.pos.distance_to(goal)
	var enemy := unit.is_enemy()
	if dist <= STRAIGHT_RANGE:
		return goal
	if unit.path_version != version or unit.path_goal.distance_to(goal) > maxf(10.0, dist * 0.2) \
			or (not unit.path.is_empty() and unit.path_index >= unit.path.size()):
		unit.path_goal = goal
		unit.path_version = version
		unit.path_index = 0
		unit.path = find_path(unit.pos, goal, enemy)
		# Walk straight when that is at least as quick as the route (open ground, or a road that isn't worth the detour).
		if _line_time(unit.pos, goal, enemy) <= _route_time(unit.pos, unit.path, goal, enemy) * 1.02:
			unit.path = PackedVector2Array()
		if unit.path.size() > 1:
			unit.path_index = 1
	if unit.path.is_empty():
		return goal
	var advanced := false
	while unit.path_index < unit.path.size() and unit.pos.distance_to(unit.path[unit.path_index]) < cell * 0.6:
		unit.path_index += 1
		advanced = true
	if advanced or unit.path_index <= 1:
		# Cut corners: head for the farthest of the next few points that is in plain sight on the same ground.
		var ahead := mini(unit.path_index + 4, unit.path.size() - 1)
		while ahead > unit.path_index and not _clear_line(unit.pos, unit.path[ahead], enemy):
			ahead -= 1
		unit.path_index = maxi(unit.path_index, ahead)
	if unit.path_index >= unit.path.size():
		return goal
	return unit.path[unit.path_index]


## Time (in distance-at-normal-speed units) to walk straight from a to b; INF if something solid
## (or a wall) is in the way.
func _line_time(a: Vector2, b: Vector2, enemy := false) -> float:
	var steps := maxi(1, ceili(a.distance_to(b) / (cell * 0.5)))
	var piece := a.distance_to(b) / steps
	var total := 0.0
	for k in range(1, steps + 1):
		var i := index_of(a.lerp(b, float(k) / steps))
		if blocks(i, enemy) and (k < steps or wall_hp[i] > 0.0):
			return INF
		total += piece / walk_speed(i, enemy)
	return total


## Time to walk a route of square centres from a, then on to the goal; INF for no route.
func _route_time(a: Vector2, route: PackedVector2Array, goal: Vector2, enemy := false) -> float:
	if route.is_empty():
		return INF
	var total := 0.0
	var at := a
	for p in route:
		total += at.distance_to(p) / walk_speed(index_of(p), enemy)
		at = p
	return total + at.distance_to(goal) / walk_speed(index_of(goal), enemy)


## True if the straight line between two points crosses nothing solid and stays on one kind of ground
## (a palisade to climb counts as its own kind).
func _clear_line(a: Vector2, b: Vector2, enemy := false) -> bool:
	var kind := _kind(index_of(a), enemy)
	var steps := ceili(a.distance_to(b) / (cell * 0.5))
	for k in range(1, steps + 1):
		var i := index_of(a.lerp(b, float(k) / steps))
		if blocks(i, enemy) or _kind(i, enemy) != kind:
			return false
	return true


func _kind(i: int, enemy: bool) -> int:
	return -1 if not enemy and climb(i) else ground[i]


# --- Trails --------------------------------------------------------------------

## Someone walked over this point for dt seconds.
func tread(p: Vector2, dt: float) -> void:
	traffic[index_of(p)] += dt


## At dawn: busy squares become trails, idle trails fade, and traffic counts decay.
## Returns how many squares changed.
func wear_trails() -> int:
	var need := float(_trail["traffic"])
	var decay := float(_trail["decay"])
	var changed := 0
	for i in traffic.size():
		var t := traffic[i]
		if t <= 0.0 and ground[i] != TRAIL:
			continue
		if t >= need and ground[i] <= TRAIL and ground[i] != TRAIL and not is_solid(i):
			set_ground(i, TRAIL)
			changed += 1
		elif ground[i] == TRAIL and t < need * 0.25:
			set_ground(i, PLAIN)
			changed += 1
		traffic[i] = t * decay
	return changed


func count_ground(kind: int) -> int:
	var n := 0
	for g in ground:
		if g == kind:
			n += 1
	return n
