class_name RunState
extends RefCounted
## One run of the game: the town, its heroes, relics and the round loop.
##
## Round loop: DECIDE (player posts bounties, builds, recruits) -> BATTLE
## (auto-resolved, see Battle) -> RELIC (pick 1 of N) -> next round's DECIDE.
## The run ends in WON (survived the last round) or LOST (keep destroyed).
## No scenes or nodes here, so whole runs can be simulated headless.

enum Phase { DECIDE, BATTLE, RELIC, WON, LOST }

var content: Content
var run_seed: int
var round_number := 1
var phase := Phase.DECIDE

var gold := 0
var keep_hp := 0.0
var markets := 0
var heroes: Array[Unit] = []
var fallen: Array[Unit] = []
var relics: Array[String] = []
var relic_acquired_round := {}
var relic_offer: Array[String] = []

## Enemy type id -> gold paid per kill this round.
var bounties := {}
## Enemy type ids of the coming wave, in spawn order.
var next_wave: Array[String] = []
## Plain-language story of what happened, newest last.
var story: Array[String] = []

## Machine-readable history of this run for stats and debugging (see to_record()).
## Format changes bump RECORD_FORMAT so old saved runs can still be read.
const RECORD_FORMAT := 1
var record_rounds: Array[Dictionary] = []
var _round_entry := {}

var _next_id := 1
var _hero_rng: SeededRng


func _init(game_content: Content, seed_value: int) -> void:
	content = game_content
	run_seed = seed_value
	_hero_rng = SeededRng.stream(run_seed, "heroes")
	gold = content.int_num("start_gold")
	keep_hp = keep_max_hp()
	for i in content.int_num("start_heroes"):
		_add_hero()
	next_wave = generate_wave(round_number)
	_begin_round_entry()
	_tell("Round 1. %d heroes answer the call." % heroes.size())


# --- Modifiers -------------------------------------------------------------

## Sum of one relic effect across all owned relics (0 if none have it).
func mod(key: String) -> float:
	var total := 0.0
	for id in relics:
		var effects: Dictionary = content.relics[id]["effects"]
		total += float(effects.get(key, 0.0))
	return total


func keep_max_hp() -> float:
	return content.num("keep_max_hp") + mod("keep_max_hp")


func income() -> int:
	var total := content.num("income_per_round") + mod("income")
	total += markets * (content.num("market_income") + mod("market_income"))
	for id in relics:
		var growth := float(content.relics[id]["effects"].get("income_growth", 0.0))
		total += growth * (round_number - int(relic_acquired_round[id]))
	return int(total)


# --- Decisions -------------------------------------------------------------

func recruit_cost() -> int:
	return maxi(0, content.int_num("recruit_cost") - int(mod("recruit_discount")))


func can_recruit() -> bool:
	return phase == Phase.DECIDE and heroes.size() < content.int_num("max_heroes") \
		and free_gold() >= recruit_cost()


func recruit() -> bool:
	if not can_recruit():
		return false
	gold -= recruit_cost()
	var hero := _add_hero()
	_note_action("recruit", recruit_cost(), hero.display_name)
	_tell("%s joins the town." % describe(hero))
	return true


func can_build_market() -> bool:
	return phase == Phase.DECIDE and markets < content.int_num("max_markets") \
		and free_gold() >= content.int_num("market_cost")


func build_market() -> bool:
	if not can_build_market():
		return false
	gold -= content.int_num("market_cost")
	markets += 1
	_note_action("market", content.int_num("market_cost"))
	return true


func can_repair() -> bool:
	return phase == Phase.DECIDE and keep_hp < keep_max_hp() \
		and free_gold() >= content.int_num("repair_cost")


func repair_keep() -> bool:
	if not can_repair():
		return false
	gold -= content.int_num("repair_cost")
	keep_hp = minf(keep_max_hp(), keep_hp + content.num("repair_amount"))
	_note_action("repair", content.int_num("repair_cost"))
	return true


## Gold set aside to pay every posted bounty if every bountied enemy dies.
func bounty_reserved(override := {}) -> int:
	var b: Dictionary = override if not override.is_empty() else bounties
	var total := 0
	for enemy_type in next_wave:
		total += int(b.get(enemy_type, 0))
	return total


func free_gold() -> int:
	return gold - bounty_reserved()


## Sets the per-kill bounty on an enemy type. Fails if the town can't cover it.
func set_bounty(enemy_type: String, amount: int) -> bool:
	if phase != Phase.DECIDE:
		return false
	amount = clampi(amount, 0, content.int_num("bounty_max"))
	var trial := bounties.duplicate()
	trial[enemy_type] = amount
	if bounty_reserved(trial) > gold:
		return false
	bounties = trial
	return true


# --- Round flow ------------------------------------------------------------

func start_battle() -> Battle:
	assert(phase == Phase.DECIDE)
	phase = Phase.BATTLE
	_round_entry["bounties"] = bounties.duplicate()
	_round_entry["gold_before_battle"] = gold
	_round_entry["keep_hp_before"] = roundi(keep_hp)
	_round_entry["heroes_before"] = heroes.map(_hero_snapshot)
	var reserved := bounty_reserved()
	gold -= reserved
	for hero in heroes:
		_apply_hero_stats(hero)
	return Battle.new(self, SeededRng.stream(run_seed, "battle", round_number), reserved)


