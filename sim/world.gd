class_name World
extends RefCounted
## The map and everything living on it, simulated in fixed time steps.
##
## The hearth sits at (0, 0). Resource nodes ring the settlement, dens sit far
## out in the wilds, and waves arrive from the map edge on warned sides.
## A round is several days; each day is followed by a night, and the round's
## wave comes on the last night. Nobody here takes orders: townsfolk do their
## jobs, heroes follow their personalities, enemies hunt whatever is close.
## RunState pauses the world at each dawn (for the newcomer pick) and when the
## round's last night is over.

const HEARTH_RADIUS := 34.0
const HOME_RADIUS := 60.0
const HEAL_UNTIL := 0.85
const TARGET_STICKINESS := 3.0
const FLEE_DISTANCE := 70.0

enum Pause { NONE, DAWN, ROUND_OVER, HEARTH_LOST }

var run: RunState
var content: Content
var rng: SeededRng
var dt: float

var hearth_hp := 0.0
var hearth_cooldown_left := 0.0
var nodes: Array[Dictionary] = []  ## {type, gives, pos, amount, max, heroes_only, wild, age}
## {type, spawns, pos, respawn_left}; the war camp (at most one, always last) also has camp, joined, cleared.
var dens: Array[Dictionary] = []
## The ground and how units find their way (see Pathing), and the town's plots, gates and paving (see Town).
var pathing: Pathing
var town: Town
## The earth plates past the town, which turn between rounds (see Earth).
var earth: Earth
## {type, plot, pos, work_left, cooldown_left, goods (stalls), craft, craft_left, craft_tier, made (workshops)}
var buildings: Array[Dictionary] = []

var folk: Array[Unit] = []
var enemies: Array[Unit] = []

## Seconds since this round's first dawn.
var time := 0.0
var wave_sides: Array[float] = []
## Per wave side, the den type the warband marches past, or "" for open country. The warband comes by the dens'
## ways, so as the earth carries the dens round, the attack comes round with them.
var wave_side_dens: Array[String] = []
var wave_spawned := false
var pause := Pause.NONE
var cold_tonight := false

## Recent attacks for drawing: {from: Vector2, to: Vector2, ranged: bool, time: float}, and tower: true on the hearth's and watch posts' shots.
var shots: Array[Dictionary] = []
## Facts for this round's record.
var deaths: Array[Dictionary] = []
var wave_stats := {}
## What happened since the last dawn pick: {raiders, kills, hearth_damage, deaths: [names], left: [names]}.
## RunState reads it at each dawn and at the end of the round.
var night_report := {}
## Relic rules that count per night: skeletons raised and raiders turned (reset at nightfall).
var risen_tonight := 0
var turncoats_tonight := 0
## Townsfolk joining mid-step (turncoats, the risen), added once everyone has acted.
var _joining: Array[Dictionary] = []
## Enemies chasing a fleeing worker (seen last tick); warriors answer the call.
var alarms: Array[Unit] = []
var new_alarms: Array[Unit] = []
## Goods carried back to the hearth so far this run, by good: townsfolk hauls and what heroes bring in from the
## wilds (`bring_in`). Only grows. The view reads it for the "+2 stone" popups over the hearth.
var brought_in := {}
## Runners' deliveries to heroes in the wilds, newest last ({pos, text}), at most SUPPLY_DROPS_KEPT, and how many
## there have been this run. The view reads them for the popups where supplies land.
var supply_drops: Array[Dictionary] = []
var supplies_delivered := 0
const SUPPLY_DROPS_KEPT := 8
## The last enemy to fall: {pos, type, boss, invader (a raider, not a den wanderer), by (who felled it, or ""), time},
## {} before any. The view reads it to make the night's last kill land (LastKill); no rule does.
var last_felled := {}
## Quick defences (data/town.json barricades): {plot, pos, work_left, built, broken, cost} per barricade thrown up
## since dawn, the barricade on each walled square (square index -> index into barricades), and the ways the alarm
## has been raised from since dawn (angles). All cleared at dawn (Town.clear_barricades).
var barricades: Array[Dictionary] = []
var barricade_square := {}
var alarm_ways: Array[float] = []
## Recent spottings for the view: {by (where the spotter stood), at (the raider), time}. No rule reads it.
var spots: Array[Dictionary] = []
## The routes the warned attack would take tonight (route_preview), cached until the ground or the ways change.
var _routes: Array = []
var _routes_seen := []

## Where enemies and friends (townsfolk and heroes) stand, for fast nearest-unit lookups (see UnitGrid).
## Rebuilt each step when those units stop moving; a stale grid is never read (the lookups scan the lists instead).
var _enemy_grid: UnitGrid
var _friend_grid: UnitGrid
var _enemy_grid_ok := false
var _friend_grid_ok := false

