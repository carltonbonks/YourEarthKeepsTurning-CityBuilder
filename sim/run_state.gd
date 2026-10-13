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

const RESOURCES := ["food", "fuel", "wood", "stone", "shells", "flint", "hides", "bone", "obsidian",
	"copper", "cassiterite", "tin", "bronze"]

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
## Raiders held back from this round's scheduled wave by catch-up (see plan_wave).
var wave_eased := 0
## Plain-language story of what happened, newest last.
var story: Array[String] = []
## The last night's report, shown at the next decision (see World.night_report).
var last_night := {}
## Price level per stall kind ("cheap", "fair" or "dear"; see data/recipes.json), set while building.
var prices := {}
## The town's tech age (an id from data/ages.json) and the round it was reached (0 = the start).
var age := ""
var age_up_round := 0
## Tool sets bought for townsfolk groups (ids from "tools" in data/ages.json).
var tools: Array[String] = []
## What the trader still has for sale this round: good -> count. Empty when no trader is here.
var trader_stock := {}
## Heroes who left town unhappy.
var departed: Array[Unit] = []
var _hungry_today := false
## The role of whoever left hungry this dawn ("" if nobody): none of that role come to the dawn pick.
var hunger_turned_away := ""

## Machine-readable history of this run for stats and debugging (see to_record()).
## Format changes bump RECORD_FORMAT so old saved runs can still be read.
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
const RECORD_FORMAT := 12
var record_rounds: Array[Dictionary] = []
var _round_entry := {}

var _next_id := 1
var _hero_rng: SeededRng


func _init(game_content: Content, seed_value: int) -> void:
	content = game_content
	run_seed = seed_value
	_hero_rng = SeededRng.stream(run_seed, "heroes")
	age = content.ages["order"][0]
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
			world.folk_ai.add_folk(role)
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
	return phase == Phase.BUILD and can_afford(def["cost"]) \
		and world.count_buildings(type, false) < int(def.get("max", 99)) \
		and (needs == "" or world.count_buildings(needs, false) > 0) \
		and content.age_reached(age, def.get("age", "")) and population() >= int(def.get("min_people", 0)) \
		and world.town.choose_plot(type) >= 0


func build(type: String) -> bool:
	if not can_build(type) or not world.add_building(type):
		return false
	var cost: Dictionary = content.buildings[type]["cost"]
	for r: String in cost:
		stock[r] = int(stock[r]) - int(cost[r])
	_round_entry["actions"].append({"kind": "build", "building": type})
	return true


# --- Paving and gates ---------------------------------------------------------

## Goods spent this round on something, e.g. "paving" (roads).
func note_spend(key: String, cost: Dictionary) -> void:
	if not _round_entry.has(key):
		return
	for r: String in cost:
		_round_entry[key][r] = int(_round_entry[key].get(r, 0)) + int(cost[r])


## A raider broke a square of a gate.
func note_breach() -> void:
	if _round_entry.has("breaches"):
		_round_entry["breaches"] = int(_round_entry["breaches"]) + 1


## How the town's ground looks now, for the round record.
func _town_snapshot() -> Dictionary:
	var rings := {}
	for plot in world.town.plots:
		if int(plot["building"]) >= 0:
			rings[str(plot["ring"] + 1)] = int(rings.get(str(plot["ring"] + 1), 0)) + 1
	return {"paved": world.town.paved_counts(), "trails": world.pathing.count_ground(Pathing.TRAIL),
		"paths": world.pathing.count_ground(Pathing.PATH), "plots_by_ring": rings, "gates": world.town.gate_counts()}


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
		world.hero_ai.assign_lodgings()
	var next_age: String = content.buildings[type].get("ages_up", "")
	if next_age != "" and not content.age_reached(age, next_age):
		age = next_age
		age_up_round = round_number
		_round_entry["aged_up"] = next_age
		tell("The %s is raised. The %s begins: copper in the hills, tin by the dens, and traders from the south." % [
			content.buildings[type]["name"], content.age_name(age)])


# --- Ages: tool sets and the trader -----------------------------------------

func can_buy_tools(id: String) -> bool:
	var def: Dictionary = content.ages["tools"][id]
	return phase == Phase.BUILD and not tools.has(id) and content.age_reached(age, def.get("age", "")) and can_afford(def["cost"])


