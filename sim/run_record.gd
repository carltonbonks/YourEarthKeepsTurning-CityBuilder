class_name RunRecord
extends RefCounted
## The run's machine-readable history (`run.record`), for the Run history screen, bot balance runs,
## tools/run_report.gd and tools/export_csv.py. `entry` is the round being played; finished rounds
## go to `rounds`. Every rule that should show up in the data logs it through a note_* method here.
##
## Format changes bump RECORD_FORMAT so old saved runs can still be read. Never drop or rename fields.
## 1: one wave per round. 2: days, dawn picks, townsfolk, dens.
## 3: small raids on early nights, a report per night ("nights").
## 4: hero energy, lodgings, whims and items ("whims", "loot", "sales", "hero_spending"; hero items).
## 5: each night's report also lists who walked away hungry ("left").
## 6: the marketplace: "prices", "crafted", "market" (stall sales), "prizes", "obsidian", "yields"; hero "pack";
##    "sales" are now made at the market and there are no trader purchases.
## 7: ages and promotions: "age", "age_up_round", "tools", "departed" (heroes who left unhappy), hero "mood";
##    per round "promotions", "trades", "cassiterite", "heroes_left"; per night "heroes_left", "hero_deaths", "cold".
## 8: the ring town and roads: "road" actions (waypoints, squares), per round "paving" (goods spent on roads) and
##    "town" at the round's end (squares staked, paved per road kind, trail squares, plots built per ring);
##    "plots" (each building's ring and sector) in the run record.
## 9: palisades: "wall" / "unstake_wall" actions, per round "walling" (goods spent on palisades) and
##    "breaches" (palisade squares raiders broke), and "walls" in the round's "town" (squares staked, standing, gates).
## 10: roads and palisades are no longer staked (no "road" / "wall" actions, no "walling"); the round's
##    "town" drops "staked" and "walls" and adds "paths" (worn path squares) and "gates" ({built, broken});
##    "breaches" now counts gate squares raiders broke. Stone-layers pave the busiest worn paths.
## 11: per round "power" when the wave comes: the town's power level by part (heroes, fighters, defences, total)
##     and the wave's ("wave", and "wave_scheduled" before catch-up), on the same scale (sim/power.gd);
##     per round "wave_eased" (raiders catch-up held back from the scheduled wave).
## 12: per round "food_grown" (food gardens brought in at dawns); a dawn pick has "hunger_turned_away"
##     (the role of someone who had just left hungry, so none of that role were offered).
## 13: the medieval age: "age_rounds" (age -> round reached), new goods in "stock" (bog_iron, charcoal, iron, steel);
##     a dawn pick can take "family" (several townsfolk at once); "promotions" can be a champion knighted
##     (role "champion", "level"); per round "siege_damage" (what battering rams did to gates and the hearth).
## 14: building cards: per round "build_hands" (the building cards dealt, then one more list per redraw,
##     each {"cards": [building types]}); a "redraw" action ({"kind": "redraw", "cost"}).
## 15: towers can be broken: per round "towers_broken" (watch posts or the keep knocked out by sentient raiders).
const RECORD_FORMAT := 15

var run: RunState
## Finished rounds, oldest first.
var rounds: Array[Dictionary] = []
## The round being played ({} between a finished run's last round and nothing).
var entry := {}


func _init(run_state: RunState) -> void:
	run = run_state


