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
## Building index -> how many townsfolk are raising it (it is still going up).
var _builders := {}
## How much the town needs the good of the trip plan_trip last chose (gather_need_floor = it has enough).
var _trip_need := 0.0
## Where gatherers out past the houses are this step, farthest first: by day warriors shadow them (_warrior_tick).
var _shadow_spots: Array[Vector2] = []
## The gatherers behind _shadow_spots, in the same order.
var _shadowed: Array[Unit] = []
## Warriors in slot order (as _warrior_slot numbers them), this step.
var _warrior_list: Array[Unit] = []
## Warriors free to drill beside a hero this step (patrolling by day, no mark yet, not drilling already).
var _free_pupils: Array[Unit] = []
## Hero -> how many warriors drill beside them this step.
var _pupils_of := {}
## Living warriors this step.
var _warriors := 0
## Role -> daytime seconds spent idle not yet written to the record (it counts whole seconds).
var _idle_time := {}
## Role -> time kind -> seconds this round (FolkAI._note_time), written to the record as "folk_time".
var role_time := {}


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
	_builders.clear()
	_shadow_spots.clear()
	_shadowed.clear()
	_warrior_list.clear()
	_free_pupils.clear()
	_pupils_of.clear()
	_warriors = 0
	fighters = 0
	leaning_counts = count_leanings()
	for unit in w.folk:
		if unit.alive and w.content.unit_has_tag(unit, "fighter"):
			fighters += 1
		unit.escorted = false
		if unit.type_id == "warrior":
			_warrior_slot[unit] = _warrior_slot.size()
			_warrior_list.append(unit)
			if unit.alive:
				_warriors += 1
				if unit.drill_with != null:
					_pupils_of[unit.drill_with] = int(_pupils_of.get(unit.drill_with, 0)) + 1
		elif unit.alive:
			if (unit.task == "gather" or unit.task == "return") and unit.pos.length() > World.HOME_RADIUS:
				_shadowed.append(unit)
			if unit.task == "gather":
				var good: String = w.nodes[unit.task_index]["gives"]
				_claim(unit.task_index, carry_of(unit, good, w.nodes[unit.task_index]["type"]))
				_note_bumpable(unit, unit.task_index, good)
			elif unit.task == "assist":
				_helpers[unit.task_index] = int(_helpers.get(unit.task_index, 0)) + 1
			elif unit.task == "craft":
				_crafters[unit.task_index] = int(_crafters.get(unit.task_index, 0)) + 1
			elif unit.task == "build":
				_builders[unit.task_index] = int(_builders.get(unit.task_index, 0)) + 1
			if unit.carry_amount > 0:
				_inbound[unit.carrying] = int(_inbound.get(unit.carrying, 0)) + unit.carry_amount
	_shadowed.sort_custom(func(a: Unit, b: Unit) -> bool: return a.pos.length_squared() > b.pos.length_squared())
	for unit in _shadowed:
		_shadow_spots.append(unit.pos)
	_note_escorts()
	_note_free_pupils()
	_dispatch_runners()


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
	unit.max_hp *= 1.0 + unit_mod(unit, "hp")
	unit.attack *= 1.0 + unit_mod(unit, "attack")
	unit.speed *= 1.0 + unit_mod(unit, "speed")
	unit.hp = minf(unit.hp, unit.max_hp)


## One effect key summed over a townsperson's mark (data/marks.json) and card modifiers (data/card_mods.json).
func unit_mod(unit: Unit, key: String) -> float:
	if unit.mark == "" and unit.boons.is_empty():
		return 0.0
	var total := float(w.content.marks[unit.mark].get(key, 0.0)) if unit.mark != "" else 0.0
	for id in unit.boons:
		total += float(w.content.card_mods[id].get(key, 0.0))
	return total


## One effect key summed over every living townsperson (for dawn and night rules, not per step).
func folk_sum(key: String) -> float:
	var total := 0.0
	for unit in w.folk:
		if unit.alive:
			total += unit_mod(unit, key)
	return total