## Buys a tool set: a lasting upgrade for one townsfolk group.
func buy_tools(id: String) -> bool:
	if not can_buy_tools(id):
		return false
	var def: Dictionary = content.ages["tools"][id]
	for r: String in def["cost"]:
		stock[r] = int(stock[r]) - int(def["cost"][r])
	tools.append(id)
	for u in world.folk:
		world.folk_ai.apply_folk_stats(u)
	_round_entry["actions"].append({"kind": "tools", "tools": id})
	tell("%s for the %ss." % [def["name"], content.townsfolk[def["role"]]["name"].to_lower()])
	return true


## Sum of one tool-set bonus for a townsfolk role (0 if none).
func tool_bonus(role: String, key: String) -> float:
	var total := 0.0
	for id in tools:
		var def: Dictionary = content.ages["tools"][id]
		if def["role"] == role:
			total += float(def.get(key, 0.0))
	return total


func has_metal_tools(role: String) -> bool:
	return tools.any(func(id: String) -> bool:
		return content.ages["tools"][id]["role"] == role and content.ages["tools"][id].get("metal", false))


func trader_price(good: String) -> int:
	return int(content.ages["trader"]["goods"][good]["price"])


func can_trade(good: String) -> bool:
	return phase == Phase.BUILD and int(trader_stock.get(good, 0)) > 0 and int(stock["shells"]) >= trader_price(good)


## Buys one of a good from the visiting trader.
func trade(good: String) -> bool:
	if not can_trade(good):
		return false
	stock["shells"] = int(stock["shells"]) - trader_price(good)
	stock[good] = int(stock[good]) + 1
	trader_stock[good] = int(trader_stock[good]) - 1
	_round_entry["trades"][good] = int(_round_entry["trades"].get(good, 0)) + 1
	return true


# --- Dawn picks ------------------------------------------------------------

func can_take_pick(index: int) -> bool:
	if phase != Phase.PICK or index < 0 or index >= pick_offer.size():
		return false
	var card := pick_offer[index]
	return (card["kind"] == "promote" or population() < housing()) and int(stock["shells"]) >= int(card["cost"])


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
			tell("%s arrives and sleeps in %s." % [describe(hero), world.hero_ai.bed_name(hero.lodging)])
		elif card["kind"] == "promote":
			_promote(card)
			taken = _card_label(card)
		else:
			world.folk_ai.add_folk(card["role"])
			taken = card["role"]
			tell("A %s joins the settlement." % content.townsfolk[card["role"]]["name"].to_lower())
	var entry := {"day": world.day_index() + 1, "offered": pick_offer.map(_card_label), "taken": taken}
	if hunger_turned_away != "":
		entry["hunger_turned_away"] = hunger_turned_away
	_round_entry["picks"].append(entry)
	pick_offer = []
	hunger_turned_away = ""
	phase = Phase.SIM
	world.resume()
	tell("Day %d dawns." % (world.day_index() + 1))
	world.hero_ai.roll_whims()


func _offer_picks() -> void:
	var rng := SeededRng.stream(run_seed, "picks", round_number * 10 + world.day_index())
	var pool: Array[Dictionary] = []
	var roles := content.townsfolk.keys()
	roles.sort()
	for role: String in roles:
		if role != hunger_turned_away:
			pool.append({"kind": "folk", "role": role, "cost": 0})
	if world.hero_ai.count_lodgings() > 0:
		pool.append({"kind": "hero", "role": "hero", "cost": content.int_num("hero_card_cost"), "hero": _make_hero(true)})
	pick_offer = []
	var promote := _promotion_card(rng)
	var slots := content.int_num("pick_choices") - (0 if promote.is_empty() else 1)
	while pick_offer.size() < slots and not pool.is_empty():
		var card: Dictionary = rng.pick(pool)
		pool.erase(card)
		pick_offer.append(card)
	if not promote.is_empty():
		pick_offer.append(promote)
	phase = Phase.PICK


func _card_label(card: Dictionary) -> String:
	if card["kind"] == "promote":
		return "promote:" + card["role"]
	return "hero:" + card["hero"].type_id if card["kind"] == "hero" else card["role"]


# --- Promotions -------------------------------------------------------------

