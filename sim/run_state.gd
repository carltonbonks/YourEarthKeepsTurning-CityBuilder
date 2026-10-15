class_name RunState
extends RefCounted
## One run of the game: the settlement, its stock, relics and the round loop.
##
## Round loop: BUILD (order buildings) -> for each day: PICK (choose a newcomer
## at dawn) -> SIM (the day and night play out on their own) -> after the last
## night, which brings the round's warned wave: RELIC (pick 1 of N) -> next BUILD.
## The run ends in WON (survived the last round) or LOST (hearth destroyed or
## everyone gone). No scenes or nodes here, so whole runs can be simulated headless.
##
## Three parts hold the rest: `people` (People: dawn cards, promotions, heroes and their mood),
## `waves` (WavePlanner: what attacks and when) and `record` (RunRecord: the run's history).

enum Phase { BUILD, PICK, SIM, RELIC, WON, LOST }

const RESOURCES := ["food", "fuel", "wood", "stone", "shells", "flint", "hides", "bone", "obsidian",
	"copper", "cassiterite", "tin", "bronze", "bog_iron", "charcoal", "iron", "steel"]

var content: Content
var run_seed: int
var round_number := 1
var phase := Phase.BUILD

var world: World
var people: People
var hand: BuildHand
var waves: WavePlanner
var record: RunRecord
var stock := {}
var heroes: Array[Unit] = []
var fallen: Array[Unit] = []
var fallen_folk := 0
var relics: Array[String] = []
var relic_acquired_round := {}
var relic_offer: Array[String] = []
## Dawn cards: {kind: "folk"|"hero"|"promote"|"family", role: String, cost: int, hero: Unit (for hero cards),
## roles: Array (for a family)}.
var pick_offer: Array[Dictionary] = []
## Enemy type ids of this round's wave, in spawn order.
var next_wave: Array[String] = []
## Raiders held back from this round's scheduled wave by catch-up (see WavePlanner.plan).
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
## The round each age after the first was reached: age id -> round.
var age_rounds := {}
## Tool sets bought for townsfolk groups (ids from "tools" in data/ages.json).
var tools: Array[String] = []
## What the trader still has for sale this round: good -> count. Empty when no trader is here.
var trader_stock := {}
## Heroes who left town unhappy.
var departed: Array[Unit] = []
## The role of whoever left hungry this dawn ("" if nobody): none of that role come to the dawn pick.
var hunger_turned_away := ""

var _next_id := 1


func _init(game_content: Content, seed_value: int) -> void:
	content = game_content
	run_seed = seed_value
	people = People.new(self)
	hand = BuildHand.new(self)
	waves = WavePlanner.new(self)
	record = RunRecord.new(self)
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
		people.add_hero(people.make_hero())
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


## The hearth's health: the base, relics, and standing buildings that strengthen it (the Stone keep).
func hearth_max_hp() -> float:
	var total := content.num("hearth_max_hp") + mod("hearth_max_hp")
	if world == null:
		return total
	for b in world.buildings:
		if float(b["work_left"]) <= 0.0:
			total += float(content.buildings[b["type"]].get("hearth_hp", 0.0))
	return total


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
		and world.count_buildings(type, false) < building_max(type) \
		and (needs == "" or world.count_buildings(needs, false) > 0) \
		and content.age_reached(age, def.get("age", "")) and population() >= int(def.get("min_people", 0)) \
		and world.town.choose_plot(type) >= 0


## How many of a building the town may have: its max, raised by max_by_age once the town reaches that age.
func building_max(type: String) -> int:
	var def: Dictionary = content.buildings[type]
	var most := int(def.get("max", 99))
	var by_age: Dictionary = def.get("max_by_age", {})
	for a: String in by_age:
		if content.age_reached(age, a):
			most = maxi(most, int(by_age[a]))
	return most


func build(type: String) -> bool:
	if not can_build(type) or not world.add_building(type):
		return false
	var cost: Dictionary = content.buildings[type]["cost"]
	for r: String in cost:
		stock[r] = int(stock[r]) - int(cost[r])
	record.note_action({"kind": "build", "building": type})
	return true


# --- Market prices ----------------------------------------------------------

## Sets a stall kind's price level for the coming round ("cheap", "fair" or "dear").
func set_price(kind: String, level: String) -> void:
	if phase != Phase.BUILD or not prices.has(kind) or not content.market["price_levels"].has(level) or prices[kind] == level:
		return
	prices[kind] = level
	record.note_action({"kind": "price", "stall": kind, "level": level})


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
	people.offer_picks()