## The whole run so far as plain data (saved by the game, read by tools/run_report.gd).
## Deterministic: no clock or machine details; the game adds those when saving.
func to_record() -> Dictionary:
	var world := run.world
	var result := "in_progress"
	if run.phase == RunState.Phase.WON:
		result = "won"
	elif run.phase == RunState.Phase.LOST:
		result = "lost"
	var all_rounds: Array = rounds.duplicate(true)
	if not run.is_over():
		all_rounds.append(entry.duplicate(true))
	return {
		"format": RECORD_FORMAT,
		"seed": run.run_seed,
		"result": result,
		"round_reached": run.round_number,
		"rounds_to_win": run.content.int_num("rounds_to_win"),
		"stock": run.stock.duplicate(),
		"keep_hp": roundi(world.hearth_hp),
		"buildings": world.buildings.map(func(b: Dictionary) -> String: return b["type"]),
		"plots": world.buildings.map(func(b: Dictionary) -> Dictionary:
			var plot: Dictionary = world.town.plots[b["plot"]]
			return {"building": b["type"], "ring": int(plot["ring"]) + 1, "sector": int(plot["sector"])}),
		"townsfolk": folk_counts(),
		"townsfolk_lost": run.fallen_folk,
		"relics": run.relics.duplicate(),
		"prices": run.prices.duplicate(),
		"age": run.age,
		"age_up_round": run.age_up_round,
		"age_rounds": run.age_rounds.duplicate(),
		"tools": run.tools.duplicate(),
		"heroes": run.heroes.map(hero_snapshot),
		"fallen": run.fallen.map(hero_snapshot),
		"departed": run.departed.map(hero_snapshot),
		"rounds": all_rounds,
		"story": run.story.duplicate(),
	}


func folk_counts() -> Dictionary:
	var counts := {}
	for u in run.world.folk:
		counts[u.type_id] = int(counts.get(u.type_id, 0)) + 1
	return counts


func begin_round() -> void:
	entry = {"round": run.round_number, "stock_start": run.stock.duplicate(), "keep_hp_start": roundi(run.world.hearth_hp),
		"wave": run.waves.counts(), "wave_sides": run.world.side_names(), "townsfolk_start": folk_counts(),
		"heroes_start": run.living_heroes().size(), "actions": [], "picks": [],
		"whims": [], "loot": [], "sales": [], "hero_spending": {},
		"prices": run.prices.duplicate(), "crafted": {}, "market": [], "prizes": 0, "obsidian": 0, "yields": {},
		"age": run.age, "promotions": [], "trades": {}, "cassiterite": 0, "heroes_left": [], "paving": {},
		"breaches": 0, "wave_eased": run.wave_eased, "siege_damage": 0, "towers_broken": 0,
		"build_hands": [{"cards": run.hand.labels()}]}


func end_round() -> void:
	entry["stock_end"] = run.stock.duplicate()
	entry["town"] = town_snapshot()
	entry["townsfolk_end"] = folk_counts()
	rounds.append(entry)
	entry = {}


## How the town's ground looks now, for the round record.
func town_snapshot() -> Dictionary:
	var world := run.world
	var rings := {}
	for plot in world.town.plots:
		if int(plot["building"]) >= 0:
			rings[str(plot["ring"] + 1)] = int(rings.get(str(plot["ring"] + 1), 0)) + 1
	return {"paved": world.town.paved_counts(), "trails": world.pathing.count_ground(Pathing.TRAIL),
		"paths": world.pathing.count_ground(Pathing.PATH), "plots_by_ring": rings, "gates": world.town.gate_counts()}


func hero_snapshot(hero: Unit) -> Dictionary:
	var items := []
	for slot: String in Loot.SLOTS:
		if hero.items.has(slot):
			items.append(item_record(hero.items[slot]))
	return {"name": hero.display_name, "class": hero.type_id, "trait": hero.trait_id, "level": hero.level,
		"hp": roundi(hero.hp), "max_hp": roundi(hero.max_hp), "gold": hero.gold,
		"weapon": int(hero.items.get("weapon", {}).get("tier", 0)), "armor": int(hero.items.get("armor", {}).get("tier", 0)),
		"charm": int(hero.items.get("charm", {}).get("tier", 0)), "items": items,
		"energy": roundi(hero.energy), "pack": hero.pack.duplicate(),
		"lodging": run.world.buildings[hero.lodging]["type"] if hero.lodging >= 0 else "",
		"kills": hero.kills, "alive": hero.alive, "mood": roundi(hero.mood)}