## The world's behaviour is split by who acts; each part reads and changes this World's state.
var folk_ai: FolkAI
var hero_ai: HeroAI
var market: Market
var enemy_ai: EnemyAI
var pedlar: PedlarCamp
## Effects of the finished buildings that carry "effects" (data/buildings.json), summed; RunState.mod() adds them in.
var building_effects := {}
## plate_knobs from standing buildings ({tag: {knob: add}}, Earth.kind_def); a new dict whenever they change.
var building_plate_knobs := {}


func _init(run_state: RunState) -> void:
	run = run_state
	content = run.content
	folk_ai = FolkAI.new(self)
	hero_ai = HeroAI.new(self)
	market = Market.new(self)
	enemy_ai = EnemyAI.new(self)
	pedlar = PedlarCamp.new(self)
	rng = SeededRng.stream(run.run_seed, "world")
	dt = 1.0 / content.num("ticks_per_second")
	hearth_hp = run.hearth_max_hp()
	pathing = Pathing.new(content)
	_enemy_grid = UnitGrid.new(content.num("world_radius"))
	_friend_grid = UnitGrid.new(content.num("world_radius"))
	town = Town.new(self)
	_place_nodes()
	_place_dens()
	_place_den_nodes()
	earth = Earth.new(self)
	reset_night_report()


# --- Clock -----------------------------------------------------------------

func day_length() -> float:
	return content.num("day_seconds") + content.num("night_seconds")


## 0-based day within the round.
func day_index() -> int:
	return mini(int(time / day_length()), content.int_num("days_per_round") - 1)


func time_of_day() -> float:
	return time - day_index() * day_length()


func is_night() -> bool:
	return time_of_day() >= content.num("day_seconds")


func is_dusk() -> bool:
	var t := time_of_day()
	return is_night() or t >= content.num("day_seconds") - content.num("dusk_seconds")


func is_wave_night() -> bool:
	return is_night() and day_index() == content.int_num("days_per_round") - 1


## Called by RunState when a new round starts (after building, before the first pick).
func start_round() -> void:
	time = 0.0
	wave_spawned = false
	deaths = []
	wave_stats = {"seconds": 0.0, "keep_damage": 0.0, "hero_deaths": [], "retreats": 0, "hearth_hp_before": hearth_hp}
	reset_night_report()
	folk_ai.start_round()
	for den in dens:
		den["respawn_left"] = 0.0
	pause = Pause.NONE


func reset_night_report() -> void:
	night_report = {"raiders": 0, "kills": 0, "hearth_damage": 0.0, "deaths": [], "left": [], "heroes_left": [],
		"hero_deaths": 0, "cold": false}


## Decides (reproducibly) which sides this round's wave comes from, so it can be warned of. The warband marches
## by the way of a den still standing (or the war camp), from wherever the earth has carried it; once no den is
## left on a free side, it comes from open country on a compass side.
func roll_wave_sides() -> void:
	wave_sides = []
	wave_side_dens = []
	var side_rng := SeededRng.stream(run.run_seed, "sides", run.round_number)
	var side_count := 2 if run.round_number >= content.int_num("wave_two_sides_from_round") and not run.has_effect("one_side") else 1
	var apart := deg_to_rad(content.num("wave_sides_apart"))
	var ways: Array = dens.filter(func(d: Dictionary) -> bool: return not d.get("cleared", false))
	while wave_sides.size() < side_count:
		var free := ways.filter(func(d: Dictionary) -> bool: return _side_free(Vector2(d["pos"]).angle(), apart))
		if not free.is_empty():
			var den: Dictionary = side_rng.pick(free)
			ways.erase(den)
			wave_sides.append(Vector2(den["pos"]).angle())
			wave_side_dens.append(den["type"])
			continue
		var compass: Array = [0, 1, 2, 3].map(func(q: int) -> float: return q * PI / 2.0).filter(
			func(a: float) -> bool: return _side_free(a, apart))
		wave_sides.append(side_rng.pick(compass))
		wave_side_dens.append("")


func _side_free(angle: float, apart: float) -> bool:
	return wave_sides.all(func(s: float) -> bool: return absf(angle_difference(s, angle)) >= apart)


## The compass name of a direction from the hearth (east is angle 0, south is a quarter turn on: y points down).
static func compass(angle: float) -> String:
	return ["east", "south-east", "south", "south-west", "west", "north-west", "north", "north-east"][posmod(roundi(angle / (PI / 4.0)), 8)]


## The way each of this round's warned sides would come in tonight, as the raiders' own pathfinding sees the
## ground now (Pathing.route_preview from the map's edge to the hearth): one point list per side. The view draws
## it; no rule reads it. Cached until the town's squares, its gates or the ways change.
func raider_routes() -> Array:
	var seen := [pathing.version, pathing.ground_version, wave_sides.duplicate()]
	if seen != _routes_seen:
		_routes_seen = seen
		_routes = []
		for side in wave_sides:
			_routes.append(pathing.route_preview(Vector2.from_angle(side) * content.num("world_radius") * 0.98, Vector2.ZERO))
	return _routes


