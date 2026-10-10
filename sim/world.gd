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
const PLOT_RINGS := [[78.0, 8], [118.0, 12], [158.0, 16]]

enum Pause { NONE, DAWN, ROUND_OVER, HEARTH_LOST }

var run: RunState
var content: Content
var rng: SeededRng
var dt: float

var hearth_hp := 0.0
var hearth_cooldown_left := 0.0
var nodes: Array[Dictionary] = []  ## {type, gives, pos, amount, max}
var dens: Array[Dictionary] = []  ## {type, spawns, pos, respawn_left}
var plots: Array[Vector2] = []
var buildings: Array[Dictionary] = []  ## {type, pos, work_left, cooldown_left}

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


func _init(run_state: RunState) -> void:
	run = run_state
	content = run.content
	rng = SeededRng.stream(run.run_seed, "world")
	dt = 1.0 / content.num("ticks_per_second")
	hearth_hp = run.hearth_max_hp()
	for ring: Array in PLOT_RINGS:
		var count: int = ring[1]
		for i in count:
			var angle := TAU * (i + 0.5 * (plots.size() % 2)) / count
			plots.append(Vector2.from_angle(angle) * float(ring[0]))
	_place_nodes()
	_place_dens()


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
	for den in dens:
		den["respawn_left"] = 0.0
	pause = Pause.NONE


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
		_spawn_wave()
	var night_end := float(content.int_num("days_per_round")) * day_length()
	if day_index() != old_day:
		_dawn()
		return
	if wave_spawned:
		wave_stats["seconds"] = time - (night_end - content.num("night_seconds"))

	_dens_tick()
	for enemy in enemies:
		if not enemy.spawned and time >= enemy.spawn_time:
			enemy.spawned = true
	for unit in folk:
		if unit.alive:
			_folk_tick(unit)
	for hero in run.heroes:
		if hero.alive:
			_hero_tick(hero)
	for enemy in enemies:
		if enemy.alive and enemy.spawned:
			_enemy_tick(enemy)
	_towers_tick()
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
	if run.stock["fuel"] >= need:
		run.stock["fuel"] -= need
		cold_tonight = false
	else:
		run.stock["fuel"] = 0
		cold_tonight = true
		run.tell("The fuel runs out. A cold night: everyone suffers.")
	run.tell("Night %d falls." % (day_index() + 1) if not is_wave_night() else "Night %d falls. The warned attack is coming from the %s." % [day_index() + 1, " and ".join(side_names())])


func _end_of_night_effects() -> void:
	if cold_tonight:
		for unit in folk + run.heroes:
			if unit.alive:
				unit.hp = maxf(1.0, unit.hp - unit.max_hp * content.num("cold_night_damage"))
	cold_tonight = false


func _dawn() -> void:
	_end_of_night_effects()
	for node in nodes:
		node["amount"] = mini(int(node["max"]), int(node["amount"]) + content.int_num("node_regrow_per_day"))
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
	var lo := content.num("node_min_distance")
	var hi := content.num("node_max_distance")
	for id: String in ids:
		var def: Dictionary = content.world["nodes"][id]
		for i in int(def["count"]):
			# Spread each type around the circle, nearer and farther out.
			var angle := TAU * (i + rng.randf()) / float(def["count"])
			var dist := lerpf(lo, hi, (i + rng.randf()) / float(def["count"]))
			nodes.append({"type": id, "gives": def["gives"], "pos": Vector2.from_angle(angle) * dist,
				"amount": int(def["amount"]), "max": int(def["amount"])})


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


func free_plot() -> int:
	for i in plots.size():
		if not buildings.any(func(b: Dictionary) -> bool: return b["plot"] == i):
			return i
	return -1


func add_building(type: String) -> void:
	var plot := free_plot()
	if plot < 0:
		return
	buildings.append({"type": type, "plot": plot, "pos": plots[plot],
		"work_left": float(content.buildings[type]["work"]), "cooldown_left": 0.0})


