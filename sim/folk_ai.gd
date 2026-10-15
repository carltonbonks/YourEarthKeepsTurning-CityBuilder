class_name FolkAI
extends RefCounted
## Townsfolk behaviour in the World: warriors patrol and answer calls for help;
## tribespeople and craftspeople gather, haul, build, craft, patch the hearth and
## go home at dusk. Townsfolk are handled as groups; nobody gives them orders.
## Its only state is per-step indexes built in one pass over the townsfolk: warriors' patrol slots, and the
## gathering already planned (so each gatherer plans its trip without scanning everyone).

## Seconds an idle townsperson waits before looking for work again.
const IDLE_RECHECK := 1.0

var w: World
## Warrior -> its place among the warriors in w.folk (dead ones included until cleanup), rebuilt each step.
var _warrior_slot := {}
## Node index -> how much the gatherers already heading there will take.
var _claimed := {}
## Good -> how much is on its way in (claimed at nodes or being hauled home).
var _inbound := {}
## The town's wants this step (RunState.resource_wants), worked out the first time someone plans a trip.
var _wants := {}


func _init(world: World) -> void:
	w = world


## Called by World at the start of each step, before anyone acts.
func begin_step() -> void:
	_warrior_slot.clear()
	_claimed.clear()
	_inbound.clear()
	_wants = {}
	for unit in w.folk:
		if unit.type_id == "warrior":
			_warrior_slot[unit] = _warrior_slot.size()
		elif unit.alive:
			if unit.task == "gather":
				_claim(unit.task_index, carry_of(unit))
			if unit.carry_amount > 0:
				_inbound[unit.carrying] = int(_inbound.get(unit.carrying, 0)) + unit.carry_amount


func _claim(node_index: int, amount: int) -> void:
	_claimed[node_index] = int(_claimed.get(node_index, 0)) + amount
	var good: String = w.nodes[node_index]["gives"]
	_inbound[good] = int(_inbound.get(good, 0)) + amount


func add_folk(role: String) -> Unit:
	var def: Dictionary = w.content.townsfolk[role]
	var unit := Unit.new()
	unit.id = w.run.new_id()
	unit.team = Unit.Team.FOLK
	unit.type_id = role
	unit.display_name = def["name"]
	unit.home = Vector2.from_angle(w.rng.randf() * TAU) * w.rng.randf_range(20.0, World.HOME_RADIUS)
	unit.pos = unit.home
	unit.joined_round = w.run.round_number
	apply_folk_stats(unit)
	unit.hp = unit.max_hp
	w.folk.append(unit)
	return unit


func apply_folk_stats(unit: Unit) -> void:
	var def: Dictionary = w.content.townsfolk[unit.type_id]
	unit.max_hp = float(def["hp"])
	unit.attack = float(def["attack"])
	if unit.type_id == "warrior":
		unit.max_hp += w.run.mod("warrior_hp")
		unit.attack += w.run.mod("warrior_attack")
	unit.max_hp += w.run.tool_bonus(unit.type_id, "hp")
	unit.attack += w.run.tool_bonus(unit.type_id, "attack")
	unit.attack_range = float(def["range"])
	unit.cooldown = float(def["cooldown"])
	unit.speed = float(def["speed"])
	unit.hp = minf(unit.hp, unit.max_hp)


func folk_tick(unit: Unit) -> void:
	unit.cooldown_left -= w.dt
	# Rest at night heals anyone not in a fight.
	if w.is_night() and w.nearest_enemy(unit.pos, 120.0) == null:
		unit.hp = minf(unit.max_hp, unit.hp + w.content.num("folk_night_heal") * w.dt)
	match unit.type_id:
		"warrior":
			_warrior_tick(unit)
		_:
			_worker_tick(unit)