## The wave side names, for the UI and story.
func side_names() -> Array[String]:
	var names: Array[String] = []
	for angle in wave_sides:
		names.append(compass(angle))
	return names


# --- Step ------------------------------------------------------------------

func step() -> void:
	if pause != Pause.NONE:
		return
	var was_night := is_night()
	var was_dusk := is_dusk()
	var old_day := day_index()
	time += dt
	if is_dusk() and not was_dusk and day_index() == content.int_num("days_per_round") - 1 and run.has_effect("dusk_stakes"):
		folk_ai.stake_the_way()
	if is_night() and not was_night:
		_nightfall()
	if is_wave_night() and not wave_spawned:
		enemy_ai.spawn_wave()
	var night_end := float(content.int_num("days_per_round")) * day_length()
	if day_index() != old_day:
		_dawn()
		return
	if wave_spawned:
		wave_stats["seconds"] = time - (night_end - content.num("night_seconds"))

	alarms = new_alarms
	new_alarms = []
	market.refresh_prizes()
	market.outposts_tick()
	pedlar.tick()
	enemy_ai.dens_tick()
	for enemy in enemies:
		if not enemy.spawned and time >= enemy.spawn_time:
			enemy.spawned = true
	# Enemies stand still while townsfolk and heroes act, and they stand still while enemies act.
	folk_ai.begin_step()
	pathing.reroutes_left = Pathing.REROUTES_PER_STEP
	_enemy_grid.rebuild(enemies)
	_enemy_grid_ok = true
	for unit in folk:
		if unit.alive:
			folk_ai.folk_tick(unit)
	for hero in run.heroes:
		if hero.alive:
			hero_ai.hero_tick(hero)
	_enemy_grid_ok = false
	_friend_grid.rebuild(folk + run.heroes)
	_friend_grid_ok = true
	for enemy in enemies:
		if enemy.alive and enemy.spawned:
			enemy_ai.enemy_tick(enemy)
	enemy_ai.spot_tick()
	_friend_grid_ok = false
	enemy_ai.towers_tick()
	_cleanup()
	_join_folk()
	shots = shots.filter(func(s: Dictionary) -> bool: return time - float(s["time"]) < 0.25)

	if hearth_hp <= 0.0 or (folk.is_empty() and not run.heroes.any(func(h: Unit) -> bool: return h.alive)):
		pause = Pause.HEARTH_LOST
		return
	if time >= night_end:
		var wave_left := enemies.filter(func(e: Unit) -> bool: return e.alive and e.den_index < 0)
		if wave_left.is_empty() or time >= night_end + content.num("night_seconds") * 2.0:
			for e in wave_left:
				run.record.note_impact("defences", "hearth", "taken", minf(e.attack * 3.0, maxf(0.0, hearth_hp)))
				hearth_hp -= e.attack * 3.0
				e.alive = false
			if not wave_left.is_empty():
				run.tell("The last raiders loot the edge of town and slip away.", RunState.PROBLEM)
			_finish_round()


func _nightfall() -> void:
	risen_tonight = 0
	turncoats_tonight = 0
	var need := run.fuel_needed_tonight()
	cold_tonight = false
	if int(run.stock["fuel"]) >= need:
		run.stock["fuel"] = int(run.stock["fuel"]) - need
	else:
		var short := need - int(run.stock["fuel"])
		run.stock["fuel"] = 0
		var wood := mini(short, int(run.stock["wood"])) if content.balance.get("wood_burns_as_fuel", false) else 0
		if wood > 0:
			run.stock["wood"] = int(run.stock["wood"]) - wood
			run.tell("Out of fuel: %d wood goes on the fire instead." % wood, RunState.PROBLEM)
		if wood < short:
			cold_tonight = true
			night_report["cold"] = true
			run.tell("The fire burns low. A cold night: everyone suffers.", RunState.PROBLEM)
	if is_wave_night():
		run.tell("Night %d falls. The warned attack is coming from the %s." % [day_index() + 1, " and ".join(side_names())])
		var spears := folk.filter(func(u: Unit) -> bool: return u.alive and folk_ai.levied(u)).size()
		if spears > 0 and run.has_effect("muster"):
			run.record.note_count("mustered", spears)
			run.tell("%d tribespeople take up spears beside the warriors." % spears)
	else:
		run.tell("Night %d falls." % (day_index() + 1), RunState.AMBIENT)
		enemy_ai.spawn_probe()


func _end_of_night_effects() -> void:
	if cold_tonight:
		for unit in folk + run.heroes:
			if unit.alive:
				unit.hp = maxf(1.0, unit.hp - unit.max_hp * content.num("cold_night_damage"))
	cold_tonight = false