func count_buildings(type: String, built_only := true) -> int:
	return buildings.filter(func(b: Dictionary) -> bool:
		return b["type"] == type and (not built_only or float(b["work_left"]) <= 0.0)).size()


# --- Townsfolk -------------------------------------------------------------

func add_folk(role: String) -> Unit:
	var def: Dictionary = content.townsfolk[role]
	var unit := Unit.new()
	unit.id = run.new_id()
	unit.team = Unit.Team.FOLK
	unit.type_id = role
	unit.display_name = def["name"]
	unit.home = Vector2.from_angle(rng.randf() * TAU) * rng.randf_range(20.0, HOME_RADIUS)
	unit.pos = unit.home
	apply_folk_stats(unit)
	unit.hp = unit.max_hp
	folk.append(unit)
	return unit


func apply_folk_stats(unit: Unit) -> void:
	var def: Dictionary = content.townsfolk[unit.type_id]
	unit.max_hp = float(def["hp"])
	unit.attack = float(def["attack"])
	if unit.type_id == "warrior":
		unit.max_hp += run.mod("warrior_hp")
		unit.attack += run.mod("warrior_attack")
	unit.attack_range = float(def["range"])
	unit.cooldown = float(def["cooldown"])
	unit.speed = float(def["speed"])
	unit.hp = minf(unit.hp, unit.max_hp)


func _folk_tick(unit: Unit) -> void:
	unit.cooldown_left -= dt
	match unit.type_id:
		"warrior":
			_warrior_tick(unit)
		_:
			_worker_tick(unit)


func _warrior_tick(unit: Unit) -> void:
	var patrol := float(content.townsfolk["warrior"]["patrol_radius"])
	if unit.hp_fraction() < 0.3:
		unit.intent = "falling back to the hearth"
		_go_heal(unit)
		return
	var threat := _nearest_enemy(unit.pos, 220.0, patrol + 60.0)
	if threat != null:
		unit.intent = "defending the camp"
		_fight(unit, threat)
		return
	var index := folk.filter(func(u: Unit) -> bool: return u.type_id == "warrior").find(unit)
	var angle := time * 0.05 + index * 2.4
	unit.intent = "patrolling"
	_move_toward(unit, Vector2.from_angle(angle) * patrol)


## Tribespeople and craftspeople: gather, haul, build, repair, and go home at dusk.
func _worker_tick(unit: Unit) -> void:
	var def: Dictionary = content.townsfolk[unit.type_id]
	var danger := _nearest_enemy(unit.pos, FLEE_DISTANCE)
	if danger != null:
		unit.intent = "fleeing to the hearth"
		unit.task = ""
		var away := unit.pos + (unit.pos - danger.pos).normalized() * 30.0
		_move_toward(unit, away.lerp(Vector2.ZERO, 0.5))
		if danger.pos.distance_to(unit.pos) <= danger.attack_range + 4.0 and unit.cooldown_left <= 0.0:
			_hit(unit, danger)
		return
	if unit.carry_amount > 0 and (unit.task != "gather" or is_dusk()):
		unit.task = "return"
	if unit.task == "return":
		unit.intent = "hauling %s" % unit.carrying
		if _move_toward(unit, unit.home.limit_length(HEARTH_RADIUS + 8.0)):
			run.stock[unit.carrying] = int(run.stock[unit.carrying]) + unit.carry_amount
			unit.carry_amount = 0
			unit.task = ""
		return
	if is_dusk():
		unit.task = ""
		unit.intent = "sleeping" if is_night() else "heading home"
		_move_toward(unit, unit.home)
		if unit.pos.distance_to(unit.home) < 4.0:
			unit.hp = minf(unit.max_hp, unit.hp + dt)
		return
	if unit.task == "":
		_choose_work(unit)
	match unit.task:
		"build":
			if unit.task_index >= buildings.size() or float(buildings[unit.task_index]["work_left"]) <= 0.0:
				unit.task = ""
				return
			var site: Dictionary = buildings[unit.task_index]
			unit.intent = "raising a %s" % content.buildings[site["type"]]["name"].to_lower()
			if _move_toward(unit, site["pos"], 14.0):
				site["work_left"] = float(site["work_left"]) - float(def.get("build_rate", 0.5)) * dt
				if float(site["work_left"]) <= 0.0:
					run.tell("A %s is finished." % content.buildings[site["type"]]["name"].to_lower())
					run.on_building_done(site["type"])
					unit.task = ""
		"repair":
			unit.intent = "patching the hearth"
			if _move_toward(unit, Vector2.ZERO, HEARTH_RADIUS + 6.0):
				unit.task_timer -= dt
				if unit.task_timer <= 0.0:
					unit.task_timer = 2.0
					if int(run.stock["wood"]) <= 0 or hearth_hp >= run.hearth_max_hp():
						unit.task = ""
						return
					run.stock["wood"] = int(run.stock["wood"]) - 1
					hearth_hp = minf(run.hearth_max_hp(), hearth_hp + float(def.get("repair_per_wood", 4)))
		"gather":
			var node: Dictionary = nodes[unit.task_index]
			unit.intent = "gathering %s" % node["gives"]
			if int(node["amount"]) <= 0:
				unit.task = "" if unit.carry_amount == 0 else "return"
				return
			if _move_toward(unit, node["pos"], 10.0):
				unit.task_timer -= dt
				if unit.task_timer <= 0.0:
					var take := mini(int(node["amount"]), int(float(def.get("carry", 2)) * (1.0 + run.mod("carry_mult"))))
					node["amount"] = int(node["amount"]) - take
					unit.carrying = node["gives"]
					unit.carry_amount = take
					unit.task = "return"
		_:
			unit.intent = "idle"
			_move_toward(unit, unit.home)