## A new round: each townsperson's time and goods this round become last round's (Your people panel).
func start_round() -> void:
	role_time = {}
	for unit in w.folk:
		unit.time_last = unit.time
		unit.time = {}
		unit.brought_last = unit.brought
		unit.brought = 0


func folk_tick(unit: Unit) -> void:
	unit.activity = ""
	_folk_act(unit)
	_note_time(unit)


## Counts this step toward the unit's time kind (data/townsfolk.json time_kinds: its activity, else its task).
## Workers count by day only; warriors day and night, when their work happens.
func _note_time(unit: Unit) -> void:
	if unit.type_id != "warrior" and w.is_dusk():
		return
	var kind: String = w.content.townsfolk[unit.type_id].get("time_kinds", {}).get(
		unit.activity if unit.activity != "" else unit.task, "")
	if kind == "":
		return
	unit.time[kind] = float(unit.time.get(kind, 0.0)) + w.dt
	var row: Dictionary = role_time.get_or_add(unit.type_id, {})
	row[kind] = float(row.get(kind, 0.0)) + w.dt


func _folk_act(unit: Unit) -> void:
	unit.cooldown_left -= w.dt
	# Rest at night heals anyone not in a fight.
	if w.is_night() and w.nearest_enemy(unit.pos, 120.0) == null:
		unit.hp = minf(unit.max_hp, unit.hp + w.content.num("folk_night_heal") * w.dt)
	# A hollow-eyed seer (data/card_mods.json idle) never works: they stay by their home, seeing.
	if not unit.boons.is_empty() and unit_mod(unit, "idle") > 0.0:
		unit.intent = "staring into the fire, seeing what is to come"
		unit.activity = "seer"
		w.walk_toward(unit, unit.home, 8.0)
		return
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
## wilds no farther out than shadow_reach; the rest, and everyone at dusk and night, walk the patrol round the town's
## edge (Town.patrol_radius), spread evenly round it, alone at first and then in pairs and squads (patrol_group_size).
func _warrior_tick(unit: Unit) -> void:
	var def: Dictionary = w.content.townsfolk["warrior"]
	var patrol := w.town.patrol_radius(unit.pos.angle())
	var index: int = _warrior_slot.get(unit, -1)
	if index < 0:  # joined since the step began (or ticked outside World.step)
		index = w.folk.filter(func(u: Unit) -> bool: return u.type_id == "warrior").find(unit)
	var shadow := Vector2.INF
	if not levied(unit) and _shadows(index):
		shadow = _shadow_spots[index].limit_length(float(def["shadow_reach"]))
		patrol = shadow.length()
	if unit.hp_fraction() < 0.3:
		unit.retreating = true
	if unit.retreating:
		unit.intent = "falling back to heal"
		unit.activity = "heal"
		if w.go_heal(unit) and unit.hp_fraction() >= World.HEAL_UNTIL:
			unit.retreating = false
		return
	# A tight patrol round a young town still goes for foes as far out as patrol_watch (data/townsfolk.json).
	var threat := w.nearest_enemy(unit.pos, 220.0, maxf(patrol, float(def["patrol_watch"])) + 60.0)
	if threat != null:
		unit.intent = "defending the camp"
		unit.activity = "fight"
		w.fight(unit, threat)
		return
	var call := w.nearest_alarm(unit.pos)
	if call != null:
		unit.intent = "answering a call for help"
		unit.activity = "fight"
		w.fight(unit, call)
		return
	if unit.drill_with != null and _drill_with(unit):
		unit.activity = "drill"
		return
	if shadow != Vector2.INF:
		unit.intent = "keeping watch over the gatherers"
		unit.activity = "shadow"
		w.walk_toward(unit, shadow - shadow.normalized() * 20.0, 6.0)
		return
	if index < 0:  # a levied tribesperson, not one of the warriors: holds the edge where it stands
		unit.intent = "patrolling"
		unit.activity = "patrol"
		w.walk_toward(unit, Vector2.from_angle(unit.pos.angle()) * patrol)
		return
	unit.activity = "patrol"
	var slot := index - _shadowing()
	var size := patrol_group_size()
	var groups := ceili(float(maxi(_warrior_list.size() - _shadowing(), slot + 1)) / size)
	var angle := w.time * 0.05 + TAU * floori(float(slot) / size) / groups
	# Partners walk a few paces apart along the same stretch of the patrol.
	angle += (slot % size - (size - 1) / 2.0) * float(def["patrol_spacing"]) / w.town.patrol_radius(angle)
	unit.intent = "patrolling" if size == 1 else ("patrolling in a pair" if size == 2 else "patrolling with a squad")
	w.walk_toward(unit, Vector2.from_angle(angle) * w.town.patrol_radius(angle))