func _dawn() -> void:
	_end_of_night_effects()
	_lay_risen()
	var stayed := enemies.filter(func(e: Unit) -> bool: return e.alive and e.is_probe)
	if not stayed.is_empty():
		run.tell("At first light the last %d raiders slip back into the wilds." % stayed.size())
	enemies = enemies.filter(func(e: Unit) -> bool: return not e.is_probe)
	for node in nodes:
		if regrows(node):
			node["amount"] = mini(int(node["max"]), int(node["amount"]) + content.int_num("node_regrow_per_day"))
	_tend_nodes()
	earth.dawn()
	pathing.wear_trails()
	town.clear_barricades()
	town.patch_walls()
	enemy_ai.mend_towers()
	pedlar.hire_guards()
	market.outposts_dawn()
	hero_ai.kennel_dawn()
	hero_ai.duels_dawn()
	run.daily_upkeep()
	for b in buildings:
		b["assisted"] = 0.0
	pause = Pause.DAWN


## Buildings that tend nodes ("tends" in buildings.json): each dawn every node carrying their tag within
## their radius regrows a share of its full size, once per such building.
## Nodes a trades guild works ("guild_tend", FolkAI._guild_drain) regrow their share too, until full.
func _tend_nodes() -> void:
	for node in nodes:
		var share := float(node.get("guild_tend", 0.0))
		if share <= 0.0:
			continue
		var before := int(node["amount"])
		if before >= int(node["max"]):
			node.erase("guild_tend")
			continue
		node["amount"] = mini(int(node["max"]), before + maxi(1, roundi(float(node["max"]) * share)))
		run.record.note_count("tended", int(node["amount"]) - before, node["gives"])
		run.record.note_count("guild_tended", int(node["amount"]) - before, node["gives"])
	for b in buildings:
		var tends := tending(b["type"])
		if tends.is_empty() or float(b["work_left"]) > 0.0:
			continue
		for node in nodes:
			if tends_node(tends, b["pos"], node):
				var before := int(node["amount"])
				node["amount"] = mini(int(node["max"]), before + maxi(1, roundi(float(node["max"]) * float(tends["share"]))))
				run.record.note_count("tended", int(node["amount"]) - before, node["gives"])


## A building type's "tends" ({} if it has none, or its share is 0 until an upgrade raises it).
func tending(type: String) -> Dictionary:
	var tends: Dictionary = content.buildings[type].get("tends", {})
	return tends if float(tends.get("share", 0.0)) > 0.0 else {}


## Whether a building's "tends" from pos reaches this node.
func tends_node(tends: Dictionary, pos: Vector2, node: Dictionary) -> bool:
	return content.has_tag("node", node["type"], tends["tag"]) and node_active(node) \
		and pos.distance_to(node["pos"]) <= float(tends["radius"])


## How much a node regrows each dawn: node_regrow_per_day, plus what buildings tending it add.
func node_regrowth(node: Dictionary) -> int:
	if not regrows(node):
		return 0
	var total := content.int_num("node_regrow_per_day")
	for b in buildings:
		var tends := tending(b["type"])
		if not tends.is_empty() and float(b["work_left"]) <= 0.0 and tends_node(tends, b["pos"], node):
			total += maxi(1, roundi(float(node["max"]) * float(tends["share"])))
	return total


## How full the nodes carrying a tag are, 0 to 1 (1 when there are none).
func nodes_fullness(tag: String) -> float:
	var amount := 0
	var full := 0
	for node in nodes:
		if content.has_tag("node", node["type"], tag) and node_active(node):
			amount += int(node["amount"])
			full += int(node["max"])
	return float(amount) / full if full > 0 else 1.0


func _finish_round() -> void:
	_end_of_night_effects()
	# Hired blades (Trade path tier II) take their pay and go at the round's end.
	var hired := folk.filter(func(u: Unit) -> bool: return u.hired)
	if not hired.is_empty():
		folk = folk.filter(func(u: Unit) -> bool: return not u.hired)
		var alive := hired.filter(func(u: Unit) -> bool: return u.alive).size()
		run.record.note_count("hired_blades", alive)
		if alive > 0:
			run.tell("The hired blades take their pay and ride south with the caravan.", RunState.AMBIENT)
	_lay_risen()
	# Wanderers slink back to their dens at the end of a round.
	enemies = enemies.filter(func(e: Unit) -> bool: return e.alive and e.den_index >= 0)
	pause = Pause.ROUND_OVER


## Lets the world run again after a dawn pause.
func resume() -> void:
	if pause == Pause.DAWN:
		pause = Pause.NONE


# --- Map -------------------------------------------------------------------

func _place_nodes() -> void:
	var ids: Array = content.world["nodes"].keys()
	ids.sort()
	# Later ages' nodes use their own random stream, so adding them leaves the stone-age map as it was.
	var age_rng := SeededRng.stream(run.run_seed, "age_nodes")
	for id: String in ids:
		var def: Dictionary = content.world["nodes"][id]
		if def.get("near_dens", false):
			continue
		var r := age_rng if def.has("age") else rng
		var lo := float(def.get("min_distance", content.num("node_min_distance")))
		var hi := float(def.get("max_distance", content.num("node_max_distance")))
		for i in int(def["count"]):
			# Spread each type around the circle, nearer and farther out.
			var angle := TAU * (i + r.randf()) / float(def["count"])
			var dist := lerpf(lo, hi, (i + r.randf()) / float(def["count"]))
			_add_node(id, Vector2.from_angle(angle) * dist)


