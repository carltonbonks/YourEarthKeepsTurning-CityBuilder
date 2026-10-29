class_name BuildHand
extends RefCounted
## Blueprints (`run.hand`), like Against the Storm's: each round's build phase offers a few buildings to draft,
## weighted toward what the town needs, and a drafted building stays on offer for the rest of the run.
## Basic buildings (homes and food) are always on offer and never drafted. Ageing up is its own card whenever
## it can be raised, and the building the next age-up needs is always among the offers until it is drafted.
## Ordering pays the building's cost (RunState.build) as often as its max allows.
## A craft (data/crafts.json, Yusuf 2026-10-26) is one card that adds a workshop and the stall that sells its goods;
## their pieces never come up alone. The market comes with the first craft: until it is drafted, the draft offers
## market_crafts crafts with the market in them. A craft opens buildings that only come up once the town has it.
## Of each draft's offers, one builds on what the town has started (`deep`: an upgrade, a building a craft opened,
## or another craft once the market is in) and the rest are new buildings. Once the open rings are nearly full (clear_when_full in
## data/town.json), the draft also offers to clear the next ring of plots for its clear_cost, in place of a building (`ring_offer`, `clear_ring`).
## Each run drafts from its own pool of blueprints (Yusuf, 2026-10-23): buildings tagged staple, the founding
## traditions' buildings and what the age-ups require are always in it, and blueprint_pool_share of the rest, per age,
## is dealt from the run's seed, so runs differ in which buildings they can have at all (`in_pool`).
## Blueprint and upgrade offers roll their own rarity each time they are dealt (CardRoll, Yusuf 2026-10-23): a rolled
## offer carries modifiers, and drafting it writes them into the building's numbers for the rest of the run, so the
## rolled blueprint is the one in the town's hand. Rows, the ring offer and the age-up card don't roll.
## Numbers are in data/balance.json (blueprint_*, build_need_weight, build_new_weight, build_redraw_cost).

var run: RunState
## This round's draft offers, each {"building": type, "need": why the town wants it ("" if nothing in particular)},
## plus "roll" and "boons" (CardRoll) when it rolled above white.
var cards: Array[Dictionary] = []
## The ageing-up card ({} when no age-up building can be ordered).
var milestone := {}
## Craft offers in the draft, each {"craft": id from data/crafts.json, "need": why the town wants it}.
var crafts: Array[Dictionary] = []
## Upgrade offers in the draft, each {"upgrade": id from data/upgrades.json}, plus "roll" and "boons" when it rolled.
## Any offer dealt as the draft's deepening offer (one that builds on what the town has) carries "deep": true.
var upgrade_offers: Array[Dictionary] = []
## Buildings drafted this run, in the order they were taken: on offer for good.
var blueprints: Array[String] = []
## Drafted blueprints and taken upgrades that rolled: building type or "upgrade:<id>" -> {"roll", "boons"}.
var rolled := {}
## Crafts drafted this run, in the order they were taken.
var crafts_taken: Array[String] = []
## Drafts left to take (unspent picks carry over to the next round).
var picks := 0
## Rerolls of the offers used this round.
var redraws := 0
var _dealt_round := -1
## This run's blueprint pool (see `in_pool`), dealt once the founding traditions are chosen.
var _pool: Array[String] = []
var _dealt_age := ""
var _fills := 0


func _init(run_state: RunState) -> void:
	run = run_state


## Deals fresh offers for the round (called as the build phase begins). The first round brings
## blueprint_first_picks drafts and every later one blueprint_picks; reaching a new age adds blueprint_age_picks.
func deal() -> void:
	redraws = 0
	if _dealt_round != run.round_number:
		var content := run.content
		picks += content.int_num("blueprint_first_picks") if _dealt_round < 0 else content.int_num("blueprint_picks")
		if _dealt_age != "" and _dealt_age != run.age:
			picks += content.int_num("blueprint_age_picks")
		_dealt_round = run.round_number
		_dealt_age = run.age
	_fill(SeededRng.stream(run.run_seed, "build_cards", run.round_number * 10))


