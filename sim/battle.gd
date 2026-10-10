class_name Battle
extends RefCounted
## One wave, resolved automatically in fixed time steps (no player input).
##
## Call step() repeatedly (the game does a few per frame so you can watch),
## or run_to_end() to resolve instantly (tests and balance runs).
## Heroes pick their own targets from their personality, bounties and danger;
## the player only influenced the inputs during the decision phase.

const KEEP_RADIUS := 40.0
const ENEMY_AGGRO := 40.0
const HEAL_UNTIL := 0.85
const TARGET_STICKINESS := 3.0

var run: RunState
var content: Content
var rng: SeededRng
var dt: float
var arena := Vector2.ZERO
var keep_pos := Vector2.ZERO

var heroes: Array[Unit] = []
var enemies: Array[Unit] = []
var keep_hp := 0.0
var keep_cooldown_left := 0.0
var time := 0.0
var over := false
var won := false

var bounties := {}
var bounty_reserved := 0
var bounty_paid := 0
## Plain-language notable moments, newest last.
var story: Array[String] = []
## Structured facts for the run record: {hero, killer, time} per hero death.
var hero_deaths: Array[Dictionary] = []
var retreats := 0
var keep_damage_taken := 0.0
## Recent attacks for drawing: {from: Vector2, to: Vector2, ranged: bool, time: float}.
var shots: Array[Dictionary] = []


func _init(run_state: RunState, battle_rng: SeededRng, reserved: int) -> void:
	run = run_state
	content = run.content
	rng = battle_rng
	dt = 1.0 / content.num("ticks_per_second")
	arena = Vector2(content.num("arena_width"), content.num("arena_height"))
	keep_pos = Vector2(80, arena.y / 2.0)
	keep_hp = run.keep_hp
	bounties = run.bounties.duplicate()
	bounty_reserved = reserved
	heroes = run.heroes.duplicate()
	for i in heroes.size():
		var hero := heroes[i]
		hero.pos = _guard_pos(hero, i)
		hero.target = null
		hero.retreating = false
		hero.cooldown_left = 0.0
		hero.intent = "waiting"
	var interval := content.num("wave_spawn_interval")
	for i in run.next_wave.size():
		enemies.append(_make_enemy(run.next_wave[i], i * interval))


func run_to_end() -> void:
	while not over:
		step()


func step() -> void:
	if over:
		return
	time += dt
	for enemy in enemies:
		if not enemy.spawned and time >= enemy.spawn_time:
			enemy.spawned = true
	for hero in heroes:
		if hero.alive:
			_hero_tick(hero)
	for enemy in enemies:
		if enemy.alive and enemy.spawned:
			_enemy_tick(enemy)
	_keep_tick()
	shots = shots.filter(func(s: Dictionary) -> bool: return time - float(s["time"]) < 0.2)
	_check_end()


## Breaks hero<->enemy references so the wave's units can be freed.
func release() -> void:
	for unit in heroes + enemies:
		unit.target = null


func living_enemies() -> Array[Unit]:
	return enemies.filter(func(e: Unit) -> bool: return e.alive and e.spawned)


## Enemy damage multiplier from living war-chanting enemies (shamans).
func war_chant() -> float:
	var mult := 1.0
	for enemy in living_enemies():
		mult += float(content.enemies[enemy.type_id].get("war_chant", 0.0))
	return mult


func enemies_remaining() -> int:
	return enemies.filter(func(e: Unit) -> bool: return e.alive).size()


# --- Heroes ----------------------------------------------------------------

func _hero_tick(hero: Unit) -> void:
	var t: Dictionary = content.traits[hero.trait_id]
	hero.cooldown_left -= dt
	var retreat_at := clampf(float(t["retreat_at"]) + run.mod("retreat_shift"), 0.0, 0.95)
	if not hero.retreating and hero.hp_fraction() < retreat_at:
		hero.retreating = true
		hero.target = null
		story.append("%s is badly hurt and falls back to the keep." % hero.display_name)
		retreats += 1
	if hero.retreating:
		hero.intent = "retreating to heal"
		if hero.pos.distance_to(keep_pos) > KEEP_RADIUS:
			_move_toward(hero, keep_pos)
		else:
			var rate := content.num("keep_heal_rate") * (1.0 + run.mod("keep_heal_mult"))
			hero.hp = minf(hero.max_hp, hero.hp + rate * dt)
			if hero.hp_fraction() >= HEAL_UNTIL:
				hero.retreating = false
		return
	hero.target = _choose_target(hero, t)
	if hero.target == null:
		hero.intent = "guarding the keep"
		if hero.pos.distance_to(_guard_pos(hero)) > 4.0:
			_move_toward(hero, _guard_pos(hero))
		return
	if hero.pos.distance_to(hero.target.pos) > hero.attack_range:
		_move_toward(hero, hero.target.pos)
	elif hero.cooldown_left <= 0.0:
		_hit(hero, hero.target)