func _choose_work(unit: Unit) -> void:
	if unit.type_id == "craftsperson":
		for i in buildings.size():
			if float(buildings[i]["work_left"]) > 0.0:
				unit.task = "build"
				unit.task_index = i
				return
	if unit.type_id == "tribesperson" and hearth_hp < run.hearth_max_hp() * 0.8 and int(run.stock["wood"]) > 0 \
			and not folk.any(func(u: Unit) -> bool: return u.task == "repair"):
		unit.task = "repair"
		unit.task_timer = 2.0
		return
	var want := "wood" if unit.type_id == "craftsperson" else run.most_needed_resource()
	var best := -1
	var best_d := INF
	for i in nodes.size():
		var node := nodes[i]
		if node["gives"] != want or int(node["amount"]) <= 0:
			continue
		var d := unit.pos.distance_to(node["pos"])
		# Gatherers avoid nodes with a monster prowling nearby.
		if _nearest_enemy(node["pos"], 120.0) != null:
			d += 400.0
		if d < best_d:
			best_d = d
			best = i
	if best < 0:
		unit.task = ""
		return
	unit.task = "gather"
	unit.task_index = best
	unit.task_timer = float(content.townsfolk[unit.type_id].get("gather_seconds", 3))


# --- Heroes ----------------------------------------------------------------

func _hero_tick(hero: Unit) -> void:
	var t: Dictionary = content.traits[hero.trait_id]
	hero.cooldown_left -= dt
	var retreat_at := clampf(float(t["retreat_at"]) + run.mod("retreat_shift"), 0.0, 0.95)
	if not hero.retreating and hero.hp_fraction() < retreat_at:
		hero.retreating = true
		hero.target = null
		if wave_spawned:
			wave_stats["retreats"] = int(wave_stats["retreats"]) + 1
		run.tell("%s is badly hurt and falls back to the hearth." % hero.display_name)
	if hero.retreating:
		hero.intent = "retreating to heal"
		if _go_heal(hero, 1.0 + run.mod("hearth_heal_mult")):
			if hero.hp_fraction() >= HEAL_UNTIL:
				hero.retreating = false
		return
	var wilds := float(t["wilds"])
	# By day the keen ones hunt far out; at dusk and night everyone stays near home.
	var reach := content.num("settlement_radius") + 160.0
	if not is_dusk():
		reach = maxf(reach, wilds * (content.num("den_max_distance") + 120.0))
	hero.target = _choose_target(hero, t, reach)
	if hero.target != null:
		_fight(hero, hero.target)
		return
	if not is_dusk() and wilds > 0.5 and not dens.is_empty():
		var den: Dictionary = dens[hero.id % dens.size()]
		hero.intent = "stalking the %s" % content.world["dens"][den["type"]]["name"].to_lower()
		_move_toward(hero, den["pos"] * 0.85, 10.0)
		return
	hero.intent = "guarding the camp" if not is_dusk() else "returning for the night"
	var index := run.heroes.find(hero)
	_move_toward(hero, Vector2.from_angle(index * 1.7 + 0.4) * (content.num("settlement_radius") * 0.6), 4.0)