## Rerolls the offers, once a round while a draft is left, for shells.
func can_redraw() -> bool:
	return run.phase == RunState.Phase.BUILD and picks > 0 and redraws == 0 and int(run.stock["shells"]) >= redraw_cost() \
		and not run.has_effect("no_redraw") and not (run.gentle and run.round_number == 1)


func redraw() -> bool:
	if not can_redraw():
		return false
	run.stock["shells"] = int(run.stock["shells"]) - redraw_cost()
	redraws += 1
	var before := labels()
	_fill(SeededRng.stream(run.run_seed, "build_cards", run.round_number * 10 + redraws), before)
	run.record.note_action({"kind": "redraw", "cost": redraw_cost()})
	run.record.note_list("build_hands", hand_entry())
	return true


func redraw_cost() -> int:
	return run.content.int_num("build_redraw_cost")


## Basic buildings (homes and food, `basic` in data/buildings.json) that can go up now: always on offer,
## as many as the town can pay for, never drafted.
func basics() -> Array[String]:
	var out: Array[String] = []
	var types := run.content.buildings.keys()
	types.sort()
	for type: String in types:
		if run.content.buildings[type].get("basic", false) and eligible(type):
			out.append(type)
	return out


## True if this building type can be ordered from the hand: a basic, a blueprint or the ageing-up card.
func offers(type: String) -> bool:
	return run.content.buildings[type].get("basic", false) or milestone.get("building", "") == type or blueprints.has(type)


func can_order(type: String) -> bool:
	return offers(type) and run.can_build(type)


func order(type: String) -> bool:
	if not can_order(type) or not run.build(type):
		return false
	if milestone.get("building", "") == type:
		milestone = {}
	return true


## True while the draft has anything on offer (a building, a craft or an upgrade).
func has_offers() -> bool:
	return not cards.is_empty() or not crafts.is_empty() or not upgrade_offers.is_empty()


## True if this building is among the offers and a draft is left.
func can_draft(type: String) -> bool:
	return run.phase == RunState.Phase.BUILD and picks > 0 and cards.any(func(c: Dictionary) -> bool: return c["building"] == type)


## Drafts an offered building for the rest of the run; fresh offers follow while drafts are left.
func draft(type: String) -> bool:
	if not can_draft(type):
		return false
	var card: Dictionary = cards.filter(func(c: Dictionary) -> bool: return c["building"] == type)[0]
	_take(type, card)
	run.record.note_action({"kind": "blueprint", "building": type})
	_after_draft()
	return true


func can_clear_ring() -> bool:
	return ring_offer() and run.can_afford(run.ring_cost())


## Takes the draft's ring offer: pays to clear the next ring of plots, which opens for good.
func clear_ring() -> bool:
	if not can_clear_ring():
		return false
	var cost := run.ring_cost()
	for r: String in cost:
		run.stock[r] = int(run.stock[r]) - int(cost[r])
	run.open_ring()
	run.record.note_action({"kind": "clear_ring", "ring": run.rings_open})
	run.tell("Townsfolk clear the ground for a new ring of plots round the town.", RunState.AMBIENT)
	_after_draft()
	return true


## True while the draft offers to clear the next ring: a draft is left, a ring is still closed and the open rings
## are nearly full. It is checked live, so it turns up as soon as building fills the town.
func ring_offer() -> bool:
	return run.phase == RunState.Phase.BUILD and picks > 0 and run.ring_closed() \
		and run.world.town.fullness() >= float(run.content.town["clear_when_full"])


## Drafts a founding tradition's blueprint for the town (`blueprint` in data/traditions.json: a building type, or
## craft:<id> for a craft with the market if the town has none), in place of one of the drafts left (Yusuf, 2026-10-26).
func gift(key: String) -> void:
	if key.begins_with("craft:"):
		var id := key.trim_prefix("craft:")
		if crafts_taken.has(id):
			return
		crafts_taken.append(id)
		for type in craft_adds(id):
			_take(type)
		run.record.note_action({"kind": "tradition_blueprint", "craft": id})
	else:
		if blueprints.has(key):
			return
		_take(key)
		run.record.note_action({"kind": "tradition_blueprint", "building": key})
	picks = maxi(0, picks - 1)