## Scores every visible enemy from this hero's point of view and picks the best.
## Unpaid, a hero only goes as far from the keep as their personality allows
## ("roam"); a bounty, or an enemy attacking them, overrides that. Greedy heroes
## chase bounties, dutiful ones protect the keep, cautious ones avoid enemies
## that could kill them quickly. Nearby enemies are always tempting.
func _choose_target(hero: Unit, t: Dictionary) -> Unit:
	var best: Unit = null
	var best_score := -INF
	var best_reason := ""
	for enemy in living_enemies():
		var distance := hero.pos.distance_to(enemy.pos)
		var bounty := float(bounties.get(enemy.type_id, 0))
		if bounty <= 0.0 and enemy.target != hero and enemy.pos.distance_to(keep_pos) > float(t["roam"]):
			continue
		var threat_to_keep := 1.0 - clampf(enemy.pos.distance_to(keep_pos) / arena.x, 0.0, 1.0)
		var danger := enemy.attack / maxf(hero.hp, 1.0) * 10.0
		var bounty_pull := float(t["greed"]) * bounty * 0.5
		var duty_pull := float(t["duty"]) * threat_to_keep * 8.0
		var score := 10.0 - distance / 50.0 + bounty_pull + duty_pull - float(t["caution"]) * danger * 2.0
		if enemy == hero.target:
			score += TARGET_STICKINESS
		if score > best_score:
			best_score = score
			best = enemy
			if bounty_pull >= 4.0 and bounty_pull >= duty_pull:
				best_reason = "chasing the %dg bounty" % int(bounty)
			elif duty_pull >= 4.0:
				best_reason = "defending the keep"
			else:
				best_reason = "fighting"
	if best != null:
		hero.intent = "%s (%s)" % [best_reason, best.display_name]
	return best


# --- Enemies ---------------------------------------------------------------

func _enemy_tick(enemy: Unit) -> void:
	enemy.cooldown_left -= dt
	if enemy.target == null or not enemy.target.alive or enemy.pos.distance_to(enemy.target.pos) > ENEMY_AGGRO * 1.5:
		enemy.target = _nearest_hero(enemy.pos, ENEMY_AGGRO)
	if enemy.target != null:
		if enemy.pos.distance_to(enemy.target.pos) > enemy.attack_range:
			_move_toward(enemy, enemy.target.pos)
		elif enemy.cooldown_left <= 0.0:
			_hit(enemy, enemy.target)
		return
	var hold_at := float(content.enemies[enemy.type_id].get("hold_at", 0.0))
	if hold_at > 0.0 and enemy.pos.distance_to(keep_pos) <= hold_at and not _only_holders_left():
		return
	if enemy.pos.distance_to(keep_pos) > enemy.attack_range + KEEP_RADIUS:
		_move_toward(enemy, keep_pos)
	elif enemy.cooldown_left <= 0.0:
		enemy.cooldown_left = enemy.cooldown
		keep_hp -= enemy.attack * war_chant()
		keep_damage_taken += enemy.attack * war_chant()
		shots.append({"from": enemy.pos, "to": keep_pos, "ranged": enemy.attack_range > 60, "time": time})


## True once every enemy still alive (or still to come) is one that hangs back.
func _only_holders_left() -> bool:
	for enemy in enemies:
		if enemy.alive and float(content.enemies[enemy.type_id].get("hold_at", 0.0)) <= 0.0:
			return false
	return true


func _nearest_hero(from: Vector2, max_distance: float) -> Unit:
	var best: Unit = null
	var best_d := max_distance
	for hero in heroes:
		if hero.alive:
			var d := from.distance_to(hero.pos)
			if d < best_d:
				best_d = d
				best = hero
	return best


# --- Keep ------------------------------------------------------------------

