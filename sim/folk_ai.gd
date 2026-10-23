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
## Living townsfolk whose role stands and fights (tag fighter), counted each step (Horde Drum).
var fighters := 0
## Living townsfolk per role and leaning ("role/leaning" -> count), counted each step: a band's size (band_tier).
var leaning_counts := {}
## Node index -> [[unit, amount], ...]: gatherers walking there for a good they don't lean to. A gatherer that leans
## to the node's good may bump them (first dibs), and they plan another trip.
var _bumpable := {}
## Building index -> how many townsfolk are lending a hand there.
var _helpers := {}
## Building index -> how many craftspeople are working its bench.
var _crafters := {}
## How much the town needs the good of the trip plan_trip last chose (gather_need_floor = it has enough).
var _trip_need := 0.0
## Where gatherers out past the houses are this step, farthest first: by day warriors shadow them (_warrior_tick).
var _shadow_spots: Array[Vector2] = []
## Living warriors this step.
var _warriors := 0
## Role -> daytime seconds spent idle not yet written to the record (it counts whole seconds).
var _idle_time := {}


func _init(world: World) -> void:
	w = world


## Called by World at the start of each step, before anyone acts.
func begin_step() -> void:
	_warrior_slot.clear()
	_claimed.clear()
	_inbound.clear()
	_wants = {}
	_bumpable.clear()
	_helpers.clear()
	_crafters.clear()
	_shadow_spots.clear()
	_warriors = 0
	fighters = 0
	leaning_counts = count_leanings()
	for unit in w.folk:
		if unit.alive and w.content.unit_has_tag(unit, "fighter"):
			fighters += 1
		if unit.type_id == "warrior":
			_warrior_slot[unit] = _warrior_slot.size()
			if unit.alive:
				_warriors += 1
		elif unit.alive:
			if (unit.task == "gather" or unit.task == "return") and unit.pos.length() > World.HOME_RADIUS:
				_shadow_spots.append(unit.pos)
			if unit.task == "gather":
				var good: String = w.nodes[unit.task_index]["gives"]
				_claim(unit.task_index, carry_of(unit, good, w.nodes[unit.task_index]["type"]))
				_note_bumpable(unit, unit.task_index, good)
			elif unit.task == "assist":
				_helpers[unit.task_index] = int(_helpers.get(unit.task_index, 0)) + 1
			elif unit.task == "craft":
				_crafters[unit.task_index] = int(_crafters.get(unit.task_index, 0)) + 1
			if unit.carry_amount > 0:
				_inbound[unit.carrying] = int(_inbound.get(unit.carrying, 0)) + unit.carry_amount
	_shadow_spots.sort_custom(func(a: Vector2, b: Vector2) -> bool: return a.length_squared() > b.length_squared())


func _claim(node_index: int, amount: int) -> void:
	_claimed[node_index] = int(_claimed.get(node_index, 0)) + amount
	var good: String = w.nodes[node_index]["gives"]
	_inbound[good] = int(_inbound.get(good, 0)) + amount


## Lists a gatherer still walking out for a good it doesn't lean to, so a leaned gatherer can bump it.
func _note_bumpable(unit: Unit, node_index: int, good: String) -> void:
	if unit.carry_amount == 0 and not leans_to(unit, good):
		if not _bumpable.has(node_index):
			_bumpable[node_index] = []
		_bumpable[node_index].append([unit, carry_of(unit, good, w.nodes[node_index]["type"])])


## How much a leaned gatherer could free at a node by bumping the gatherers there who don't lean to its good.
func _bumpable_amount(node_index: int) -> int:
	var total := 0
	for pair: Array in _bumpable.get(node_index, []):
		total += int(pair[1])
	return total


## First dibs: bumps gatherers who don't lean to the node's good until want is free there for the one who does.
## The bumped plan another trip on their next tick.
func _bump(node_index: int, want: int) -> void:
	var node := w.nodes[node_index]
	var good: String = node["gives"]
	var short := want - (int(node["amount"]) - int(_claimed.get(node_index, 0)))
	var list: Array = _bumpable.get(node_index, [])
	while short > 0 and not list.is_empty():
		var pair: Array = list.pop_back()
		var other: Unit = pair[0]
		if other.task != "gather" or other.task_index != node_index or other.carry_amount > 0:
			continue
		other.task = ""
		_claimed[node_index] = int(_claimed[node_index]) - int(pair[1])
		_inbound[good] = int(_inbound.get(good, 0)) - int(pair[1])
		short -= int(pair[1])
		w.run.record.note_count("trips_bumped", 1, good)