## How many warriors walk the patrol together: alone at first, then in pairs and small squads as more of them patrol
## (patrol_groups in data/townsfolk.json; the largest tier reached counts).
func patrol_group_size() -> int:
	var patrolling := _warriors - _shadowing()
	var size := 1
	for tier: Dictionary in w.content.townsfolk["warrior"]["patrol_groups"]:
		if patrolling >= int(tier["from"]):
			size = maxi(size, int(tier["size"]))
	return size


## How many warriors shadow gatherers this step: the first slots, by day only (see _shadows).
func _shadowing() -> int:
	if w.is_dusk():
		return 0
	return mini(int(_warriors * float(w.content.townsfolk["warrior"].get("shadow_share", 0.0))), _shadow_spots.size())


## True when the warrior in this slot shadows a gatherer this step (by day, the first shadow_share of them).
func _shadows(index: int) -> bool:
	return index < _shadowing()


# --- Escorts and drilling (idle warriors on quiet days) ---------------------------

## Marks each gatherer whose shadowing warrior stands within escort_reach, while no foe is within escort_safe of it:
## it walks escort_speed faster this step (World.walk_toward). Only the shadowed gatherers are looked at.
func _note_escorts() -> void:
	var def: Dictionary = w.content.townsfolk["warrior"]
	for i in mini(_shadowed.size(), _warrior_list.size()):
		var warrior := _warrior_list[i]
		var gatherer := _shadowed[i]
		if not _shadows(i) or not warrior.alive or warrior.retreating \
				or warrior.pos.distance_to(gatherer.pos) > float(def["escort_reach"]) \
				or w.nearest_enemy(gatherer.pos, float(def["escort_safe"])) != null:
			continue
		gatherer.escorted = true
		if fmod(w.time, 1.0) < w.dt:
			w.run.record.note_count("escort_seconds", 1)


## Lists the warriors free to drill beside a hero this step: by day, patrolling (not shadowing), unhurt enough to
## stay out, with no mark yet and no drill partner.
func _note_free_pupils() -> void:
	if w.is_dusk():
		return
	for i in _warrior_list.size():
		var u := _warrior_list[i]
		if u.alive and not u.retreating and u.mark == "" and u.drill_with == null and not _shadows(i):
			_free_pupils.append(u)


## A drilling hero whose class teaches a mark (teaches in data/heroes.json) takes the nearest free warriors as drill
## partners, up to pupils_per_hero. Called by HeroAI as the hero drills.
func take_pupils(hero: Unit) -> void:
	if str(w.content.hero_classes[hero.type_id].get("teaches", "")) == "":
		return
	var room := int(w.content.townsfolk["warrior"]["pupils_per_hero"]) - int(_pupils_of.get(hero, 0))
	while room > 0 and not _free_pupils.is_empty():
		var best := 0
		for i in _free_pupils.size():
			if _free_pupils[i].pos.distance_squared_to(hero.pos) < _free_pupils[best].pos.distance_squared_to(hero.pos):
				best = i
		_free_pupils[best].drill_with = hero
		_free_pupils.remove_at(best)
		_pupils_of[hero] = int(_pupils_of.get(hero, 0)) + 1
		room -= 1