## Scores every reachable enemy from this hero's point of view and picks the best.
## Brave and greedy heroes value wanderers (glory and loot); dutiful ones value
## threats to the camp; cautious ones avoid enemies that could kill them fast.
func _choose_target(hero: Unit, t: Dictionary, reach: float) -> Unit:
	var best: Unit = null
	var best_score := -INF
	var reason := ""
	for enemy in enemies:
		if not enemy.alive or not enemy.spawned:
			continue
		var from_home := enemy.pos.length()
		if from_home > reach and enemy.target != hero:
			continue
		var distance := hero.pos.distance_to(enemy.pos)
		var threat_to_camp := 1.0 - clampf(from_home / content.num("world_radius"), 0.0, 1.0)
		var danger := enemy.attack / maxf(hero.hp, 1.0) * 10.0
		var glory := float(t["wilds"]) * (4.0 if enemy.den_index >= 0 else 1.0) * (0.5 + float(t["greed"]) * 0.5)
		var duty := float(t["duty"]) * threat_to_camp * 8.0
		var score := 10.0 - distance / 60.0 + glory + duty - float(t["caution"]) * danger * 2.0
		if enemy == hero.target:
			score += TARGET_STICKINESS
		if score > best_score:
			best_score = score
			best = enemy
			reason = "hunting for glory" if glory >= duty and enemy.den_index >= 0 else ("defending the camp" if duty >= 3.0 else "fighting")
	if best != null:
		hero.intent = "%s (%s)" % [reason, best.display_name]
	return best


func apply_hero_stats(hero: Unit) -> void:
	var c: Dictionary = content.hero_classes[hero.type_id]
	var old_max := hero.max_hp
	hero.max_hp = float(c["hp"]) + (hero.level - 1) * content.num("level_hp") \
		+ hero.armor_tier * float(content.gear["armor"]["hp"]) + run.mod("hero_hp")
	hero.attack = float(c["attack"]) + (hero.level - 1) * content.num("level_attack") \
		+ hero.weapon_tier * float(content.gear["weapon"]["attack"]) + run.mod("hero_attack")
	hero.attack_range = float(c["range"])
	hero.cooldown = float(c["cooldown"])
	hero.speed = float(c["speed"])
	if old_max > 1.0 and hero.max_hp > old_max:
		hero.hp += hero.max_hp - old_max
	hero.hp = minf(hero.hp, hero.max_hp)


# --- Enemies ---------------------------------------------------------------

func _dens_tick() -> void:
	var level := 1 + (run.round_number - 1) / 2.0
	var cap := content.int_num("den_base_wanderers") + int(content.num("den_wanderers_per_level") * (level - 1.0))
	for i in dens.size():
		var den := dens[i]
		var living := enemies.filter(func(e: Unit) -> bool: return e.alive and e.den_index == i).size()
		den["respawn_left"] = float(den["respawn_left"]) - dt
		if living < cap and float(den["respawn_left"]) <= 0.0:
			den["respawn_left"] = content.num("den_respawn_seconds")
			var e := _make_enemy(den["spawns"], den["pos"] + Vector2.from_angle(rng.randf() * TAU) * 20.0, time,
				1.0 + 0.08 * (run.round_number - 1))
			e.den_index = i
			e.wander_goal = e.pos
			enemies.append(e)