## Nodes that sit by the dens (cassiterite veins): one per den, between the den and the camp.
func _place_den_nodes() -> void:
	var ids: Array = content.world["nodes"].keys()
	ids.sort()
	var den_rng := SeededRng.stream(run.run_seed, "den_nodes")
	for id: String in ids:
		var def: Dictionary = content.world["nodes"][id]
		if not def.get("near_dens", false):
			continue
		for i in mini(int(def["count"]), dens.size()):
			var den_pos: Vector2 = dens[i]["pos"]
			var at := den_pos * 0.82 + Vector2.from_angle(den_rng.randf() * TAU) * 30.0
			_add_node(id, at)


func _add_node(id: String, at: Vector2) -> void:
	var def: Dictionary = content.world["nodes"][id]
	nodes.append({"type": id, "gives": def["gives"], "pos": at, "amount": int(def["amount"]), "max": int(def["amount"]),
		"heroes_only": def.get("heroes_only", false), "wild": def.get("wild", false), "age": def.get("age", "")})


## A node counts once the town has reached its age, until the shifting earth takes it away.
## Goods carried back to the hearth go into stock and the `brought_in` tally.
func bring_in(good: String, n: int) -> void:
	run.stock[good] = int(run.stock[good]) + n
	brought_in[good] = int(brought_in.get(good, 0)) + n


func node_active(node: Dictionary) -> bool:
	return not node.get("gone", false) and content.age_reached(run.age, node.get("age", ""))


## False for nodes that never grow back ("regrows": false in world.json, like seam embers).
func regrows(node: Dictionary) -> bool:
	return bool(content.world["nodes"][node["type"]].get("regrows", true))


## Townsfolk only go to a wild node when no monster is anywhere near it, and never to one the war camp holds.
func node_safe(node: Dictionary) -> bool:
	if held_by_camp(node):
		return false
	return not node.get("wild", false) or nearest_enemy(node["pos"], float(content.world["wild_safe_radius"])) == null


## The war camp's index in dens, or -1 when there is none.
func camp_index() -> int:
	if not dens.is_empty() and dens[-1].get("camp", false) and not dens[-1].get("cleared", false):
		return dens.size() - 1
	return -1


## True while the war camp sits close enough to a node that townsfolk won't gather it.
func held_by_camp(node: Dictionary) -> bool:
	var ci := camp_index()
	return ci >= 0 and node["pos"].distance_to(dens[ci]["pos"]) <= content.num("camp_hold_radius")


func _place_dens() -> void:
	var ids: Array = content.world["dens"].keys()
	ids.sort()
	var start := rng.randf() * TAU
	ids = ids.filter(func(id: String) -> bool: return not content.world["dens"][id].get("camp", false))
	for i in content.int_num("den_count"):
		var id: String = ids[i % ids.size()]
		var angle := start + TAU * i / content.num("den_count") + rng.randf_range(-0.4, 0.4)
		var dist := rng.randf_range(content.num("den_min_distance"), content.num("den_max_distance"))
		dens.append({"type": id, "spawns": content.world["dens"][id]["spawns"],
			"pos": Vector2.from_angle(angle) * dist, "respawn_left": 0.0})


## Orders a building: it goes on the free plot that suits it (see Town.choose_plot). False if none is left.
func add_building(type: String) -> bool:
	if content.buildings[type].has("outpost"):
		return market.add_outpost(type)
	var plot := town.choose_plot(type)
	if plot < 0:
		return false
	buildings.append({"type": type, "plot": plot, "pos": town.plots[plot]["pos"],
		"work_left": float(content.buildings[type]["work"]), "cooldown_left": 0.0,
		"hp": float(content.buildings[type].get("tower_hp", 0.0)),
		"goods": [], "craft": "", "craft_left": 0.0, "craft_tier": 1, "made": 0})
	town.occupy(plot, buildings.size() - 1)
	return true


## True if building type has somewhere to go now: a free plot, or for an outpost a node to stand by.
func has_spot(type: String) -> bool:
	if content.buildings[type].has("outpost"):
		return market.outpost_node(type) >= 0
	return town.choose_plot(type) >= 0


func count_buildings(type: String, built_only := true) -> int:
	return buildings.filter(func(b: Dictionary) -> bool:
		return b["type"] == type and (not built_only or float(b["work_left"]) <= 0.0)).size()


func night_key() -> int:
	return run.round_number * 10 + day_index()


func first_built(type: String) -> int:
	for i in buildings.size():
		if buildings[i]["type"] == type and float(buildings[i]["work_left"]) <= 0.0:
			return i
	return -1


# --- Shared: movement, combat and lookups used by every part ---------------

