class_name EnemyAI
extends RefCounted
## Enemies in the World: den wanderers, the warned wave, early-night probes,
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
		var living := w.enemies.filter(func(e: Unit) -> bool: return e.alive and e.den_index == i).size()
		den["respawn_left"] = float(den["respawn_left"]) - w.dt
		if living < cap and float(den["respawn_left"]) <= 0.0:
			den["respawn_left"] = w.content.num("den_respawn_seconds")
			var e := make_enemy(den["spawns"], den["pos"] + Vector2.from_angle(w.rng.randf() * TAU) * 20.0, w.time,
				1.0 + 0.08 * (w.run.round_number - 1))
			e.den_index = i
			e.wander_goal = e.pos
			w.enemies.append(e)


func enemy_tick(enemy: Unit) -> void:
	enemy.cooldown_left -= w.dt
	var aggro := w.content.num("enemy_aggro")
	var holding_grudge := enemy.target != null and enemy.target.alive and w.time < enemy.grudge_until
	if not holding_grudge and (enemy.target == null or not enemy.target.alive or enemy.pos.distance_to(enemy.target.pos) > aggro * 3.0):
		enemy.target = w.nearest_friend(enemy.pos, aggro)
	if enemy.target != null:
		w.fight(enemy, enemy.target)
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
		w.hearth_hp -= dmg
		w.wave_stats["keep_damage"] = float(w.wave_stats["keep_damage"]) + dmg
		w.night_report["hearth_damage"] = float(w.night_report["hearth_damage"]) + dmg
		w.shots.append({"from": enemy.pos, "to": Vector2.ZERO, "ranged": enemy.attack_range > 60, "time": w.time})


## Wanderers drift around their den, ranging much farther at night.
func _wander(enemy: Unit) -> void:
	var den: Dictionary = w.dens[enemy.den_index]
	var roam := w.content.num("den_roam_night") if w.is_night() else w.content.num("den_roam_day")
	if enemy.pos.distance_to(enemy.wander_goal) < 6.0 or enemy.wander_goal.distance_to(den["pos"]) > roam:
		var goal: Vector2 = den["pos"] + Vector2.from_angle(w.rng.randf() * TAU) * w.rng.randf_range(0.0, roam)
		enemy.wander_goal = goal.limit_length(w.content.num("world_radius"))
	var old_speed := enemy.speed
	enemy.speed *= 0.5
	w.walk_toward(enemy, enemy.wander_goal)
	enemy.speed = old_speed


func spawn_wave() -> void:
	w.wave_spawned = true
	w.wave_stats["hearth_hp_before"] = w.hearth_hp
	var types := w.run.next_wave
	w.run.note_power(types)
	var interval := w.content.num("wave_spawn_interval")
	w.night_report["raiders"] = int(w.night_report["raiders"]) + types.size()
	for i in types.size():
		var side: float = w.wave_sides[i % w.wave_sides.size()]
		var at := Vector2.from_angle(side + w.rng.randf_range(-0.25, 0.25)) * w.content.num("world_radius")
		w.enemies.append(make_enemy(types[i], at, w.time + i * interval))


## A small raid on an early night, from a random side, not warned of.
func spawn_probe() -> void:
	var types := w.run.generate_probe(w.run.round_number, w.day_index())
	var side := SeededRng.stream(w.run.run_seed, "probe", w.run.round_number * 10 + w.day_index()).randi_range(0, 3) * PI / 2.0
	for i in types.size():
		var at := Vector2.from_angle(side + w.rng.randf_range(-0.3, 0.3)) * w.content.num("world_radius") * 0.8
		var e := make_enemy(types[i], at, w.time + i * w.content.num("wave_spawn_interval"))
		e.is_probe = true
		w.enemies.append(e)
	w.night_report["raiders"] = int(w.night_report["raiders"]) + types.size()
	if not types.is_empty():
		w.run.tell("Raiders probe the camp from the %s." % ["east", "south", "west", "north"][int(round(side / (PI / 2.0))) % 4])


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
		var target := w.nearest_enemy(Vector2.ZERO, w.content.num("hearth_range"))
		if target != null:
			w.hearth_cooldown_left = w.content.num("hearth_cooldown")
			w.shots.append({"from": Vector2.ZERO, "to": target.pos, "ranged": true, "time": w.time})
			w.damage(null, target, (w.content.num("hearth_attack") + w.run.mod("tower_attack")) * shield_left(target))
	for b in w.buildings:
		var def: Dictionary = w.content.buildings[b["type"]]
		if not def.has("attack") or float(b["work_left"]) > 0.0:
			continue
		b["cooldown_left"] = float(b["cooldown_left"]) - w.dt
		if float(b["cooldown_left"]) > 0.0:
			continue
		var target := w.nearest_enemy(b["pos"], float(def["range"]))
		if target != null:
			b["cooldown_left"] = float(def["cooldown"])
			w.shots.append({"from": b["pos"], "to": target.pos, "ranged": true, "time": w.time})
			w.damage(null, target, (float(def["attack"]) + w.run.mod("tower_attack")) * shield_left(target))


## Share of a stone blow (arrows, the hearth's fire) that gets past a shield.
func shield_left(enemy: Unit) -> float:
	return 1.0 - float(w.content.enemies[enemy.type_id].get("shield", 0.0))