func _enemy_tick(enemy: Unit) -> void:
	enemy.cooldown_left -= dt
	var aggro := content.num("enemy_aggro")
	if enemy.target == null or not enemy.target.alive or enemy.pos.distance_to(enemy.target.pos) > aggro * 3.0:
		enemy.target = _nearest_friend(enemy.pos, aggro)
	if enemy.target != null:
		_fight(enemy, enemy.target)
		return
	if enemy.den_index >= 0:
		_wander(enemy)
		return
	var hold_at := float(content.enemies[enemy.type_id].get("hold_at", 0.0))
	if hold_at > 0.0 and enemy.pos.length() <= hold_at and not _only_holders_left():
		return
	if enemy.pos.length() > enemy.attack_range + HEARTH_RADIUS:
		_move_toward(enemy, Vector2.ZERO)
	elif enemy.cooldown_left <= 0.0:
		enemy.cooldown_left = enemy.cooldown
		var dmg := enemy.attack * war_chant()
		hearth_hp -= dmg
		wave_stats["keep_damage"] = float(wave_stats["keep_damage"]) + dmg
		shots.append({"from": enemy.pos, "to": Vector2.ZERO, "ranged": enemy.attack_range > 60, "time": time})


## Wanderers drift around their den, ranging much farther at night.
func _wander(enemy: Unit) -> void:
	var den: Dictionary = dens[enemy.den_index]
	var roam := content.num("den_roam_night") if is_night() else content.num("den_roam_day")
	if enemy.pos.distance_to(enemy.wander_goal) < 6.0 or enemy.wander_goal.distance_to(den["pos"]) > roam:
		var goal: Vector2 = den["pos"] + Vector2.from_angle(rng.randf() * TAU) * rng.randf_range(0.0, roam)
		enemy.wander_goal = goal.limit_length(content.num("world_radius"))
	var old_speed := enemy.speed
	enemy.speed *= 0.5
	_move_toward(enemy, enemy.wander_goal)
	enemy.speed = old_speed


func _spawn_wave() -> void:
	wave_spawned = true
	wave_stats["hearth_hp_before"] = hearth_hp
	var types := run.generate_wave(run.round_number)
	var interval := content.num("wave_spawn_interval")
	for i in types.size():
		var side: float = wave_sides[i % wave_sides.size()]
		var at := Vector2.from_angle(side + rng.randf_range(-0.25, 0.25)) * content.num("world_radius")
		enemies.append(_make_enemy(types[i], at, time + i * interval))


func war_chant() -> float:
	var mult := 1.0
	for enemy in enemies:
		if enemy.alive and enemy.spawned:
			mult += float(content.enemies[enemy.type_id].get("war_chant", 0.0))
	return mult


func _only_holders_left() -> bool:
	for enemy in enemies:
		if enemy.alive and enemy.den_index < 0 and float(content.enemies[enemy.type_id].get("hold_at", 0.0)) <= 0.0:
			return false
	return true


func _make_enemy(type_id: String, at: Vector2, spawn_time: float, scale := 1.0) -> Unit:
	var e: Dictionary = content.enemies[type_id]
	var enemy := Unit.new()
	enemy.id = run.new_id()
	enemy.team = Unit.Team.ENEMY
	enemy.type_id = type_id
	enemy.display_name = e["name"]
	enemy.max_hp = float(e["hp"]) * scale
	enemy.hp = enemy.max_hp
	enemy.attack = float(e["attack"]) * scale
	enemy.attack_range = float(e["range"])
	enemy.cooldown = float(e["cooldown"])
	enemy.speed = float(e["speed"])
	enemy.is_boss = e.get("boss", false)
	enemy.spawn_time = spawn_time
	enemy.spawned = spawn_time <= time
	enemy.pos = at
	return enemy


# --- Towers ----------------------------------------------------------------

