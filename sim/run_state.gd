class_name RunState
extends RefCounted
## One run of the game: the settlement, its people, relics and the round loop.
##
## Round loop: BUILD (order buildings) -> for each day: PICK (choose a newcomer
## at dawn) -> SIM (the day and night play out on their own) -> after the last
## night, which brings the round's warned wave: RELIC (pick 1 of N) -> next BUILD.
## The run ends in WON (survived the last round) or LOST (hearth destroyed or
## everyone gone). No scenes or nodes here, so whole runs can be simulated headless.

enum Phase { BUILD, PICK, SIM, RELIC, WON, LOST }

const RESOURCES := ["food", "fuel", "wood", "stone", "shells", "flint", "hides", "bone", "obsidian"]

var content: Content
var run_seed: int
var round_number := 1
var phase := Phase.BUILD

var world: World
var stock := {}
var heroes: Array[Unit] = []
var fallen: Array[Unit] = []
var fallen_folk := 0
var relics: Array[String] = []
var relic_acquired_round := {}
var relic_offer: Array[String] = []
## Dawn cards: {kind: "folk"|"hero", role: String, cost: int, hero: Unit (for hero cards)}.
var pick_offer: Array[Dictionary] = []
## Enemy type ids of this round's wave, in spawn order.
var next_wave: Array[String] = []
## Plain-language story of what happened, newest last.
var story: Array[String] = []
## The last night's report, shown at the next decision (see World.night_report).
var last_night := {}
## Price level per stall kind ("cheap", "fair" or "dear"; see data/recipes.json), set while building.
var prices := {}

## Machine-readable history of this run for stats and debugging (see to_record()).
## Format changes bump RECORD_FORMAT so old saved runs can still be read.
## 1: one wave per round. 2: days, dawn picks, townsfolk, dens.
## 3: small raids on early nights, a report per night ("nights").
## 4: hero energy, lodgings, whims and items ("whims", "loot", "sales", "hero_spending"; hero items).
## 5: each night's report also lists who walked away hungry ("left").
## 6: the marketplace: "prices", "crafted", "market" (stall sales), "prizes", "obsidian", "yields"; hero "pack";
##    "sales" are now made at the market and there are no trader purchases.
const RECORD_FORMAT := 6
var record_rounds: Array[Dictionary] = []
var _round_entry := {}

var _next_id := 1
var _hero_rng: SeededRng


func _init(game_content: Content, seed_value: int) -> void:
	content = game_content
	run_seed = seed_value
	_hero_rng = SeededRng.stream(run_seed, "heroes")
	for r in RESOURCES:
		stock[r] = int(content.balance["start_stock"].get(r, 0))
	var kinds: Array = content.market["stall_names"].keys()
	kinds.sort()
	for kind: String in kinds:
		prices[kind] = "fair"
	world = World.new(self)
	var start_people: Dictionary = content.balance["start_people"]
	var roles := start_people.keys()
	roles.sort()
	for role: String in roles:
		for i in int(start_people[role]):
			world.add_folk(role)
	for i in content.int_num("start_heroes"):
		_add_hero(_make_hero())
	tell("Round 1. A handful of people gather around a fire at the edge of the world.")
	_enter_build()


# --- Modifiers -------------------------------------------------------------

## Sum of one relic effect across all owned relics (0 if none have it).
func mod(key: String) -> float:
	var total := 0.0
	for id in relics:
		var effects: Dictionary = content.relics[id]["effects"]
		total += float(effects.get(key, 0.0))
	return total


func hearth_max_hp() -> float:
	return content.num("hearth_max_hp") + mod("hearth_max_hp")


## Shells the settlement earns at the start of each round.
func income() -> int:
	return int(content.num("income_shells_per_round") + mod("income"))


func living_heroes() -> Array[Unit]:
	return heroes.filter(func(h: Unit) -> bool: return h.alive)


func population() -> int:
	return world.folk.size() + living_heroes().size()


func housing() -> int:
	var total := content.int_num("base_housing")
	for type: String in content.buildings:
		total += world.count_buildings(type) * int(content.buildings[type].get("housing", 0))
	return total


func count_role(role: String) -> int:
	return world.folk.filter(func(u: Unit) -> bool: return u.type_id == role).size()


# --- Building (start of round) ----------------------------------------------

