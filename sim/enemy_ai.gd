class_name EnemyAI
extends RefCounted
## Enemies in the World: den wanderers, the war camp, the warned wave, early-night probes,
## how enemies pick targets and attack the hearth, plus the hearth's and towers' fire.
## Holds no state of its own: everything lives on `w` (the World).

var w: World


func _init(world: World) -> void:
	w = world


func dens_tick() -> void:
	var level := 1 + (w.run.round_number - 1) / 2.0
	var cap := w.content.int_num("den_base_wanderers") + int(w.content.num("den_wanderers_per_level") * (level - 1.0))
	for i in w.dens.size():
		var den := w.dens[i]
		if den.get("camp", false):
			continue
		var living := w.enemies.filter(func(e: Unit) -> bool: return e.alive and e.den_index == i).size()
		den["respawn_left"] = float(den["respawn_left"]) - w.dt
		if living < cap and float(den["respawn_left"]) <= 0.0:
			den["respawn_left"] = w.content.num("den_respawn_seconds")
			var e := make_enemy(den_spawns(den), den["pos"] + Vector2.from_angle(w.rng.randf() * TAU) * 20.0, w.time,
				1.0 + 0.08 * (w.run.round_number - 1))
			e.den_index = i
			e.wander_goal = e.pos
			w.enemies.append(e)


## What a den sends out this round: its later creature once that round comes (by round, never by age).
func den_spawns(den: Dictionary) -> String:
	var later: Dictionary = w.content.world["dens"][den["type"]].get("later", {})
	if not later.is_empty() and w.run.round_number >= int(later["from_round"]):
		return later["spawns"]
	return den["spawns"]


func enemy_tick(enemy: Unit) -> void:
	enemy.cooldown_left -= w.dt
	var aggro := w.content.num("enemy_aggro")
	var holding_grudge := enemy.target != null and enemy.target.alive and w.time < enemy.grudge_until
	if enemy.target_tower >= 0:
		if w.time < enemy.grudge_until and tower_standing(enemy.target_tower):
			_attack_tower(enemy, enemy.target_tower)
			return
		enemy.target_tower = -1
	if w.content.unit_has_tag(enemy, "siege"):
		enemy.target = null
	elif not holding_grudge and (enemy.target == null or not enemy.target.alive or enemy.pos.distance_to(enemy.target.pos) > aggro * 3.0):
		enemy.target = w.nearest_friend(enemy.pos, aggro)
		# Wolf-mother's skull: beasts let townsfolk be unless one strikes them (a grudge).
		if enemy.target != null and enemy.target.is_folk() and w.run.has_effect("beast_peace") and w.content.unit_has_tag(enemy, "beast"):
			enemy.target = null
	if enemy.target != null:
		w.fight(enemy, enemy.target)
		return
	# A pedlar's camp close by is easy pickings.
	if w.pedlar.draws(enemy):
		w.pedlar.raid(enemy)
		return
	if enemy.den_index >= 0:
		_wander(enemy)
		return
	var hold_at := float(w.content.enemies[enemy.type_id].get("hold_at", 0.0))
	if hold_at > 0.0 and enemy.pos.length() <= hold_at and not _only_holders_left():
		return
	if enemy.pos.length() > enemy.attack_range + World.HEARTH_RADIUS:
		w.walk_toward(enemy, Vector2.ZERO)
	elif enemy.cooldown_left <= 0.0:
		enemy.cooldown_left = enemy.cooldown
		var dmg := enemy.attack * war_chant()
		if w.content.unit_has_tag(enemy, "siege"):
			w.run.record.note_count("siege_damage", roundi(dmg))
			thorns(enemy)
		w.run.record.note_impact("defences", "hearth", "taken", minf(dmg, maxf(0.0, w.hearth_hp)))
		w.hearth_hp -= dmg
		w.wave_stats["keep_damage"] = float(w.wave_stats["keep_damage"]) + dmg
		w.night_report["hearth_damage"] = float(w.night_report["hearth_damage"]) + dmg
		w.shots.append({"from": enemy.pos, "to": Vector2.ZERO, "ranged": enemy.attack_range > 60, "time": w.time})


## Wanderers drift around their den, ranging much farther at night.
func _wander(enemy: Unit) -> void:
	var den: Dictionary = w.dens[enemy.den_index]
	var roam := w.content.num("den_roam_night") if w.is_night() else w.content.num("den_roam_day")
	if den.get("camp", false):
		roam = w.content.num("camp_roam")
	if enemy.pos.distance_to(enemy.wander_goal) < 6.0 or enemy.wander_goal.distance_to(den["pos"]) > roam:
		var goal: Vector2 = den["pos"] + Vector2.from_angle(w.rng.randf() * TAU) * w.rng.randf_range(0.0, roam)
		enemy.wander_goal = goal.limit_length(w.content.num("world_radius"))
	var old_speed := enemy.speed
	enemy.speed *= 0.5
	w.walk_toward(enemy, enemy.wander_goal)
	enemy.speed = old_speed