func on_building_done(type: String) -> void:
	var def: Dictionary = content.buildings[type]
	if def.has("lodging"):
		world.hero_ai.assign_lodgings()
	if def.has("hearth_hp"):
		world.hearth_hp = minf(hearth_max_hp(), world.hearth_hp + float(def["hearth_hp"]))
	# Goods a building brings with it when it stands (the age-up buildings' founding gifts).
	for good: String in def.get("gift", {}):
		stock[good] = int(stock.get(good, 0)) + int(def["gift"][good])
	var next_age: String = def.get("ages_up", "")
	if next_age != "" and not content.age_reached(age, next_age):
		age = next_age
		age_up_round = round_number
		age_rounds[next_age] = round_number
		record.note_value("aged_up", next_age)
		tell("The %s is raised. The %s begins: %s." % [def["name"], content.age_name(age), content.ages["ages"][age].get("begins", "")])


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
	record.note_action({"kind": "tools", "tools": id})
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


## True if a group has a tool set with this flag ("metal": pierces shields, "steel": cuts mail).
func has_tools_with(role: String, flag: String) -> bool:
	return tools.any(func(id: String) -> bool:
		return content.ages["tools"][id]["role"] == role and content.ages["tools"][id].get(flag, false))


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
	record.note_count("trades", 1, good)
	return true


# --- Dawn picks ------------------------------------------------------------

func can_take_pick(index: int) -> bool:
	if phase != Phase.PICK or index < 0 or index >= pick_offer.size():
		return false
	var card := pick_offer[index]
	return (card["kind"] == "promote" or population() + people.card_people(card) <= housing()) and int(stock["shells"]) >= int(card["cost"])


## Takes a dawn card (-1 skips), then lets the day begin.
func choose_pick(index: int) -> void:
	assert(phase == Phase.PICK)
	var taken := ""
	if can_take_pick(index):
		var card := pick_offer[index]
		stock["shells"] = int(stock["shells"]) - int(card["cost"])
		if card["kind"] == "hero":
			var hero: Unit = card["hero"]
			people.add_hero(hero)
			taken = "hero:" + hero.type_id
			tell("%s arrives and sleeps in %s." % [describe(hero), world.hero_ai.bed_name(hero.lodging)])
		elif card["kind"] == "promote":
			people.promote(card)
			taken = people.card_label(card)
		elif card["kind"] == "family":
			for role: String in card["roles"]:
				world.folk_ai.add_folk(role)
			taken = "family"
			tell("A family of %d comes to settle." % card["roles"].size())
		else:
			world.folk_ai.add_folk(card["role"])
			taken = card["role"]
			tell("A %s joins the settlement." % content.townsfolk[card["role"]]["name"].to_lower())
	var entry := {"day": world.day_index() + 1, "offered": pick_offer.map(people.card_label), "taken": taken}
	if hunger_turned_away != "":
		entry["hunger_turned_away"] = hunger_turned_away
	record.note_list("picks", entry)
	pick_offer = []
	hunger_turned_away = ""
	phase = Phase.SIM
	world.resume()
	tell("Day %d dawns." % (world.day_index() + 1))
	world.hero_ai.roll_whims()


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
			people.bury_heroes()
			people.update_moods()
			_close_night()
			people.offer_picks()
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


## Food that standing buildings (gardens, fields) bring in each dawn, before anyone eats. A building
## with worked_by only yields while enough of that role are in town to work it, plus their tools' field_mult.
func food_grown_daily() -> int:
	var total := 0
	for type: String in content.buildings:
		var def: Dictionary = content.buildings[type]
		var each := int(def.get("daily", {}).get("food", 0))
		if each <= 0:
			continue
		var count := world.count_buildings(type)
		var worked: Dictionary = def.get("worked_by", {})
		if not worked.is_empty():
			count = mini(count, count_role(worked["role"]) / int(worked["per"]))
			each = roundi(each * (1.0 + tool_bonus(worked["role"], "field_mult")))
		total += count * each
	return total


## Food eaten at each dawn. If there isn't enough, someone leaves, and none of their role join that dawn.
func daily_upkeep() -> void:
	var grown := food_grown_daily()
	if grown > 0:
		stock["food"] = int(stock["food"]) + grown
		record.note_count("food_grown", grown)
	var need := food_needed_today()
	if int(stock["food"]) >= need:
		stock["food"] = int(stock["food"]) - need
		return
	stock["food"] = 0
	people.hungry_today = true
	if not world.folk.is_empty():
		var leaver: Unit = world.folk[SeededRng.stream(run_seed, "hunger", round_number * 10 + world.day_index()).randi_range(0, world.folk.size() - 1)]
		world.folk.erase(leaver)
		world.night_report["left"].append(leaver.display_name)
		record.note_count("left_hungry", 1)
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
	var wants := resource_wants()
	var gaps := {}
	for r: String in wants:
		gaps[r] = (wants[r] - float(stock[r])) / maxf(wants[r], 1.0)
	var out: Array[String] = []
	out.assign(wants.keys())
	out.sort_custom(func(a: String, b: String) -> bool: return gaps[a] > gaps[b] or (gaps[a] == gaps[b] and a < b))
	return out