func add_folk(role: String, leaning := "") -> Unit:
	var def: Dictionary = w.content.townsfolk[role]
	var unit := Unit.new()
	unit.leaning = leaning
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
	if unit.type_id == "warrior" or levied(unit):
		_warrior_tick(unit)
	else:
		_worker_tick(unit)


## Levy Horn: on the warned night tribespeople fight like warriors.
func levied(unit: Unit) -> bool:
	return unit.type_id == "tribesperson" and w.is_wave_night() and w.run.has_effect("levy")


## A townsperson's blow after relics: Horde Drum (fighters hit harder the more of them there are)
## and Levy Horn (levied tribespeople hit as hard as warriors).
func relic_damage(unit: Unit, amount: float) -> float:
	if levied(unit):
		amount = maxf(amount, float(w.content.townsfolk["warrior"]["attack"]) * amount / maxf(1.0, unit.attack))
	var per := int(w.run.mod("horde_per"))
	if per > 0 and w.content.unit_has_tag(unit, "fighter"):
		amount += w.run.mod("horde_damage") * ((fighters - 1) / per)
	return amount


## Warriors: fall back to heal when hurt, fight what comes near, answer calls for help. Otherwise, by day, the first
## shadow_share of them each shadow a gatherer out past the houses (farthest first), standing between it and the
## wilds no farther out than shadow_reach; the rest, and everyone at dusk and night, walk the patrol circle.
func _warrior_tick(unit: Unit) -> void:
	var def: Dictionary = w.content.townsfolk["warrior"]
	var patrol := float(def["patrol_radius"])
	var index: int = _warrior_slot.get(unit, -1)
	if index < 0:  # joined since the step began (or ticked outside World.step)
		index = w.folk.filter(func(u: Unit) -> bool: return u.type_id == "warrior").find(unit)
	var shadow := Vector2.INF
	if not w.is_dusk() and not levied(unit) and index < int(_warriors * float(def.get("shadow_share", 0.0))) \
			and index < _shadow_spots.size():
		shadow = _shadow_spots[index].limit_length(float(def["shadow_reach"]))
		patrol = shadow.length()
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
	if shadow != Vector2.INF:
		unit.intent = "keeping watch over the gatherers"
		w.walk_toward(unit, shadow - shadow.normalized() * 20.0, 6.0)
		return
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
			w.bring_in(unit.carrying, unit.carry_amount)
			w.run.record.note_impact("folk", unit.type_id, "goods", unit.carry_amount, unit.carrying)
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
					w.run.record.note_impact("folk", unit.type_id, "raised", 1.0)
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
				rate *= 1.0 + w.town.combo_effect(unit.task_index, "craft_speed")
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
					if w.town.pave(square):
						w.run.record.note_impact("folk", unit.type_id, "paved", 1.0)
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
					var mended := minf(w.run.hearth_max_hp() - w.hearth_hp, float(def.get("repair_per_wood", 4)))
					w.hearth_hp += mended
					w.run.record.note_impact("folk", unit.type_id, "patched", mended)
		"assist":
			if not can_assist(unit, unit.task_index):
				unit.task = ""
				return
			var b: Dictionary = w.buildings[unit.task_index]
			unit.intent = "lending a hand at the %s" % w.content.buildings[b["type"]]["name"].to_lower()
			if w.walk_toward(unit, b["pos"], 14.0):
				unit.task_timer -= w.dt
				w.run.record.note_impact("folk", unit.type_id, "helped", w.dt)
				if w.content.buildings[b["type"]].has("workshop"):
					if b["craft"] != "":
						b["craft_left"] = float(b["craft_left"]) - work_rate(unit) * w.content.num("assist_rate") * w.dt
						if float(b["craft_left"]) <= 0.0:
							w.market.finish_craft(unit.task_index, unit)
				else:
					b["assisted"] = float(b.get("assisted", 0.0)) + w.dt
				if unit.task_timer <= 0.0:
					# Look again: a trip may be worth taking now.
					unit.task = ""
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
					var take := mini(int(node["amount"]), carry_of(unit, node["gives"], node["type"]))
					# What the band added: this take less what the gatherer would have carried alone.
					var band_extra := take - mini(int(node["amount"]), carry_of(unit, "", node["type"]))
					var plain := mini(int(node["amount"]), carry_of(unit, node["gives"]))
					if take > plain:
						w.run.relic_fired("node_yield", take - plain)
					node["amount"] = int(node["amount"]) - take
					w.run.record.note_count("gathered", take, node["gives"])
					if leans_to(unit, node["gives"]):
						w.run.record.note_count("gathered_leaned", take, node["gives"])
					if band_extra > 0:
						w.run.record.note_count("gathered_band", band_extra, node["gives"])
					unit.carrying = node["gives"]
					unit.carry_amount = take
					unit.task = "return"
		_:
			unit.intent = "idle"
			_note_idle(unit)
			w.walk_toward(unit, unit.home)
			unit.task_timer -= w.dt
			if unit.task_timer <= 0.0:
				unit.task = ""