func _warrior_tick(unit: Unit) -> void:
	var patrol := float(w.content.townsfolk["warrior"]["patrol_radius"])
	if unit.hp_fraction() < 0.3:
		unit.retreating = true
	if unit.retreating:
		unit.intent = "falling back to heal"
		if w.go_heal(unit) and unit.hp_fraction() >= World.HEAL_UNTIL:
			unit.retreating = false
		return
	var threat := w.nearest_enemy(unit.pos, 220.0, patrol + 60.0)
	if threat != null:
		unit.intent = "defending the camp"
		w.fight(unit, threat)
		return
	var call := w.nearest_alarm(unit.pos)
	if call != null:
		unit.intent = "answering a call for help"
		w.fight(unit, call)
		return
	var index: int = _warrior_slot.get(unit, -1)
	if index < 0:  # joined since the step began (or ticked outside World.step)
		index = w.folk.filter(func(u: Unit) -> bool: return u.type_id == "warrior").find(unit)
	var angle := w.time * 0.05 + index * 2.4
	unit.intent = "patrolling"
	w.walk_toward(unit, Vector2.from_angle(angle) * patrol)


## Tribespeople and craftspeople: gather, haul, build, repair, and go home at dusk.
func _worker_tick(unit: Unit) -> void:
	var def: Dictionary = w.content.townsfolk[unit.type_id]
	var danger := w.nearest_enemy(unit.pos, World.FLEE_DISTANCE)
	if danger != null:
		unit.intent = "fleeing and calling for help"
		unit.task = ""
		if not w.new_alarms.has(danger):
			w.new_alarms.append(danger)
		var away := unit.pos + (unit.pos - danger.pos).normalized() * 30.0
		w.walk_toward(unit, away.lerp(Vector2.ZERO, 0.5))
		if danger.pos.distance_to(unit.pos) <= danger.attack_range + 4.0 and unit.cooldown_left <= 0.0:
			w.hit(unit, danger)
		return
	if unit.carry_amount > 0 and (unit.task != "gather" or w.is_dusk()):
		unit.task = "return"
	if unit.task == "return":
		unit.intent = "hauling %s" % unit.carrying
		if w.walk_toward(unit, unit.home.limit_length(World.HEARTH_RADIUS + 8.0)):
			w.run.stock[unit.carrying] = int(w.run.stock[unit.carrying]) + unit.carry_amount
			unit.carry_amount = 0
			unit.task = ""
		return
	if w.is_dusk():
		if unit.task == "gather":
			w.run.record.note_count("trips_cut_short", 1, "dusk")
		unit.task = ""
		unit.intent = "sleeping" if w.is_night() else "heading home"
		w.walk_toward(unit, unit.home)
		if unit.pos.distance_to(unit.home) < 4.0:
			unit.hp = minf(unit.max_hp, unit.hp + w.dt)
		return
	if unit.task == "":
		_choose_work(unit)
	match unit.task:
		"build":
			if unit.task_index >= w.buildings.size() or float(w.buildings[unit.task_index]["work_left"]) <= 0.0:
				unit.task = ""
				return
			var site: Dictionary = w.buildings[unit.task_index]
			unit.intent = "raising a %s" % w.content.buildings[site["type"]]["name"].to_lower()
			if w.walk_toward(unit, site["pos"], 14.0):
				site["work_left"] = float(site["work_left"]) - work_rate(unit) * w.dt
				if float(site["work_left"]) <= 0.0:
					w.run.tell("A %s is finished." % w.content.buildings[site["type"]]["name"].to_lower())
					w.run.on_building_done(site["type"])
					w.town.on_built(unit.task_index)
					unit.task = ""
		"craft":
			if unit.task_index >= w.buildings.size():
				unit.task = ""
				return
			var shop: Dictionary = w.buildings[unit.task_index]
			if shop["craft"] == "" and not w.market.start_craft(unit.task_index):
				unit.task = ""
				return
			unit.intent = "making a %s at the %s" % [w.content.recipe_name(shop["craft"]), w.content.buildings[shop["type"]]["name"].to_lower()]
			if w.walk_toward(unit, shop["pos"], 14.0):
				var rate := work_rate(unit)
				if unit.master_of == shop["type"]:
					rate *= float(w.run.craft_trait(unit).get("craft_rate", 1.0))
				shop["craft_left"] = float(shop["craft_left"]) - rate * w.dt
				if float(shop["craft_left"]) <= 0.0:
					w.market.finish_craft(unit.task_index, unit)
					# Look again: a new order or another workshop may need these hands more.
					unit.task = ""
		"pave":
			var square := unit.task_index
			var kind := w.town.best_road()
			if kind < 0 or w.pathing.ground[square] >= kind or w.pathing.is_solid(square):
				unit.task = ""
				return
			unit.intent = "laying a %s" % w.town.road_def(kind)["name"].to_lower()
			if w.walk_toward(unit, w.pathing.center(square), 3.0):
				unit.task_timer -= work_rate(unit) * w.dt
				if unit.task_timer <= 0.0:
					w.town.pave(square)
					unit.task = ""
		"repair":
			unit.intent = "patching the hearth"
			if w.walk_toward(unit, Vector2.ZERO, World.HEARTH_RADIUS + 6.0):
				unit.task_timer -= w.dt
				if unit.task_timer <= 0.0:
					unit.task_timer = 2.0
					if int(w.run.stock["wood"]) <= 0 or w.hearth_hp >= w.run.hearth_max_hp():
						unit.task = ""
						return
					w.run.stock["wood"] = int(w.run.stock["wood"]) - 1
					w.hearth_hp = minf(w.run.hearth_max_hp(), w.hearth_hp + float(def.get("repair_per_wood", 4)))
		"gather":
			var node: Dictionary = w.nodes[unit.task_index]
			unit.intent = "gathering %s" % node["gives"]
			if int(node["amount"]) <= 0 or not w.node_safe(node):
				if unit.carry_amount == 0:
					w.run.record.note_count("trips_cut_short", 1, "emptied" if int(node["amount"]) <= 0 else "unsafe")
				unit.task = "" if unit.carry_amount == 0 else "return"
				return
			if w.walk_toward(unit, node["pos"], 10.0):
				unit.task_timer -= w.dt
				if unit.task_timer <= 0.0:
					var take := mini(int(node["amount"]), carry_of(unit))
					node["amount"] = int(node["amount"]) - take
					w.run.record.note_count("gathered", take, node["gives"])
					unit.carrying = node["gives"]
					unit.carry_amount = take
					unit.task = "return"
		_:
			unit.intent = "idle"
			w.walk_toward(unit, unit.home)
			unit.task_timer -= w.dt
			if unit.task_timer <= 0.0:
				unit.task = ""