## Raiders the warband held back make a war camp in the wilds instead of vanishing (see _camp_note in
## data/balance.json). They join the camp already standing, up to camp_max_raiders living; battering rams
## never camp. Returns how many joined.
func make_camp(types: Array[String]) -> int:
	var ci := w.camp_index()
	var room := w.content.int_num("camp_max_raiders") - (camp_raiders().size() if ci >= 0 else 0)
	var joining: Array[String] = []
	for id in types:
		if joining.size() < room and not w.content.has_tag("enemy", id, "siege"):
			joining.append(id)
	if joining.is_empty():
		return 0
	if ci < 0:
		w.dens.append({"type": "war_camp", "spawns": joining[0], "pos": _camp_site(), "respawn_left": 0.0,
			"camp": true, "joined": 0})
		ci = w.dens.size() - 1
	var camp := w.dens[ci]
	var rng := SeededRng.stream(w.run.run_seed, "camp_raiders", w.run.round_number)
	for id in joining:
		var e := make_enemy(id, camp["pos"] + Vector2.from_angle(rng.randf() * TAU) * rng.randf_range(5.0, 25.0), 0.0)
		e.spawned = true
		e.den_index = ci
		e.wander_goal = e.pos
		e.joined_round = w.run.round_number
		w.enemies.append(e)
	camp["joined"] = int(camp["joined"]) + joining.size()
	return joining.size()


## The war camp's living raiders.
func camp_raiders() -> Array[Unit]:
	var ci := w.camp_index()
	var out: Array[Unit] = []
	for e in w.enemies:
		if ci >= 0 and e.alive and e.den_index == ci:
			out.append(e)
	return out


## The node the war camp sits by: one townsfolk gather, a fair way out. The camp goes a little beyond it.
func _camp_site() -> Vector2:
	var rng := SeededRng.stream(w.run.run_seed, "camp", w.run.round_number)
	var lo := w.content.num("camp_node_min_distance")
	var hi := w.content.num("camp_node_max_distance")
	var options: Array[Vector2] = []
	for node in w.nodes:
		var d: float = node["pos"].length()
		if d >= lo and d <= hi and int(node["amount"]) > 0 and not node["heroes_only"] and not node["wild"] and w.node_active(node):
			options.append(node["pos"])
	var at := Vector2.from_angle(rng.randf() * TAU) * hi
	if not options.is_empty():
		at = options[rng.randi_range(0, options.size() - 1)]
	return at.normalized() * maxf(at.length() + w.content.num("camp_offset"), w.content.num("camp_min_distance"))


## When the war camp's last raider falls the camp is cleared: the town takes the spoils (camp_spoils_per_raider,
## 0 since mercy became a loan), and a hero who struck the last blow finds an item.
func on_camper_killed(victim: Unit, attacker: Unit) -> void:
	var ci := w.camp_index()
	if ci < 0 or victim.den_index != ci or not camp_raiders().is_empty():
		return
	var camp := w.dens[ci]
	camp["cleared"] = true
	var spoils := int(camp["joined"]) * w.content.int_num("camp_spoils_per_raider")
	w.run.stock["shells"] = int(w.run.stock["shells"]) + spoils
	w.run.record.note_count("camps_cleared", 1)
	w.run.record.note_count("camp_spoils", spoils)
	var who := "%s breaks" % attacker.display_name if attacker != null and attacker.is_hero() else "Your people break"
	var plunder := ": %d shells of plunder come back to town, and" % spoils if spoils > 0 else ": nobody marches from it now, and"
	w.run.tell("%s the war camp%s the land round it is free again." % [who, plunder])
	if attacker != null and attacker.is_hero():
		w.hero_ai.give_item(attacker, Loot.roll(w.content, w.rng, w.run.round_number, w.run.age))


func spawn_wave() -> void:
	w.wave_spawned = true
	w.wave_stats["hearth_hp_before"] = w.hearth_hp
	var types := w.run.next_wave
	w.run.record.note_power(w.run.waves.attack())
	var interval := w.content.num("wave_spawn_interval")
	w.night_report["raiders"] = int(w.night_report["raiders"]) + types.size()
	for i in types.size():
		var side: float = w.wave_sides[i % w.wave_sides.size()]
		var at := Vector2.from_angle(side + w.rng.randf_range(-0.25, 0.25)) * w.content.num("world_radius")
		w.enemies.append(make_enemy(types[i], at, w.time + i * interval))
	_camp_marches()