## A warrior drilling beside a hero: walks to them and drills, earning the hero's mark after mark_seconds (a teach_mult
## trait teaches faster). Lets go (false) once it is dusk or the hero has stopped drilling.
func _drill_with(unit: Unit) -> bool:
	var hero := unit.drill_with
	if w.is_dusk() or not hero.alive or w.time - hero.drilled_at > w.dt * 1.5:
		unit.drill_with = null
		return false
	unit.intent = "drilling with %s" % hero.display_name
	if w.walk_toward(unit, hero.pos, 18.0):
		unit.drill_seconds += w.dt * float(w.content.traits[hero.trait_id].get("teach_mult", 1.0))
		w.run.record.note_impact("folk", unit.type_id, "trained", w.dt)
		if unit.drill_seconds >= float(w.content.townsfolk[unit.type_id]["mark_seconds"]):
			grant_mark(unit, hero)
	return true


## A townsperson earns the mark the hero's class teaches, for good (data/marks.json).
func grant_mark(unit: Unit, hero: Unit) -> void:
	var mark: String = w.content.hero_classes[hero.type_id]["teaches"]
	var m: Dictionary = w.content.marks[mark]
	unit.mark = mark
	unit.mark_from = "%s the %s" % [hero.display_name, w.content.hero_classes[hero.type_id]["name"].to_lower()]
	unit.drill_with = null
	var before := unit.max_hp
	apply_folk_stats(unit)
	unit.hp = minf(unit.max_hp, unit.hp + unit.max_hp - before)
	w.run.record.note_count("marks_earned", 1, mark)
	w.run.tell("A %s who drilled beside %s is now %s: %s." % [w.content.townsfolk[unit.type_id]["name"].to_lower(),
		unit.mark_from, m["name"].to_lower(), m["text"]])


## Tribespeople and craftspeople: gather, haul, build, repair, and go home at dusk.
func _worker_tick(unit: Unit) -> void:
	var def: Dictionary = w.content.townsfolk[unit.type_id]
	var danger := w.nearest_enemy(unit.pos, World.FLEE_DISTANCE)
	if danger != null:
		unit.intent = "fleeing and calling for help"
		unit.activity = "flee"
		unit.task = ""
		if not w.new_alarms.has(danger):
			w.new_alarms.append(danger)
		var away := unit.pos + (unit.pos - danger.pos).normalized() * 30.0
		w.walk_toward(unit, away.lerp(Vector2.ZERO, 0.5))
		if danger.pos.distance_to(unit.pos) <= danger.attack_range + 4.0 and unit.cooldown_left <= 0.0:
			w.hit(unit, danger)
		return
	if unit.errand_for != null:
		_run_errand(unit)
		return
	if unit.barricade >= 0 and _barricade_tick(unit):
		return
	if unit.carry_amount > 0 and (unit.task != "gather" or w.is_dusk()):
		unit.task = "return"
	if unit.task == "return":
		unit.intent = "hauling %s" % unit.carrying
		if w.walk_toward(unit, unit.home.limit_length(World.HEARTH_RADIUS + 8.0)):
			w.bring_in(unit.carrying, unit.carry_amount)
			w.run.record.note_impact("folk", unit.type_id, "goods", unit.carry_amount, unit.carrying)
			unit.brought += unit.carry_amount
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
				rate *= 1.0 + float(w.content.buildings[shop["type"]].get("craft_speed", 0.0))
				shop["craft_left"] = float(shop["craft_left"]) - rate * w.dt
				if float(shop["craft_left"]) <= 0.0:
					w.market.finish_craft(unit.task_index, unit)
					# Look again: a new order or another workshop may need these hands more. Its own bench is free
					# again, so it may well stay.
					_crafters[unit.task_index] = int(_crafters.get(unit.task_index, 0)) - 1
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