## The name of what a tradition's blueprint key brings: a building's name, or a craft's.
static func gift_name(content: Content, key: String) -> String:
	if key.begins_with("craft:"):
		return content.crafts[key.trim_prefix("craft:")]["name"]
	return content.buildings[key]["name"]


## Adds a blueprint; a rolled offer's modifiers change the building for the rest of the run, and Twin-built raises
## one for free at once.
func _take(type: String, card := {}) -> void:
	blueprints.append(type)
	var entry := {"building": type}
	if card.has("roll"):
		entry["roll"] = card["roll"]
		entry["mods"] = card["boons"].duplicate()
		_apply_roll(type, card, type)
	run.record.note_list("blueprints", entry)


## Writes a drafted roll into a building's numbers and raises Twin-built's free one (if a plot is free).
func _apply_roll(type: String, card: Dictionary, key: String) -> void:
	rolled[key] = {"roll": card["roll"], "boons": card["boons"].duplicate()}
	CardRoll.apply_to_building(run, type, card)
	var name: String = run.content.buildings[type]["name"]
	run.tell("%s %s: %s." % [run.content.rarity_tier(card["roll"])["name"], name.to_lower(),
		"; ".join(PackedStringArray(CardRoll.lines(run.content, card)))])
	if CardRoll.card_has(run.content, card, "free_copy") and run.world.count_buildings(type, false) < run.building_max(type) \
			and run.world.add_building(type):
		run.record.note_count("card_mods_fired", 1, "twin_built")
		run.tell("A second %s goes up for free." % name.to_lower(), RunState.AMBIENT)


func _after_draft() -> void:
	picks -= 1
	if picks > 0:
		_fill(SeededRng.stream(run.run_seed, "build_cards", run.round_number * 10 + 5 + blueprints.size()))
		run.record.note_list("build_hands", hand_entry())
	else:
		cards = []
		crafts = []
		upgrade_offers = []


## Buildings that could be drafted now on their own card: not basic or ageing up, not a craft's piece (those come
## with their craft), opened (`opened`), not drafted yet, in reach of the age, below their max, and whatever they
## require already drafted or standing.
func draftable(type: String) -> bool:
	var content := run.content
	var def: Dictionary = content.buildings[type]
	var needs: String = def.get("requires", "")
	return not def.get("basic", false) and not def.has("ages_up") and not blueprints.has(type) and in_pool(type) \
		and not is_piece(type) and opened(type) \
		and content.age_reached(run.age, def.get("age", "")) \
		and run.world.count_buildings(type, false) < run.building_max(type) \
		and (needs == "" or blueprints.has(needs) or run.world.count_buildings(needs, false) > 0)


## True if this building can come up in this run's draft. Basics and age-up buildings are never drafted, so they
## are not in the pool but always on offer.
func in_pool(type: String) -> bool:
	return pool().has(type)


## This run's blueprint pool, sorted: staples, the traditions' buildings, the crafts' pieces and what they open
## (a craft decides those), what the age-ups require (and what those require), and blueprint_pool_share of the rest of each age's blueprints, at least one per age, from the run's seed.
func pool() -> Array[String]:
	if not _pool.is_empty():
		return _pool
	var content := run.content
	var keep := {}
	var rest := {}
	var types := content.buildings.keys()
	types.sort()
	for type: String in types:
		var def: Dictionary = content.buildings[type]
		if def.has("ages_up"):
			keep[def.get("requires", "")] = true
		if def.get("basic", false) or def.has("ages_up"):
			continue
		if content.has_tag("building", type, "staple") or run.tradition_favours(type) or is_piece(type) or opener(type) != "":
			keep[type] = true
		else:
			var age: String = def.get("age", content.ages["order"][0])
			if not rest.has(age):
				rest[age] = []
			rest[age].append(type)
	var rng := SeededRng.stream(run.run_seed, "blueprint_pool")
	for age: String in content.ages["order"]:
		var left: Array = rest.get(age, [])
		var take := maxi(1, roundi(left.size() * content.num("blueprint_pool_share"))) if not left.is_empty() else 0
		for i in take:
			var type: String = left.pop_at(rng.randi_range(0, left.size() - 1))
			keep[type] = true
	# A pooled building brings what it requires.
	var grew := true
	while grew:
		grew = false
		for type: String in keep.keys():
			var needs: String = content.buildings.get(type, {}).get("requires", "")
			if needs != "" and not keep.has(needs):
				keep[needs] = true
				grew = true
	keep.erase("")
	var out: Array[String] = []
	out.assign(keep.keys())
	out.sort()
	# Before the traditions are chosen the pool is only a preview, so it is dealt again after.
	if not run.awaiting_traditions():
		_pool = out
	return out