## A Promote card for one townsperson who has earned it, or {} if nobody has.
## The outcome (name, class, trait) is rolled now so the card can show it.
func _promotion_card(rng: SeededRng) -> Dictionary:
	var rules := content.promotions
	var candidates: Array[Dictionary] = []
	for u in world.folk:
		if u.type_id == "warrior" and u.kills >= int(rules["warrior"]["kills"]) and world.hero_ai.count_lodgings() > 0:
			candidates.append({"kind": "promote", "role": "warrior", "cost": int(rules["warrior"]["cost"]), "unit": u})
		elif u.type_id == "craftsperson" and u.master_of == "":
			var best := ""
			var shops := u.made.keys()
			shops.sort()
			for shop: String in shops:
				if int(u.made[shop]) >= int(rules["craftsperson"]["made"]) and (best == "" or int(u.made[shop]) > int(u.made[best])):
					best = shop
			if best != "":
				candidates.append({"kind": "promote", "role": "craftsperson", "cost": int(rules["craftsperson"]["cost"]),
					"unit": u, "workshop": best})
	if candidates.is_empty():
		return {}
	var card: Dictionary = rng.pick(candidates)
	if card["role"] == "warrior":
		var hero := _make_hero()
		hero.type_id = rules["warrior"]["becomes"]
		hero.level = int(rules["warrior"]["start_level"])
		world.hero_ai.apply_hero_stats(hero)
		hero.hp = hero.max_hp
		card["hero"] = hero
	else:
		var traits: Array = rules["craftsperson"]["traits"].keys()
		traits.sort()
		card["trait"] = rng.pick(traits)
		card["name"] = _unused_name()
	return card


func _promote(card: Dictionary) -> void:
	var u: Unit = card["unit"]
	var since := "round %d" % u.joined_round if u.joined_round > 1 else "the first fire"
	var entry := {"day": world.day_index() + 1, "role": card["role"], "joined_round": u.joined_round}
	if card["role"] == "warrior":
		var hero: Unit = card["hero"]
		hero.kills = u.kills
		world.folk.erase(u)
		_add_hero(hero)
		tell("A warrior who has stood watch since %s and killed %d foes is raised up: %s." % [since, u.kills, describe(hero)])
		entry.merge({"name": hero.display_name, "became": hero.type_id, "trait": hero.trait_id, "kills": u.kills})
	else:
		u.display_name = card["name"]
		u.master_of = card["workshop"]
		u.craft_trait = card["trait"]
		var t: Dictionary = content.promotions["craftsperson"]["traits"][u.craft_trait]
		tell("%s, a craftsperson since %s, becomes master of the %s (%s)." % [u.display_name, since,
			content.buildings[u.master_of]["name"].to_lower(), t["name"]])
		entry.merge({"name": u.display_name, "became": "master_" + u.master_of, "trait": u.craft_trait, "made": int(u.made[u.master_of])})
	_round_entry["promotions"].append(entry)


## A master crafter's trait numbers ({} for an ordinary craftsperson).
func craft_trait(unit: Unit) -> Dictionary:
	if unit.craft_trait == "":
		return {}
	return content.promotions["craftsperson"]["traits"][unit.craft_trait]


# --- Simulation ------------------------------------------------------------

func step() -> void:
	if phase != Phase.SIM:
		return
	world.step()
	match world.pause:
		World.Pause.DAWN:
			_bury_heroes()
			_update_moods()
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


## Food the town eats each dawn: every person, townsfolk and heroes alike, less drying racks and relics.
func food_needed_today() -> int:
	var racks := world.count_buildings("drying_rack")
	var growth := 0.0
	for id in relics:
		growth += float(content.relics[id]["effects"].get("food_growth", 0.0)) * (round_number - int(relic_acquired_round[id]))
	return maxi(0, int(ceil(population() * content.num("food_per_person_per_day") * (1.0 - 0.25 * racks) - growth)))


## Food that standing buildings (gardens) bring in each dawn, before anyone eats.
func food_grown_daily() -> int:
	var total := 0
	for type: String in content.buildings:
		total += world.count_buildings(type) * int(content.buildings[type].get("daily", {}).get("food", 0))
	return total