## Gatherable good -> how much the town wants in store (two days of need, plus what its buildings eat).
func resource_wants() -> Dictionary:
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
	# The charcoal burner eats wood, and the bloomery wants bog iron.
	if world.count_buildings("charcoal_burner") > 0:
		wants["wood"] += 6.0 * world.count_buildings("charcoal_burner")
	if world.count_buildings("bloomery") > 0:
		wants["bog_iron"] = 8.0
	return wants


## Files the night's report in the round record and keeps it for the UI.
func _close_night() -> void:
	var report := world.night_report.duplicate(true)
	report["night"] = world.day_index() + (0 if world.pause == World.Pause.DAWN else 1)
	report["hearth_damage"] = roundi(float(report["hearth_damage"]))
	last_night = report
	record.note_night(report)
	world.reset_night_report()


func _finish_round() -> void:
	people.bury_heroes()
	people.update_moods()
	_close_night()
	world.release()
	var stats := world.wave_stats
	record.note_value("battle", {
		"seconds": snappedf(float(stats["seconds"]), 0.1),
		"keep_hp_after": roundi(world.hearth_hp),
		"keep_damage": roundi(float(stats["keep_damage"])),
		"bounty_paid": 0,
		"bounty_refunded": 0,
		"hero_deaths": stats["hero_deaths"].duplicate(),
		"retreats": int(stats["retreats"]),
	})
	record.note_value("deaths", world.deaths.duplicate())
	for hero in heroes:
		people.level_up(hero)
	if world.hearth_hp <= 0.0:
		_lose()
		return
	if round_number >= content.int_num("rounds_to_win"):
		phase = Phase.WON
		tell("The people endured all %d rounds!" % round_number)
		record.end_round()
		return
	people.heal_between_rounds()
	people.heroes_sell_finds()
	relic_offer = _roll_relic_offer()
	record.note_value("relic_offer", relic_offer.duplicate())
	phase = Phase.RELIC


func _lose() -> void:
	if world.pause == World.Pause.HEARTH_LOST:
		_close_night()
	phase = Phase.LOST
	people.bury_heroes()
	world.release()
	if world.hearth_hp <= 0.0:
		tell("The hearth is trampled and goes dark in round %d." % round_number)
	else:
		tell("No one is left to tend the fire in round %d." % round_number)
	record.note_value("deaths", world.deaths.duplicate())
	record.end_round()


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
			var hero := people.make_hero()
			people.add_hero(hero)
			tell("%s follows the wanderer's fire to your camp." % describe(hero))
		for u in world.folk:
			world.folk_ai.apply_folk_stats(u)
		tell("Relic taken: %s." % content.relics[relic_id]["name"])
	record.note_value("relic_pick", relic_id)
	record.end_round()
	relic_offer = []
	round_number += 1
	var earned := income()
	stock["shells"] = int(stock["shells"]) + earned
	tell("Round %d. Traders leave %d shells." % [round_number, earned])
	_enter_build()


func _enter_build() -> void:
	phase = Phase.BUILD
	next_wave = waves.plan(round_number)
	if wave_eased > 0:
		tell("Scouts say the warband holds back %d of its number: your camp looks too weak to be worth them all." % wave_eased)
	world.roll_wave_sides()
	trader_stock = {}
	var trader: Dictionary = content.ages["trader"]
	if world.count_buildings(trader["needs"]) > 0:
		for good: String in trader["goods"]:
			trader_stock[good] = int(trader["goods"][good]["stock"])
		tell("The %s has come with %s." % [trader["name"].to_lower(), ", ".join(trader_stock.keys())])
	hand.deal()
	record.begin_round()


func is_over() -> bool:
	return phase == Phase.WON or phase == Phase.LOST


## The whole run so far as plain data (see RunRecord.to_record).
func to_record() -> Dictionary:
	return record.to_record()


## Breaks the run <-> world and run <-> part reference loops so a finished run can be freed.
func dispose() -> void:
	world.dispose()
	people.run = null
	hand.run = null
	waves.run = null
	record.run = null


func describe(hero: Unit) -> String:
	return "%s the %s %s" % [hero.display_name, content.traits[hero.trait_id]["name"].to_lower(),
		content.hero_classes[hero.type_id]["name"].to_lower()]


func new_id() -> int:
	_next_id += 1
	return _next_id


## The last id handed out (for placeholder names).
func peek_id() -> int:
	return _next_id


func tell(line: String) -> void:
	story.append(line)


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