## The building the next age-up requires, if it is neither drafted nor standing ("" if none).
func ageing_need() -> String:
	var order: Array = run.content.ages["order"]
	var next := order.find(run.age) + 1
	if next >= order.size():
		return ""
	for type: String in run.content.buildings:
		var def: Dictionary = run.content.buildings[type]
		if def.get("ages_up", "") != order[next]:
			continue
		var needs: String = def.get("requires", "")
		if needs != "" and not blueprints.has(needs) and run.world.count_buildings(needs, false) == 0:
			return needs
	return ""


## A "build_hands" record entry: the offers, and their rolls when any rolled above white.
func hand_entry() -> Dictionary:
	var entry := {"cards": labels()}
	var r := rolls()
	if r.any(func(x: String) -> bool: return x != "white"):
		entry["rolls"] = r
	return entry


## Each draft offer's rolled rarity, in labels() order, for the run record.
func rolls() -> Array:
	var out := cards.map(CardRoll.roll_of)
	for c in crafts:
		out.append("white")
	if ring_offer():
		out.append("white")
	for c in upgrade_offers:
		out.append(CardRoll.roll_of(c))
	return out


## The draft offers, for the run record.
func labels() -> Array:
	var out := cards.map(func(c: Dictionary) -> String: return c["building"])
	for c in crafts:
		out.append("craft:" + c["craft"])
	if ring_offer():
		out.append("ring")
	for c in upgrade_offers:
		out.append("upgrade:" + c["upgrade"])
	return out


## Buildings that could go up now: in reach of the age, requirements met, below their max,
## enough people, and a free plot. Cost is not checked.
func eligible(type: String) -> bool:
	var content := run.content
	var def: Dictionary = content.buildings[type]
	var needs: String = def.get("requires", "")
	return content.age_reached(run.age, def.get("age", "")) \
		and run.world.count_buildings(type, false) < run.building_max(type) \
		and (needs == "" or run.world.count_buildings(needs, false) > 0) \
		and run.population() >= int(def.get("min_people", 0)) \
		and not (def.has("ages_up") and content.age_reached(run.age, def["ages_up"])) \
		and run.world.has_spot(type)


## Why the town wants a building now: "housing", "food", "beds", "regrow" (the nodes it tends are picked over),
## "fuel" (it makes fuel and there is less than two nights' worth), "supply" (a stall has nobody making
## its goods), "stall" (a workshop has nowhere to sell), "heroes" (no hero lodging drafted or standing),
## "ageing" (the next age-up needs it), "age" (new in the town's current age),
## or "" for nothing in particular.
func need(type: String) -> String:
	var content := run.content
	var def: Dictionary = content.buildings[type]
	if def.has("housing") and not def.has("lodging") and run.housing() - run.population() <= 2:
		return "housing"
	if feeds(type) and float(run.stock["food"]) < run.food_needed_today() * 3.0:
		return "food"
	if def.has("lodging") and run.world.hero_ai.count_lodgings() > 0 and free_beds() <= 0:
		return "beds"
	if def.has("lodging") and not _any_lodging():
		return "heroes"
	if type == ageing_need():
		return "ageing"
	if not run.world.tending(type).is_empty() and run.world.nodes_fullness(def["tends"]["tag"]) < content.num("build_tend_below"):
		return "regrow"
	if def.has("workshop") and makes_fuel(type) and float(run.stock["fuel"]) < run.fuel_needed_tonight() * 2.0:
		return "fuel"
	if def.has("workshop"):
		for id in content.recipes_for(type):
			var kind: String = content.market["recipes"][id].get("stall", "")
			if kind == "":
				continue
			if _has_stall(kind) and not _supplied(kind):
				return "supply"
			if not _has_stall(kind) and run.world.count_buildings(type, false) > 0:
				return "stall"
	if run.world.buildings.any(func(b: Dictionary) -> bool: return content.buildings[b["type"]].has("workshop")) \
			and not run.world.buildings.any(func(b: Dictionary) -> bool: return content.buildings[b["type"]].has("stall")) \
			and content.buildings.values().any(func(d: Dictionary) -> bool: return d.has("stall") and d.get("requires", "") == type):
		return "stall"
	if def.has("stall") and not _has_stall(def["stall"]["sells"]) and _supplied(def["stall"]["sells"]):
		return "stall"
	if def.has("runners") and _has_stall("provisions") and run.living_heroes().size() >= 2:
		return "runners"
	var own_age: String = def.get("age", "")
	if own_age != "" and own_age == run.age and run.world.count_buildings(type, false) == 0:
		return "age"
	return ""