## Food eaten at each dawn. If there isn't enough, someone leaves, and none of their role join that dawn.
func daily_upkeep() -> void:
	var grown := food_grown_daily()
	if grown > 0:
		stock["food"] = int(stock["food"]) + grown
		_round_entry["food_grown"] = int(_round_entry.get("food_grown", 0)) + grown
	var need := food_needed_today()
	if int(stock["food"]) >= need:
		stock["food"] = int(stock["food"]) - need
		return
	stock["food"] = 0
	_hungry_today = true
	if not world.folk.is_empty():
		var leaver: Unit = world.folk[SeededRng.stream(run_seed, "hunger", round_number * 10 + world.day_index()).randi_range(0, world.folk.size() - 1)]
		world.folk.erase(leaver)
		world.night_report["left"].append(leaver.display_name)
		_round_entry["left_hungry"] = int(_round_entry.get("left_hungry", 0)) + 1
		tell("Hunger: a %s walks away into the wilds." % leaver.display_name.to_lower())
		if content.balance.get("hunger_turns_folk_away", false):
			hunger_turned_away = leaver.type_id


func fuel_needed_tonight() -> int:
	var need := content.num("fuel_per_night_base") + population() * content.num("fuel_per_person_per_night") - mod("fuel_saving")
	for type: String in content.buildings:
		need += world.count_buildings(type) * float(content.buildings[type].get("fuel", 0.0))
	return maxi(0, int(ceil(need)))


## What gatherers should fetch next: whatever is shortest against two days of need.
func most_needed_resource() -> String:
	return needed_resources()[0]


## Gatherable goods, most needed first (shortest against two days of need).
func needed_resources() -> Array[String]:
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
	# The smelter wants copper and cassiterite, and burns fuel.
	if world.count_buildings("smelter") > 0:
		wants["copper"] = 8.0
		wants["cassiterite"] = 4.0
		wants["fuel"] += 3.0
	var gaps := {}
	for r: String in wants:
		gaps[r] = (wants[r] - float(stock[r])) / maxf(wants[r], 1.0)
	var out: Array[String] = []
	out.assign(wants.keys())
	out.sort_custom(func(a: String, b: String) -> bool: return gaps[a] > gaps[b] or (gaps[a] == gaps[b] and a < b))
	return out


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
	_bury_heroes()
	_update_moods()
	_close_night()
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
			world.folk_ai.apply_folk_stats(u)
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
	next_wave = plan_wave(round_number)
	if wave_eased > 0:
		tell("Scouts say the warband holds back %d of its number: your camp looks too weak to be worth them all." % wave_eased)
	world.roll_wave_sides()
	trader_stock = {}
	var trader: Dictionary = content.ages["trader"]
	if world.count_buildings(trader["needs"]) > 0:
		for good: String in trader["goods"]:
			trader_stock[good] = int(trader["goods"][good]["stock"])
		tell("The %s has come with %s." % [trader["name"].to_lower(), ", ".join(trader_stock.keys())])
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


## The round's warned wave: the scheduled wave, eased off while it would far outmatch the town.
## Catch-up only ever shrinks a wave, so a town that pulls ahead keeps its lead. Raiders are held
## back from the end of the list (never the boss) until the wave is at most catch_up_max_ratio
## times the town's power, keeping at least catch_up_min_share of them.
func plan_wave(for_round: int) -> Array[String]:
	var wave := generate_wave(for_round)
	wave_eased = 0
	var cap := content.num("catch_up_max_ratio")
	if cap <= 0.0:
		return wave
	var limit := cap * float(Power.town(world)["total"])
	var keep := ceili(wave.size() * content.num("catch_up_min_share"))
	while wave.size() > keep and Power.wave(content, wave) > limit:
		var i := wave.size() - 1
		while i >= 0 and content.enemies[wave[i]].get("boss", false):
			i -= 1
		if i < 0:
			break
		wave.remove_at(i)
		wave_eased += 1
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
	world.dispose()


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
		"plots": world.buildings.map(func(b: Dictionary) -> Dictionary:
			var plot: Dictionary = world.town.plots[b["plot"]]
			return {"building": b["type"], "ring": int(plot["ring"]) + 1, "sector": int(plot["sector"])}),
		"townsfolk": _folk_counts(),
		"townsfolk_lost": fallen_folk,
		"relics": relics.duplicate(),
		"prices": prices.duplicate(),
		"age": age,
		"age_up_round": age_up_round,
		"tools": tools.duplicate(),
		"heroes": heroes.map(_hero_snapshot),
		"fallen": fallen.map(_hero_snapshot),
		"departed": departed.map(_hero_snapshot),
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
		"prices": prices.duplicate(), "crafted": {}, "market": [], "prizes": 0, "obsidian": 0, "yields": {},
		"age": age, "promotions": [], "trades": {}, "cassiterite": 0, "heroes_left": [], "paving": {},
		"breaches": 0, "wave_eased": wave_eased}