## Raiders were spotted at `at`: unless the alarm was already raised from that way since dawn, the town barricades
## up to per_alarm gaps on that side (Town.barricade_plots), paying each one's cost from stock while it can, and the
## nearest free hands run to raise each one (data/town.json barricades). Folk only know what was seen: the way the
## spotted raider comes, not the warned way.
func raise_alarm(at: Vector2) -> void:
	var def: Dictionary = w.content.town["barricades"]
	var angle := at.angle()
	if w.alarm_ways.any(func(a: float) -> bool: return absf(angle_difference(a, angle)) < float(def["band"])):
		return
	w.alarm_ways.append(angle)
	var raised := 0
	for k in w.town.barricade_plots(angle, int(def["per_alarm"])):
		var cost: Dictionary = def["cost"]
		if not cost.keys().all(func(good: String) -> bool: return int(w.run.stock.get(good, 0)) >= int(cost[good])):
			break
		for good: String in cost:
			w.run.stock[good] = int(w.run.stock[good]) - int(cost[good])
		w.barricades.append({"plot": k, "pos": w.town.plots[k]["pos"], "work_left": float(def["work"]), "built": false,
			"broken": false, "cost": cost})
		_send_hands(w.barricades.size() - 1)
		raised += 1
	if raised > 0:
		w.run.tell("Raiders spotted to the %s: folk run to barricade %d gap%s." % [World.compass(angle), raised, "" if raised == 1 else "s"])
		w.run.record.note_count("barricades_planned", raised)


## The nearest hands townsfolk free to barricade (a role with "barricades", not on an errand, levied or already
## barricading) within reach of barricade bi run to it.
func _send_hands(bi: int) -> void:
	var def: Dictionary = w.content.town["barricades"]
	var site: Vector2 = w.barricades[bi]["pos"]
	var free: Array = []
	for unit in w.folk:
		if unit.alive and unit.barricade < 0 and unit.errand_for == null and not levied(unit) \
				and w.content.townsfolk[unit.type_id].get("barricades", false) and unit.pos.distance_to(site) <= float(def["reach"]):
			free.append([unit.pos.distance_to(site), unit])
	free.sort_custom(func(a: Array, b: Array) -> bool: return a[0] < b[0])
	for n in mini(int(def["hands"]), free.size()):
		(free[n][1] as Unit).barricade = bi


## A townsperson running to raise its barricade. Returns false once there is nothing left to do there.
func _barricade_tick(unit: Unit) -> bool:
	var b: Dictionary = w.barricades[unit.barricade] if unit.barricade < w.barricades.size() else {}
	if b.is_empty() or b["built"]:
		unit.barricade = -1
		return false
	unit.intent = "throwing up a barricade"
	unit.activity = "barricade"
	if w.walk_toward(unit, b["pos"], 12.0):
		b["work_left"] = float(b["work_left"]) - work_rate(unit) * w.dt
		if float(b["work_left"]) <= 0.0:
			w.town.raise_barricade(unit.barricade)
			w.run.record.note_impact("folk", unit.type_id, "barricaded", 1.0)
			unit.barricade = -1
	return true


## Counts a daytime second spent idle toward the round's "idle_seconds" for the unit's role.
func _note_idle(unit: Unit) -> void:
	var t := float(_idle_time.get(unit.type_id, 0.0)) + w.dt
	if t >= 1.0:
		w.run.record.note_count("idle_seconds", int(t), unit.type_id)
		t -= int(t)
	_idle_time[unit.type_id] = t


func _choose_work(unit: Unit) -> void:
	if unit.type_id == "craftsperson":
		if _craft_job(unit):
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


## Sends a craftsperson to the open work with the fewest hands: each building going up and each workshop with
## something to make and a free bench is one task, a building's builders counting build_hand_weight hands each.
## On a tie a building comes first (oldest order first), then the workshop whose stall is emptiest, so one
## craftsperson keeps building while the others spread over the benches instead of all crowding the building
## site. A master has first dibs on a bench of their own workshop. Returns false when there is no such work
## (the craftsperson then paves or fetches wood).
func _craft_job(unit: Unit) -> bool:
	if unit.master_of != "" and _take_own_bench(unit):
		return true
	var weight := w.content.num("build_hand_weight")
	var best := -1
	var best_load := INF
	var best_tie := INF
	for i in w.buildings.size():
		var b := w.buildings[i]
		var load := 0.0
		var tie := 0.0
		if float(b["work_left"]) > 0.0:
			load = int(_builders.get(i, 0)) * weight
			tie = i - 100000.0
		elif _bench_open(i):
			load = int(_crafters.get(i, 0))
			tie = w.market.bench_tie(i)
		else:
			continue
		if load < best_load or (load == best_load and tie < best_tie):
			best = i
			best_load = load
			best_tie = tie
	if best < 0:
		return false
	if float(w.buildings[best]["work_left"]) > 0.0:
		unit.task = "build"
		_builders[best] = int(_builders.get(best, 0)) + 1
	else:
		unit.task = "craft"
		_crafters[best] = int(_crafters.get(best, 0)) + 1
	unit.task_index = best
	return true