## True for a building that brings food in (daily food, or the drying rack's smoked meat).
func feeds(type: String) -> bool:
	return run.content.buildings[type].get("daily", {}).has("food") or type == "drying_rack"


## True for a workshop with a recipe that makes fuel.
func makes_fuel(type: String) -> bool:
	return run.content.recipes_for(type).any(func(id: String) -> bool:
		return run.content.market["recipes"][id].get("makes", {}).has("fuel"))


## How many offers each draft deals: blueprint_offers (crafts and the deepening offer count among them), plus
## relics' hand_bonus.
func size() -> int:
	return run.content.int_num("blueprint_offers") + int(run.mod("hand_bonus"))


func _fill(rng: SeededRng, avoid: Array = []) -> void:
	var content := run.content
	cards = []
	crafts = []
	upgrade_offers = []
	milestone = {}
	var types := content.buildings.keys()
	types.sort()
	for type: String in types:
		if content.buildings[type].has("ages_up") and eligible(type):
			milestone = {"building": type, "need": ""}
	if picks <= 0:
		return
	var weights := {}
	for type: String in types:
		if not draftable(type):
			continue
		# Rarer blueprints (data/rarity.json) come up less often, a little more as the run goes on.
		var weight := content.rarity_odds(content.rarity_of("building", type), run.round_number)
		if need(type) != "":
			weight *= content.num("build_need_weight")
		if run.world.count_buildings(type, false) == 0:
			weight *= content.num("build_new_weight")
		if run.tradition_favours(type):
			weight *= content.num("tradition_card_weight")
		if run.path_favours(type):
			weight *= content.num("path_card_weight")
		# A reroll leans away from what was just offered, so it feels like a fresh deal.
		if avoid.has(type):
			weight *= 0.25
		weights[type] = weight
	var room := size()
	# What the next age-up needs is always offered, so ageing up never waits on luck. The market comes as a
	# choice of first craft.
	var must := ageing_need()
	if must != "" and is_piece(must):
		var choices := _craft_weights(avoid)
		while crafts.size() < content.int_num("market_crafts") and not choices.is_empty():
			var id := rng.weighted(choices)
			choices.erase(id)
			crafts.append({"craft": id, "need": craft_need(id)})
		room -= crafts.size()
	elif must != "" and weights.has(must) and room > 0:
		weights.erase(must)
		cards.append({"building": must, "need": need(must)})
		room -= 1
	# One offer builds on what the town has started; the rest are new buildings.
	var deep := _deep_weights(weights, avoid)
	for key: String in deep:
		weights.erase(key)
	if room > 0 and not deep.is_empty():
		_deal_offer(rng.weighted(deep), deep, true)
		room -= 1
	while room > 0 and not weights.is_empty():
		var type := rng.weighted(weights)
		weights.erase(type)
		cards.append({"building": type, "need": need(type)})
		room -= 1
	# Too few new buildings left: the rest of the deepening offers fill the draft.
	while room > 0 and not deep.is_empty():
		_deal_offer(rng.weighted(deep), deep, false)
		room -= 1
	# Each offer rolls on its own stream, so the roll never changes which buildings are offered.
	_fills += 1
	var roll_rng := SeededRng.stream(run.run_seed, "blueprint_roll", _fills)
	for c in cards:
		CardRoll.roll_building(content, roll_rng, c, "blueprint", c["building"], run.round_number)
	for c in upgrade_offers:
		CardRoll.roll_building(content, roll_rng, c, "upgrade", content.upgrades[c["upgrade"]]["building"], run.round_number)