func finish_battle(battle: Battle) -> void:
	assert(phase == Phase.BATTLE)
	gold += battle.bounty_reserved - battle.bounty_paid
	keep_hp = maxf(0.0, battle.keep_hp)
	battle.release()
	_round_entry["battle"] = {
		"seconds": snappedf(battle.time, 0.1),
		"keep_hp_after": roundi(keep_hp),
		"keep_damage": roundi(battle.keep_damage_taken),
		"bounty_paid": battle.bounty_paid,
		"bounty_refunded": battle.bounty_reserved - battle.bounty_paid,
		"hero_deaths": battle.hero_deaths.duplicate(),
		"retreats": battle.retreats,
	}
	for line in battle.story:
		_tell(line)
	for hero in heroes.duplicate():
		if not hero.alive:
			heroes.erase(hero)
			fallen.append(hero)
	for hero in heroes:
		_level_up(hero)
	if keep_hp <= 0.0:
		phase = Phase.LOST
		_tell("The keep has fallen in round %d." % round_number)
		_end_round_entry()
		return
	if round_number >= content.int_num("rounds_to_win"):
		phase = Phase.WON
		_tell("The town survived all %d rounds!" % round_number)
		_end_round_entry()
		return
	_heal_heroes()
	_heroes_go_shopping()
	relic_offer = _roll_relic_offer()
	_round_entry["relic_offer"] = relic_offer.duplicate()
	phase = Phase.RELIC


## Takes a relic from the offer ("" skips), then starts the next round.
func choose_relic(relic_id: String) -> void:
	assert(phase == Phase.RELIC)
	if relic_id != "" and relic_id in relic_offer:
		var before_max := keep_max_hp()
		relics.append(relic_id)
		relic_acquired_round[relic_id] = round_number + 1
		var effects: Dictionary = content.relics[relic_id]["effects"]
		keep_hp = clampf(keep_hp + keep_max_hp() - before_max, 1.0, keep_max_hp())
		for i in int(effects.get("free_hero", 0)):
			if heroes.size() < content.int_num("max_heroes"):
				_tell("%s arrives, drawn by the posters." % describe(_add_hero()))
		_tell("Relic taken: %s." % content.relics[relic_id]["name"])
	_round_entry["relic_pick"] = relic_id
	_end_round_entry()
	relic_offer = []
	round_number += 1
	var earned := income()
	gold += earned
	bounties = {}
	next_wave = generate_wave(round_number)
	phase = Phase.DECIDE
	_begin_round_entry()
	_round_entry["income"] = earned
	_tell("Round %d. The town earns %d gold." % [round_number, earned])


## Wave contents for a round: random enemies bought from a growing budget.
func generate_wave(for_round: int) -> Array[String]:
	var rng := SeededRng.stream(run_seed, "wave", for_round)
	var budget := content.int_num("wave_budget_base") + content.int_num("wave_budget_per_round") * (for_round - 1)
	var wave: Array[String] = []
	while budget > 0:
		var options := []
		for id: String in content.enemies:
			var e: Dictionary = content.enemies[id]
			if not e.get("boss", false) and int(e["min_round"]) <= for_round and int(e["cost"]) <= budget:
				options.append(id)
		if options.is_empty():
			break
		options.sort()
		var pick: String = rng.pick(options)
		wave.append(pick)
		budget -= int(content.enemies[pick]["cost"])
	if for_round == content.int_num("rounds_to_win"):
		for id: String in content.enemies:
			if content.enemies[id].get("boss", false):
				wave.append(id)
	return wave


## Enemy type id -> count, for the wave preview.
func wave_counts() -> Dictionary:
	var counts := {}
	for id in next_wave:
		counts[id] = int(counts.get(id, 0)) + 1
	return counts


## The whole run so far as plain data (saved by the game, read by tools/run_report.gd).
## Deterministic: no clock or machine details; the game adds those when saving.
func to_record() -> Dictionary:
	var result := "in_progress"
	if phase == Phase.WON:
		result = "won"
	elif phase == Phase.LOST:
		result = "lost"
	var rounds: Array = record_rounds.duplicate(true)
	if not is_over():
		rounds.append(_round_entry.duplicate(true))
	return {
		"format": RECORD_FORMAT,
		"seed": run_seed,
		"result": result,
		"round_reached": round_number,
		"rounds_to_win": content.int_num("rounds_to_win"),
		"gold": gold,
		"keep_hp": roundi(keep_hp),
		"markets": markets,
		"relics": relics.duplicate(),
		"heroes": heroes.map(_hero_snapshot),
		"fallen": fallen.map(_hero_snapshot),
		"rounds": rounds,
		"story": story.duplicate(),
	}


func is_over() -> bool:
	return phase == Phase.WON or phase == Phase.LOST


func describe(hero: Unit) -> String:
	return "%s the %s %s" % [hero.display_name, content.traits[hero.trait_id]["name"].to_lower(),
		content.hero_classes[hero.type_id]["name"]]