## Whether workshop i is standing, has a free bench and has something to make (or something on the go).
func _bench_open(i: int) -> bool:
	var b := w.buildings[i]
	var def: Dictionary = w.content.buildings[b["type"]]
	if not def.has("workshop") or float(b["work_left"]) > 0.0:
		return false
	if int(_crafters.get(i, 0)) >= int(def["workshop"]["slots"]):
		return false
	return b["craft"] != "" or w.market.next_recipe(i) != ""


## First dibs: sends a master to a bench of their own workshop that has work, taking a free bench or bumping a
## plain craftsperson off a full one (the work done stays with the building, and the bumped one looks again).
func _take_own_bench(unit: Unit) -> bool:
	for i in w.buildings.size():
		var b := w.buildings[i]
		if b["type"] != unit.master_of or float(b["work_left"]) > 0.0:
			continue
		if b["craft"] == "" and w.market.next_recipe(i) == "":
			continue
		if not _bench_open(i):
			var plain: Array = w.folk.filter(func(u: Unit) -> bool:
				return u != unit and u.alive and u.task == "craft" and u.task_index == i and u.master_of != b["type"])
			if plain.is_empty():
				continue
			plain[0].task = ""
			_crafters[i] = int(_crafters.get(i, 0)) - 1
		unit.task = "craft"
		unit.task_index = i
		_crafters[i] = int(_crafters.get(i, 0)) + 1
		return true
	return false


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


## True if a point lies outside the town within attack_way_band radians of one of this round's attack ways.
func _on_attack_way(p: Vector2) -> bool:
	if p.length() <= w.content.num("settlement_radius"):
		return false
	var band := w.content.num("attack_way_band")
	return w.wave_sides.any(func(side: float) -> bool: return absf(angle_difference(side, p.angle())) < band)


## Picks the gathering trip worth the most to the town, or -1. Each trip is scored by how badly the town
## needs the good (after what is already on its way in) times what this gatherer can carry back from what
## the node will have left once the others heading there have taken theirs, over the time the round trip takes.
## A trip that can't reach the node and finish gathering before dusk isn't started.
## Craftspeople only fetch wood. A gatherer's leaning makes trips for its goods worth leaning_weight times more, and
## gives it first dibs on them: it counts what gatherers there who don't lean to the good claimed as free (_choose_work bumps them).
## On the attack's day trips out along the way it comes in are worth attack_way_keep_off as much.
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
	var attack_day := w.day_index() == w.content.int_num("days_per_round") - 1
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
		# On the attack's day they keep away from the way it will come in.
		if attack_day and _on_attack_way(node["pos"]):
			score *= w.content.num("attack_way_keep_off")
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
	var carry := float(w.content.townsfolk[unit.type_id].get("carry", 2)) + w.run.tool_bonus(unit.type_id, "carry") \
		+ unit_mod(unit, "carry")
	if leans_to(unit, good):
		carry += float(band_tier(unit).get("carry", 0))
	var mult := 1.0 + w.run.mod("carry_mult")
	if node_type != "":
		mult += w.run.tag_mod("node_yield", w.content.tags_of("node", node_type))
	return int(carry * mult)


## Seconds a townsperson spends gathering a good at a node (tools and its band included).
func gather_time(unit: Unit, good := "") -> float:
	var mult := w.run.tool_bonus(unit.type_id, "gather_mult") + unit_mod(unit, "gather_mult")
	if leans_to(unit, good):
		mult += float(band_tier(unit).get("gather_mult", 0))
	return float(w.content.townsfolk[unit.type_id].get("gather_seconds", 3)) / (1.0 + mult)