## Moves toward a goal along a route round buildings, faster on trails and roads; returns true
## once within `close` of it. Townsfolk and heroes wear desire paths as they go and walk
## through gates; a raider that walks into a gate stops to batter it instead.
func walk_toward(unit: Unit, goal: Vector2, close := 2.0) -> bool:
	var to_goal := goal - unit.pos
	if to_goal.length() <= close:
		return true
	var step_len := unit.speed * dt * pathing.speed_at(unit.pos, unit.is_enemy()) * earth.walk_factor(unit.pos, unit.is_enemy())
	if unit.escorted:
		step_len *= 1.0 + float(content.townsfolk["warrior"]["escort_speed"])
	var here := pathing.index_of(unit.pos)
	if not unit.is_enemy():
		pathing.tread(unit.pos, dt)
	var aim := pathing.next_point(unit, goal)
	if aim == goal and to_goal.length() - close <= step_len:
		unit.pos = goal - to_goal.normalized() * close
		return true
	var to_aim := aim - unit.pos
	var next := unit.pos + (to_aim.normalized() * minf(step_len, to_aim.length()) if to_aim.length() > 0.0 else Vector2.ZERO)
	if unit.is_enemy():
		var ahead := pathing.index_of(next)
		if ahead != here and pathing.wall_hp[ahead] > 0.0:
			_batter(unit, ahead)
			return false
	unit.pos = next.limit_length(content.num("world_radius"))
	return false


## A raider strikes the gate in its way.
func _batter(unit: Unit, square: int) -> void:
	if unit.cooldown_left > 0.0:
		return
	unit.cooldown_left = unit.cooldown
	shots.append({"from": unit.pos, "to": pathing.center(square), "ranged": false, "time": time})
	if content.unit_has_tag(unit, "siege"):
		run.record.note_count("siege_damage", roundi(unit.attack * enemy_ai.war_chant()))
		enemy_ai.thorns(unit)
	if pathing.hit_wall(square, unit.attack * enemy_ai.war_chant()):
		if barricade_square.has(square):
			var b: Dictionary = barricades[barricade_square[square]]
			if not b["broken"]:
				b["broken"] = true
				run.record.note_count("barricades_broken", 1)
				run.tell("Raiders break through a barricade.", RunState.PROBLEM)
			return
		run.record.note_breach()
		if not bool(night_report.get("breached", false)):
			night_report["breached"] = true
			run.tell("Raiders break through a gate.", RunState.PROBLEM)


func fight(unit: Unit, foe: Unit) -> void:
	if unit.pos.distance_to(foe.pos) > unit.attack_range:
		walk_toward(unit, foe.pos, unit.attack_range * 0.9)
	elif unit.cooldown_left <= 0.0:
		hit(unit, foe)


## Walks to the hearth and heals there. Returns true while healing.
func go_heal(unit: Unit, mult := 1.0) -> bool:
	if not walk_toward(unit, unit.pos.limit_length(HEARTH_RADIUS + 10.0).lerp(Vector2.ZERO, 0.2), HEARTH_RADIUS + 14.0):
		return false
	unit.hp = minf(unit.max_hp, unit.hp + content.num("hearth_heal_rate") * mult * dt)
	return true


func hit(attacker: Unit, victim: Unit) -> void:
	attacker.cooldown_left = attacker.cooldown
	shots.append({"from": attacker.pos, "to": victim.pos, "ranged": attacker.attack_range > 60, "time": time})
	var amount := attacker.attack * rng.randf_range(0.85, 1.15)
	if attacker.is_enemy():
		amount *= enemy_ai.war_chant()
	elif attacker.is_hero():
		if attacker.energy <= 0.0:
			amount *= content.num("exhausted_attack")
		attacker.energy = maxf(0.0, attacker.energy - content.num("energy_per_attack"))
	if victim.is_enemy():
		if attacker.is_hero():
			amount += Loot.bane(content, attacker, victim)
			amount *= hero_ai.relic_damage_mult(attacker)
		elif attacker.is_folk():
			amount = folk_ai.relic_damage(attacker, amount)
		# Relics keyed on the victim's tags (foe_damage), e.g. Grave salt on undead.
		var bane := run.tag_mod("foe_damage", content.unit_tags(victim))
		if bane != 0.0:
			amount *= 1.0 + bane
			run.relic_fired("foe_damage")
		amount *= enemy_ai.armour_left(victim, _blow_is(attacker, "metal"), _blow_is(attacker, "steel"))
	damage(attacker, victim, amount)


## Bronze shields turn stone and mail turns anything short of steel. A hero's blow is what their
## weapon is made of; a warrior's is what their group's tool sets give ("metal", "steel").
func _blow_is(attacker: Unit, kind: String) -> bool:
	if attacker.is_hero():
		return attacker.items.has("weapon") and content.items["bases"][attacker.items["weapon"]["base"]].get(kind, false)
	return attacker.is_folk() and run.has_tools_with(attacker.type_id, kind)