## The loan comes due: the war camp's raiders who joined it in an earlier round leave it and march on the hearth
## with the attack. A camp left empty is gone (no plunder: nobody broke it).
func _camp_marches() -> void:
	var ci := w.camp_index()
	if ci < 0:
		return
	var marching := camp_raiders().filter(func(e: Unit) -> bool: return e.joined_round < w.run.round_number)
	if marching.is_empty():
		return
	for e: Unit in marching:
		e.den_index = -1
		e.target = null
	w.night_report["raiders"] = int(w.night_report["raiders"]) + marching.size()
	w.run.record.note_count("camp_marched", marching.size())
	if camp_raiders().is_empty():
		w.dens[ci]["cleared"] = true
		w.dens[ci]["marched"] = true
	w.run.tell("The war camp's %d raider%s march on the hearth with the attack." % [marching.size(), "" if marching.size() == 1 else "s"])


## A small raid on an early night, from a random side, not warned of.
func spawn_probe() -> void:
	if w.run.has_effect("no_probes"):
		w.run.relic_fired("no_probes")
		return
	var types := w.run.waves.probe(w.run.round_number, w.day_index())
	var side := SeededRng.stream(w.run.run_seed, "probe", w.run.round_number * 10 + w.day_index()).randi_range(0, 3) * PI / 2.0
	for i in types.size():
		var at := Vector2.from_angle(side + w.rng.randf_range(-0.3, 0.3)) * w.content.num("world_radius") * 0.8
		var e := make_enemy(types[i], at, w.time + i * w.content.num("wave_spawn_interval"))
		e.is_probe = true
		w.enemies.append(e)
	w.night_report["raiders"] = int(w.night_report["raiders"]) + types.size()
	if not types.is_empty():
		w.run.tell("Raiders probe the town from the %s." % ["east", "south", "west", "north"][int(round(side / (PI / 2.0))) % 4])


## Ram-thorn stakes: a siege engine that strikes a gate or the hearth is hurt in turn.
func thorns(enemy: Unit) -> void:
	var hurt := w.run.mod("siege_thorns")
	if hurt > 0.0 and enemy.alive:
		w.damage(null, enemy, hurt, "relic")
		w.run.relic_fired("siege_thorns")


func war_chant() -> float:
	var mult := 1.0
	for enemy in w.enemies:
		if enemy.alive and enemy.spawned:
			mult += float(w.content.enemies[enemy.type_id].get("war_chant", 0.0))
	return mult


func _only_holders_left() -> bool:
	for enemy in w.enemies:
		if enemy.alive and enemy.den_index < 0 and float(w.content.enemies[enemy.type_id].get("hold_at", 0.0)) <= 0.0:
			return false
	return true


func make_enemy(type_id: String, at: Vector2, spawn_time: float, scale := 1.0) -> Unit:
	var e: Dictionary = w.content.enemies[type_id]
	var enemy := Unit.new()
	enemy.id = w.run.new_id()
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
	enemy.spawned = spawn_time <= w.time
	enemy.pos = at
	return enemy


func towers_tick() -> void:
	w.hearth_cooldown_left -= w.dt
	if w.hearth_cooldown_left <= 0.0:
		var target := sighted(Vector2.ZERO, w.content.num("hearth_range"))
		if target != null:
			w.hearth_cooldown_left = w.content.num("hearth_cooldown")
			w.shots.append({"from": Vector2.ZERO, "to": target.pos, "ranged": true, "tower": true, "time": w.time})
			w.damage(null, target, (w.content.num("hearth_attack") + w.run.mod("tower_attack")) * armour_left(target), "hearth")
	for b in w.buildings:
		var def: Dictionary = w.content.buildings[b["type"]]
		if not def.has("attack") or float(b["work_left"]) > 0.0:
			continue
		b["cooldown_left"] = float(b["cooldown_left"]) - w.dt
		if float(b["cooldown_left"]) > 0.0:
			continue
		if def.has("tower_hp") and float(b["hp"]) <= 0.0:
			continue
		var target := sighted(b["pos"], float(def["range"]))
		if target != null:
			b["cooldown_left"] = float(def["cooldown"])
			w.shots.append({"from": b["pos"], "to": target.pos, "ranged": true, "tower": true, "time": w.time})
			w.damage(null, target, (float(def["attack"]) + w.run.mod("tower_attack")) * armour_left(target), b["type"])
			# Sentient raiders turn on the tower that shot them (siege engines only want gates and the hearth); every
			# raider turns on a Wrathful one (grudge_all, data/card_mods.json).
			if target.alive and def.has("tower_hp") \
					and (w.content.unit_has_tag(target, "sentient") or float(def.get("grudge_all", 0.0)) > 0.0) \
					and not w.content.unit_has_tag(target, "siege"):
				target.target = null
				target.target_tower = w.buildings.find(b)
				target.grudge_until = w.time + w.content.num("tower_grudge_seconds")