## Living townsfolk per role and leaning, keyed "role/leaning".
func count_leanings() -> Dictionary:
	var out := {}
	for unit in w.folk:
		if unit.alive and unit.leaning != "":
			var key := unit.type_id + "/" + unit.leaning
			# A born leader (data/card_mods.json band_weight) counts as more than one.
			out[key] = int(out.get(key, 0)) + 1 + int(unit_mod(unit, "band_weight"))
	return out


## The highest band tier a role's townsfolk sharing a leaning reach at this size (data band_tiers), or {}.
## A leaning the town's traditions favour bands tradition_band_ease sooner.
func tier_for(role: String, leaning: String, size: int) -> Dictionary:
	var tiers: Array = w.content.townsfolk[role].get("band_tiers", [])
	var level := band_level(role, leaning, size)
	return tiers[level - 1] if level > 0 else {}


## How many band tiers a role's townsfolk sharing a leaning reach at this size (0 for none).
func band_level(role: String, leaning: String, size: int) -> int:
	var ease := band_ease(leaning)
	var level := 0
	for tier: Dictionary in w.content.townsfolk[role].get("band_tiers", []):
		if size >= int(tier["size"]) - ease:
			level += 1
	return level


## The size a band tier needs for this leaning (traditions included).
func band_size_needed(role: String, leaning: String, tier: Dictionary) -> int:
	return int(tier["size"]) - band_ease(leaning)


## How many fewer townsfolk this leaning's bands need: tradition_band_ease for a tradition's leaning, plus
## band_ease from buildings (the brewhouse).
func band_ease(leaning: String) -> int:
	return (w.content.int_num("tradition_band_ease") if w.run.tradition_leanings().has(leaning) else 0) + int(w.run.mod("band_ease"))


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
	return (float(w.content.townsfolk[unit.type_id].get("build_rate", 0.5)) + w.run.tool_bonus(unit.type_id, "build_rate")) \
		* (1.0 + unit_mod(unit, "build"))


# --- Runners ------------------------------------------------------------------

## The first finished building tagged courier (the runners' hut), or -1.
func courier_hut() -> int:
	for i in w.buildings.size():
		var b := w.buildings[i]
		if float(b["work_left"]) <= 0.0 and w.content.has_tag("building", b["type"], "courier"):
			return i
	return -1


func _runners_def(hut: int) -> Dictionary:
	return w.content.buildings[w.buildings[hut]["type"]].get("runners", {})


## Shells a hero pays a courier building's runner on top of the stall price.
func runner_fee(hut: int) -> int:
	return int(_runners_def(hut).get("fee", 0))


## Each step: heroes in the wilds who sent for supplies (HeroAI._call_for_supplies) get a runner, while the courier
## building has runners to spare. A runner is a tribesperson in town not hauling anything, nearest the building first.
func _dispatch_runners() -> void:
	if w.is_dusk():
		return
	var hut := courier_hut()
	if hut < 0:
		return
	var def := _runners_def(hut)
	var out := 0
	var callers: Array[Unit] = []
	for hero in w.run.heroes:
		if not hero.alive:
			continue
		if w.hero_ai.runner_coming(hero):
			out += 1
		elif hero.supply_call != "" and hero.pos.length() <= float(def.get("reach", INF)):
			callers.append(hero)
	for hero in callers:
		if out >= int(def.get("slots", 1)):
			return
		var runner := _free_runner(w.buildings[hut]["pos"])
		if runner == null:
			return
		if runner.task == "gather":
			w.run.record.note_count("trips_cut_short", 1, "runner")
		runner.task = "run"
		runner.errand_for = hero
		runner.parcel = {}
		hero.runner = runner
		out += 1


## The tribesperson in town nearest `at` who is free to run: alive, carrying nothing and not already running.
func _free_runner(at: Vector2) -> Unit:
	var best: Unit = null
	var best_d := INF
	for unit in w.folk:
		if not unit.alive or unit.type_id != "tribesperson" or unit.errand_for != null or unit.carry_amount > 0 or levied(unit):
			continue
		if unit.pos.length() > w.content.num("settlement_radius"):
			continue
		var d := unit.pos.distance_squared_to(at)
		if d < best_d:
			best_d = d
			best = unit
	return best