func _end_round_entry() -> void:
	_round_entry["stock_end"] = stock.duplicate()
	_round_entry["town"] = _town_snapshot()
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
		"kills": hero.kills, "alive": hero.alive, "mood": roundi(hero.mood)}


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


## The town's and the wave's power levels as the wave comes (see Power).
func note_power(wave_types: Array) -> void:
	if not _round_entry.is_empty():
		_round_entry["power"] = {"town": Power.town(world), "wave": snappedf(Power.wave(content, wave_types), 0.1),
			"wave_scheduled": snappedf(Power.wave(content, generate_wave(round_number)), 0.1)}


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
	hero.mood = content.num("mood_start")
	world.hero_ai.apply_hero_stats(hero)
	hero.hp = hero.max_hp
	return hero


func _add_hero(hero: Unit) -> void:
	hero.pos = Vector2.from_angle(heroes.size() * 1.7 + 0.4) * 60.0
	world.hero_ai.apply_hero_stats(hero)
	heroes.append(hero)
	world.hero_ai.assign_lodgings()


func _bury_heroes() -> void:
	for hero in heroes.duplicate():
		if not hero.alive:
			heroes.erase(hero)
			fallen.append(hero)


func _unused_name() -> String:
	var taken := {}
	for h in heroes + fallen + departed:
		taken[h.display_name] = true
	for u in world.folk:
		taken[u.display_name] = true
	var free := content.hero_names.filter(func(n: String) -> bool: return not taken.has(n))
	if free.is_empty():
		return "Wanderer %d" % _next_id
	return _hero_rng.pick(free)


# --- Hero mood --------------------------------------------------------------

## Moves each hero's mood by what happened since the last dawn, then lets the
## unhappiest walk away. Called at each dawn and at the end of each round.
func _update_moods() -> void:
	var report := world.night_report
	var comrades := int(report.get("hero_deaths", 0))
	for hero in living_heroes():
		var changes := {}
		match hero.slept:
			"favourite":
				changes["slept in their favourite lodging"] = content.num("mood_slept_favourite")
			"other":
				changes["slept somewhere they don't like"] = content.num("mood_slept_other")
			"rough":
				changes["slept rough by the hearth"] = content.num("mood_slept_rough")
		if hero.mood_events.has("bought"):
			changes["bought something they wanted"] = content.num("mood_bought")
		if int(hero.mood_events.get("prize", 0)) > 0:
			changes["won prizes"] = content.num("mood_prize")
		if comrades > 0:
			changes["lost comrades"] = content.num("mood_comrade_died") * comrades
		if _hungry_today:
			changes["went hungry"] = content.num("mood_hungry")
		if report.get("cold", false):
			changes["shivered through a cold night"] = content.num("mood_cold")
		var before := hero.mood
		for why: String in changes:
			hero.mood += float(changes[why])
		hero.mood = clampf(hero.mood, 0.0, 100.0)
		hero.slept = ""
		hero.mood_events = {}
		var worst := ""
		for why: String in changes:
			if float(changes[why]) < 0.0 and (worst == "" or float(changes[why]) < float(changes[worst])):
				worst = why
		if hero.mood <= content.num("mood_leave_at"):
			_hero_leaves(hero, worst)
		elif hero.mood <= content.num("mood_grumble_at") and hero.mood < before and worst != "":
			tell("%s grumbles: they %s. They may leave if this goes on." % [hero.display_name, worst])
	_hungry_today = false


func _hero_leaves(hero: Unit, why: String) -> void:
	heroes.erase(hero)
	departed.append(hero)
	hero.target = null
	world.night_report["left"].append(hero.display_name)
	world.night_report["heroes_left"].append(hero.display_name)
	if _round_entry.has("heroes_left"):
		_round_entry["heroes_left"].append({"day": world.day_index() + 1, "hero": hero.display_name, "trait": hero.trait_id,
			"mood": roundi(hero.mood), "why": why})
	tell("%s has had enough%s and leaves town with their gear." % [describe(hero), " (%s)" % why if why != "" else ""])
	world.hero_ai.assign_lodgings()


func _level_up(hero: Unit) -> void:
	var per_level := content.num("xp_per_level")
	while hero.xp >= per_level * hero.level:
		hero.xp -= per_level * hero.level
		hero.level += 1
		world.hero_ai.apply_hero_stats(hero)
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