## Counts a daytime second spent idle toward the round's "idle_seconds" for the unit's role.
func _note_idle(unit: Unit) -> void:
	var t := float(_idle_time.get(unit.type_id, 0.0)) + w.dt
	if t >= 1.0:
		w.run.record.note_count("idle_seconds", int(t), unit.type_id)
		t -= int(t)
	_idle_time[unit.type_id] = t


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
	# With nothing the town is short of in reach, lend a hand in town rather than fetch more of what it has.
	if (best < 0 or _trip_need <= w.content.num("gather_need_floor")) and _lend_a_hand(unit):
		return
	if best < 0:
		# Nothing worth fetching: wait a moment before looking again.
		unit.task = "idle"
		unit.task_timer = IDLE_RECHECK
		return
	unit.task = "gather"
	unit.task_index = best
	var gives: String = w.nodes[best]["gives"]
	unit.task_timer = gather_time(unit, gives)
	var carry := carry_of(unit, gives, w.nodes[best]["type"])
	if leans_to(unit, gives):
		_bump(best, carry)
	_claim(best, carry)
	_note_bumpable(unit, best, gives)


## Finds work in town for someone with no trip worth taking: lending a hand at a building that takes help
## ("assist" in buildings.json; a tribesperson only where its leaning fits), else helping raise a building
## (tribespeople; craftspeople already raise them first). Returns false when there is nothing.
func _lend_a_hand(unit: Unit) -> bool:
	var best := -1
	var best_d := INF
	for i in w.buildings.size():
		if can_assist(unit, i, true):
			var d := unit.pos.distance_to(w.buildings[i]["pos"])
			if d < best_d:
				best_d = d
				best = i
	if best >= 0:
		unit.task = "assist"
		unit.task_index = best
		unit.task_timer = w.content.num("assist_recheck")
		_helpers[best] = int(_helpers.get(best, 0)) + 1
		return true
	if unit.type_id != "tribesperson":
		return false
	for i in w.buildings.size():
		if float(w.buildings[i]["work_left"]) > 0.0:
			unit.task = "build"
			unit.task_index = i
			return true
	return false


## Whether a townsperson can lend a hand at building i now. A workshop takes help while something is being made
## there or a craftsperson is at its bench (craftspeople help at any workshop, tribespeople where their leaning fits
## or they have none); a food building takes help until today's helping has earned its most extra food.
## With new_hand, the building must also have room for one more helper (its "hands").
func can_assist(unit: Unit, i: int, new_hand := false) -> bool:
	if i >= w.buildings.size():
		return false
	var b := w.buildings[i]
	var def: Dictionary = w.content.buildings[b["type"]]
	var assist: Dictionary = def.get("assist", {})
	if assist.is_empty() or float(b["work_left"]) > 0.0:
		return false
	if new_hand and int(_helpers.get(i, 0)) >= int(assist.get("hands", 1)):
		return false
	if unit.type_id == "craftsperson":
		if not def.has("workshop"):
			return false
	elif unit.leaning != "" and not assist.get("leanings", []).has(unit.leaning):
		return false
	if def.has("workshop"):
		return b["craft"] != "" or int(_crafters.get(i, 0)) > 0
	return assist.has("food") and assisted_food(b) < int(assist.get("food_max", 0))


## Extra food a building's helpers have earned today (paid at the next dawn, World._dawn resets it).
func assisted_food(b: Dictionary) -> int:
	var assist: Dictionary = w.content.buildings[b["type"]].get("assist", {})
	if not assist.has("food"):
		return 0
	var earned := floori(float(b.get("assisted", 0.0)) / float(assist["seconds"])) * int(assist["food"])
	return mini(earned, int(assist.get("food_max", 0)))