func can_afford(cost: Dictionary) -> bool:
	for r: String in cost:
		if int(stock.get(r, 0)) < int(cost[r]):
			return false
	return true


func can_build(type: String) -> bool:
	var def: Dictionary = content.buildings[type]
	var needs: String = def.get("requires", "")
	return phase == Phase.BUILD and can_afford(def["cost"]) and world.free_plot() >= 0 \
		and world.count_buildings(type, false) < int(def.get("max", 99)) \
		and (needs == "" or world.count_buildings(needs, false) > 0)


func build(type: String) -> bool:
	if not can_build(type):
		return false
	var cost: Dictionary = content.buildings[type]["cost"]
	for r: String in cost:
		stock[r] = int(stock[r]) - int(cost[r])
	world.add_building(type)
	_round_entry["actions"].append({"kind": "build", "building": type})
	return true


# --- Market prices ----------------------------------------------------------

## Sets a stall kind's price level for the coming round ("cheap", "fair" or "dear").
func set_price(kind: String, level: String) -> void:
	if phase != Phase.BUILD or not prices.has(kind) or not content.market["price_levels"].has(level) or prices[kind] == level:
		return
	prices[kind] = level
	_round_entry["actions"].append({"kind": "price", "stall": kind, "level": level})


func price_markup(kind: String) -> float:
	return float(content.market["price_levels"][prices.get(kind, "fair")])


## What a hero pays for a good: the recipe's price per tier x the stall's level, less relic discounts.
func price_of(good: Dictionary) -> int:
	var r: Dictionary = content.market["recipes"][good["recipe"]]
	var discount := clampf(mod("gear_discount"), 0.0, 0.9) if r.has("item") else 0.0
	return maxi(1, roundi(float(r["price"]) * int(good.get("tier", 1)) * price_markup(r["stall"]) * (1.0 - discount)))


## Tier a workshop makes a recipe at this round.
func craft_tier(recipe_id: String) -> int:
	var r: Dictionary = content.market["recipes"][recipe_id]
	var tier := 1 + (round_number - 1) / int(content.market["tier_every_rounds"])
	return clampi(tier, int(r.get("min_tier", 1)), int(r.get("max_tier", 1)))


## Ends the build phase; the first dawn of the round follows.
func begin_round() -> void:
	assert(phase == Phase.BUILD)
	world.start_round()
	_offer_picks()


func on_building_done(type: String) -> void:
	if content.buildings[type].has("lodging"):
		world.assign_lodgings()


# --- Dawn picks ------------------------------------------------------------

func can_take_pick(index: int) -> bool:
	if phase != Phase.PICK or index < 0 or index >= pick_offer.size():
		return false
	var card := pick_offer[index]
	return population() < housing() and int(stock["shells"]) >= int(card["cost"])


## Takes a dawn card (-1 skips), then lets the day begin.
func choose_pick(index: int) -> void:
	assert(phase == Phase.PICK)
	var taken := ""
	if can_take_pick(index):
		var card := pick_offer[index]
		stock["shells"] = int(stock["shells"]) - int(card["cost"])
		if card["kind"] == "hero":
			var hero: Unit = card["hero"]
			_add_hero(hero)
			taken = "hero:" + hero.type_id
			tell("%s arrives and sleeps in %s." % [describe(hero), world.bed_name(hero.lodging)])
		else:
			world.add_folk(card["role"])
			taken = card["role"]
			tell("A %s joins the settlement." % content.townsfolk[card["role"]]["name"].to_lower())
	_round_entry["picks"].append({"day": world.day_index() + 1, "offered": pick_offer.map(_card_label), "taken": taken})
	pick_offer = []
	phase = Phase.SIM
	world.resume()
	tell("Day %d dawns." % (world.day_index() + 1))
	world.roll_whims()


func _offer_picks() -> void:
	var rng := SeededRng.stream(run_seed, "picks", round_number * 10 + world.day_index())
	var pool: Array[Dictionary] = []
	var roles := content.townsfolk.keys()
	roles.sort()
	for role: String in roles:
		pool.append({"kind": "folk", "role": role, "cost": 0})
	if world.count_lodgings() > 0:
		pool.append({"kind": "hero", "role": "hero", "cost": content.int_num("hero_card_cost"), "hero": _make_hero(true)})
	pick_offer = []
	while pick_offer.size() < content.int_num("pick_choices") and not pool.is_empty():
		var card: Dictionary = rng.pick(pool)
		pool.erase(card)
		pick_offer.append(card)
	phase = Phase.PICK