## A runner fetches the provision its hero sent for from the stall, then runs it out to them, chasing them as they
## move. It gives up at dusk, when the hero dies, comes home or goes out of reach, or when the stall has none.
func _run_errand(unit: Unit) -> void:
	var hero := unit.errand_for
	var hut := courier_hut()
	var reach := float(_runners_def(hut).get("reach", INF)) if hut >= 0 else 0.0
	if hut < 0 or w.is_dusk() or not hero.alive or hero.runner != unit or hero.pos.length() > reach + 60.0 \
			or hero.pos.length() <= w.content.num("settlement_radius") or (unit.parcel.is_empty() and hero.supply_call == ""):
		_end_errand(unit)
		return
	if unit.parcel.is_empty():
		var pick := w.market.provision_on_stall(hero.supply_call)
		if pick.is_empty():
			_end_errand(unit)
			return
		var stall: Dictionary = w.buildings[pick["stall"]]
		unit.intent = "fetching %s for %s" % [w.content.recipe_name(stall["goods"][pick["index"]]["recipe"]), hero.display_name]
		if w.walk_toward(unit, stall["pos"], 12.0):
			unit.parcel = stall["goods"][pick["index"]]
			unit.parcel["stall"] = pick["stall"]
			stall["goods"].remove_at(pick["index"])
		return
	unit.intent = "running %s out to %s" % [w.content.recipe_name(unit.parcel["recipe"]), hero.display_name]
	if w.walk_toward(unit, hero.pos, 14.0):
		_deliver(unit, hero)


## The hero pays the stall price and the fee into the town's stock and takes the provision; a hero who can no longer
## pay sends the runner back.
func _deliver(unit: Unit, hero: Unit) -> void:
	var good := unit.parcel.duplicate()
	good.erase("stall")
	var price := w.run.price_of(good)
	var fee := runner_fee(courier_hut())
	if hero.gold < price + fee:
		_end_errand(unit)
		return
	hero.gold -= price + fee
	w.run.stock["shells"] = int(w.run.stock["shells"]) + price + fee
	w.run.record.note_hero_spending("market", price)
	w.run.record.note_hero_spending("runners", fee)
	w.run.record.note_market_sale(hero, good, price)
	w.run.record.note_count("supply_runs", 1, good["recipe"])
	w.run.record.note_impact("folk", unit.type_id, "supplied", 1.0)
	var key := w.run.record.impact_key(hero)
	if not key.is_empty():
		w.run.record.note_impact(key[0], key[1], "supplied", 1.0)
	var r: Dictionary = w.content.market["recipes"][good["recipe"]]
	var effect := "heal" if w.content.market["provisions"][r["provision"]].has("heal") else "energy"
	w.supply_drops.append({"pos": hero.pos, "text": "+%s" % w.content.recipe_name(good["recipe"])})
	if w.supply_drops.size() > World.SUPPLY_DROPS_KEPT:
		w.supply_drops.pop_front()
	w.supplies_delivered += 1
	w.run.tell("A runner reaches %s with %s (%d shells)." % [hero.display_name, w.content.recipe_name(good["recipe"]), price + fee])
	unit.parcel = {}
	hero.pack.append(good["recipe"])
	w.hero_ai.on_supplied(hero, effect)
	_end_errand(unit)


## Ends a runner's errand. A provision it still carries goes back on its stall.
func _end_errand(unit: Unit) -> void:
	if not unit.parcel.is_empty():
		var s := int(unit.parcel["stall"])
		var good := unit.parcel.duplicate()
		good.erase("stall")
		if s < w.buildings.size() and w.content.buildings[w.buildings[s]["type"]].has("stall"):
			w.buildings[s]["goods"].append(good)
		unit.parcel = {}
	var hero := unit.errand_for
	if hero != null and hero.runner == unit:
		hero.runner = null
	unit.errand_for = null
	unit.task = ""