func _towers_tick() -> void:
	hearth_cooldown_left -= dt
	if hearth_cooldown_left <= 0.0:
		var target := _nearest_enemy(Vector2.ZERO, content.num("hearth_range"))
		if target != null:
			hearth_cooldown_left = content.num("hearth_cooldown")
			shots.append({"from": Vector2.ZERO, "to": target.pos, "ranged": true, "time": time})
			_damage(null, target, content.num("hearth_attack") + run.mod("tower_attack"))
	for b in buildings:
		var def: Dictionary = content.buildings[b["type"]]
		if not def.has("attack") or float(b["work_left"]) > 0.0:
			continue
		b["cooldown_left"] = float(b["cooldown_left"]) - dt
		if float(b["cooldown_left"]) > 0.0:
			continue
		var target := _nearest_enemy(b["pos"], float(def["range"]))
		if target != null:
			b["cooldown_left"] = float(def["cooldown"])
			shots.append({"from": b["pos"], "to": target.pos, "ranged": true, "time": time})
			_damage(null, target, float(def["attack"]) + run.mod("tower_attack"))


# --- Shared ----------------------------------------------------------------

## Moves toward a goal; returns true once within `close` of it.
func _move_toward(unit: Unit, goal: Vector2, close := 2.0) -> bool:
	var to_goal := goal - unit.pos
	if to_goal.length() <= close:
		return true
	var step_len := unit.speed * dt
	if to_goal.length() - close <= step_len:
		unit.pos = goal - to_goal.normalized() * close
		return true
	unit.pos += to_goal.normalized() * step_len
	unit.pos = unit.pos.limit_length(content.num("world_radius"))
	return false


func _fight(unit: Unit, foe: Unit) -> void:
	if unit.pos.distance_to(foe.pos) > unit.attack_range:
		_move_toward(unit, foe.pos, unit.attack_range * 0.9)
	elif unit.cooldown_left <= 0.0:
		_hit(unit, foe)


## Walks to the hearth and heals there. Returns true while healing.
func _go_heal(unit: Unit, mult := 1.0) -> bool:
	if not _move_toward(unit, unit.pos.limit_length(HEARTH_RADIUS + 10.0).lerp(Vector2.ZERO, 0.2), HEARTH_RADIUS + 14.0):
		return false
	unit.hp = minf(unit.max_hp, unit.hp + content.num("hearth_heal_rate") * mult * dt)
	return true


func _hit(attacker: Unit, victim: Unit) -> void:
	attacker.cooldown_left = attacker.cooldown
	shots.append({"from": attacker.pos, "to": victim.pos, "ranged": attacker.attack_range > 60, "time": time})
	var amount := attacker.attack * rng.randf_range(0.85, 1.15)
	if attacker.is_enemy():
		amount *= war_chant()
	_damage(attacker, victim, amount)


func _damage(attacker: Unit, victim: Unit, amount: float) -> void:
	victim.hp -= amount
	if victim.hp > 0.0:
		return
	victim.alive = false
	victim.hp = 0.0
	if not victim.is_enemy():
		var killer := attacker.type_id if attacker != null else ""
		var death := {"name": victim.display_name, "role": victim.type_id, "hero": victim.is_hero(),
			"killer": killer, "day": day_index() + 1, "night": is_night()}
		deaths.append(death)
		if victim.is_hero():
			if wave_spawned:
				wave_stats["hero_deaths"].append({"hero": victim.display_name, "killer": killer, "time": snappedf(time, 0.1)})
			run.tell("%s fell to a %s." % [run.describe(victim), attacker.display_name if attacker != null else "the dark"])
		else:
			run.tell("A %s was killed by a %s." % [victim.display_name.to_lower(), attacker.display_name.to_lower() if attacker != null else "beast"])
		return
	if attacker == null or not attacker.is_hero():
		return
	var e: Dictionary = content.enemies[victim.type_id]
	attacker.kills += 1
	attacker.xp += float(e["xp"]) * (1.0 + run.mod("xp_mult"))
	attacker.gold += int(e["loot"]) + int(run.mod("loot_shells"))
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


func _nearest_enemy(from: Vector2, max_distance: float, max_from_home := INF) -> Unit:
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


func _nearest_friend(from: Vector2, max_distance: float) -> Unit:
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
	for unit in folk + enemies + run.heroes:
		unit.target = null