## Picks the gathering trip worth the most to the town, or -1. Each trip is scored by how badly the town
## needs the good (after what is already on its way in) times what this gatherer can carry back from what
## the node will have left once the others heading there have taken theirs, over the time the round trip takes.
## A trip that can't reach the node and finish gathering before dusk isn't started.
## Craftspeople only fetch wood. A gatherer's leaning makes trips for its goods worth leaning_weight times more, and
## gives it first dibs on them: it counts what gatherers there who don't lean to the good claimed as free (_choose_work bumps them).
func plan_trip(unit: Unit) -> int:
	_trip_need = 0.0
	var time_left := w.content.num("day_seconds") - w.content.num("dusk_seconds") - w.time_of_day()
	if time_left <= gather_time(unit):
		return -1
	if _wants.is_empty():
		_wants = w.run.resource_wants()
	var wants := _wants
	var floor_need := w.content.num("gather_need_floor")
	var slack := w.content.num("gather_trip_slack")
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
		var free := int(node["amount"]) - int(_claimed.get(i, 0))
		# First dibs: a gatherer leaning to the good counts what the others there who don't could leave it.
		if leans_to(unit, good):
			free += _bumpable_amount(i)
		var take := mini(carry_of(unit, good, node["type"]), free)
		if take <= 0:
			continue
		var d := unit.pos.distance_to(node["pos"])
		# Gatherers avoid nodes with a monster prowling nearby.
		if w.nearest_enemy(node["pos"], 120.0) != null:
			d += 400.0
		var walk := d / maxf(unit.speed, 1.0) * slack
		var gather := gather_time(unit, good)
		if walk + gather > time_left:
			continue
		var score := float(need[good]) * take / (walk * 2.0 + gather)
		if leans_to(unit, good):
			score *= float(w.content.townsfolk[unit.type_id].get("leaning_weight", 1.0))
		if score > best_score:
			best_score = score
			best = i
			_trip_need = float(need[good])
	return best


## True when a townsperson's leaning is toward this good.
func leans_to(unit: Unit, good: String) -> bool:
	return unit.leaning != "" and w.content.townsfolk[unit.type_id]["leanings"][unit.leaning]["goods"].has(good)


## How much a townsperson brings back from one gathering trip of a good (tools, relics and its band included).
## node_type, when known, adds relics keyed on the node's tags (node_yield, e.g. more from stone ground).
func carry_of(unit: Unit, good := "", node_type := "") -> int:
	var carry := float(w.content.townsfolk[unit.type_id].get("carry", 2)) + w.run.tool_bonus(unit.type_id, "carry")
	if leans_to(unit, good):
		carry += float(band_tier(unit).get("carry", 0))
	var mult := 1.0 + w.run.mod("carry_mult")
	if node_type != "":
		mult += w.run.tag_mod("node_yield", w.content.tags_of("node", node_type))
	return int(carry * mult)


## Seconds a townsperson spends gathering a good at a node (tools and its band included).
func gather_time(unit: Unit, good := "") -> float:
	var mult := w.run.tool_bonus(unit.type_id, "gather_mult")
	if leans_to(unit, good):
		mult += float(band_tier(unit).get("gather_mult", 0))
	return float(w.content.townsfolk[unit.type_id].get("gather_seconds", 3)) / (1.0 + mult)


## Living townsfolk per role and leaning, keyed "role/leaning".
func count_leanings() -> Dictionary:
	var out := {}
	for unit in w.folk:
		if unit.alive and unit.leaning != "":
			var key := unit.type_id + "/" + unit.leaning
			out[key] = int(out.get(key, 0)) + 1
	return out


## The highest band tier a role's townsfolk sharing a leaning reach at this size (data band_tiers), or {}.
## A leaning the town's traditions favour bands tradition_band_ease sooner.
func tier_for(role: String, leaning: String, size: int) -> Dictionary:
	var tiers: Array = w.content.townsfolk[role].get("band_tiers", [])
	var level := band_level(role, leaning, size)
	return tiers[level - 1] if level > 0 else {}


## How many band tiers a role's townsfolk sharing a leaning reach at this size (0 for none).
func band_level(role: String, leaning: String, size: int) -> int:
	var ease := w.content.int_num("tradition_band_ease") if w.run.tradition_leanings().has(leaning) else 0
	var level := 0
	for tier: Dictionary in w.content.townsfolk[role].get("band_tiers", []):
		if size >= int(tier["size"]) - ease:
			level += 1
	return level


## The size a band tier needs for this leaning (traditions included).
func band_size_needed(role: String, leaning: String, tier: Dictionary) -> int:
	return int(tier["size"]) - (w.content.int_num("tradition_band_ease") if w.run.tradition_leanings().has(leaning) else 0)


## The band tier a townsperson's leaning reaches this step, or {} when it has no leaning or too few share it.
func band_tier(unit: Unit) -> Dictionary:
	if unit.leaning == "" or not unit.alive:
		return {}
	return tier_for(unit.type_id, unit.leaning, int(leaning_counts.get(unit.type_id + "/" + unit.leaning, 0)))


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