func item_record(item: Dictionary) -> Dictionary:
	return {"base": item["base"], "slot": Loot.slot(run.content, item), "tier": item["tier"],
		"affixes": item["affixes"].duplicate(), "value": Loot.value(run.content, item)}


## Something the player did in the build phase (a building order, a price, a tool set).
func note_action(action: Dictionary) -> void:
	entry["actions"].append(action)


## Appends to one of the round's lists ("picks", "promotions", "heroes_left", "sales").
func note_list(key: String, item: Dictionary) -> void:
	if entry.has(key):
		entry[key].append(item)


## Adds to one of the round's counters (a plain number, or good -> number when `what` is given).
func note_count(key: String, amount: int, what := "") -> void:
	if entry.is_empty():
		return
	if what != "":
		if not entry.has(key):
			entry[key] = {}
		entry[key][what] = int(entry[key].get(what, 0)) + amount
	else:
		entry[key] = int(entry.get(key, 0)) + amount


## Sets a plain value on the round ("aged_up", "relic_offer", "battle", ...).
func note_value(key: String, value: Variant) -> void:
	entry[key] = value


## Files a night's report.
func note_night(report: Dictionary) -> void:
	if not entry.has("nights"):
		entry["nights"] = []
	entry["nights"].append(report)


## Goods spent this round on something, e.g. "paving" (roads).
func note_spend(key: String, cost: Dictionary) -> void:
	if not entry.has(key):
		return
	for r: String in cost:
		entry[key][r] = int(entry[key].get(r, 0)) + int(cost[r])


## A raider broke a square of a gate.
func note_breach() -> void:
	if entry.has("breaches"):
		entry["breaches"] = int(entry["breaches"]) + 1


func note_whim(hero: Unit) -> void:
	if entry.has("whims"):
		entry["whims"].append({"day": run.world.day_index() + 1, "hero": hero.display_name, "whim": hero.whim})


func note_loot(hero: Unit, item: Dictionary, equipped: bool) -> void:
	if entry.has("loot"):
		var e := item_record(item)
		e.merge({"day": run.world.day_index() + 1, "hero": hero.display_name, "trait": hero.trait_id, "equipped": equipped})
		entry["loot"].append(e)


## Shells heroes paid the settlement this round, by reason (tavern nights, carousing).
func note_hero_spending(reason: String, shells: int) -> void:
	if entry.has("hero_spending"):
		entry["hero_spending"][reason] = int(entry["hero_spending"].get(reason, 0)) + shells


## The town's and the wave's power levels as the wave comes (see Power).
func note_power(wave_types: Array) -> void:
	if not entry.is_empty():
		entry["power"] = {"town": Power.town(run.world), "wave": snappedf(Power.wave(run.content, wave_types), 0.1),
			"wave_scheduled": snappedf(Power.wave(run.content, run.waves.generate(run.round_number)), 0.1)}


func note_crafted(recipe_id: String) -> void:
	if entry.has("crafted"):
		entry["crafted"][recipe_id] = int(entry["crafted"].get(recipe_id, 0)) + 1


func note_market_sale(hero: Unit, good: Dictionary, price: int) -> void:
	if entry.has("market"):
		entry["market"].append({"day": run.world.day_index() + 1, "hero": hero.display_name, "trait": hero.trait_id,
			"recipe": good["recipe"], "tier": int(good.get("tier", 1)), "price": price,
			"stall": run.content.market["recipes"][good["recipe"]]["stall"]})


## Goods the settlement got from carcasses, prize shells paid and obsidian shards bought.
func note_economy(key: String, amount: int, what := "") -> void:
	if not entry.has(key):
		return
	if key == "yields":
		entry["yields"][what] = int(entry["yields"].get(what, 0)) + amount
	else:
		entry[key] = int(entry[key]) + amount