## `source` names the defence that struck when there is no attacker ("hearth", a tower's type, "relic"), for the impact tally.
func damage(attacker: Unit, victim: Unit, amount: float, source := "") -> void:
	var before := maxf(0.0, victim.hp)
	victim.hp -= amount
	run.record.note_blow(attacker, victim, clampf(amount, 0.0, before), source, victim.hp <= 0.0 and before > 0.0)
	if victim.hp > 0.0:
		# Sentient creatures turn on whoever hurt them.
		if victim.is_enemy() and attacker != null and content.unit_has_tag(victim, "sentient"):
			victim.target = attacker
			victim.target_tower = -1
			victim.grudge_until = time + 8.0
		return
	# A raider who falls on a Barrow may get up again, once (data/plates.json near_kinds).
	if victim.is_enemy() and not victim.rose_again and not victim.risen and earth.kind_at(victim.pos) != "":
		var kd := earth.kind_def(earth.kind_at(victim.pos))
		if rng.randf() < float(kd.get("rise_chance", 0.0)):
			victim.rose_again = true
			victim.hp = victim.max_hp * float(kd.get("rise_hp", 0.5))
			run.record.note_count("earth_risen", 1, victim.type_id)
			return
	victim.alive = false
	victim.hp = 0.0
	if victim.risen:
		return
	if not victim.is_enemy():
		if victim.is_hero():
			hero_ai.mourn(victim)
		var killer := attacker.type_id if attacker != null else ""
		var death := {"name": victim.display_name, "role": victim.type_id, "hero": victim.is_hero(),
			"killer": killer, "day": day_index() + 1, "night": is_night()}
		deaths.append(death)
		if victim.is_hero():
			night_report["hero_deaths"] = int(night_report["hero_deaths"]) + 1
			if wave_spawned:
				wave_stats["hero_deaths"].append({"hero": victim.display_name, "killer": killer, "time": snappedf(time, 0.1)})
			run.tell("%s fell to a %s." % [run.describe(victim), attacker.display_name if attacker != null else "the dark"], RunState.MOMENT)
		else:
			run.tell("A %s was killed by a %s." % [victim.display_name.to_lower(), attacker.display_name.to_lower() if attacker != null else "beast"], RunState.PROBLEM)
		night_report["deaths"].append(victim.display_name)
		if victim.errand_for != null:
			run.record.note_count("runners_lost", 1, victim.errand_for.display_name)
			run.tell("The runner carrying supplies to %s never arrives." % victim.errand_for.display_name, RunState.PROBLEM)
			victim.errand_for.runner = null
			victim.errand_for = null
			victim.parcel = {}
		return
	night_report["kills"] = int(night_report["kills"]) + 1
	last_felled = {"pos": victim.pos, "type": victim.type_id, "boss": victim.is_boss, "invader": victim.den_index < 0,
		"by": _felled_by(attacker, source), "time": time}
	market.carcass(victim)
	enemy_ai.on_camper_killed(victim, attacker)
	_relic_kill(victim)
	if attacker != null and attacker.is_folk():
		attacker.kills += 1
	if attacker == null or not attacker.is_hero():
		return
	var e: Dictionary = content.enemies[victim.type_id]
	attacker.kills += 1
	attacker.xp += float(e["xp"]) * (1.0 + run.mod("xp_mult") + hero_ai.chosen_xp(attacker)
		+ (content.num("hearty_xp") if attacker.well_fed else 0.0) + market.prize_xp(victim.type_id))
	var earned := int(e["loot"]) + int(run.mod("loot_shells")) + int(Loot.total(content, attacker, "loot", run.gear_bonus()))
	var tithe := int(earned * run.mod("hero_tithe"))
	if tithe > 0:
		run.stock["shells"] = int(run.stock["shells"]) + tithe
		run.relic_fired("hero_tithe", tithe)
	attacker.gold += earned - tithe
	hero_ai.count_trophy(attacker)
	market.pay_prizes(attacker, victim)
	hero_ai.maybe_drop(attacker, victim)
	# A hero who kills on a Barrow may dig up grave goods.
	var grave := float(earth.kind_def(earth.kind_at(victim.pos)).get("grave_goods", 0.0))
	if grave > 0.0 and rng.randf() < grave:
		hero_ai.give_item(attacker, Loot.roll(content, rng, run.round_number, run.age))
		run.record.note_count("grave_goods", 1)
		run.tell("%s turns up grave goods on the barrow." % attacker.display_name)
	if victim.is_boss:
		run.tell("%s slays %s!" % [attacker.display_name, victim.display_name], RunState.MOMENT)


## Who landed a killing blow, for the view: a hero by name, a townsperson by role ("a warrior"), else the hearth or the tower that shot.
func _felled_by(attacker: Unit, source: String) -> String:
	if attacker != null:
		return attacker.display_name if attacker.is_hero() else "a " + attacker.display_name.to_lower()
	if source == "hearth":
		return "the hearth"
	if content.buildings.has(source):
		return "the " + String(content.buildings[source]["name"]).to_lower()
	return ""