func _card_label(card: Dictionary) -> String:
	return "hero:" + card["hero"].type_id if card["kind"] == "hero" else card["role"]


# --- Simulation ------------------------------------------------------------

func step() -> void:
	if phase != Phase.SIM:
		return
	world.step()
	match world.pause:
		World.Pause.DAWN:
			_bury_heroes()
			_close_night()
			_offer_picks()
		World.Pause.ROUND_OVER:
			_finish_round()
		World.Pause.HEARTH_LOST:
			_lose()


## Runs the world until it needs a decision (a dawn pick, a relic, or the end).
func run_until_pause() -> void:
	while phase == Phase.SIM:
		step()


## Food eaten at each dawn. If there isn't enough, someone leaves.
func daily_upkeep() -> void:
	var racks := world.count_buildings("drying_rack")
	var growth := 0.0
	for id in relics:
		growth += float(content.relics[id]["effects"].get("food_growth", 0.0)) * (round_number - int(relic_acquired_round[id]))
	var need := maxi(0, int(ceil(population() * content.num("food_per_person_per_day") * (1.0 - 0.25 * racks) - growth)))
	if int(stock["food"]) >= need:
		stock["food"] = int(stock["food"]) - need
		return
	stock["food"] = 0
	if not world.folk.is_empty():
		var leaver: Unit = world.folk[SeededRng.stream(run_seed, "hunger", round_number * 10 + world.day_index()).randi_range(0, world.folk.size() - 1)]
		world.folk.erase(leaver)
		world.night_report["left"].append(leaver.display_name)
		_round_entry["left_hungry"] = int(_round_entry.get("left_hungry", 0)) + 1
		tell("Hunger: a %s walks away into the wilds." % leaver.display_name.to_lower())


func fuel_needed_tonight() -> int:
	var need := content.num("fuel_per_night_base") + population() * content.num("fuel_per_person_per_night") - mod("fuel_saving")
	for type: String in content.buildings:
		need += world.count_buildings(type) * float(content.buildings[type].get("fuel", 0.0))
	return maxi(0, int(ceil(need)))


## What gatherers should fetch next: whatever is shortest against two days of need.
func most_needed_resource() -> String:
	var wants := {
		"food": population() * content.num("food_per_person_per_day") * 2.0,
		"fuel": fuel_needed_tonight() * 2.0,
		"wood": 12.0,
		"stone": 6.0,
	}
	# Knappers need flint, and the smoke hut eats food and fuel.
	if world.count_buildings("knapper") > 0:
		wants["flint"] = 6.0 * world.count_buildings("knapper")
	if world.count_buildings("smoke_hut") > 0:
		wants["food"] += 4.0
		wants["fuel"] += 2.0
	var best := "food"
	var best_gap := -INF
	for r: String in wants:
		var gap: float = (wants[r] - float(stock[r])) / maxf(wants[r], 1.0)
		if gap > best_gap:
			best_gap = gap
			best = r
	return best


## Files the night's report in the round record and keeps it for the UI.
func _close_night() -> void:
	var report := world.night_report.duplicate(true)
	report["night"] = world.day_index() + (0 if world.pause == World.Pause.DAWN else 1)
	report["hearth_damage"] = roundi(float(report["hearth_damage"]))
	last_night = report
	if not _round_entry.has("nights"):
		_round_entry["nights"] = []
	_round_entry["nights"].append(report)
	world.reset_night_report()


func _finish_round() -> void:
	_close_night()
	_bury_heroes()
	world.release()
	var stats := world.wave_stats
	_round_entry["battle"] = {
		"seconds": snappedf(float(stats["seconds"]), 0.1),
		"keep_hp_after": roundi(world.hearth_hp),
		"keep_damage": roundi(float(stats["keep_damage"])),
		"bounty_paid": 0,
		"bounty_refunded": 0,
		"hero_deaths": stats["hero_deaths"].duplicate(),
		"retreats": int(stats["retreats"]),
	}
	_round_entry["deaths"] = world.deaths.duplicate()
	for hero in heroes:
		_level_up(hero)
	if world.hearth_hp <= 0.0:
		_lose()
		return
	if round_number >= content.int_num("rounds_to_win"):
		phase = Phase.WON
		tell("The people endured all %d rounds!" % round_number)
		_end_round_entry()
		return
	_heal_heroes()
	_heroes_sell_finds()
	relic_offer = _roll_relic_offer()
	_round_entry["relic_offer"] = relic_offer.duplicate()
	phase = Phase.RELIC