## Deals one offer from the deepening offers (an "upgrade:<id>", a "craft:<id>" or a building a craft opened) and
## takes it out of them.
func _deal_offer(key: String, deep: Dictionary, first: bool) -> void:
	deep.erase(key)
	var offer := {}
	if key.begins_with("upgrade:"):
		offer = {"upgrade": key.trim_prefix("upgrade:")}
		upgrade_offers.append(offer)
	elif key.begins_with("craft:"):
		var id := key.trim_prefix("craft:")
		offer = {"craft": id, "need": craft_need(id)}
		crafts.append(offer)
	else:
		offer = {"building": key, "need": need(key)}
		cards.insert(0, offer)
	if first:
		offer["deep"] = true


## The offers that build on what the town has, by weight: upgrades for buildings standing, buildings a craft the
## town has opened (their weights from `weights`) and, once the market is in, crafts not taken yet.
func _deep_weights(weights: Dictionary, avoid: Array) -> Dictionary:
	var deep := {}
	var ids := run.content.upgrades.keys()
	ids.sort()
	for id: String in ids:
		if not upgradable(id):
			continue
		var weight := run.content.rarity_odds(run.content.upgrades[id].get("rarity", "white"), run.round_number)
		if avoid.has("upgrade:" + id):
			weight *= 0.25
		deep["upgrade:" + id] = weight
	for type: String in weights:
		if opener(type) != "" and crafts_taken.has(opener(type)):
			deep[type] = weights[type]
	if has_building("market"):
		var choices := _craft_weights(avoid)
		# Each further craft counts for less, so upgrades and opened buildings get their turn.
		for id: String in choices:
			deep["craft:" + id] = choices[id] * run.content.num("deep_craft_weight")
	return deep


## Crafts not taken yet whose pieces are in reach of the age, by weight: more when the town needs one of their
## pieces or its founding tradition favours one.
func _craft_weights(avoid: Array) -> Dictionary:
	var out := {}
	var ids := run.content.crafts.keys()
	ids.sort()
	for id: String in ids:
		if not craft_draftable(id):
			continue
		var craft: Dictionary = run.content.crafts[id]
		var weight := 1.0
		if craft_need(id) != "":
			weight *= run.content.num("build_need_weight")
		if run.tradition_favours(craft["workshop"]) or run.tradition_favours(craft["stall"]):
			weight *= run.content.num("tradition_card_weight")
		if run.path_favours(craft["workshop"]) or run.path_favours(craft["stall"]):
			weight *= run.content.num("path_card_weight")
		if avoid.has("craft:" + id):
			weight *= 0.25
		out[id] = weight
	return out


## True if this craft could be offered: not taken, and its pieces in reach of the age.
func craft_draftable(id: String) -> bool:
	if crafts_taken.has(id):
		return false
	var craft: Dictionary = run.content.crafts[id]
	for type: String in [craft["workshop"], craft["stall"]]:
		if not run.content.age_reached(run.age, run.content.buildings[type].get("age", "")):
			return false
	return true


func can_draft_craft(id: String) -> bool:
	return run.phase == RunState.Phase.BUILD and picks > 0 and crafts.any(func(c: Dictionary) -> bool: return c["craft"] == id)


## Drafts an offered craft: its workshop and stall as blueprints, and the market with the first one.
func draft_craft(id: String) -> bool:
	if not can_draft_craft(id):
		return false
	crafts_taken.append(id)
	for type in craft_adds(id):
		_take(type)
	run.record.note_action({"kind": "blueprint", "craft": id})
	var craft: Dictionary = run.content.crafts[id]
	var opens := craft_opens(id)
	run.tell("%s drafted.%s" % [craft["name"], "" if opens.is_empty() else " The draft can now offer " + _names(opens) + "."])
	_after_draft()
	return true


## The blueprints drafting this craft adds: the market if the town has none yet, its workshop and its stall.
func craft_adds(id: String) -> Array[String]:
	var craft: Dictionary = run.content.crafts[id]
	var out: Array[String] = []
	for type: String in ["market", craft["workshop"], craft["stall"]]:
		if not has_building(type) and not out.has(type):
			out.append(type)
	return out