## Relics that act when an enemy falls, whoever felled it: shells and fuel for the town, goods for foes of a tag (foe_spoils),
## raiders who turn their coats, and the fallen raised to fight for the town tonight.
func _relic_kill(victim: Unit) -> void:
	if run.has_effect("kill_shells"):
		run.stock["shells"] = int(run.stock["shells"]) + int(run.mod("kill_shells"))
		run.relic_fired("kill_shells", int(run.mod("kill_shells")))
	if run.has_effect("kill_fuel") and victim.pos.length() <= content.num("settlement_radius"):
		run.stock["fuel"] = int(run.stock["fuel"]) + int(run.mod("kill_fuel"))
		run.relic_fired("kill_fuel", int(run.mod("kill_fuel")))
	var spoils := run.tag_sums("foe_spoils", content.unit_tags(victim))
	for good: String in spoils:
		run.stock[good] = int(run.stock.get(good, 0)) + int(spoils[good])
		run.relic_fired("foe_spoils", int(spoils[good]))
	if run.has_effect("turncoat_chance") and not victim.is_boss and content.unit_has_tag(victim, "human") \
			and turncoats_tonight < int(run.mod("turncoat_max")) and rng.randf() < run.mod("turncoat_chance"):
		turncoats_tonight += 1
		_joining.append({"role": "warrior", "pos": victim.pos, "risen": false})
		run.relic_fired("turncoat_chance")
		run.tell("A %s throws down their arms and begs to join you. They fight as a warrior now." % victim.display_name.to_lower())
	elif is_night() and risen_tonight < int(run.mod("risen_per_night")):
		risen_tonight += 1
		_joining.append({"role": "warrior", "pos": victim.pos, "risen": true})
		run.relic_fired("risen_per_night")
		if risen_tonight == 1:
			run.tell("The bone flute plays: the fallen rise to fight for the town until dawn.")


## Adds the townsfolk who joined during this step where they stood.
func _join_folk() -> void:
	for j in _joining:
		var unit := folk_ai.add_folk(j["role"])
		unit.pos = j["pos"]
		if j["risen"]:
			unit.risen = true
			unit.display_name = "Risen bones"
	_joining = []


## The risen crumble at dawn (or when the round ends).
func _lay_risen() -> void:
	folk = folk.filter(func(u: Unit) -> bool: return not u.risen)


func _cleanup() -> void:
	for unit in folk.duplicate():
		if not unit.alive:
			folk.erase(unit)
			if not unit.risen:
				run.fallen_folk += 1
	enemies = enemies.filter(func(e: Unit) -> bool: return e.alive or not e.spawned)
	if not dens.is_empty() and dens[-1].get("cleared", false):
		dens.pop_back()
	for e in enemies:
		if e.target != null and not e.target.alive:
			e.target = null
	for u in folk + run.heroes:
		if u.target != null and not u.target.alive:
			u.target = null


## Lookups within this distance use the grids; longer ones scan the whole list.
const GRID_LOOKUP_MAX := 400.0


func nearest_enemy(from: Vector2, max_distance: float, max_from_home := INF) -> Unit:
	if _enemy_grid_ok and max_distance <= GRID_LOOKUP_MAX:
		return _enemy_grid.nearest(from, max_distance, max_from_home, true)
	var best: Unit = null
	var best_d := max_distance
	for enemy in enemies:
		if not enemy.alive or not enemy.spawned or enemy.pos.length() > max_from_home:
			continue
		var d := from.distance_to(enemy.pos)
		if d < best_d:
			best_d = d
			best = enemy
	return best


## The closest enemy chasing a worker, if it is within reach of the warriors.
func nearest_alarm(from: Vector2) -> Unit:
	var best: Unit = null
	var best_d := INF
	for enemy in alarms:
		if not enemy.alive or enemy.pos.length() > content.num("warrior_answer_radius"):
			continue
		var d := from.distance_to(enemy.pos)
		if d < best_d:
			best_d = d
			best = enemy
	return best


func nearest_friend(from: Vector2, max_distance: float) -> Unit:
	if _friend_grid_ok and max_distance <= GRID_LOOKUP_MAX:
		return _friend_grid.nearest(from, max_distance)
	var best: Unit = null
	var best_d := max_distance
	for unit in folk + run.heroes:
		if not unit.alive:
			continue
		var d := from.distance_to(unit.pos)
		if d < best_d:
			best_d = d
			best = unit
	return best


## Breaks unit-to-unit references so everything can be freed.
func release() -> void:
	alarms = []
	new_alarms = []
	_enemy_grid.rebuild([] as Array[Unit])
	_friend_grid.rebuild([] as Array[Unit])
	for unit in folk + enemies + run.heroes:
		unit.target = null


## Breaks every reference loop (run, parts, units) so a finished run can be freed.
func dispose() -> void:
	release()
	run = null
	folk_ai = null
	hero_ai = null
	market = null
	enemy_ai = null
	pedlar = null
	town = null