func _lose() -> void:
	if world.pause == World.Pause.HEARTH_LOST:
		_close_night()
	phase = Phase.LOST
	_bury_heroes()
	world.release()
	if world.hearth_hp <= 0.0:
		tell("The hearth is trampled and goes dark in round %d." % round_number)
	else:
		tell("No one is left to tend the fire in round %d." % round_number)
	_round_entry["deaths"] = world.deaths.duplicate()
	_end_round_entry()


## Takes a relic from the offer ("" skips), then starts the next round.
func choose_relic(relic_id: String) -> void:
	assert(phase == Phase.RELIC)
	if relic_id != "" and relic_id in relic_offer:
		var before_max := hearth_max_hp()
		relics.append(relic_id)
		relic_acquired_round[relic_id] = round_number + 1
		var effects: Dictionary = content.relics[relic_id]["effects"]
		world.hearth_hp = clampf(world.hearth_hp + hearth_max_hp() - before_max, 1.0, hearth_max_hp())
		for i in int(effects.get("free_hero", 0)):
			var hero := _make_hero()
			_add_hero(hero)
			tell("%s follows the wanderer's fire to your camp." % describe(hero))
		for u in world.folk:
			world.apply_folk_stats(u)
		tell("Relic taken: %s." % content.relics[relic_id]["name"])
	_round_entry["relic_pick"] = relic_id
	_end_round_entry()
	relic_offer = []
	round_number += 1
	var earned := income()
	stock["shells"] = int(stock["shells"]) + earned
	tell("Round %d. Traders leave %d shells." % [round_number, earned])
	_enter_build()


func _enter_build() -> void:
	phase = Phase.BUILD
	next_wave = generate_wave(round_number)
	world.roll_wave_sides()
	_begin_round_entry()


## Wave contents for a round: random enemies bought from a growing budget.
func generate_wave(for_round: int) -> Array[String]:
	var rng := SeededRng.stream(run_seed, "wave", for_round)
	var budget := content.int_num("wave_budget_base") + content.int_num("wave_budget_per_round") * (for_round - 1)
	var wave: Array[String] = []
	var ids := content.enemies.keys()
	ids.sort()
	while budget > 0:
		var options := []
		for id: String in ids:
			var e: Dictionary = content.enemies[id]
			if e.get("wave", true) and not e.get("boss", false) and int(e["min_round"]) <= for_round and int(e["cost"]) <= budget:
				options.append(id)
		if options.is_empty():
			break
		var pick: String = rng.pick(options)
		wave.append(pick)
		budget -= int(content.enemies[pick]["cost"])
	if for_round == content.int_num("rounds_to_win"):
		for id: String in ids:
			if content.enemies[id].get("boss", false):
				wave.append(id)
	return wave


## A small raid for an early night: cheap enemies from a small budget.
func generate_probe(for_round: int, night: int) -> Array[String]:
	var rng := SeededRng.stream(run_seed, "probe_units", for_round * 10 + night)
	var budget := int(content.num("probe_budget_base") + content.num("probe_budget_per_round") * (for_round - 1))
	var ids := content.enemies.keys()
	ids.sort()
	var probe: Array[String] = []
	while budget > 0:
		var options := []
		for id: String in ids:
			var e: Dictionary = content.enemies[id]
			if e.get("wave", true) and not e.get("boss", false) and not e.has("hold_at") \
					and int(e["min_round"]) <= for_round and int(e["cost"]) <= budget:
				options.append(id)
		if options.is_empty():
			break
		var pick: String = rng.pick(options)
		probe.append(pick)
		budget -= int(content.enemies[pick]["cost"])
	return probe


## Enemy type id -> count, for the wave preview.
func wave_counts() -> Dictionary:
	var counts := {}
	for id in next_wave:
		counts[id] = int(counts.get(id, 0)) + 1
	return counts


func is_over() -> bool:
	return phase == Phase.WON or phase == Phase.LOST