func new_id() -> int:
	_next_id += 1
	return _next_id


# --- Internals -------------------------------------------------------------

func _add_hero() -> Unit:
	var hero := Unit.new()
	hero.id = new_id()
	hero.team = Unit.Team.HERO
	var class_ids := content.hero_classes.keys()
	class_ids.sort()
	var trait_ids := content.traits.keys()
	trait_ids.sort()
	hero.type_id = _hero_rng.pick(class_ids)
	hero.trait_id = _hero_rng.pick(trait_ids)
	hero.display_name = _unused_name()
	_apply_hero_stats(hero)
	hero.hp = hero.max_hp
	heroes.append(hero)
	return hero


func _unused_name() -> String:
	var taken := {}
	for h in heroes + fallen:
		taken[h.display_name] = true
	var free := content.hero_names.filter(func(n: String) -> bool: return not taken.has(n))
	if free.is_empty():
		return "Hero %d" % _next_id
	return _hero_rng.pick(free)


## Recomputes a hero's combat stats from class, level, gear and relics.
func _apply_hero_stats(hero: Unit) -> void:
	var c: Dictionary = content.hero_classes[hero.type_id]
	var old_max := hero.max_hp
	hero.max_hp = float(c["hp"]) + (hero.level - 1) * content.num("level_hp") \
		+ hero.armor_tier * float(content.gear["armor"]["hp"]) + mod("hero_hp")
	hero.attack = float(c["attack"]) + (hero.level - 1) * content.num("level_attack") \
		+ hero.weapon_tier * float(content.gear["weapon"]["attack"]) + mod("hero_attack")
	hero.attack_range = float(c["range"])
	hero.cooldown = float(c["cooldown"])
	hero.speed = float(c["speed"])
	if old_max > 1.0 and hero.max_hp > old_max:
		hero.hp += hero.max_hp - old_max
	hero.hp = minf(hero.hp, hero.max_hp)


func _level_up(hero: Unit) -> void:
	var per_level := content.num("xp_per_level")
	while hero.xp >= per_level * hero.level:
		hero.xp -= per_level * hero.level
		hero.level += 1
		_apply_hero_stats(hero)
		_tell("%s reaches level %d." % [hero.display_name, hero.level])


func _heal_heroes() -> void:
	var full := mod("full_heal") > 0.0
	for hero in heroes:
		var heal := hero.max_hp if full else hero.max_hp * content.num("between_round_heal")
		hero.hp = minf(hero.max_hp, hero.hp + heal)


## Heroes spend their own gold on gear, by personality. The player doesn't choose.
func _heroes_go_shopping() -> void:
	var discount := clampf(mod("gear_discount"), 0.0, 0.9)
	for hero in heroes:
		var t: Dictionary = content.traits[hero.trait_id]
		var order := ["weapon", "armor"] if t["prefers"] == "weapon" else ["armor", "weapon"]
		var bought := true
		while bought:
			bought = false
			for slot: String in order:
				var tier := hero.weapon_tier if slot == "weapon" else hero.armor_tier
				var costs: Array = content.gear[slot]["costs"]
				if tier >= costs.size():
					continue
				var cost := int(round(float(costs[tier]) * (1.0 - discount)))
				# Hoarders only buy when they have plenty left over.
				if hero.gold < cost * float(t["hoard"]):
					continue
				hero.gold -= cost
				if slot == "weapon":
					hero.weapon_tier += 1
				else:
					hero.armor_tier += 1
				_apply_hero_stats(hero)
				_tell("%s buys a tier %d %s for %dg." % [hero.display_name, tier + 1, slot, cost])
				bought = true
				break


func _roll_relic_offer() -> Array[String]:
	var rng := SeededRng.stream(run_seed, "relics", round_number)
	var pool: Array = content.relics.keys().filter(func(id: String) -> bool: return not relics.has(id))
	pool.sort()
	var offer: Array[String] = []
	while offer.size() < content.int_num("relic_choices") and not pool.is_empty():
		var pick: String = rng.pick(pool)
		pool.erase(pick)
		offer.append(pick)
	return offer


func _begin_round_entry() -> void:
	_round_entry = {"round": round_number, "gold_start": gold, "keep_hp_start": roundi(keep_hp),
		"wave": wave_counts(), "actions": []}


func _end_round_entry() -> void:
	_round_entry["gold_end"] = gold
	record_rounds.append(_round_entry)
	_round_entry = {}


func _note_action(kind: String, cost: int, detail := "") -> void:
	var action := {"kind": kind, "cost": cost}
	if detail != "":
		action["detail"] = detail
	_round_entry["actions"].append(action)


func _hero_snapshot(hero: Unit) -> Dictionary:
	return {"name": hero.display_name, "class": hero.type_id, "trait": hero.trait_id, "level": hero.level,
		"hp": roundi(hero.hp), "max_hp": roundi(hero.max_hp), "gold": hero.gold, "weapon": hero.weapon_tier,
		"armor": hero.armor_tier, "kills": hero.kills, "alive": hero.alive}


func _tell(line: String) -> void:
	story.append(line)