## The buildings a craft opens that the town has not drafted yet.
func craft_opens(id: String) -> Array[String]:
	var out: Array[String] = []
	for type: String in run.content.crafts[id].get("opens", []):
		if not blueprints.has(type) and in_pool(type):
			out.append(type)
	return out


## Why the town wants a craft: the market for ageing up, or why it wants its workshop or stall.
func craft_need(id: String) -> String:
	if not has_building("market") and ageing_need() == "market":
		return "ageing"
	var craft: Dictionary = run.content.crafts[id]
	var why := need(craft["workshop"])
	return why if why != "" else need(craft["stall"])


## True for the market and the workshops and stalls that crafts bring: they are never drafted on their own.
func is_piece(type: String) -> bool:
	return craft_of(type) != "" or (type == "market" and not run.content.crafts.is_empty())


## The craft this building is the workshop or stall of ("" if none).
func craft_of(type: String) -> String:
	for id: String in run.content.crafts:
		var craft: Dictionary = run.content.crafts[id]
		if craft["workshop"] == type or craft["stall"] == type:
			return id
	return ""


## The craft that opens this building ("" if none does).
func opener(type: String) -> String:
	for id: String in run.content.crafts:
		if run.content.crafts[id].get("opens", []).has(type):
			return id
	return ""


## True if this building can come up in the draft as far as crafts go: no craft opens it, the town has the craft
## that does, or a founding tradition favours it (a tradition's buildings are never held back).
func opened(type: String) -> bool:
	var id := opener(type)
	return id == "" or crafts_taken.has(id) or run.tradition_favours(type)


func _names(types: Array[String]) -> String:
	var names := PackedStringArray(types.map(func(t: String) -> String: return run.content.buildings[t]["name"].to_lower()))
	if names.size() <= 1:
		return "".join(names)
	return ", ".join(names.slice(0, names.size() - 1)) + " and " + names[names.size() - 1]


## An upgrade can be offered once its building stands, until it is taken.
func upgradable(id: String) -> bool:
	return not run.upgrades.has(id) and run.world.count_buildings(run.content.upgrades[id]["building"]) > 0


func can_draft_upgrade(id: String) -> bool:
	return run.phase == RunState.Phase.BUILD and picks > 0 and upgrade_offers.any(func(c: Dictionary) -> bool: return c["upgrade"] == id)


## Takes an offered upgrade for the rest of the run, spending the draft.
func draft_upgrade(id: String) -> bool:
	if not can_draft_upgrade(id):
		return false
	var offer: Dictionary = upgrade_offers.filter(func(c: Dictionary) -> bool: return c["upgrade"] == id)[0]
	run.take_upgrade(id, offer)
	if offer.has("roll"):
		_apply_roll(run.content.upgrades[id]["building"], offer, "upgrade:" + id)
	_after_draft()
	return true


## True if the town has this building: a basic, a blueprint or one standing.
func has_building(type: String) -> bool:
	return run.content.buildings[type].get("basic", false) or blueprints.has(type) or run.world.count_buildings(type, false) > 0


func _any_lodging() -> bool:
	for type: String in run.content.buildings:
		if run.content.buildings[type].has("lodging") and (blueprints.has(type) or run.world.count_buildings(type, false) > 0):
			return true
	return false


func free_beds() -> int:
	var beds := 0
	for b in run.world.buildings:
		var def: Dictionary = run.content.buildings[b["type"]]
		if def.has("lodging"):
			beds += int(def["lodging"]["beds"])
	return beds - run.living_heroes().size()


func _has_stall(kind: String) -> bool:
	for type: String in run.content.buildings:
		if run.content.buildings[type].get("stall", {}).get("sells", "") == kind and run.world.count_buildings(type, false) > 0:
			return true
	return false


func _supplied(kind: String) -> bool:
	for id: String in run.content.market["recipes"]:
		var r: Dictionary = run.content.market["recipes"][id]
		if r.get("stall", "") == kind and run.world.count_buildings(r["workshop"], false) > 0:
			return true
	return false