## Breaks the run <-> world reference loop so a finished run can be freed.
func dispose() -> void:
	world.release()
	world.run = null


func describe(hero: Unit) -> String:
	return "%s the %s %s" % [hero.display_name, content.traits[hero.trait_id]["name"].to_lower(),
		content.hero_classes[hero.type_id]["name"].to_lower()]


func new_id() -> int:
	_next_id += 1
	return _next_id


func tell(line: String) -> void:
	story.append(line)


# --- Run record ------------------------------------------------------------

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
		"stock": stock.duplicate(),
		"keep_hp": roundi(world.hearth_hp),
		"buildings": world.buildings.map(func(b: Dictionary) -> String: return b["type"]),
		"townsfolk": _folk_counts(),
		"townsfolk_lost": fallen_folk,
		"relics": relics.duplicate(),
		"prices": prices.duplicate(),
		"heroes": heroes.map(_hero_snapshot),
		"fallen": fallen.map(_hero_snapshot),
		"rounds": rounds,
		"story": story.duplicate(),
	}


func _folk_counts() -> Dictionary:
	var counts := {}
	for u in world.folk:
		counts[u.type_id] = int(counts.get(u.type_id, 0)) + 1
	return counts


func _begin_round_entry() -> void:
	_round_entry = {"round": round_number, "stock_start": stock.duplicate(), "keep_hp_start": roundi(world.hearth_hp),
		"wave": wave_counts(), "wave_sides": world.side_names(), "townsfolk_start": _folk_counts(),
		"heroes_start": living_heroes().size(), "actions": [], "picks": [],
		"whims": [], "loot": [], "sales": [], "hero_spending": {},
		"prices": prices.duplicate(), "crafted": {}, "market": [], "prizes": 0, "obsidian": 0, "yields": {}}


func _end_round_entry() -> void:
	_round_entry["stock_end"] = stock.duplicate()
	_round_entry["townsfolk_end"] = _folk_counts()
	record_rounds.append(_round_entry)
	_round_entry = {}


func _hero_snapshot(hero: Unit) -> Dictionary:
	var items := []
	for slot: String in Loot.SLOTS:
		if hero.items.has(slot):
			items.append(_item_record(hero.items[slot]))
	return {"name": hero.display_name, "class": hero.type_id, "trait": hero.trait_id, "level": hero.level,
		"hp": roundi(hero.hp), "max_hp": roundi(hero.max_hp), "gold": hero.gold,
		"weapon": int(hero.items.get("weapon", {}).get("tier", 0)), "armor": int(hero.items.get("armor", {}).get("tier", 0)),
		"charm": int(hero.items.get("charm", {}).get("tier", 0)), "items": items,
		"energy": roundi(hero.energy), "pack": hero.pack.duplicate(), "lodging": world.buildings[hero.lodging]["type"] if hero.lodging >= 0 else "",
		"kills": hero.kills, "alive": hero.alive}


func _item_record(item: Dictionary) -> Dictionary:
	return {"base": item["base"], "slot": Loot.slot(content, item), "tier": item["tier"],
		"affixes": item["affixes"].duplicate(), "value": Loot.value(content, item)}


func note_whim(hero: Unit) -> void:
	if _round_entry.has("whims"):
		_round_entry["whims"].append({"day": world.day_index() + 1, "hero": hero.display_name, "whim": hero.whim})


func note_loot(hero: Unit, item: Dictionary, equipped: bool) -> void:
	if _round_entry.has("loot"):
		var entry := _item_record(item)
		entry.merge({"day": world.day_index() + 1, "hero": hero.display_name, "trait": hero.trait_id, "equipped": equipped})
		_round_entry["loot"].append(entry)


## Shells heroes paid the settlement this round, by reason (tavern nights, carousing).
func note_hero_spending(reason: String, shells: int) -> void:
	if _round_entry.has("hero_spending"):
		_round_entry["hero_spending"][reason] = int(_round_entry["hero_spending"].get(reason, 0)) + shells


func note_crafted(recipe_id: String) -> void:
	if _round_entry.has("crafted"):
		_round_entry["crafted"][recipe_id] = int(_round_entry["crafted"].get(recipe_id, 0)) + 1


