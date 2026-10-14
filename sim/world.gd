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
var dens: Array[Dictionary] = []  ## {type, spawns, pos, respawn_left}
## The ground and how units find their way (see Pathing), and the town's plots, gates and paving (see Town).
var pathing: Pathing
var town: Town
## {type, plot, pos, work_left, cooldown_left, goods (stalls), craft, craft_left, craft_tier, made (workshops)}
var buildings: Array[Dictionary] = []

var folk: Array[Unit] = []
var enemies: Array[Unit] = []

## Seconds since this round's first dawn.
var time := 0.0
var wave_sides: Array[float] = []
var wave_spawned := false
var pause := Pause.NONE
var cold_tonight := false

## Recent attacks for drawing: {from: Vector2, to: Vector2, ranged: bool, time: float}.
var shots: Array[Dictionary] = []
## Facts for this round's record.
var deaths: Array[Dictionary] = []
var wave_stats := {}
## What happened since the last dawn pick: {raiders, kills, hearth_damage, deaths: [names], left: [names]}.
## RunState reads it at each dawn and at the end of the round.
var night_report := {}
## Enemies chasing a fleeing worker (seen last tick); warriors answer the call.
var alarms: Array[Unit] = []
var new_alarms: Array[Unit] = []

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


func _init(run_state: RunState) -> void:
	run = run_state
	content = run.content
	folk_ai = FolkAI.new(self)
	hero_ai = HeroAI.new(self)
	market = Market.new(self)
	enemy_ai = EnemyAI.new(self)
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
	for den in dens:
		den["respawn_left"] = 0.0
	pause = Pause.NONE


func reset_night_report() -> void:
	night_report = {"raiders": 0, "kills": 0, "hearth_damage": 0.0, "deaths": [], "left": [], "heroes_left": [],
		"hero_deaths": 0, "cold": false}


## Decides (reproducibly) which sides this round's wave comes from, so it can be warned of.
func roll_wave_sides() -> void:
	wave_sides = []
	var side_rng := SeededRng.stream(run.run_seed, "sides", run.round_number)
	var side_count := 2 if run.round_number >= content.int_num("wave_two_sides_from_round") else 1
	var first := side_rng.randi_range(0, 3)
	wave_sides.append(first * PI / 2.0)
	if side_count == 2:
		wave_sides.append(((first + side_rng.randi_range(1, 3)) % 4) * PI / 2.0)


## The wave side names, for the UI and story.
func side_names() -> Array[String]:
	var names: Array[String] = []
	for angle in wave_sides:
		names.append(["east", "south", "west", "north"][int(round(angle / (PI / 2.0))) % 4])
	return names


# --- Step ------------------------------------------------------------------

func step() -> void:
	if pause != Pause.NONE:
		return
	var was_night := is_night()
	var old_day := day_index()
	time += dt
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
	_friend_grid_ok = false
	enemy_ai.towers_tick()
	_cleanup()
	shots = shots.filter(func(s: Dictionary) -> bool: return time - float(s["time"]) < 0.25)

	if hearth_hp <= 0.0 or (folk.is_empty() and not run.heroes.any(func(h: Unit) -> bool: return h.alive)):
		pause = Pause.HEARTH_LOST
		return
	if time >= night_end:
		var wave_left := enemies.filter(func(e: Unit) -> bool: return e.alive and e.den_index < 0)
		if wave_left.is_empty() or time >= night_end + content.num("night_seconds") * 2.0:
			for e in wave_left:
				hearth_hp -= e.attack * 3.0
				e.alive = false
			if not wave_left.is_empty():
				run.tell("The last raiders loot the edge of the camp and slip away.")
			_finish_round()


func _nightfall() -> void:
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
			run.tell("Out of fuel: %d wood goes on the fire instead." % wood)
		if wood < short:
			cold_tonight = true
			night_report["cold"] = true
			run.tell("The fire burns low. A cold night: everyone suffers.")
	if is_wave_night():
		run.tell("Night %d falls. The warned attack is coming from the %s." % [day_index() + 1, " and ".join(side_names())])
	else:
		run.tell("Night %d falls." % (day_index() + 1))
		enemy_ai.spawn_probe()


func _end_of_night_effects() -> void:
	if cold_tonight:
		for unit in folk + run.heroes:
			if unit.alive:
				unit.hp = maxf(1.0, unit.hp - unit.max_hp * content.num("cold_night_damage"))
	cold_tonight = false


func _dawn() -> void:
	_end_of_night_effects()
	var stayed := enemies.filter(func(e: Unit) -> bool: return e.alive and e.is_probe)
	if not stayed.is_empty():
		run.tell("At first light the last %d raiders slip back into the wilds." % stayed.size())
	enemies = enemies.filter(func(e: Unit) -> bool: return not e.is_probe)
	for node in nodes:
		node["amount"] = mini(int(node["max"]), int(node["amount"]) + content.int_num("node_regrow_per_day"))
	pathing.wear_trails()
	town.patch_walls()
	enemy_ai.mend_towers()
	run.daily_upkeep()
	pause = Pause.DAWN


