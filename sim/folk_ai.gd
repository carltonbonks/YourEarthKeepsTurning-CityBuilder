class_name FolkAI
extends RefCounted
## Townsfolk behaviour in the World: warriors patrol and answer calls for help;
## tribespeople and craftspeople gather, haul, build, craft, patch the hearth and
## go home at dusk. Townsfolk are handled as groups; nobody gives them orders.
## Holds no state of its own: everything lives on `w` (the World).

var w: World


func _init(world: World) -> void:
	w = world


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
	var index := w.folk.filter(func(u: Unit) -> bool: return u.type_id == "warrior").find(unit)
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
				unit.task = "" if unit.carry_amount == 0 else "return"
				return
			if w.walk_toward(unit, node["pos"], 10.0):
				unit.task_timer -= w.dt
				if unit.task_timer <= 0.0:
					var carry := float(def.get("carry", 2)) + w.run.tool_bonus(unit.type_id, "carry")
					var take := mini(int(node["amount"]), int(carry * (1.0 + w.run.mod("carry_mult"))))
					node["amount"] = int(node["amount"]) - take
					unit.carrying = node["gives"]
					unit.carry_amount = take
					unit.task = "return"
		_:
			unit.intent = "idle"
			w.walk_toward(unit, unit.home)


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
	if unit.type_id == "tribesperson" and w.hearth_hp < w.run.hearth_max_hp() * 0.8 and int(w.run.stock["wood"]) > 0 \
			and not w.folk.any(func(u: Unit) -> bool: return u.task == "repair"):
		unit.task = "repair"
		unit.task_timer = 2.0
		return
	var wants: Array[String] = ["wood"]
	if unit.type_id != "craftsperson":
		wants = w.run.needed_resources()
	var best := -1
	for want in wants:
		best = nearest_node(unit, want)
		if best >= 0:
			break
	if best < 0:
		unit.task = ""
		return
	unit.task = "gather"
	unit.task_index = best
	unit.task_timer = float(w.content.townsfolk[unit.type_id].get("gather_seconds", 3)) / (1.0 + w.run.tool_bonus(unit.type_id, "gather_mult"))


## The closest node a townsperson can gather a good from, or -1.
func nearest_node(unit: Unit, want: String) -> int:
	var best := -1
	var best_d := INF
	for i in w.nodes.size():
		var node := w.nodes[i]
		if node["gives"] != want or int(node["amount"]) <= 0 or node.get("heroes_only", false) \
				or not w.node_active(node) or not w.node_safe(node):
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