func _choose_work(unit: Unit) -> void:
	if unit.type_id == "craftsperson":
		for i in w.buildings.size():
			if float(w.buildings[i]["work_left"]) > 0.0:
				unit.task = "build"
				unit.task_index = i
				return
		var shop := w.market.workshop_needing_hands(unit)
		if shop >= 0:
			unit.task = "craft"
			unit.task_index = shop
			return
		if w.town.can_pave() and w.town.can_afford_paving():
			var taken := w.folk.filter(func(u: Unit) -> bool: return u != unit and u.task == "pave").map(func(u: Unit) -> int: return u.task_index)
			var square := w.town.next_to_pave(taken)
			if square >= 0:
				unit.task = "pave"
				unit.task_index = square
				unit.task_timer = w.town.pave_work()
				return
	if unit.type_id == "tribesperson" and w.hearth_hp < w.run.hearth_max_hp() * 0.8 and int(w.run.stock["wood"]) > 0 \
			and not w.folk.any(func(u: Unit) -> bool: return u.task == "repair"):
		unit.task = "repair"
		unit.task_timer = 2.0
		return
	var best := plan_trip(unit)
	if best < 0:
		# Nothing worth fetching: wait a moment before looking again.
		unit.task = "idle"
		unit.task_timer = IDLE_RECHECK
		return
	unit.task = "gather"
	unit.task_index = best
	unit.task_timer = gather_time(unit)
	_claim(best, carry_of(unit))