func note_market_sale(hero: Unit, good: Dictionary, price: int) -> void:
	if _round_entry.has("market"):
		_round_entry["market"].append({"day": world.day_index() + 1, "hero": hero.display_name, "trait": hero.trait_id,
			"recipe": good["recipe"], "tier": int(good.get("tier", 1)), "price": price,
			"stall": content.market["recipes"][good["recipe"]]["stall"]})


## Goods the settlement got from carcasses, prize shells paid and obsidian shards bought.
func note_economy(key: String, amount: int, what := "") -> void:
	if not _round_entry.has(key):
		return
	if key == "yields":
		_round_entry["yields"][what] = int(_round_entry["yields"].get(what, 0)) + amount
	else:
		_round_entry[key] = int(_round_entry[key]) + amount


# --- Internals -------------------------------------------------------------

## A new hero, not yet in the settlement (dawn cards show these).
## For dawn cards, heroes whose favourite lodging stands are likelier to turn up.
func _make_hero(drawn_by_lodging := false) -> Unit:
	var hero := Unit.new()
	hero.id = new_id()
	hero.team = Unit.Team.HERO
	var class_ids := content.hero_classes.keys()
	class_ids.sort()
	var trait_ids := content.traits.keys()
	trait_ids.sort()
	hero.type_id = _hero_rng.pick(class_ids)
	if drawn_by_lodging:
		var weights := {}
		for id: String in trait_ids:
			var favourite: Array = content.traits[id].get("lodging", [])
			weights[id] = 1.0 + (content.num("lodging_draw_bonus") if not favourite.is_empty() and world.count_buildings(favourite[0]) > 0 else 0.0)
		hero.trait_id = _hero_rng.weighted(weights)
	else:
		hero.trait_id = _hero_rng.pick(trait_ids)
	hero.display_name = _unused_name()
	world.apply_hero_stats(hero)
	hero.hp = hero.max_hp
	return hero


func _add_hero(hero: Unit) -> void:
	hero.pos = Vector2.from_angle(heroes.size() * 1.7 + 0.4) * 60.0
	world.apply_hero_stats(hero)
	heroes.append(hero)
	world.assign_lodgings()


func _bury_heroes() -> void:
	for hero in heroes.duplicate():
		if not hero.alive:
			heroes.erase(hero)
			fallen.append(hero)


func _unused_name() -> String:
	var taken := {}
	for h in heroes + fallen:
		taken[h.display_name] = true
	var free := content.hero_names.filter(func(n: String) -> bool: return not taken.has(n))
	if free.is_empty():
		return "Wanderer %d" % _next_id
	return _hero_rng.pick(free)


func _level_up(hero: Unit) -> void:
	var per_level := content.num("xp_per_level")
	while hero.xp >= per_level * hero.level:
		hero.xp -= per_level * hero.level
		hero.level += 1
		world.apply_hero_stats(hero)
		tell("%s reaches level %d." % [hero.display_name, hero.level])


func _heal_heroes() -> void:
	var full := mod("full_heal") > 0.0
	for hero in heroes:
		hero.energy = content.num("hero_energy_max")
		hero.resting = false
		var heal := hero.max_hp if full else hero.max_hp * content.num("between_round_heal")
		hero.hp = minf(hero.max_hp, hero.hp + heal)
	for unit in world.folk:
		unit.hp = minf(unit.max_hp, unit.hp + unit.max_hp * content.num("between_round_heal"))


## Between rounds heroes sell the loot they carry (the settlement takes a cut).
## Gear and provisions are only bought at the market's stalls, by day (see World).
func _heroes_sell_finds() -> void:
	var tax_rate := float(content.items["sell_tax"])
	var where := "at the market" if world.count_buildings("market") > 0 else "to passing traders"
	for hero in heroes:
		if hero.spares.is_empty():
			continue
		var total := 0
		var tax := 0
		for item in hero.spares:
			var v := Loot.value(content, item)
			var cut := roundi(v * tax_rate)
			total += v
			tax += cut
			_round_entry["sales"].append({"hero": hero.display_name, "base": item["base"], "tier": item["tier"],
				"affixes": item["affixes"].duplicate(), "value": v, "town_cut": cut})
		hero.gold += total - tax
		stock["shells"] = int(stock["shells"]) + tax
		tell("%s sells %d found item%s %s for %d shells; the settlement keeps %d." % [hero.display_name,
			hero.spares.size(), "" if hero.spares.size() == 1 else "s", where, total, tax])
		hero.spares.clear()


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