func _finish_round() -> void:
	_end_of_night_effects()
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


## A node counts once the town has reached its age.
func node_active(node: Dictionary) -> bool:
	return content.age_reached(run.age, node.get("age", ""))


## Townsfolk only go to a wild node when no monster is anywhere near it.
func node_safe(node: Dictionary) -> bool:
	return not node.get("wild", false) or nearest_enemy(node["pos"], float(content.world["wild_safe_radius"])) == null


func _place_dens() -> void:
	var ids: Array = content.world["dens"].keys()
	ids.sort()
	var start := rng.randf() * TAU
	for i in content.int_num("den_count"):
		var id: String = ids[i % ids.size()]
		var angle := start + TAU * i / content.num("den_count") + rng.randf_range(-0.4, 0.4)
		var dist := rng.randf_range(content.num("den_min_distance"), content.num("den_max_distance"))
		dens.append({"type": id, "spawns": content.world["dens"][id]["spawns"],
			"pos": Vector2.from_angle(angle) * dist, "respawn_left": 0.0})


## Orders a building: it goes on the free plot that suits it (see Town.choose_plot). False if none is left.
func add_building(type: String) -> bool:
	var plot := town.choose_plot(type)
	if plot < 0:
		return false
	buildings.append({"type": type, "plot": plot, "pos": town.plots[plot]["pos"],
		"work_left": float(content.buildings[type]["work"]), "cooldown_left": 0.0,
		"hp": float(content.buildings[type].get("tower_hp", 0.0)),
		"goods": [], "craft": "", "craft_left": 0.0, "craft_tier": 1, "made": 0})
	town.occupy(plot, buildings.size() - 1)
	return true


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
	var step_len := unit.speed * dt * pathing.speed_at(unit.pos, unit.is_enemy())
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
	if pathing.hit_wall(square, unit.attack * enemy_ai.war_chant()):
		run.record.note_breach()
		if not bool(night_report.get("breached", false)):
			night_report["breached"] = true
			run.tell("Raiders break through a gate.")


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
		amount *= enemy_ai.armour_left(victim, _blow_is(attacker, "metal"), _blow_is(attacker, "steel"))
	damage(attacker, victim, amount)


## Bronze shields turn stone and mail turns anything short of steel. A hero's blow is what their
## weapon is made of; a warrior's is what their group's tool sets give ("metal", "steel").
func _blow_is(attacker: Unit, kind: String) -> bool:
	if attacker.is_hero():
		return attacker.items.has("weapon") and content.items["bases"][attacker.items["weapon"]["base"]].get(kind, false)
	return attacker.is_folk() and run.has_tools_with(attacker.type_id, kind)


func damage(attacker: Unit, victim: Unit, amount: float) -> void:
	victim.hp -= amount
	if victim.hp > 0.0:
		# Sentient creatures turn on whoever hurt them.
		if victim.is_enemy() and attacker != null and content.unit_has_tag(victim, "sentient"):
			victim.target = attacker
			victim.target_tower = -1
			victim.grudge_until = time + 8.0
		return
	victim.alive = false
	victim.hp = 0.0
	if not victim.is_enemy():
		var killer := attacker.type_id if attacker != null else ""
		var death := {"name": victim.display_name, "role": victim.type_id, "hero": victim.is_hero(),
			"killer": killer, "day": day_index() + 1, "night": is_night()}
		deaths.append(death)
		if victim.is_hero():
			night_report["hero_deaths"] = int(night_report["hero_deaths"]) + 1
			if wave_spawned:
				wave_stats["hero_deaths"].append({"hero": victim.display_name, "killer": killer, "time": snappedf(time, 0.1)})
			run.tell("%s fell to a %s." % [run.describe(victim), attacker.display_name if attacker != null else "the dark"])
		else:
			run.tell("A %s was killed by a %s." % [victim.display_name.to_lower(), attacker.display_name.to_lower() if attacker != null else "beast"])
		night_report["deaths"].append(victim.display_name)
		return
	night_report["kills"] = int(night_report["kills"]) + 1
	market.carcass(victim)
	if attacker != null and attacker.is_folk():
		attacker.kills += 1
	if attacker == null or not attacker.is_hero():
		return
	var e: Dictionary = content.enemies[victim.type_id]
	attacker.kills += 1
	attacker.xp += float(e["xp"]) * (1.0 + run.mod("xp_mult"))
	attacker.gold += int(e["loot"]) + int(run.mod("loot_shells")) + int(Loot.total(content, attacker, "loot"))
	market.pay_prizes(attacker, victim)
	hero_ai.maybe_drop(attacker, victim)
	if victim.is_boss:
		run.tell("%s slays %s!" % [attacker.display_name, victim.display_name])


func _cleanup() -> void:
	for unit in folk.duplicate():
		if not unit.alive:
			folk.erase(unit)
			run.fallen_folk += 1
	enemies = enemies.filter(func(e: Unit) -> bool: return e.alive or not e.spawned)
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
	town = null