## Picks the gathering trip worth the most to the town, or -1. Each trip is scored by how badly the town
## needs the good (after what is already on its way in) times what this gatherer can carry back from what
## the node will have left once the others heading there have taken theirs, over the time the round trip takes.
## A trip that can't reach the node and finish gathering before dusk isn't started.
## Craftspeople only fetch wood.
func plan_trip(unit: Unit) -> int:
	var time_left := w.content.num("day_seconds") - w.content.num("dusk_seconds") - w.time_of_day()
	var gather := gather_time(unit)
	if time_left <= gather:
		return -1
	if _wants.is_empty():
		_wants = w.run.resource_wants()
	var wants := _wants
	var floor_need := w.content.num("gather_need_floor")
	var slack := w.content.num("gather_trip_slack")
	var carry := carry_of(unit)
	var need := {}
	for good: String in wants:
		var short := float(wants[good]) - float(w.run.stock[good]) - float(_inbound.get(good, 0))
		need[good] = maxf(floor_need, short / maxf(float(wants[good]), 1.0))
	var best := -1
	var best_score := 0.0
	for i in w.nodes.size():
		var node := w.nodes[i]
		var good: String = node["gives"]
		if not need.has(good) or (unit.type_id == "craftsperson" and good != "wood") or not _can_gather(node):
			continue
		var take := mini(carry, int(node["amount"]) - int(_claimed.get(i, 0)))
		if take <= 0:
			continue
		var d := unit.pos.distance_to(node["pos"])
		# Gatherers avoid nodes with a monster prowling nearby.
		if w.nearest_enemy(node["pos"], 120.0) != null:
			d += 400.0
		var walk := d / maxf(unit.speed, 1.0) * slack
		if walk + gather > time_left:
			continue
		var score := float(need[good]) * take / (walk * 2.0 + gather)
		if score > best_score:
			best_score = score
			best = i
	return best


## How much a townsperson brings back from one gathering trip (tools and relics included).
func carry_of(unit: Unit) -> int:
	var carry := float(w.content.townsfolk[unit.type_id].get("carry", 2)) + w.run.tool_bonus(unit.type_id, "carry")
	return int(carry * (1.0 + w.run.mod("carry_mult")))


## Seconds a townsperson spends gathering at a node (tools included).
func gather_time(unit: Unit) -> float:
	return float(w.content.townsfolk[unit.type_id].get("gather_seconds", 3)) / (1.0 + w.run.tool_bonus(unit.type_id, "gather_mult"))


## A node townsfolk may gather from now: stocked, theirs to work, of the town's age, and safe.
func _can_gather(node: Dictionary) -> bool:
	return int(node["amount"]) > 0 and not node.get("heroes_only", false) and w.node_active(node) and w.node_safe(node)


## The closest node a townsperson can gather a good from, or -1.
func nearest_node(unit: Unit, want: String) -> int:
	var best := -1
	var best_d := INF
	for i in w.nodes.size():
		var node := w.nodes[i]
		if node["gives"] != want or not _can_gather(node):
			continue
		var d := unit.pos.distance_to(node["pos"])
		# Gatherers avoid nodes with a monster prowling nearby.
		if w.nearest_enemy(node["pos"], 120.0) != null:
			d += 400.0
		if d < best_d:
			best_d = d
			best = i
	return best


## How fast a craftsperson builds and crafts (tool sets included).
func work_rate(unit: Unit) -> float:
	return float(w.content.townsfolk[unit.type_id].get("build_rate", 0.5)) + w.run.tool_bonus(unit.type_id, "build_rate")