## The town spots raiders coming for it (not den wanderers): a townsperson or hero near one, or the hearth or a
## standing tower that can see it, each farther on open ground and nearer in cover (Earth.sight_at). The first
## sighting of each raider raises the alarm from its way (FolkAI.raise_alarm), where folk run to barricade the gaps.
func spot_tick() -> void:
	var def: Dictionary = w.content.town["barricades"]
	for e in w.enemies:
		if e.spotted or not e.alive or not e.spawned or e.den_index >= 0 or e.risen:
			continue
		var by := _spotter(e, float(def["spot_range"]))
		if by.is_empty():
			continue
		e.spotted = true
		w.spots.append({"by": by["pos"], "at": e.pos, "time": w.time})
		w.run.record.note_count("spotted", 1, by["who"])
		w.folk_ai.raise_alarm(e.pos)
	var keep := float(def["spot_show_seconds"])
	w.spots = w.spots.filter(func(s: Dictionary) -> bool: return w.time - float(s["time"]) < keep)


## Who sees raider e first: {pos, who} ("folk", "hero", "tower" or "hearth"), or {} for nobody yet.
func _spotter(e: Unit, reach: float) -> Dictionary:
	var sight := w.earth.sight_at(e.pos)
	var friend := w.nearest_friend(e.pos, reach * sight)
	if friend != null:
		return {"pos": friend.pos, "who": "hero" if friend.is_hero() else "folk"}
	for b in w.buildings:
		var def: Dictionary = w.content.buildings[b["type"]]
		if def.has("range") and def.has("attack") and float(b["work_left"]) <= 0.0 \
				and not (def.has("tower_hp") and float(b["hp"]) <= 0.0) and (b["pos"] as Vector2).distance_to(e.pos) <= float(def["range"]) * sight:
			return {"pos": b["pos"], "who": "tower"}
	if e.pos.length() <= w.content.num("hearth_range") * sight:
		return {"pos": Vector2.ZERO, "who": "hearth"}
	return {}


## The nearest raider the hearth or a tower at `from` can see with this range: the near plate a raider stands on
## stretches or shortens how far off it is seen (Earth.sight_at: open Stonefield, Greenwood cover).
func sighted(from: Vector2, reach: float) -> Unit:
	var sights: Array = [1.0]
	for kind: String in w.content.plates["near_kinds"]:
		var s := float(w.earth.kind_def(kind).get("sight", 1.0))
		if not sights.has(s):
			sights.append(s)
	sights.sort()
	sights.reverse()
	for s: float in sights:
		var target := w.nearest_enemy(from, reach * s)
		if target != null and from.distance_to(target.pos) <= reach * w.earth.sight_at(target.pos):
			return target
	return null


## True if building b is a tower that still stands (not broken).
func tower_standing(b: int) -> bool:
	if b < 0 or b >= w.buildings.size():
		return false
	var building: Dictionary = w.buildings[b]
	return w.content.buildings[building["type"]].has("tower_hp") and float(building["work_left"]) <= 0.0 and float(building["hp"]) > 0.0


## Walks up to a tower and hits it. A tower at 0 health is broken: it stops shooting until mended at dawn.
func _attack_tower(enemy: Unit, b: int) -> void:
	var building: Dictionary = w.buildings[b]
	var reach := enemy.attack_range + w.content.num("tower_reach")
	if not w.walk_toward(enemy, building["pos"], reach):
		return
	if enemy.cooldown_left > 0.0:
		return
	enemy.cooldown_left = enemy.cooldown
	var dmg := enemy.attack * war_chant()
	w.shots.append({"from": enemy.pos, "to": building["pos"], "ranged": enemy.attack_range > 60, "time": w.time})
	w.run.record.note_impact("defences", building["type"], "taken", minf(dmg, float(building["hp"])))
	building["hp"] = maxf(0.0, float(building["hp"]) - dmg)
	if float(building["hp"]) <= 0.0:
		enemy.target_tower = -1
		w.run.record.note_count("towers_broken", 1)
		w.run.tell("A %s broke the %s: it shoots no more until it is mended at dawn." % [
			enemy.display_name.to_lower(), w.content.buildings[building["type"]]["name"].to_lower()])


## At dawn, every tower is mended to full health.
func mend_towers() -> void:
	for b in w.buildings:
		var def: Dictionary = w.content.buildings[b["type"]]
		if def.has("tower_hp"):
			b["hp"] = float(def["tower_hp"])


## Share of a blow that gets past an enemy's armour: a shield turns blows that aren't metal,
## mail turns blows that aren't steel. Arrows and the hearth's fire are neither.
func armour_left(enemy: Unit, metal := false, steel := false) -> float:
	var e: Dictionary = w.content.enemies[enemy.type_id]
	var left := 1.0
	if not metal and not steel:
		left *= 1.0 - float(e.get("shield", 0.0))
	if not steel:
		left *= 1.0 - float(e.get("mail", 0.0))
	return left