func _keep_tick() -> void:
	keep_cooldown_left -= dt
	if keep_cooldown_left > 0.0:
		return
	var target: Unit = null
	var best_d := content.num("keep_range")
	for enemy in living_enemies():
		var d := keep_pos.distance_to(enemy.pos)
		if d < best_d:
			best_d = d
			target = enemy
	if target == null:
		return
	keep_cooldown_left = content.num("keep_cooldown")
	var damage := content.num("keep_attack") + run.mod("keep_attack")
	shots.append({"from": keep_pos, "to": target.pos, "ranged": true, "time": time})
	_damage(null, target, damage)


# --- Shared ----------------------------------------------------------------

func _hit(attacker: Unit, victim: Unit) -> void:
	attacker.cooldown_left = attacker.cooldown
	shots.append({"from": attacker.pos, "to": victim.pos, "ranged": attacker.attack_range > 60, "time": time})
	var amount := attacker.attack * rng.randf_range(0.85, 1.15)
	if not attacker.is_hero():
		amount *= war_chant()
	_damage(attacker, victim, amount)


func _damage(attacker: Unit, victim: Unit, amount: float) -> void:
	victim.hp -= amount
	if victim.hp > 0.0:
		return
	victim.alive = false
	victim.hp = 0.0
	if victim.is_hero():
		var by := attacker.display_name if attacker != null else "the enemy"
		story.append("%s fell to a %s." % [run.describe(victim), by])
		hero_deaths.append({"hero": victim.display_name, "killer": attacker.type_id if attacker != null else "",
			"time": snappedf(time, 0.1)})
		return
	if attacker == null:
		return
	var e: Dictionary = content.enemies[victim.type_id]
	attacker.kills += 1
	var bounty := int(bounties.get(victim.type_id, 0))
	var xp_mult := (1.0 + run.mod("xp_mult")) * (content.num("bounty_xp_mult") if bounty > 0 else 1.0)
	attacker.xp += float(e["xp"]) * xp_mult
	attacker.gold += int(e["loot"]) + int(run.mod("loot_gold"))
	if bounty > 0:
		bounty_paid += bounty
		var earned := int(round(bounty * (1.0 + run.mod("bounty_bonus"))))
		attacker.gold += earned
		if victim.is_boss or bounty >= 10:
			story.append("%s claims the %dg bounty on a %s." % [attacker.display_name, earned, victim.display_name])
	if victim.is_boss:
		story.append("%s slays the %s!" % [attacker.display_name, victim.display_name])


## Where a hero stands when there's nothing worth fighting.
func _guard_pos(hero: Unit, index := -1) -> Vector2:
	if index < 0:
		index = heroes.find(hero)
	return keep_pos + Vector2(55, (index - (heroes.size() - 1) / 2.0) * 34)


func _move_toward(unit: Unit, goal: Vector2) -> void:
	var step_len := unit.speed * dt
	var to_goal := goal - unit.pos
	if to_goal.length() <= step_len:
		unit.pos = goal
	else:
		unit.pos += to_goal.normalized() * step_len
	unit.pos = unit.pos.clamp(Vector2.ZERO, arena)


func _make_enemy(type_id: String, spawn_time: float) -> Unit:
	var e: Dictionary = content.enemies[type_id]
	var enemy := Unit.new()
	enemy.id = run.new_id()
	enemy.team = Unit.Team.ENEMY
	enemy.type_id = type_id
	enemy.display_name = e["name"]
	enemy.max_hp = float(e["hp"])
	enemy.hp = enemy.max_hp
	enemy.attack = float(e["attack"])
	enemy.attack_range = float(e["range"])
	enemy.cooldown = float(e["cooldown"])
	enemy.speed = float(e["speed"])
	enemy.is_boss = e.get("boss", false)
	enemy.spawn_time = spawn_time
	enemy.pos = Vector2(arena.x - 10, rng.randf_range(40.0, arena.y - 40.0))
	return enemy


func _check_end() -> void:
	if keep_hp <= 0.0:
		over = true
		won = false
		return
	if enemies_remaining() == 0:
		over = true
		won = true
		return
	if time >= content.num("max_battle_seconds"):
		# Stragglers that outlast the clock raid the keep on their way out.
		for enemy in enemies:
			if enemy.alive:
				keep_hp -= enemy.attack * 3.0
				enemy.alive = false
		story.append("The fighting dragged on; stragglers raided the keep.")
		over = true
		won = keep_hp > 0.0
